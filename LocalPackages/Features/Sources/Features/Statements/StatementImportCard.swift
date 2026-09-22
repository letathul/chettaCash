import SwiftUI
import UniformTypeIdentifiers
import Domain

/// The Import statement card in Settings (§7.6).
///
/// Owns its own presentation state rather than pushing it up into ``SettingsView``, which is
/// both better encapsulation and what keeps that file within the 300-line limit.
///
/// **One destination, not four.** The import used to chain a picker, a card step, a duplicate
/// wizard and a summary, committing before the first of them appeared. Now picking a file
/// opens ``StatementReviewView`` and the user stays there until they approve or cancel.
struct StatementImportCard: View {
    /// The Settings screen's view model, which holds the import model across dismissals.
    let model: SettingsViewModel

    /// Whether the document picker is open.
    @State private var isPicking = false
    /// Whether the review screen is open.
    @State private var isReviewing = false
    /// Whether the summary is open.
    @State private var isShowingSummary = false

    /// The view body.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Statements").sectionLabel()
            CardContainer {
                VStack(alignment: .leading, spacing: 16) {
                    importRow
                    if let importModel = model.pendingImport, importModel.hasPendingReview {
                        Divider().overlay(Palette.borderSubtle)
                        resumeRow(importModel)
                    } else if model.pendingImport?.outcome != nil {
                        Divider().overlay(Palette.borderSubtle)
                        summaryRow
                    }
                    if let message = model.pendingImport?.errorMessage {
                        Divider().overlay(Palette.borderSubtle)
                        Text(message)
                            .font(Typography.rowSecondary)
                            .foregroundStyle(Palette.negativeRed)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isPicking,
            allowedContentTypes: [.pdf, .image, .commaSeparatedText, .tabSeparatedText, .text],
            allowsMultipleSelection: false
        ) { result in
            handle(result)
        }
        .fullScreenCover(isPresented: $isReviewing, onDismiss: showSummaryIfFinished) {
            if let importModel = model.pendingImport {
                StatementReviewView(model: importModel)
            }
        }
        .sheet(isPresented: $isShowingSummary) {
            if let outcome = model.pendingImport?.outcome {
                StatementImportSummarySheet(outcome: outcome, pendingTitle: nil, onResolve: {})
            }
        }
    }

    /// The row that opens the document picker.
    private var importRow: some View {
        Button {
            isPicking = true
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import statement…")
                        .font(Typography.rowPrimary)
                        .foregroundStyle(Palette.brandPurple)
                    Text(
                        "Read a card statement PDF or a CSV export. You review every row "
                            + "before anything is added, and it all stays on this device."
                    )
                    .font(Typography.rowSecondary)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
            }
            .tappableSurface()
        }
        .buttonStyle(.plain)
    }

    /// The amber row offering to finish a review the user left part-way.
    ///
    /// Styled like ``InterestPromptCard``, the app's existing "this needs you" affordance, so
    /// an unfinished import reads the same way an unanswered statement prompt does.
    ///
    /// - Parameter importModel: The import holding the unfinished review.
    /// - Returns: The row.
    private func resumeRow(_ importModel: StatementImportViewModel) -> some View {
        Button {
            isReviewing = true
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(Palette.attentionAmber)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(importModel.resumeButtonTitle)
                        .font(Typography.rowPrimary)
                        .foregroundStyle(Palette.textPrimary)
                    Text("Nothing has been added yet.")
                        .font(Typography.rowSecondary)
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").foregroundStyle(Palette.textSecondary)
            }
            .tappableSurface()
        }
        .buttonStyle(.plain)
    }

    /// The row offering the last import's summary again.
    private var summaryRow: some View {
        Button {
            isShowingSummary = true
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("View last import summary")
                        .font(Typography.rowPrimary)
                        .foregroundStyle(Palette.textPrimary)
                    Text(model.pendingImport?.outcome?.summary ?? "")
                        .font(Typography.rowSecondary)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").foregroundStyle(Palette.textSecondary)
            }
            .tappableSurface()
        }
        .buttonStyle(.plain)
    }

    /// The extensions read as a delimited export rather than as a document.
    private static let delimitedExtensions: Set<String> = ["csv", "tsv", "txt", "tab"]

    /// What to hand the importer for a picked file.
    ///
    /// Decided by extension because that is what the user's file actually carries: a bank
    /// export is routinely served as `public.data` or `text/plain`, so trusting the content
    /// type alone would send half of them down the PDF path.
    ///
    /// - Parameter url: The picked file.
    /// - Returns: The source, or `nil` when the file could not be read at all.
    private static func source(for url: URL) -> StatementFileSource? {
        guard delimitedExtensions.contains(url.pathExtension.lowercased()) else {
            return .url(url)
        }
        guard let text = try? StatementFileReader.text(at: url) else { return nil }
        return .csv(text)
    }

    /// Starts an import from the picked file.
    ///
    /// The review screen opens *before* the reading finishes, so the user watches it happen
    /// rather than staring at a spinner in Settings and then being handed a result.
    ///
    /// - Parameter result: What the document picker returned.
    private func handle(_ result: Result<[URL], any Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard let importModel = model.makeStatementImportModel() else { return }
        guard let source = Self.source(for: url) else {
            importModel.errorMessage = StatementImportViewModel.message(for: .unreadableCSV)
            return
        }
        isReviewing = true
        Task { await importModel.begin(source) }
    }

    /// Shows the summary once an approved import has one.
    private func showSummaryIfFinished() {
        guard model.pendingImport?.outcome != nil else { return }
        isShowingSummary = true
    }
}
