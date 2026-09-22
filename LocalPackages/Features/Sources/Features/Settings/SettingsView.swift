import SwiftUI
import AppIntents
import Domain

/// The Settings screen (§7.6).
///
/// Creating is group-first: "+ New group" pushes ``CreateGroupView``, and accounts are
/// added from a specific group's card through ``AddAccountSheet``, which is already
/// scoped to that group. This deliberately departs from §7.6's "inline forms, not
/// sheets" — that rule predated the group page, and Settings already opens the Edit,
/// Close and Correct sheets, so creation was the only self-contained part left.
///
/// The Cloud backup card (§9) and the Security card (§11) appear when the app wires
/// storage and the lock in; the previews used by tests omit them.
public struct SettingsView: View {
    /// The screen's view model.
    @State private var model: SettingsViewModel
    /// The account whose Edit sheet is open.
    @State private var editingAccount: Domain.Account?
    /// Whether the group page is pushed.
    @State private var isCreatingGroup = false
    /// The group whose add-account sheet is open.
    @State private var addingToGroup: Domain.AccountGroup?
    /// The group whose rename sheet is open.
    @State private var renamingGroup: Domain.AccountGroup?
    /// Whether the merchant mapping screen is pushed.
    @State private var isMappingMerchants = false
    /// Whether the feature-flag menu is pushed.
    @State private var isShowingFeatureFlags = false

    /// The Siri tip for the Add Expense intent, supplied by the app (§10).
    ///
    /// Type-erased rather than generic because the intent itself lives in the app
    /// target — `Features` must not know it exists — and making the whole screen
    /// generic over the tip would push that parameter through ``RootTabView`` too.
    private let siriTip: AnyView?

    /// Creates the screen.
    /// - Parameters:
    ///   - model: The screen's view model.
    ///   - siriTip: A tip teaching the Add Expense phrase, if the app supplies one.
    public init(model: SettingsViewModel, siriTip: AnyView? = nil) {
        _model = State(initialValue: model)
        self.siriTip = siriTip
    }

