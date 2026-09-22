import SwiftUI
import PhotosUI
import Domain

/// The Scan receipt row on Add Product (§7.7, §9.7).
///
/// Every extracted field is a pre-fill, never a commitment: the row reports what it
/// read, the form stays fully editable, and a scan that finds nothing says so and
/// leaves the form untouched.
struct ReceiptCaptureView: View {
    /// What the last scan found, if one has run.
    let prefill: ReceiptPrefill?
    /// How far along the running scan is, if one is running.
    let phase: ReceiptScanPhase
    /// Called with the captured photo.
    let onCapture: (UIImage) -> Void

    /// Whether the camera-or-library choice is showing.
    @State private var isChoosingSource = false
    /// Whether the camera is showing.
    @State private var isShowingCamera = false
    /// The photo chosen from the library.
    @State private var libraryItem: PhotosPickerItem?
    /// Whether the library picker is showing.
    @State private var isShowingLibrary = false

    /// The view body.
    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Button { isChoosingSource = true } label: { label }
                    .buttonStyle(.plain)
                    .disabled(phase.isScanning)
                status
            }
        }
        .confirmationDialog("Scan receipt", isPresented: $isChoosingSource) {
            if CameraPicker.isAvailable {
                Button("Take photo") { isShowingCamera = true }
            }
            Button("Choose from library") { isShowingLibrary = true }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { image in
                isShowingCamera = false
                if let image { onCapture(image) }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $isShowingLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
    }

    /// The row's icon and title.
    private var label: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.viewfinder")
                .font(.title3)
                .foregroundStyle(Palette.brandPurple)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Scan receipt")
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.textPrimary)
                Text("Fills in what it can read, for you to check.")
                    .font(Typography.errorCaption)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
        }
        .contentShape(.rect)
    }

    /// What the last scan found, once one has run.
    @ViewBuilder
    private var status: some View {
        if phase.isScanning {
            progress
        } else if let prefill, prefill.isEmpty {
            statusLine(
                "Nothing could be read from that photo. Fill the form in yourself.",
                icon: "exclamationmark.circle",
                tint: Palette.attentionAmber
            )
        } else if let prefill {
            VStack(alignment: .leading, spacing: 8) {
                statusLine(
                    prefill.scan.source == .onDeviceModel
                        ? "Filled in from the receipt, read on this device by Apple Intelligence."
                        : "Filled in from the receipt's text. Check each field.",
                    icon: "checkmark.circle",
                    tint: Palette.positiveGreen
                )
                filledFields(prefill.filled)
            }
        }
    }

    /// Which fields the scan filled (§9.7).
    ///
    /// Named rather than merely counted. Seven fields arriving at once is more than
    /// anyone re-reads, and a pre-fill nobody noticed is a pre-fill nobody checked — so
    /// the row says exactly which fields to look at before saving.
    ///
    /// - Parameter filled: The fields the scan set.
    /// - Returns: The row.
    @ViewBuilder
    private func filledFields(_ filled: Set<ReceiptField>) -> some View {
        let names = ReceiptField.allCases.filter(filled.contains).map(\.displayName)
        if !names.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(names, id: \.self) { name in
                    Text(name)
                        .font(Typography.errorCaption)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Palette.segmentTrack, in: .capsule)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Filled in: \(names.joined(separator: ", "))")
        }
    }

    /// The running scan's progress (§9.7).
    ///
    /// Determinate rather than a bare spinner. The middle step runs Apple's on-device
    /// model and can take several seconds, and an indeterminate spinner over that long a
    /// wait is indistinguishable from a hang — so the bar moves as each step begins and
    /// the row says which step is running and how many remain.
    @ViewBuilder
    private var progress: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text(phase.message)
                    .font(Typography.errorCaption)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 8)
                if let step = phase.step {
                    Text("Step \(step) of \(ReceiptScanPhase.working.count)")
                        .font(Typography.errorCaption)
                        .foregroundStyle(Palette.textSecondary)
                        .monospacedDigit()
                }
            }
            ProgressView(value: phase.progress)
                .progressViewStyle(.linear)
                .tint(Palette.brandPurple)
                .animation(.easeInOut(duration: 0.25), value: phase)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase.message)
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// One status line, icon and colour together (§12).
    /// - Parameters:
    ///   - text: What to report.
    ///   - icon: The symbol to pair with it.
    ///   - tint: The colour to use.
    /// - Returns: The line.
    private func statusLine(_ text: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).accessibilityHidden(true)
            Text(text)
        }
        .font(Typography.errorCaption)
        .foregroundStyle(tint)
    }

    /// Loads the chosen library photo.
    /// - Parameter item: The chosen item.
    private func load(_ item: PhotosPickerItem) async {
        defer { libraryItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        onCapture(image)
    }
}
