# Chetta Cash — iOS Implementation Plan

**Version 1.0 · 12 September 2026**

This is the complete and only build specification for Chetta Cash v1. It replaces all earlier documents (`chetta-cash-implementation.md`, `chetta-cash-implementation-rev2.md`) — do not read those alongside this one, they contain superseded decisions.

## How to use this document

- **§1–3** are context. Read once.
- **§4 is the most important section.** It defines how money moves. Every number displayed anywhere in the app derives from it. Build and test it before writing any screen.
- **§5–6** define the data model and navigation.
- **§7** specifies every screen.
- **§8–12** are cross-cutting: design system, storage, notifications, security, accessibility.
- **§13** lists what is deliberately excluded. Do not implement anything in it.
- **§14** is the build order with acceptance criteria per phase.

**Where this document says "must" or "do not", treat it as a hard requirement, not a suggestion.** Where it says "recommend", you may deviate with a reason. Where a decision is genuinely open, it appears in §13.2 — stop and ask rather than inventing an answer.

---

## 1. What the app is

Chetta Cash is a **single-user personal finance app for iPhone**. It unifies four things normally scattered across separate apps:

1. **Accounts** — cash, savings and credit cards, organised into groups, with an Available Cash versus Net Worth split.
2. **Ledger** — expense, income and transfer transactions against those accounts, categorised and taggable.
3. **Smart Vault** — a registry of owned things worth tracking: free trials, warranties and subscriptions, with expiry and renewal reminders.
4. **Compare** — a unit-price calculator ($/100 g and similar) for in-aisle purchase decisions.

All data entry is manual. There is no bank aggregation (no Plaid or equivalent), no multi-user support, no social features, no account system and no login screen.

---

## 2. Tech stack

| Decision | Choice |
|---|---|
| UI framework | SwiftUI. No UIKit except where SwiftUI has no equivalent (`DataScannerViewController`). |
| Minimum OS | iOS 26 |
| Device | iPhone only. No iPad layout in v1. |
| Persistence | SwiftData |
| Sync | CloudKit private database via `.modelContainer(..., cloudKitDatabase: .automatic)`. No custom backend. |
| State | Observation framework (`@Observable`). Not `ObservableObject`/`@Published`. |
| Architecture | MVVM. Views bind to `@Observable` view models; view models own business logic and reach SwiftData through a service layer; `@Model` types stay free of view logic. |
| Navigation | `NavigationStack` per tab, `.sheet` for all add/edit forms. |
| Money | `Int` cents everywhere in the model layer. Never `Double` or `String` for currency. |
| Notifications | `UNUserNotificationCenter`, local only. No push, no server. |

### 2.1 Project structure

```
ChettaCash/
  App/
    ChettaCashApp.swift              @main, ModelContainer, onboarding gate, app lock gate
    AppSettings.swift                @Observable settings
  Models/                            §5
  Engine/                            §4 — build and test first
    BalanceEngine.swift
    TransferService.swift
    RecurringEngine.swift
    StatementEngine.swift
  DesignSystem/                      §8
    Colors.swift
    Typography.swift
    Components/
  Features/
    Dashboard/ Vault/ Ledger/ Compare/ Settings/ More/ Onboarding/
  Services/
    ReceiptStore.swift               §9 protocol
    ICloudReceiptStore.swift         §9 v1 implementation
    ReceiptUploadQueue.swift
    BackupService.swift
    NotificationScheduler.swift
    CurrencyFormatter.swift
    AppLockService.swift
```

---

## 3. Information architecture

```
Launch
 ├─ app lock enabled? ──▶ Face ID / passcode gate (§11)
 └─ hasCompletedOnboarding? ──No──▶ Onboarding (3 screens, §7.10)
                                │
                               Yes
                                ▼
        ┌──────────┬────────┬─────────┬────────┬──────────┐
        │ Dashboard │ Vault  │ Ledger  │  More  │ Settings │
        └──────────┴────────┴─────────┴────────┴──────────┘
             │         │         │         │          │
        Today sheet  + Add   + Add    Compare    Accounts
                     Product Transaction         inline forms
```

Tab order, left to right: **Dashboard, Vault, Ledger, More, Settings.**

---

## 4. The money engine

**This section is the foundation. Build it first, with unit tests, before any screen exists.**

### 4.1 Balances are derived, never stored

An account stores an **opening balance** and the date it applies from. Its current balance is computed:

```
currentBalance(account, asOf: Date = .now)
    = account.openingBalanceCents
    + sum of signedAmountCents for every transaction on that account
      where transaction.date <= asOf
```

Signed amount by transaction type:

| Type | Signed amount |
|---|---|
| `expense` | `-amountCents` |
| `income` | `+amountCents` |
| `transferOut` | `-amountCents` |
| `transferIn` | `+amountCents` |
| `adjustment` | `signedOverrideCents` (may be negative) |

**A card account's balance is negative when money is owed**, and becomes more negative as the user spends. A payment to the card is a `transferIn`, which moves it toward zero. Do not special-case card sign handling anywhere except the opening-balance form (§7.9).

**Do not store a running balance as the source of truth.** Maintain `Account.cachedBalanceCents` as a denormalised cache, recomputed whenever a transaction on that account is inserted, updated or deleted. Provide a "Recalculate balances" maintenance action that rebuilds every cache from scratch.

**Derived figures:**

- **Available Cash** = sum of `currentBalance` for every open account where `kind == .account`
- **Net Worth** = sum of `currentBalance` for every open account, including cards

### 4.2 Posted versus scheduled

A transaction dated in the future exists in the database but is **inert**. It does not affect balances, spend totals, trend charts or any summary until its date arrives.

```swift
extension Transaction {
    var isPosted: Bool { date <= Date.now }
}
```

**Every aggregate query must filter on `isPosted`.** There is no manual "post" action — posting is purely a function of the clock.

### 4.3 Transfers

A transfer creates **two** transactions sharing a `transferGroupID: UUID`:

- the outflow leg on the source account, type `transferOut`
- the inflow leg on the destination account, type `transferIn`

Rules, all mandatory:

- Both legs carry the same `amountCents`, the same `date` and the same `transferGroupID`.
- Transfers have **no category**. `categoryID` is nil on both legs.
- **Both legs are excluded from spend totals, income totals, the Ledger summary banner and the Trends Spend chart.** A credit-card payment moves money without being new spending; counting it would double-count every card purchase — once when swiped, once when paid.
- Editing either leg edits both. Deleting either leg deletes both. A half-transfer must never exist in the database.
- Source and destination must differ.

**Display:** in the Ledger with no account filter active, a transfer renders as one row reading `TD Chequing → TD Visa`. With an account filter active, only that account's leg is shown.

Transfers are how card payments, savings contributions and account closures are all recorded.

### 4.4 Adjustments

When the derived balance drifts from reality, the user has two paths. Both must exist, reached from a single "Correct balance" action on Edit Account that asks which they mean:

1. **Adjustment transaction** — type `adjustment`, signed amount, dated. For small drift and unlogged charges. Affects balances and Net Worth. **Excluded from spend and income totals** — a correction is not spending.
2. **Edit the opening balance** — for when the starting figure was simply wrong. Recomputes that account's entire history.

### 4.5 Recurring transactions

#### The rule

`RecurringRule` holds name, account, amount, type, category, frequency (`weekly` / `biweekly` / `monthly` / `yearly`), start date, and an **optional** end condition — either an end date **or** an occurrence count. If the user supplies neither, the rule runs until deleted.

#### Lazy generation

**At any moment, exactly one unposted occurrence exists per active rule.** When it posts, the next is generated immediately.

