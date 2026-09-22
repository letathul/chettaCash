import Foundation
import Domain

/// One Ledger row, with every string already rendered (§7.4).
///
/// Built once per reload or filter change by ``LedgerViewModel``, rather than derived
/// inside the row's `body`. Rendering it used to cost a currency format plus two linear
/// lookups through `accounts` and `categories` **per row, per body pass** — work the
/// list repeated on every keystroke elsewhere on the screen.
struct LedgerRowModel: Identifiable, Hashable {
    /// The row's identity, which is the item's.
    let id: UUID
    /// The row's primary line — a merchant, or "Chequing → Visa" for a transfer.
    let title: String
    /// The "Category · Account" subline.
    let subtitle: String
    /// The signed, currency-formatted amount.
    let amountText: String
    /// Which palette entry the amount reads in.
    let tone: AmountTone
    /// The SF Symbol drawn inside the avatar.
    let glyph: String
    /// The avatar's tint.
    let avatar: RowAvatar
    /// Whether the row came from a recurring rule, which earns the RECURRING badge.
    let isRecurring: Bool
    /// Whether the transaction may be edited — not so when it touches a closed account.
    ///
    /// Every row opens its detail screen; this decides only whether that screen offers
    /// an Edit button (§4.7, §7.4).
    let isEditable: Bool
    /// The transaction a tap opens, which is its read-only detail.
    let editableTransaction: Domain.Transaction
}

/// One calendar day of posted rows (§7.4).
struct LedgerDay: Identifiable, Hashable {
    /// The day's start, which is the group's identity.
    let day: Date
    /// That day's rows, newest first.
    let rows: [LedgerRowModel]

    /// The group's identity, for `ForEach`.
    var id: Date { day }
}
