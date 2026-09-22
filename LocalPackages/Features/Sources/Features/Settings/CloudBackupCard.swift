import SwiftUI
import Domain

/// Where storage stands right now (§9.6).
public struct SyncStatus: Equatable, Sendable {
    /// The four states §9.6 names.
    public enum State: Equatable, Sendable {
        /// Everything is stored and nothing is waiting.
        case upToDate(lastSynced: Date?)
        /// Work is in progress.
        case syncing(count: Int)
        /// Receipts are waiting to upload.
        case pendingUploads(count: Int)
        /// Something failed and can be retried.
        case error(message: String)
    }

    /// The current state.
    public var state: State
    /// Whether files are going to iCloud Drive rather than on-device storage.
    public var isUsingCloud: Bool

    /// Creates a status.
    /// - Parameters:
    ///   - state: The current state.
    ///   - isUsingCloud: Whether iCloud Drive is in use.
    public init(state: State, isUsingCloud: Bool) {
        self.state = state
        self.isUsingCloud = isUsingCloud
    }
}

/// The Cloud backup card in Settings (§7.6 item 3, §9.6).
///
/// There is deliberately **no provider picker** and no disabled "Google Drive coming
/// soon" row: iCloud Drive is the only v1 implementation (§9.2).
struct CloudBackupCard: View {
    /// The screen's view model.
    let model: SettingsViewModel

    /// The view body.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cloud backup").sectionLabel()
            CardContainer {
                VStack(alignment: .leading, spacing: 16) {
                    statusRow
                    Divider().overlay(Palette.borderSubtle)
                    OptionPickerRow(
                        label: "Back up",
                        options: BackupInterval.allCases,
                        selection: Binding(
                            get: { model.settings.backupInterval },
                            set: { model.settings.backupInterval = $0; model.persistSettings() }
                        ),
                        display: \.settingsLabel,
                        subtitle: \.settingsDetail
                    )
                    Divider().overlay(Palette.borderSubtle)
                    actionRow(
                        "Back up now",
                        detail: model.lastBackupSummary,
                        isBusy: model.isBackingUp
                    ) {
                        Task { await model.backUpNow() }
                    }
                    Divider().overlay(Palette.borderSubtle)
                    actionRow(
                        "Sync now",
                        detail: "Flushes pending uploads and refreshes status.",
                        isBusy: model.isSyncing
                    ) {
                        Task { await model.syncNow() }
                    }
                    Divider().overlay(Palette.borderSubtle)
                    cacheRow
                }
            }
        }
    }

    /// The one status row §9.6 specifies, reused wherever sync state appears.
    private var statusRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: model.syncStatus.symbol)
                .font(.callout)
                .foregroundStyle(model.syncStatus.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.syncStatus.headline)
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.textPrimary)
                Text(model.syncStatus.detail)
                    .font(Typography.rowSecondary)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 8)
            if case .error = model.syncStatus.state {
                Button("Retry") { Task { await model.syncNow() } }
                    .font(Typography.rowSecondary.weight(.semibold))
                    .foregroundStyle(Palette.brandPurple)
            }
        }
    }

    /// The cache size and the clear action (§9.5).
    private var cacheRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            OptionPickerRow(
                label: "Receipt cache cap",
                options: ReceiptCachePolicy.selectableCapsMB,
                selection: Binding(
                    get: { model.settings.receiptCacheCapMB == 0 ? nil : model.settings.receiptCacheCapMB },
                    set: { model.settings.receiptCacheCapMB = $0 ?? 0; model.persistSettings() }
                ),
                display: { $0.map { "\($0) MB" } ?? "Unlimited" },
                subtitle: { cap in
                    cap == nil
                        ? "Never clears cached receipts"
                        : "Clears the oldest uploaded receipts past this size"
                }
            )
            HStack {
                Text(model.cacheSummary)
                    .font(Typography.rowSecondary)
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 8)
                Button("Clear cached receipts") { Task { await model.clearReceiptCache() } }
                    .font(Typography.rowSecondary.weight(.semibold))
                    .foregroundStyle(Palette.brandPurple)
            }
            Text("Receipts still waiting to upload are never cleared.")
                .font(Typography.errorCaption)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    /// A tappable action row with a caption.
    /// - Parameters:
    ///   - title: The action's label.
    ///   - detail: What it does, or its last result.
    ///   - isBusy: Whether it is running.
    ///   - action: What to run.
    /// - Returns: The row view.
    private func actionRow(
        _ title: String,
        detail: String,
        isBusy: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isBusy ? "\(title)…" : title)
                        .font(Typography.rowPrimary)
                        .foregroundStyle(Palette.brandPurple)
                    Text(detail)
                        .font(Typography.rowSecondary)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
            }
            .tappableSurface()
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }
}

/// Display names for the backup intervals.
extension BackupInterval {
    /// The label shown in Settings.
    var settingsLabel: String {
        switch self {
        case .off: return "Off"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    /// The explanatory line shown beneath ``settingsLabel`` in the picker.
    var settingsDetail: String? {
        switch self {
        case .off: return "Only when you tap Back up now"
        case .weekly: return "Writes an archive once a week"
        case .monthly: return "Writes an archive once a month"
        }
    }
}

/// Presentation for the sync status row (§9.6).
extension SyncStatus {
    /// The row's headline.
    var headline: String {
        switch state {
        case .upToDate: return isUsingCloud ? "iCloud Drive · up to date" : "On this iPhone"
        case .syncing: return "Syncing"
        case .pendingUploads: return "Waiting to upload"
        case .error: return "Sync problem"
        }
    }

    /// The row's explanatory line.
    var detail: String {
        switch state {
        case .upToDate(let lastSynced):
            guard let lastSynced else {
                return isUsingCloud
                    ? "Receipts and backups are stored in iCloud Drive."
                    : "iCloud Drive is unavailable, so files are stored on this iPhone."
            }
            return "Last synced " + lastSynced.formatted(.relative(presentation: .named)) + "."
        case .syncing(let count):
            return "\(count) \(count == 1 ? "file" : "files") in progress."
        case .pendingUploads(let count):
            return "\(count) \(count == 1 ? "receipt" : "receipts") waiting for a connection."
        case .error(let message):
            return message
        }
    }

    /// The row's icon.
    var symbol: String {
        switch state {
        case .upToDate: return isUsingCloud ? "checkmark.icloud" : "iphone"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .pendingUploads: return "icloud.and.arrow.up"
        case .error: return "exclamationmark.icloud"
        }
    }

    /// The row's tint.
    var tint: Color {
        switch state {
        case .upToDate: return Palette.positiveGreen
        case .syncing: return Palette.brandPurple
        case .pendingUploads: return Palette.attentionAmber
        case .error: return Palette.negativeRed
        }
    }
}