`RecurringEngine.reconcile()` runs on app foreground and after any rule edit. It must:

1. Generate one occurrence for every active rule that has none unposted.
2. For every generated occurrence whose date has passed, generate the rule's next occurrence. (Posting itself is implicit via `isPosted` — no state flag to flip.)
3. **Handle catch-up.** If the app has not been opened for two months, a monthly rule generates both missed occurrences, in date order, and then the next future one.
4. Stop generating for any rule that has reached its end date or occurrence count, and set `isActive = false`.

**Month-end handling:** a monthly rule starting on the 31st fires on the last day of shorter months. Use `Calendar.nextDate(after:matching:matchingPolicy:.previousTimePreservingSmallerComponents)`. **Do not roll forward into the following month.**

**Posting is silent.** No confirmation prompt, no notification. The transaction appears in Recent Activity and the balance updates.

#### Editing and deleting a series

Both edit and delete must prompt for scope:

- **This occurrence only** — sets `isSeriesOverride = true` on that transaction; the rule is untouched.
- **This and future** — ends the current rule at this date and creates a new rule with the new values.
- **All, including past** — applies retroactively to already-posted transactions.

The third option **must show an explicit warning before proceeding**, worded concretely: *"This will change your recorded history. Past balances, totals and charts will update."* Not a generic "are you sure".

### 4.6 Credit card statements

A card carries two figures and **both must be shown**:

- **Current balance** — everything owed right now, including charges made after the statement closed.
- **Statement balance** — what was owed as of the last closing date. This is what is actually due on the due date.

**Statement balance is computed** from transactions in the period, with a **user override** for when the real statement differs.

**Payment allocation:** a `transferIn` to a card account allocates to the **oldest open statement first**, creating a `StatementPayment` record. Overflow beyond the statement balance reduces the current balance without being allocated.

This produces the required display:

> Statement $100.00 · $40.00 paid · **$60.00 due 15 Sep**

**Interest and fees:** on statement close, prompt once — *"Did TD Visa charge interest or fees this period?"* — with an amount field. A value entered creates an expense transaction on that card, dated to the closing date, categorised Bills. Dismissing sets `interestPromptResolved = true` and does not ask again for that statement.

**No APR is stored and no interest is calculated.** The user's real statement is the source of truth.

### 4.7 Account lifecycle

**Accounts are never hard-deleted.** All `deleteRule` values from `Account` are `.nullify`, except `statements` which cascades.

The close flow:

1. If the balance is non-zero, **block closing** and prompt the user to zero it first — transfer remaining cash out, or pay the card off. Offer to pre-fill that transfer.
2. At zero, set `isClosed = true` and `closedDate`.
3. The account and **every transaction touching it** become read-only. Edit and delete are disabled on those transactions.
4. The account detail screen shows an info banner: *"Closed by you on 12 September 2026."*
5. Closed accounts disappear from account pickers but **remain in the Ledger's account filter**, so history stays browsable.
6. Because the balance is zero at close, no exclusion rule is needed for Available Cash or Net Worth.

A "Reopen account" action clears both fields and restores editability.

### 4.8 Categories and tags

**One category per transaction. Unlimited tags.**

Multiple categories per transaction was considered and rejected: a $100 purchase carrying two categories would sum to $200 in a by-category total, and the Trends chart would stop reconciling with the Ledger. Tags already provide multi-label grouping without breaking arithmetic.

**Seed lists are deliberately short.** The user builds the rest through the inline "+ Custom" chip (§8.4).

- **Expense:** Groceries, Food & drink, Transport, Shopping, Bills, Other
- **Income:** Salary, Other
- **Vault product:** Subscription, Electronics, Home, Other
- **System, never shown in any picker:** Transfer, Balance adjustment

Every category picker and every category filter row is built from **whatever categories actually exist**, never from a hardcoded list. Hardcoding is what caused the two divergent lists in the original design.

**Categories are archived, never deleted.** Deleting one would orphan `Transaction.categoryID` and blank out historical rows. Archiving removes it from pickers while leaving past transactions intact and still filterable.

---

## 5. Data model

All properties carry defaults or are optional, all relationships are optional with declared inverses, and `@Attribute(.unique)` is not used anywhere — **these are CloudKit requirements, not style preferences.** A model missing a default will fail schema validation at container initialisation.

Every model carries `id: UUID` for the re-importable backup (§9.4). Uniqueness is enforced in application code.

```swift
@Model final class AccountGroup {
    var id: UUID = UUID()
    var name: String = ""
    var sortIndex: Int = 0
    @Relationship(deleteRule: .nullify, inverse: \Account.group)
    var accounts: [Account]? = []
}

@Model final class Account {
    var id: UUID = UUID()
    var name: String = ""
    var kind: AccountKind = AccountKind.account
    var openingBalanceCents: Int = 0
    var openingBalanceDate: Date = Date.now
    var cachedBalanceCents: Int = 0
    var sortIndex: Int = 0
    var isClosed: Bool = false
    var closedDate: Date?
    var group: AccountGroup?

    var statementDayOfMonth: Int?
    var paymentDueDayOfMonth: Int?
    var remindBeforeDueDate: Bool = true

    @Relationship(deleteRule: .nullify, inverse: \Transaction.account)
    var transactions: [Transaction]? = []
    @Relationship(deleteRule: .nullify, inverse: \VaultItem.account)
    var vaultItems: [VaultItem]? = []
    @Relationship(deleteRule: .cascade, inverse: \CardStatement.account)
    var statements: [CardStatement]? = []
}

enum AccountKind: String, Codable { case account, card }

@Model final class Transaction {
    var id: UUID = UUID()
    var amountCents: Int = 0
    var type: TransactionType = TransactionType.expense
    var signedOverrideCents: Int?
    var categoryID: UUID?
    var account: Account?
    var date: Date = Date.now
    var merchant: String = ""
    var location: String?
    var memo: String?
    var tags: [String] = []

    var transferGroupID: UUID?
    var recurringRule: RecurringRule?
    var isSeriesOverride: Bool = false

    var receiptFileID: String?
    var receiptFileName: String?
    var receiptChecksum: String?
    var receiptUploadState: ReceiptUploadState = ReceiptUploadState.none

    @Relationship(deleteRule: .cascade)
    var trackedProducts: [TrackedProductRef]? = []
}

enum TransactionType: String, Codable {
    case expense, income, transferOut, transferIn, adjustment
}

@Model final class RecurringRule {
    var id: UUID = UUID()
    var name: String = ""
    var amountCents: Int = 0
    var type: TransactionType = TransactionType.expense
    var categoryID: UUID?
    var account: Account?
    var frequency: RecurringFrequency = RecurringFrequency.monthly
    var startDate: Date = Date.now
    var endDate: Date?
    var occurrenceLimit: Int?
    var occurrencesGenerated: Int = 0
    var isActive: Bool = true
    var vaultItem: VaultItem?
}

enum RecurringFrequency: String, Codable { case weekly, biweekly, monthly, yearly }

@Model final class CardStatement {
    var id: UUID = UUID()
    var account: Account?
    var periodStart: Date = Date.now
    var closingDate: Date = Date.now
    var dueDate: Date = Date.now
    var computedBalanceCents: Int = 0
    var overrideBalanceCents: Int?
    var isPeriodClosed: Bool = false
    var interestPromptResolved: Bool = false
    @Relationship(deleteRule: .cascade, inverse: \StatementPayment.statement)
    var payments: [StatementPayment]? = []
}

@Model final class StatementPayment {
    var id: UUID = UUID()
    var statement: CardStatement?
    var transaction: Transaction?
    var amountCents: Int = 0
}

@Model final class Category {
    var id: UUID = UUID()
    var label: String = ""
    var context: CategoryContext = CategoryContext.expense
    var isBuiltIn: Bool = false
    var isArchived: Bool = false
    var sortIndex: Int = 0
}

enum CategoryContext: String, Codable { case expense, income, vaultProduct }

@Model final class VaultItem {
    var id: UUID = UUID()
    var name: String = ""
    var itemDescription: String?
    var priceCents: Int = 0
    var account: Account?
    var categoryID: UUID?
    var tags: [String] = []
    var purchaseDate: Date = Date.now
    var logAsExpense: Bool = true
    var linkedTransaction: Transaction?

    var hasTrial: Bool = false
    var trialEndsDate: Date?
    var trialReminderLeadTime: ReminderLeadTime = ReminderLeadTime.useDefault

    var hasWarranty: Bool = false
    var warrantyExpiresDate: Date?
    var warrantyReminderLeadTime: ReminderLeadTime = ReminderLeadTime.useDefault

    @Relationship(deleteRule: .nullify, inverse: \RecurringRule.vaultItem)
    var recurringRule: RecurringRule?
}

enum ReminderLeadTime: String, Codable {
    case useDefault, off, sameDay, oneDayBefore, threeDaysBefore, oneWeekBefore
}

@Model final class TrackedProductRef {
    var id: UUID = UUID()
    var name: String = ""
    var priceCents: Int?
}

@Model final class Comparison {
    var id: UUID = UUID()
    var label: String = ""
    var unitCategory: UnitCategory?
    var itemAPriceCents: Int?
    var itemAQuantity: Double?
    var itemAUnit: String?
    var itemBPriceCents: Int?
    var itemBQuantity: Double?
    var itemBUnit: String?
    var sortIndex: Int = 0
}

enum UnitCategory: String, Codable { case mass, volume, quantity }
enum ReceiptUploadState: String, Codable { case none, pending, uploaded, failed }
```

