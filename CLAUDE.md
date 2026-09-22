# CLAUDE.md — Chetta Cash v1.0 Execution Instructions

## Build & Test Commands
- **Fast Domain Loop** (no simulator, ~1s): `swift test --package-path LocalPackages/Domain`
- **Fast Data Loop**: `swift test --package-path LocalPackages/Data`
- **Regenerate Project** (after adding files or targets): `./Scripts/generate.sh` — use this, NOT bare `xcodegen generate`, which wipes the hand-written test schemes.
- **Build All Modules**: `xcodebuild -workspace ChettaCash.xcworkspace -scheme ChettaCashApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
- **Run Unit Tests**: `xcodebuild test -workspace ChettaCash.xcworkspace -scheme DomainTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
- **Run SwiftLint**: `swiftlint lint` — run it from the repo root and do NOT pass `--config`. Auto-discovery finds `.swiftlint.yml` at the root and also honours the nested configs under `LocalPackages/*/Tests`; passing `--config` explicitly makes SwiftLint ignore nested configs, which floods the output with `missing_docs` warnings on test declarations.

## Tooling
Requires `brew install xcodegen swiftlint`. The Xcode project and workspace are generated from `project.yml` and are not authoritative — edit `project.yml` and regenerate. The `DomainTests` and `DataTests` schemes are hand-written because XcodeGen cannot declare SPM test targets in a scheme's test action. They live in `Schemes/` and `./Scripts/generate.sh` copies them back into the project bundle after every generation.

## Project Structure & Module Boundaries
- `LocalPackages/Domain`: Pure Swift only. ZERO dependencies on SwiftUI, UIKit, SwiftData, CoreData, or Data module. Contains Entities, Protocols, and Business Engines (`BalanceEngine`, `TotalsEngine`, `TransferFactory`, `AdjustmentFactory`, `RecurringEngine`). Entities are value types carrying UUID foreign keys (`Transaction.accountID`), never object graphs — this is what keeps the module acyclic and `Sendable`.
- `LocalPackages/Data`: SwiftData models, CloudKit container, `ReceiptStore` implementations, persistence mapping. Depends ONLY on `Domain`. Persistent types are suffixed `Record` (`AccountRecord`, `TransactionRecord`) so they never collide with the Domain value type of the same concept. Repositories are `@ModelActor` actors.
- `LocalPackages/Features`: SwiftUI Views, `@Observable` ViewModels. Depends ONLY on `Domain`. NO direct dependency on `Data`.
- `App`: Thin host project for entry point, SceneDelegate, and root Dependency Injection wiring.

## Critical Business & Financial Rules (MUST FOLLOW)
1. **Money Calculations**:
   - Store money as `Int` cents everywhere in models (`100` = $1.00). NEVER use `Double` or `Float` for currency storage.
   - Balances are derived, never hard-coded as source of truth (`Account.cachedBalanceCents` is a denormalized cache).
   - Card account balances are **negative when money is owed**. A card payment is a `transferIn` that moves balance toward 0.
2. **Posted vs. Future Transactions**:
   - Filter all aggregate queries with `date <= Date.now`. Future transactions exist in DB but must not affect balances, spend totals, or trends.
3. **Transfers & Adjustments**:
   - Transfers generate two legs sharing a `transferGroupID`. Editing/deleting one leg MUST edit/delete both.
   - Both legs of a transfer and all `adjustment` type transactions MUST be excluded from spend, income, and trend totals.
4. **Products & Receipts**:
   - A `Product` is ALWAYS part of a `Transaction` (`Product.transactionID` is non-optional). Never create a product on its own — something acquired for free gets a **zero-cent transaction**, which moves no balance and counts toward no total.
   - Products carry NO price, account or date. Those live on the purchase; join the two with `ProductListing.make(product:purchase:)` before filtering or displaying.
   - The **receipt belongs to the transaction**, not the product: one receipt covers however many products that purchase contained. Products take `notes` instead.
   - Deleting a transaction cascades to its products and their recurring rules; deleting a product leaves the purchase and its receipt alone.