    /// The view body.
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let errorMessage = model.errorMessage {
                        ErrorBanner(message: errorMessage) {
                            Task { await model.load() }
                        }
                    }
                    generalCard
                    shortcutsCard
                    if model.storage != nil { CloudBackupCard(model: model) }
                    if model.canImportStatements { StatementImportCard(model: model) }
                    if let appLock = model.appLock { SecurityCard(controller: appLock) }
                    if model.showsFeatureFlags {
                        FeatureFlagsCard { isShowingFeatureFlags = true }
                    }
                    accountsSection
                }
                .padding(16)
            }
            .background(Palette.appBackground)
            .navigationTitle("Settings")
            .navigationDestination(isPresented: $isShowingFeatureFlags) {
                FeatureFlagsView(model: model)
            }
            .navigationDestination(isPresented: $isMappingMerchants) {
                if let mappingModel = model.makeMerchantMappingModel() {
                    MerchantMappingView(model: mappingModel)
                }
            }
            .navigationDestination(isPresented: $isCreatingGroup) {
                CreateGroupView(
                    existingNames: model.groups.map(\.name),
                    onCreate: create(named:),
                    onCancel: { isCreatingGroup = false }
                )
                .navigationTitle("New group")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task { await model.load() }
        .sheet(item: $editingAccount) { account in
            EditAccountSheet(account: account, model: model)
        }
        .sheet(item: $addingToGroup) { group in
            AddAccountSheet(
                group: group,
                sortIndex: model.nextSortIndex(inGroup: group.id)
            ) { account in
                await model.save(account)
                return model.errorMessage == nil
            }
        }
        .sheet(item: $renamingGroup) { group in
            RenameGroupSheet(group: group, model: model)
        }
    }

    /// Saves a new group, then opens its add-account sheet so the pair reads as one flow.
    /// - Parameter name: The group's display name.
    private func create(named name: String) {
        Task {
            guard let group = await model.addGroup(named: name) else { return }
            isCreatingGroup = false
            addingToGroup = group
        }
    }

    /// Siri, Shortcuts, and the merchant mappings a Shortcut relies on (§4.8, §10).
    private var shortcutsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Siri & Shortcuts").sectionLabel()
            CardContainer {
                VStack(alignment: .leading, spacing: 16) {
                    if let siriTip { siriTip }
                    Text(
                        "Log an expense without opening the app. Ask Siri, or add the Add Expense action to a Shortcut."
                    )
                        .font(Typography.rowSecondary)
                        .foregroundStyle(Palette.textSecondary)
                    ShortcutsLink()
                    if model.canMapMerchants {
                        Divider().overlay(Palette.borderSubtle)
                        Button { isMappingMerchants = true } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Merchant categories").font(Typography.rowPrimary)
                                    Text("Always file a shop the same way")
                                        .font(Typography.rowSecondary)
                                        .foregroundStyle(Palette.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .tappableSurface()
                    }
                }
            }
        }
    }

    /// Currency and default reminder lead time (§7.6).
    private var generalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("General").sectionLabel()
            CardContainer {
                VStack(alignment: .leading, spacing: 16) {
                    OptionPickerRow(
                        label: "Currency",
                        options: AppSettings.selectableCurrencyCodes,
                        selection: Binding(
                            get: { model.settings.currencyCode },
                            set: { model.settings.currencyCode = $0; model.persistSettings() }
                        ),
                        display: { $0 },
                        subtitle: { CurrencyFormatter.displayName(for: $0) }
                    )
                    Divider().overlay(Palette.borderSubtle)
                    OptionPickerRow(
                        label: "Default alert lead time",
                        options: AppSettings.selectableDefaultLeadTimes,
                        selection: Binding(
                            get: { model.settings.defaultReminderLeadTime },
                            set: { model.settings.defaultReminderLeadTime = $0; model.persistSettings() }
                        ),
                        display: \.settingsLabel,
                        subtitle: \.settingsDetail
                    )
                }
            }
        }
    }

    /// Net Worth summary, group blocks and the two inline triggers (§7.6).
    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Accounts").sectionLabel()
            if model.isLoading {
                SkeletonCard()
            } else {
                CardContainer {
                    HStack {
                        Text("Net Worth")
                            .font(Typography.rowPrimary)
                            .foregroundStyle(Palette.textPrimary)
                        Spacer(minLength: 8)
                        Text(money(model.netWorthCents))
                            .moneyText(Typography.rowPrimary)
                            .foregroundStyle(Palette.textPrimary)
                    }
                }
                if model.groups.isEmpty && model.accounts.isEmpty {
                    CardContainer {
                        EmptyStateView(
                            icon: "wallet.bifold",
                            title: "No accounts yet",
                            message: "Groups hold your accounts — a bank, or a part of "
                                   + "your life. Start with one.",
                            actionTitle: "Create a group",
                            action: { isCreatingGroup = true }
                        )
                    }
                }
                ForEach(model.groups) { group in
                    GroupBlock(
                        group: group,
                        model: model,
                        onSelect: { editingAccount = $0 },
                        onAddAccount: { addingToGroup = group },
                        onRename: { renamingGroup = group }
                    )
                }
                dashedTrigger("+ New group") { isCreatingGroup = true }
            }
        }
    }

    /// A dashed-border, full-width trigger.
    /// - Parameters:
    ///   - title: The trigger's label.
    ///   - action: What tapping it does.
    /// - Returns: The trigger view.
    private func dashedTrigger(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Typography.rowPrimary)
                .foregroundStyle(Palette.brandPurple)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            Palette.dashedAccent,
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                        )
                }
                .tappableSurface()
        }
        .buttonStyle(.plain)
    }

    /// Formats an amount using the display currency.
    /// - Parameter cents: The amount in cents.
    /// - Returns: The formatted string.
    private func money(_ cents: Int) -> String {
        CurrencyFormatter.string(fromCents: cents, currencyCode: model.settings.currencyCode)
    }
}

/// Display names for the lead times the Settings row offers.
extension ReminderLeadTime {
    /// The label shown in Settings.
    var settingsLabel: String {
        switch self {
        case .useDefault: return "Use default"
        case .off: return "Off"
        case .sameDay: return "Same day"
        case .oneDayBefore: return "1 day before"
        case .threeDaysBefore: return "3 days before"
        case .oneWeekBefore: return "1 week before"
        }
    }

    /// The explanatory line shown beneath ``settingsLabel`` in the picker.
    ///
    /// ``ReminderLeadTime/useDefault`` has none here: what the default resolves to is
    /// known only where the setting is read, so that caller supplies its own subtitle.
    var settingsDetail: String? {
        switch self {
        case .useDefault: return nil
        case .off: return "No reminder at all"
        case .sameDay: return "On the morning of the date"
        case .oneDayBefore: return "A day ahead of the date"
        case .threeDaysBefore: return "Three days ahead of the date"
        case .oneWeekBefore: return "A week ahead of the date"
        }
    }
}