### 5.1 App settings

```swift
@Observable final class AppSettings {
    var currencyCode: String = "USD"
    var defaultReminderLeadTime: ReminderLeadTime = .threeDaysBefore
    var backupInterval: BackupInterval = .weekly
    var receiptCacheCapMB: Int = 200
    var appLockEnabled: Bool = false
    var appLockGraceSeconds: Int = 0
    var hasCompletedOnboarding: Bool = false
}
enum BackupInterval: String, Codable { case off, weekly, monthly }
```

**The currency code is a display label only.** It changes which symbol and code are rendered, applied uniformly to every amount. There is no per-account currency, no exchange rate and no home-currency concept. Do not build conversion logic.

---

## 6. Navigation

### 6.1 Tabs

Five tabs: Dashboard, Vault, Ledger, More, Settings. Icons: house, shield-checkmark, booklet, ellipsis, gear. Active tint `#7A2FC4`, inactive `#8A8792`. Each tab root is its own `NavigationStack`.

**As shipped**, Vault has no tab of its own (§7.3's note): products are created from the transaction form and the Dashboard's floating "Add product" button, and browsed from search. The current tab order is **Dashboard, Ledger, Add, More, Settings** — icons `house`, `list.bullet`, `doc.text.badge.plus`, `ellipsis`, `gearshape`. **Add** is not a real destination: selecting it opens Add Transaction (the same form the Ledger's "+" opens) and immediately reverts the visible tab, since `TabView` has no native concept of an action item. It sits third, dead centre of five, because it is the one item reached constantly and the centre is the shortest reach.

### 6.2 The More tab

Implement as a list screen with one row today — "Compare Prices" → pushes `CompareView`. **Do not hard-route the tab straight to Compare.** The tab exists to leave room for future utilities; routing it directly would require a redesign to add a second one.

### 6.3 Modal rules

All six add/edit forms (Transaction, Product, Account) are `.sheet` modals with a `Cancel / Title / Save` header. **None of them is pushed via `NavigationStack`, and none has a back chevron.**

- Add Product and Add Transaction: `.interactiveDismissDisabled(true)`. Only Cancel or Save closes them.
- Edit sheets: standard swipe-to-dismiss is fine.

**Save lives in the header only.** Do not add a full-width Save button at the bottom of any form — that redundancy was removed deliberately. Delete, on the edit sheets, is its own row below the form.

---

## 7. Screens

### 7.0 States — applies to every list screen

Dashboard, Vault, Ledger, Compare and Settings' Accounts section must each support **Loading**, **Empty** and **Loaded**, driven by real query results. Dashboard additionally supports **Error**.

- **Loading** — skeleton placeholders. Relevant mainly while CloudKit hydrates on first launch.
- **Empty** — query returned zero rows. Icon, message, and a CTA that starts the relevant flow.
- **Error** — a red banner above otherwise-normal content, never replacing it, with a working Retry.

**Filtered-to-zero is a different state from first-run empty.** A Vault search matching nothing shows *"No products match your search or filter."* inline; it does not replace the screen with the "No products yet" first-run state. Keep the two distinct in view logic.

> The original mockup cycled these states via a tappable "Preview: Live ▸" pill. **That control is a design-tool artifact. Do not build it.**

### 7.1 Dashboard

**The organising principle: the Dashboard answers "where do I stand." The hero carousel answers "what needs me."** Everything time-sensitive lives on the carousel's lead page and behind its chevron, so nothing else on the screen needs a badge or an alert.

Sections, top to bottom:

1. **Greeting** — the screen's large title reads "Good morning / afternoon / evening" rather than "Dashboard". A name the app already knows beats a label nobody needs.
2. **Hero carousel** — a horizontally paged card with a page indicator. The lead page is **All accounts**: Available Cash, a thirty-day net-worth sparkline, the category insight, and the Today digest's status chips. Each following page is one open account: its name, its masked digits when it has them (`Account.last4`), its derived balance, its own sparkline and its own insight. The chevron on every page opens the Today sheet (§7.2).
3. **Today, falling back to Recent** — today's posted transactions when there are any, titled "Today"; otherwise the most recent posted ones, titled "Recent" and led by an explicit *"No activity today — showing recent"* line so the substitution is never silent. Rows carry a category-tinted circular avatar and read their date relatively ("Today", "Yesterday", "Sat", "12 Sep"). "See all transactions" sits inside the card, into the Ledger.

**Swiping the carousel is the focused-account picker.** The visible page writes through to `AppSettings.focusedAccountID`, so the choice persists and the Today list below rescopes to match. An id that no longer resolves to an open account behaves exactly like "All accounts." There is no separate picker row and no account strip — the carousel is both.

**The sparkline is real daily history, never sampled or faked.** `BalanceSeriesEngine` derives one point per day for the trailing thirty days, in a single sort and two linear passes rather than by re-deriving a balance per day. Note the one inversion: **transfer legs and adjustments do move a balance series**, even though `TotalsEngine` excludes them from every *total*. `BalanceSeries` also carries the min/max band and pre-normalised values, because a balance is a *stock* — a card between −$800 and −$900 scaled against a zero-anchored peak would draw as a flat line at the bottom.

**The category insight is computed, and deliberately quiet.** `CategoryInsightEngine` compares each category's spend this month against last and reports at most one — the largest move **in cents**, not in percentage, because dollars are what a person feels and percentage-first ranking always surfaces whichever small category happened to double. Three floors keep it honest ($25 spent, a $10 move, 10%), and a **fall is suppressed for the first week of the month**, since on the 3rd every category is "down 90%" against a full prior month. A rise is never suppressed — it cannot be an artefact. Uncategorised spending is excluded: that is a data-hygiene nag, and the Today card already owns it.

**The 6-month Trends charts are not on this screen.** They were removed with the redesign and have no tab of their own. `TrendsEngine.monthlySpend` / `monthlyIncome` / `monthlyNetWorth` and their tests remain, so restoring them is view-only work.

Quick actions do not sit inline: "Add product" is a floating button in the screen's bottom-trailing corner, and "Log transaction" is the centre item in the app's tab bar (§6.1).

**Colour rule, mandatory:** spending **more** is the unwelcome direction, so a rise in spend reads red and a fall reads green; net worth and income are the reverse. Colour must never be the only signal — the hero insight pairs it with a flame or a checkmark (§12).

**Dashboard states:** Empty appears only when there are **zero accounts** — "No accounts yet" with an "Add your first account" CTA.

### 7.2 The Today card and sheet

**Card contents:**

- Date line: "Today · Fri 12 Sep"
- **Available Cash** as the primary figure
- **Net Worth** as a secondary line
- A row of status chips, each shown **only when it has something to report**: amount spent today, count due soon, count of trials or warranties ending soon

**Quiet-day state:** when there is no spend, nothing due and nothing charging, the card shows the balance plus an explicit **"Nothing due"** line. It does not hide itself, and it does not show empty chips.

**Tapping the card opens a bottom sheet** (`.presentationDetents([.medium, .large])`), grouped by time horizon:

| Section | Contents |
|---|---|
| Today | Amount spent today, count posted today |
| Due soon | Card statements within their reminder window, each showing the partial-payment figure from §4.6 and a days-remaining pill |
| Upcoming charges | Next occurrence per active recurring rule, limited to the next 30 days |
| Ending soon | Trials and warranties approaching expiry |
| — | "View all active subscriptions" link |

Each section is **omitted entirely when empty** rather than showing an empty state.

**Active subscriptions** is a view over active `RecurringRule`s — name, amount, frequency, account, next charge date. It covers both standalone recurring transactions and Vault-linked subscriptions, because both are rules. There is no second subscription registry.

### 7.3 Smart Vault

Title + "+" (Add Product) → search bar (live case-insensitive substring filter on name) → "Sort: Soonest / Price / Name ›" cycling pill → 3-way segmented filter (All / Active trials / Warranties) → list of item cards → tab bar.

Card contents: icon (amber tint for trial, green for warranty), name, category, status line, optional billing subline for items with a recurring rule (e.g. "$9.99/mo · TD Visa"), chevron.

**Sort semantics:** Soonest = ascending by nearest relevant date (trial end or warranty expiry); Price = ascending `priceCents`; Name = alphabetical.

Row tap → Edit Product sheet, pre-filled.

### 7.4 Ledger

Title + "+" (Add Transaction) → period segmented control (This month / Last month / All time) → account filter chip row (All accounts + one per account, **including closed accounts**) → category filter chip row (All categories + one per non-archived category) → summary banner → **Upcoming section** → day-grouped transaction list.

**Upcoming section:** unposted future occurrences in chronological order, above today's transactions, visually lighter, and **excluded from the summary banner totals**. This overlaps deliberately with the Today sheet's Upcoming charges but is scoped differently — the sheet is a near-term glance (next per rule, 30 days), the Ledger is the full chronological list in context with posted history.

**Summary banner:** period and scope label, total spent, then "{count} transactions · Income $X · Net ±$Y". **Transfers and adjustments are excluded from spend, income and net.** They appear in the list but not in the totals.

**Row format:** category-colour avatar, merchant name with an optional "RECURRING" badge, "Category · Account" subline, signed amount.

**Filtering:** period, account and category combine with AND. Compute period boundaries from real calendar-month dates. Any combination yielding zero rows shows *"No transactions match these filters yet."* — this must work for **any** empty combination, not one specific case.

Row tap → Edit Transaction sheet. **Transactions on closed accounts render normally but are not tappable.**

### 7.5 Compare

Reached via More ▸ Compare Prices.

Title → horizontally scrolling History strip of saved comparisons (chip = label + status sub-label; "✕" to remove, hidden when only one remains; "+ New" dashed chip) → result banner → Item A card → Item B card.

**Item A** takes price and quantity, then a full unit picker grouped by Mass / Volume / Quantity. Picking a unit sets the comparison's `unitCategory`. **Item B**'s unit picker is constrained to Item A's category — it shows a hint until A's unit is chosen, then a small segmented row of that category's units only.

**Unit conversion — implement these factors verbatim:**

```swift
enum Unit: String { case g, kg, lb, oz, mL, L, flOz = "fl oz", gal, item }

struct UnitMeta { let category: UnitCategory; let toBase: Double }
let unitMeta: [Unit: UnitMeta] = [
    .g:    .init(category: .mass,     toBase: 1),
    .kg:   .init(category: .mass,     toBase: 1000),
    .lb:   .init(category: .mass,     toBase: 453.592),
    .oz:   .init(category: .mass,     toBase: 28.3495),
    .mL:   .init(category: .volume,   toBase: 1),
    .L:    .init(category: .volume,   toBase: 1000),
    .flOz: .init(category: .volume,   toBase: 29.5735),
    .gal:  .init(category: .volume,   toBase: 3785.41),
    .item: .init(category: .quantity, toBase: 1),
]
let categoryDivisor: [UnitCategory: Double] = [.mass: 100, .volume: 100, .quantity: 1]

func normalizedPrice(priceCents: Int?, quantity: Double?, unit: Unit?) -> Double? {
    guard let priceCents, let quantity, quantity > 0,
          let unit, let meta = unitMeta[unit] else { return nil }
    let price = Double(priceCents) / 100
    return (price / (quantity * meta.toBase)) * categoryDivisor[meta.category]!
}
```

**Result banner:** both valid → "Item A/B is cheaper" with both per-unit prices, and a green "CHEAPER" badge on the winning card. Difference under 0.0005 → "Both items cost the same". Missing or invalid input → a neutral prompt.

**Validation:** quantity must be a positive number, price must parse. Both **fail silently to "no result yet"** — this screen has no red-outline validation anywhere, unlike the add sheets. **A comparison can never be deleted if it is the last one remaining** — guard this in the remove action, not just in the UI.

### 7.6 Settings

1. Title "Settings".
2. **General card** — "Currency" (tap cycles USD/EUR/GBP/CAD/JPY, display label only) and "Default alert lead time" (tap cycles the five `ReminderLeadTime` options).
3. **Cloud backup card** — see §9.
4. **Security card** — app lock toggle and grace period (§11).
5. **Accounts section** — "Net Worth" summary row → collapsible per-group blocks (header = group name, subtotal, chevron; expanded = account rows with icon, name, type label, balance, and up/down reorder arrows disabled at the group's boundaries) → "+ Add account" → "+ New group".
6. Tab bar.

**"+ Add account" and "+ New group" are inline forms, not sheets.** They expand in place within the Settings scroll view — dashed-border trigger reveals a form card in the same position, Cancel or Save collapses it. This is deliberate: Settings must be fully self-contained without opening a separate sheet.

The add-account inline form asks for group, account type, name, opening balance and opening-balance date. **If no group exists, the form prompts to create one first** rather than allowing an orphaned account.

Account row tap → Edit Account sheet.

### 7.7 Add / Edit Product

Fields, top to bottom: **Scan receipt** (Add only) → Name → Location (optional) → Price → Account (tap-to-cycle) → Category (chip row + "+ Custom") → **"Log as expense"** toggle → Tags → Purchase date → **"Free trial"** toggle (reveals Trial ends date + Remind me picker) → **"Warranty / expiry"** toggle (reveals Expires on date + Remind me picker) → **"Recurring charge"** toggle (reveals frequency picker).

The "Log as expense" helper text swaps between "Will create a linked expense from {account}" and "Tracked in Vault only, no transaction created".

**Add versus Edit — build these differences deliberately:**

- **Scan receipt** appears on Add only. It makes no sense on Edit.
- **Warranty / expiry must appear on Edit too.** The original mockup omitted it from Edit, which was an oversight — the Vault list displays warranty items, so the app must let you edit them.
- **Purchase date is editable on both**, defaulting to today on Add.
- **Edit validates identically to Add** (§7.11).

### 7.8 Add / Edit Transaction

Fields: Expense / Income / Transfer segmented control → large centred amount entry (44pt, green when Income, red only when invalid) → Category chip row, **context-swapping entirely** between expense and income, with "+ Custom" per type → Account (tap-to-cycle) → Date and time → Location → **"Recurring"** toggle (reveals frequency and the optional end condition — end date or occurrence count) → **"Track a product (optional)"** → Tags → Memo.

**Transfer mode** replaces the category row with a destination account picker, and hides tags and memo is optional. Source and destination must differ. Saving creates both legs (§4.3).

**"Track a product"** is a deliberately lightweight bridge: a small Name + optional Price form that appends a `TrackedProductRef` chip to the transaction. It does **not** split the transaction into line items, does **not** change the transaction's total, and does **not** create a `VaultItem`. These chips are informational only — not searchable from Vault, no reminders. Keep `TrackedProductRef` and `VaultItem` as separate, unrelated types. A "promote to Vault item" action is a future feature, not this one.

### 7.9 Add / Edit Account

Fields: Group (chip row + "+ New group" inline add) → Account type (Account / Card segmented) → Account name → **Opening balance** → **Opening balance as of** (date, defaults to today) → *(Card only)* Statement date, Payment due date, "Remind me before due date" toggle.

**The balance field is the opening balance, not a current balance.** Label it "Opening balance" with the "as of" date beneath. This is a consequence of §4.1 — the current balance is derived and cannot be typed in.

For card accounts, store the opening balance as `-abs(value)` regardless of the sign the user typed. **This applies to the opening balance only** — the running balance sign comes from transaction types, never from a forced absolute value.

Edit Account additionally shows **"Correct balance"** (§4.4), **"Close account"** (§4.7) and, for closed accounts, a "Closed by you on {date}" banner plus "Reopen account".

### 7.10 Onboarding

Three full-screen steps, shown once, gated by `AppSettings.hasCompletedOnboarding`. Progress dots at top.

1. **Welcome** — static value-prop screen, one "Get started" CTA. **No skip link** — there is nothing to skip past.
2. **Add your first account** — a self-contained version of the §7.6 inline add-account flow, supporting **several accounts in one pass**: each successful add clears the form and appends to a running "just added" list with a checkmark, rather than closing. "Continue" is disabled until at least one account exists (label reads "Add an account to continue"). **"Skip for now"** bypasses account creation and lands on the Dashboard's empty state.
3. **Enable notifications** — explains the due-date and trial reminder use case. "Enable notifications" triggers the real `UNUserNotificationCenter` permission prompt, not a mock toggle. **"Maybe later"** skips, with the same end state as never granting permission.

Scope is exactly these three screens. Do not add a starter-subscription or starter-budget step.

Note for the notifications step: once the user answers the system prompt, iOS will not show it again. A Settings row wanting to change this must deep-link to iOS Settings ▸ Notifications.

### 7.11 Validation

**All six forms validate identically.** An edit screen whose Save button silently does nothing on invalid input is a defect, not a scope decision.

| Form | Required fields |
|---|---|
| Add / Edit Transaction | Amount, Account |
| Transfer mode | Source account, Destination account (must differ), Amount |
| Add / Edit Product | Name, Price |
| Add / Edit Account | Account name, Group, Opening balance |

**Trigger: on Save attempt only.** Not on blur, not live as the user types.

**Visual:** the invalid field's label turns `negativeRed`, the field gets a 1.5pt inset red ring at 10pt corner radius, and a reserved-height caption appears beneath with specific copy — "Enter an amount to continue.", "Product name is required." The error clears the instant the field becomes valid.

Every other field — categories, tags, toggles, the track-a-product bridge, pickers — is optional.

**Confirmation alerts are required for:** Close account, Delete transaction, Delete product, and any series delete whose scope includes past occurrences.

---

## 8. Design system

### 8.1 Money formatting

```swift
enum CurrencyFormatter {
    static func string(fromCents cents: Int, currencyCode: String) -> String {
        let value = Decimal(cents) / 100
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}
```

Negative amounts use the formatter's native negative style. Foundation places the sign correctly per locale and currency — **do not hand-roll sign placement.**

### 8.2 Colour

**Reserved semantic colours. Never reuse these for anything else, especially not as a category colour.**

| Token | Hex | Meaning |
|---|---|---|
| `brandPurple` | `#7A2FC4` | Primary action, links, selected states |
| `brandPurpleGradientEnd` | `#9B4FE0` | Gradient partner for hero cards |
| `positiveGreen` | `#2E9E5B` | Income, active status, "cheaper" badge |
| `negativeRed` | `#E0393E` | Expense, destructive actions, validation errors, failure banners |
| `attentionAmber` | `#B15E0F` | Due soon, trial ending, card-type accents |

**Category palette — transaction categories only, never status:**

| Category | Background | Foreground |
|---|---|---|
| Groceries | `#DEF3EF` | `#12806F` |
| Food & drink | `#EAF1FB` | `#2F6FCC` |
| Transport | `#E1F0FA` | `#1587C9` |
| Shopping | `#F3EDD7` | `#8A6D1B` |
| Bills | `#F1E7DC` | `#8B5E3C` |
| Entertainment | `#FBE7F1` | `#C23B7A` |
| Subscription | `#E8E8F9` | `#4F52C4` |
| *(income rows)* | `#E7F7EE` | `#2E9E5B` |

User-created categories are assigned a colour from this palette round-robin by creation order.

**Neutrals:**

| Token | Hex | Use |
|---|---|---|
| `textPrimary` | `#1C1B1F` | Primary text |
| `textSecondary` | `#8A8792` | Secondary text |
| `placeholder` | `#B4B0BE` | Placeholders, disabled hints |
| `appBackground` | `#F7F5FB` | Screen background |
| `surface` | `#FFFFFF` | Cards |
| `borderSubtle` | `#ECE7F5` | Card borders |
| `segmentTrack` | `#EDEAF3` | Segmented control track |
| `dashedAccent` | `#C9AEEE` | "+ Add new" dashed borders |
| Error banner | `#FDEAEA` / `#F5C2C4` / `#B0292E` | bg / border / text |

Cards: white surface, 16–20pt radius, `1px solid borderSubtle` or shadow only (`0 1px 3px rgba(30,10,50,0.06)`). Hero cards: `LinearGradient` at 135°, purple to gradient-end, white text.

### 8.3 Typography

System font throughout — SwiftUI's default already is SF Pro. **Do not bundle SF Pro manually.**

**Use semantic text styles, not fixed sizes** (§12). The reference scale at the default Dynamic Type size: screen titles `.largeTitle`; section labels `.caption` bold uppercase with ~0.4 tracking; card headline numbers `.title`; row primary `.subheadline` semibold; row secondary `.caption`; error captions `.caption2`.

### 8.4 Reusable components

- **Inline "+ Custom" / "+ New group" chip.** Build **one** component, used for custom categories (per context) and account groups. A dashed chip reveals a text field and a small circular "+" commit button. Enter or tap commits. Commit trims, de-dupes case-insensitively against existing entries, appends, auto-selects the new entry and closes. A blank or whitespace-only submission closes with no error and no addition.
- **Tap-to-cycle picker.** A row whose trailing value advances through a fixed list on tap, wrapping at the end. Used for Account, Currency, Default lead time, Recurring frequency. Fine for lists of five or fewer; use a real menu for anything longer.
- **Toggle row with dynamic helper text.** Purple on, `#E0DCE8` off, with a caption below that updates with state.
- **Segmented pill control.** `#EDEAF3` track, selected segment is a white pill with a subtle shadow.
- **Tag input.** Accepts arbitrary typed tags. No separate "custom tag" flow is needed.
- **Validation visual.** Per §7.11.

---

## 9. Storage, sync and backup

### 9.1 The split

**Size drives this.** A transaction row is a few hundred bytes — five thousand of them is under 2 MB. A compressed receipt photo is 300–500 KB — five hundred receipts is roughly 200 MB. Receipts are about a hundred times the storage of all the financial data combined.

| What | Where | User choice |
|---|---|---|
| Structured data | CloudKit private database via SwiftData | No — always CloudKit |
| Receipt images | iCloud Drive (v1) · Google Drive (v2) | Not in v1 |
| Backup archive | Same location as receipts | Follows receipts |

**Data is not a user choice.** CloudKit's private database counts against the user's iCloud quota, but at a couple of megabytes that is irrelevant even on a free 5 GB tier. In exchange it gives automatic sync, offline writes, conflict handling, and the same `ModelContainer` running unchanged on iPadOS and macOS later. Putting the live database on a third-party drive would mean hand-building a sync engine, conflict resolution and an auth layer to save two megabytes.

**Receipts get a provider choice in v2** because that is where the storage pressure actually is — a user out of iCloud space points receipts elsewhere while their financial data keeps syncing through CloudKit.

### 9.2 v1 scope

**Build the storage layer behind a protocol, with iCloud Drive as the only implementation.**

```swift
protocol ReceiptStore {
    func upload(_ data: Data, named: String, to path: ReceiptPath) async throws -> String
    func download(fileID: String) async throws -> Data
    func delete(fileID: String) async throws
    func list(path: ReceiptPath) async throws -> [RemoteFile]
}
```

**There is no provider picker in v1.** Settings' Cloud backup section shows iCloud status, the manual sync action and the backup interval. **Do not ship a disabled Google Drive option or a "coming soon" row.**

iCloud Drive uses the app's ubiquity container with `NSFileCoordinator` / `NSFilePresenter`. Files appear in the Files app under Chetta Cash. No authentication step.

### 9.3 Folder layout

```
Chetta Cash/
  Receipts/
    2026/
      2026-09/
        2026-09-12_whole-foods_42.10_a3f9.jpg
        manifest.csv
  Backups/
    chetta-cash-backup-2026-09-12.zip
```

Year then month folders. Filenames carry date, merchant slug, amount and a short id derived from the transaction UUID. **The per-month `manifest.csv` maps each filename to its transaction UUID**, so if the database is ever lost the receipts can be re-linked rather than becoming an anonymous pile of images.

### 9.4 Backup archive

A **re-importable backup**, not a flat transaction CSV. A `.zip` containing one CSV per entity — accounts, groups, transactions, recurring rules, statements, vault items, categories, comparisons — plus a `manifest.json` carrying schema version and export date. Every row carries its own `UUID` and its foreign-key UUIDs.

**Receipts are not included in the archive.** They already live in the Receipts folder; duplicating 200 MB into every weekly archive would be wasteful.

Written to `Backups/` on the user's schedule (off / weekly / monthly) plus a manual "Back up now". Keep the last N archives and prune older ones.

**Import matches on `id`**: existing records updated, missing ones inserted. **It must be idempotent** — importing the same backup twice produces no duplicates. Refuse an import whose manifest schema version is newer than the app's. Show a diff summary before committing: "412 transactions, 6 accounts — 3 new, 409 unchanged".

### 9.5 Upload queue and cache

**Queue:** capture → write to local cache → enqueue → background upload → mark `uploaded`. Retry with exponential backoff. Surface a persistent but non-blocking indicator when uploads are pending or failed. A receipt taken offline must be fully usable locally and upload when connectivity returns.

**Cache:** receipts download on demand and cache locally under an LRU size cap. Default **200 MB**, user-adjustable to 100 MB / 500 MB / unlimited. Settings shows current cache size and a "Clear cached receipts" action.

**Safety rule, non-negotiable: a receipt is only evictable once `receiptUploadState == .uploaded`.** Both cache clearing and LRU eviction must skip anything `pending` or `failed`. A photo taken on a plane must never be deletable before it reaches the cloud.

### 9.6 Sync status

One status row, shown in Settings and reused anywhere sync state appears, with four states: up to date (with last-sync time), syncing (with a count), pending uploads, and error (with Retry). Data state comes from `NSPersistentCloudKitContainer` event notifications; receipt state comes from the upload queue.

**"Sync now" must do real work** — flush the upload queue and request a CloudKit fetch. It is not a decorative button.

### 9.7 Receipt OCR

Scope: **amount, merchant and date only, plus the stored image.** No line-item extraction.

Use `VisionKit`'s `DataScannerViewController` for live capture, or `VNRecognizeTextRequest` on a picked image. Parse the total by finding the largest currency-formatted value near a "total" keyword, the date via `NSDataDetector`, the merchant from the topmost text block. **Compress to roughly 1600px on the long edge before storing** — full-resolution camera output triples the storage figures above for no legibility gain.

**Every extracted field is a pre-fill, not a commitment.** Present them in the normal editable form fields with a subtle "from receipt" marker. A failed scan falls back to the empty manual form with a non-blocking message. OCR is the only feature here that fails visibly, so its failure path matters more than its success path.

---

## 10. Notifications

Reminders are computed from `ReminderLeadTime` applied against:

- `VaultItem.trialEndsDate` when `hasTrial`, using `trialReminderLeadTime`, falling back to `AppSettings.defaultReminderLeadTime` when `.useDefault`.
- `VaultItem.warrantyExpiresDate` when `hasWarranty`, same fallback.
- `Account.paymentDueDayOfMonth` when `kind == .card && remindBeforeDueDate`, at a **fixed 3-day lead time**. This one is not configurable — do not add a picker for it.

Schedule with `UNCalendarNotificationTrigger`, not a time-interval trigger, since these are calendar-date based. **Cancel and reschedule** whenever a triggering date or lead time changes. Request authorisation during onboarding step 3.

If the user later revokes permission in iOS Settings, scheduling calls silently no-op. No special handling is needed beyond not double-prompting — iOS will not re-show the permission dialog once answered.

---

## 11. Security

`LocalAuthentication` with `.deviceOwnerAuthentication` — Face ID or Touch ID, falling back to the device passcode.

- Lock on cold launch and on return to foreground after `appLockGraceSeconds` (default 0, i.e. immediately).
- **Obscure the app switcher snapshot** with a blur overlay when `scenePhase == .inactive`.
- A Settings toggle enables or disables it. **Disabling requires authenticating first.**

---

## 12. Accessibility

- **Use semantic text styles**, not fixed `.system(size:)`. The scale in §8.3 is the reference at default Dynamic Type size, not a set of hard values.
- Currency figures use `.monospacedDigit()` so they don't reflow while updating.
- Every icon-only control needs an `accessibilityLabel`.
- **Colour must never be the only signal.** The Spend and Net worth deltas need an arrow or a sign alongside red or green.
- Cap growth with `.dynamicTypeSize(...DynamicTypeSize.accessibility3)` only where a layout genuinely cannot adapt. **Verify the horizontally-scrolling account strip and the Trends cards at accessibility sizes** — those are the two most likely to break.

---

## 13. Out of scope

### 13.1 Decided against — do not build

1. **True multi-currency.** The Settings currency row is a display-label cycler only. No per-account currency, no exchange rates, no home-currency concept. Explicitly declined.
2. **Compare → transaction bridge**, and **renaming a saved comparison.** Explicitly declined. Do not add a "log this as a transaction" action to Compare.
3. **Multiple categories per transaction.** Rejected on arithmetic grounds (§4.8). Tags cover this need.
4. **Hard-deleting accounts or categories.** Both are archived instead.
5. **APR storage or interest calculation.** The user's real statement is the source of truth (§4.6).
6. **iPad and macOS layouts.** iPhone only in v1, though the data layer is built so they cost little later.
7. **Promoting a `TrackedProductRef` into a `VaultItem`.** A future feature, not this one.
8. **A "More" menu beyond Compare**, and a Dashboard quick-action shortcut to Add Account. Both are reasonable follow-ups, neither is committed.
9. **A "Get Balance" App Intent**, and any other spoken read of a figure. A balance read aloud by Siri walks straight past the §11 Face ID gate, to whoever is in the room. The asymmetry that makes the rest of §15 work is that a write reveals nothing while a read reveals everything — so the write intents stay open and this one is not built. If it is ever reconsidered, its `authenticationPolicy` must be **unconditionally** `.requiresLocalDeviceAuthentication`, not conditional on whether the user enabled the app lock: someone who never turned the lock on still has not consented to their balance being spoken.

### 13.2 Deferred to v2 — designed, not built

**Google Drive receipt storage.** The v1 `ReceiptStore` protocol exists precisely so this is an implementation rather than a refactor. Design notes for when it starts:

Use `GoogleSignIn` with the **`drive.file` scope only**. Folder selection goes through the Google Picker — `drive.file` covers app-created files plus anything the user explicitly selects, which delivers "choose your own folder" without the restricted-scope security assessment that full `drive` access requires. Store the resolved folder **id**, never a path, since Drive paths change on rename or move.

Risks to design against:

- **The user can delete the folder.** Drive is a visible file system people tidy up. Trash purges after 30 days.
- **Auth is fragile.** Refresh tokens die on password changes, revocation, security events and long inactivity. Each produces a silent upload failure that must be detected and surfaced.
- **Uploads run in your process.** iCloud transfers are handled by a system daemon that works while the app is dead; Drive uploads use `URLSession` background tasks, scheduled at iOS's discretion. Pending receipts sit unuploaded longer, stressing the §9.5 eviction rule.
- **The free tier is 15 GB shared** across Gmail, Photos and Drive. A user whose iCloud is full is often a heavy Google user whose Drive is also near capacity.
- **Receipts sit outside the app's Face ID lock**, in a third-party cloud — an App Store privacy disclosure and a privacy-policy obligation that iCloud-only does not create.
- **Google changes Drive scope policy regularly.** Re-verify current `drive.file` requirements against Google's own documentation when v2 begins rather than trusting this document.

**The migration path must ship with Drive, not after it.** Switching provider **offers** to move existing receipts rather than moving them automatically — a silent 200 MB transfer over cellular is a bad surprise. Migration runs in the background with progress, verifies each file's checksum at the destination before deleting the source, and is resumable. A version where users can adopt Drive but never leave it is worse than no Drive at all.

### 13.3 Genuinely open — ask before building

Nothing. Every question raised during design has been decided. **If you hit an ambiguity not covered by this document, stop and ask rather than inventing an answer** — that is how the original spec ended up with two conflicting category lists.

---

## 14. Build order

Each phase lists its acceptance criteria. **Do not start a phase until the previous phase's criteria pass.**

### Phase 1 — Models and CloudKit
Models from §5, `ModelContainer` with CloudKit, category seeding from §4.8.

*Passes when:* the container initialises against CloudKit without schema errors, and a record created on one device appears on a second device signed into the same iCloud account.

### Phase 2 — The money engine
§4.1 through §4.4. Balance derivation, the posted filter, the balance cache, transfers, adjustments. **Unit tests first.**

*Passes when:* tests cover — expense reduces balance; income increases it; a card expense increases debt; a transfer moves money without appearing in spend totals; deleting one transfer leg deletes both; a future-dated transaction does not affect balance until its date; an adjustment corrects balance without appearing in spend or income; Available Cash excludes cards while Net Worth includes them.

### Phase 3 — Design system
§8 tokens and components, with Dynamic Type from the start. Empty, loading and error shells.

*Passes when:* a sample screen renders correctly at default and accessibility3 text sizes.

### Phase 4 — Settings ▸ Accounts
§7.6, §7.9, §4.7. Groups, accounts, reorder, inline forms, the close flow.

*Passes when:* an account can be created, edited, reordered, and closed — with closing blocked at a non-zero balance, and closed accounts read-only with the banner.

### Phase 5 — Ledger, transactions and transfers
§7.4, §7.8, §7.11.

*Passes when:* all three transaction types can be created and edited with validation; all three filters combine correctly; transfers and adjustments are absent from the summary totals while visible in the list.

### Phase 6 — Recurring engine
§4.5. **The catch-up and month-end cases are the most likely to be got wrong — test them explicitly.**

*Passes when:* tests cover — exactly one unposted occurrence exists per rule; a rule opened after a two-month gap generates and posts both missed occurrences in order; a monthly rule starting on the 31st fires on 28 February; each of the three edit and delete scopes behaves correctly; end date and occurrence limit both deactivate the rule.

### Phase 7 — Card statements
§4.6.

*Passes when:* a partial payment displays "$60.00 of $100.00 left"; overflow beyond the statement reduces current balance without allocating; the interest prompt appears once per statement and never again after dismissal.

### Phase 8 — Dashboard and Today sheet
§7.1, §7.2. Mostly aggregation once the above exist.

*Passes when:* Available Cash and Net Worth match hand-calculated values; the Today card shows "Nothing due" on a quiet day; the sheet omits empty sections entirely; Trends deltas colour correctly in both directions for both metrics.

### Phase 9 — Smart Vault
§7.3, §7.7, plus both Vault ↔ Ledger links.

*Passes when:* creating a product with "Log as expense" on creates exactly one linked transaction; editing the product's price afterwards does **not** change that transaction; a product with a recurring charge creates a `RecurringRule` that generates real Ledger transactions through the Phase 6 engine.

### Phase 10 — Onboarding
§7.10.

*Passes when:* the flow runs once, both skip paths land on the correct empty states, and multiple accounts can be added in one pass.

### Phase 11 — Notifications
§10.

*Passes when:* a scheduled reminder fires at the correct lead time, and editing the underlying date cancels and reschedules it.

### Phase 12 — Compare and More
§6.2, §7.5. Independent of everything else — buildable in parallel at any point.

*Passes when:* the conversion factors produce correct per-100g and per-100mL figures, and the last remaining comparison cannot be deleted.

### Phase 13 — Storage, backup, app lock, OCR
§9, §11.

*Passes when:* a receipt uploads to iCloud Drive and appears in the Files app in the correct folder; clearing the cache skips a pending upload; a backup exported and re-imported produces zero duplicates; the app lock engages on foreground and blurs the switcher snapshot.

### Phase 14 — Polish
Loading, empty and error states wired to real query results across every screen. Verify no "Preview" state-cycling control survives anywhere (§7.0).

---

## 15. Shortcuts and App Intents

The app exposes a small set of App Intents so an expense can be recorded without opening
it — from Siri, from the Shortcuts app, or from an automation that fires off a bank
notification. This section is the contract. It was written after the first implementation
shipped, which is why some of the rules below *revise* what that code did.

### 15.1 Where the intents live

**In the app target, not an extension.** App Intents run inside the app's own process
whether or not a window is on screen, so the intent and the UI reach one
`AppDependencies` through `AppEnvironment.shared()`. An App Intents extension would be a
separate process and would need an App Group entitlement to see the same store — and two
`ModelContainer`s over one store file is how SwiftData gets corrupted. Do not move them.

### 15.2 The intents

| Intent | Kind | Runs while the phone is locked |
| --- | --- | --- |
| Add Expense | write | yes |
| Log Income | write | yes |
| Transfer | write | yes |
| Find Transactions | read | **no** |

Get Balance is **decided against** — see §13.1.9.

**Deleting is not offered either.** `TransactionRepository.delete(id:)` cascades: both legs of
a transfer, every product on the purchase, and those products' billing rules. A spoken
confirmation naming an amount and a merchant cannot honestly describe that, and it would be
the only destructive action on a surface that runs without authentication — where the
asymmetry in §15.3 stops holding, because a write adds a row the user can see and remove
while a delete removes rows they cannot then restore. It would also need a confirmation, so
it could never run headless: the only case it served was one where the user is holding the
phone and could open the app instead.

### 15.3 The lock rule

Writing and reading are not the same risk, and the app lock (§11) treats them
differently.

**A write reveals nothing.** Someone holding a locked phone who says "add a $4 expense to
Chetta Cash" learns nothing they did not already know; they have merely made a mess that
the owner can delete. Requiring Face ID per coffee would destroy the one thing a
background intent is for. So every write intent is `.alwaysAllowed`.

**A read reveals everything.** Account names, card digits, balances and transaction
history are exactly what the Face ID gate exists to hide, and Siri will read them aloud
to whoever is in the room. So:

- Every read intent is `.requiresAuthentication` — the device must be unlocked.
- `AccountEntityQuery` returns **nothing** from `suggestedEntities()` and
  `entities(matching:)` while the app lock is on and protected data is unavailable. The
  test is `UIApplication.isProtectedDataAvailable`, which answers "is the phone unlocked
  right now" without prompting — never `LAContext` from inside a picker.
- `entities(for:)` is exempt. It confirms an identifier the caller already holds, leaks
  nothing new, and blanking it would break every saved Shortcut on a locked phone —
  including the write the owner wants.

The decision is stated once, purely, in `ShortcutPrivacyPolicy`.

### 15.4 Resolving the account

Three things can name the account: the picker in the Shortcuts editor, four card digits,
or a name as text. They are consulted **number, then name, then picker**.

**Why text outranks the picker.** A Shortcut is built once and run for months, and its
account picker is frozen at the moment it was built. A number or a name arrives with the
entry — off a Wallet card, a bank notification, or a field typed at run time — so it
describes *this* purchase where the picker only describes its author's intent long ago.

**Why the number outranks the name.** Four digits identify one card exactly. A name is
what a person calls it, and two cards from one bank are often named nearly the same.

**Four digits may create an account. A name may not.** Digits that match nothing mean a
card the user demonstrably holds and has not set up yet, so creating it with a zero
opening balance adds no phantom money — `BalanceEngine` derives the balance from that
zero plus whatever is recorded against it. A name that matches nothing is far more often
a typo, and creating from it mints a phantom credit card whose balance is
negative-when-owed and whose Net Worth contribution is wrong until someone notices. The
name still christens whatever the number creates.

### 15.5 Park on doubt — never refuse, never guess

**An entry whose account cannot be resolved is still written.** It is stored with no
account and surfaced in the Today digest for the user to assign by hand.

This applies to every doubt: a picked account that has since been deleted, a picked
account that has been closed, digits or a name matching several accounts, a name matching
none, a number too short to identify a card.

The reasoning is that the three available answers are not equally bad. *Guessing* posts
real money to the wrong balance and is silent. *Refusing* loses what the user told the
app, and from a headless automation it loses it with no one watching. *Parking* keeps the
entry, keeps it honest about what is unknown, and puts it somewhere the user will see it.

Consequences, all deliberate:

- A parked entry is exactly `accountID == nil`. Nothing else in the app produces one —
  the transaction form requires an account and statement import always has one — so no
  extra field or tag is needed to recognise it.
- A parked expense **counts toward spend totals** (§4.2 filters on posted and type, not
  on account) and cannot affect any balance. So Spend and Available Cash disagree until
  it is assigned. That is honest — the money was spent, the app does not know from where
  — and it is why the Today card has to be loud about it.
- **Transfers are the one exception.** An unresolved leg has no meaning, so a transfer
  refuses and says which side it could not resolve.

### 15.6 Duplicates

A Siri retry, a re-tapped Shortcut and an automation firing twice all look identical to
the app. An entry is treated as a repeat of one already stored when all three hold:

1. It shares a `TransactionFingerprint` with it — same account, same day, same signed
   amount, same normalised merchant, which is the definition of the same purchase.
2. The two are within `QuickExpenseDuplicateGuard.window` (two minutes). The
   fingerprint's day granularity alone is too coarse: two genuine $4.50 coffees at one
   shop on one day would collide.
3. The stored row carries the `shortcut` origin tag. The guard must never suppress a
   twin the user typed in by hand.

**A repeat is not an error.** The intent returns the transaction that already exists and
says so. An error makes an automation look broken, and returning the existing entry keeps
a chained Shortcut working on a retry. `Allow duplicate` is there for someone who really
did buy two identical coffees.

### 15.7 What the intent says back

The spoken result names everything the run did that the user cannot see, because a
background intent is the one place where a side effect has no screen to appear on:

- The amount and the merchant, always.
- That an account was **created**, and its name. A new card appearing unannounced in the
  accounts list reads as a bug rather than as what was asked for.
- That the entry was **parked**, and why, so the Today card is not a surprise.
- That the entry is **dated in the future** and will not move the balance until then. The
  row is a legitimate §4.2 construct and is not clamped — the defect was the silence.
- That a **merchant pin** was created. `Remember category` defaults on, and the pin then
  outranks what every later run of that Shortcut passes, so it has to be said out loud
  once.
- That an entry was recognised as an **already-logged repeat**.

### 15.8 Limits

`QuickEntryLimits` states them once, in Domain, and the planner enforces them:

- A single entry is capped well below what `Int` cents can hold. An unbounded amount is a
  typo away from wrecking every chart axis and total in the app.
- A merchant name is required and capped. An empty merchant also normalises to an empty
  merchant key, which silently defeats the pin, so it is refused rather than accepted and
  papered over in the dialog.
- Receipt pages are capped by count and by total bytes. A background intent has tight
  memory limits and a jetsam mid-write is worse than a refusal.

### 15.9 Everything else

The Shortcut path is not a side door. Everything else in this document applies to it
unchanged: money is `Int` cents (§2), the posted filter (§4.2), transfer legs and
adjustments excluded from totals (§4.3, §4.4), a receipt belongs to the transaction and
several files are its pages (§9.3), and only the last four digits of a card are ever
stored (§9.7).

---

*Chetta Cash v1.0 implementation plan — complete and self-contained. Design canvas reference: `https://claude.ai/code/artifact/8f3e6ab0-7628-42e9-bbc8-85079920e340` (Version 25), useful for visual detail only; where the canvas and this document disagree, this document wins.*