5. **Naming**:
   - SwiftUI declares its own `Transaction` type. In any file that imports SwiftUI, always write `Domain.Transaction`.
6. **Access Modifiers**:
   - Swift defaults to `internal`. Explicitly declare `public` on classes, structs, protocols, initializers, and methods exposed across local SPM modules.

## Concurrency & Code Standards
- **Concurrency**: Use Swift Concurrency (`async/await`, `Task`, `@MainActor`). Enforce Swift 6 Strict Concurrency (`SWIFT_STRICT_CONCURRENCY = complete`).
- **ViewModels**: Mark all ViewModels with `@MainActor`. Use `@Observable` macro (iOS 17+). Avoid `UIKit` imports in ViewModels.
- **Safety**: NEVER use force casting (`as!`) or force unwrapping (`!`). Use conditional unwrapping (`if let`, `guard let`) or throw domain errors.
- **Documentation**: Provide concise DocC (`///`) comments for all public and internal functions, detailing parameters, return values, and thrown errors.

## Git & Workflow Hygiene
- Make surgical edits. Do not rewrite whole files when fixing minor issues.
- Run tests (`xcodebuild test`) and SwiftLint before reporting a task as complete.

## Known Gotchas
- **Deleting a SwiftData record does not immediately update its inverse relationship array.** Any balance-cache rebuild must `save()` the delete first, or it recomputes from stale history. See `SwiftDataTransactionRepository.delete(id:)`.
- **`#expect` must not wrap a throwing or `rethrows` call** (`#expect(try await ...)`, `#expect(x.allSatisfy(...))`). Assign to a local first, then assert on it. Sometimes this is a compile error; in an async test it can instead crash the whole test bundle with signal 11, which looks like a SwiftData fault rather than a test-syntax problem.
- **Test fakes must upsert by `id`, like the SwiftData repositories do.** A fake that appends on save makes an edit look like a duplicate and fails tests that are actually correct.
- **CloudKit is currently off** (`ModelContainerFactory.make(cloudKit:)` defaults to `false`) pending a signing team and container identifier. The schema already satisfies every CloudKit constraint, so enabling it is a one-line change.

## SwiftUI UI & Keyboard Performance Rules

To ensure 60/120 FPS UI smoothness, sub-millisecond keyboard response, and zero frame drops:

1. **No Heavy String Computations in Body Properties**:
   - NEVER call `.trimmingCharacters()`, `.lowercased()`, `NSPredicate`, or regex matching directly inside dynamic `body` properties or computed properties accessed by `body`.
   - Pre-compute string operations outside the body or cache normalized models in a `Set` or `@Observable` ViewModel.

2. **Optimize `ForEach` Iterations & Comparisons**:
   - Avoid executing string comparison algorithms (e.g., `caseInsensitiveCompare`) inside `ForEach` closures.
   - Extract search terms or lowercased strings into local variables *above* the list/layout container before rendering child views.

3. **Explicit Keyboard & Focus Management**:
   - Always manage `TextField` focus using `@FocusState`.
   - When presenting a form or auto-opening the keyboard, defer focus activation using `DispatchQueue.main.asyncAfter(deadline: .now() + 0.15)` inside `.onAppear` to allow the navigation transition to complete before requesting the software keyboard.

4. **Minimize View Body Re-evaluations**:
   - Keep view bodies granular. Break large view trees into smaller, isolated `View` structs so SwiftUI's diffing engine only re-evaluates subviews whose inputs actually change.
   - Prefer passing primitive bindings (`Binding<String>`) or value types down to child views rather than passing entire parent state objects.

5. **Strict Main Thread Boundaries**:
   - Mark all ViewModels with `@MainActor`.
   - Never perform synchronous file I/O, heavy JSON parsing, or SwiftData context queries directly on the `@MainActor`. Offload heavy processing to background tasks/actors before updating published state.
