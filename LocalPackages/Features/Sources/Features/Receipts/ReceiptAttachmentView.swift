import SwiftUI
import Domain

/// The receipt attached to a product, with a way to look at it (§7.7, §9.3).
///
/// Nothing in the app displayed a receipt before this: `receiptFileID` was written and
/// never read. The image is loaded through ``ReceiptStorageCoordinator/image(for:)``,
/// which serves the in-memory cache when it is warm and the store when it is not —
/// and after a relaunch it is never warm, so the store path is the normal one.
struct ReceiptAttachmentView: View {
    /// The stored receipt's identifier, if it has been saved.
    let fileID: String?
    /// Bytes captured in this session but not yet saved.
    let pendingData: Data?
    /// Reads stored receipts back.
    let storage: ReceiptStorageCoordinator?
    /// Called when the user removes the attachment.
    let onRemove: () -> Void

    /// The loaded image, once it arrives.
    @State private var image: UIImage?
    /// Whether the load is still running.
    @State private var isLoading = false
    /// Whether the full-screen viewer is showing.
    @State private var isViewing = false

    /// The view body.
    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "paperclip")
                        .font(.title3)
                        .foregroundStyle(Palette.brandPurple)
                        .accessibilityHidden(true)
                    Text("Receipt")
                        .font(Typography.rowPrimary)
                        .foregroundStyle(Palette.textPrimary)
                    Spacer()
                    Button("Remove", role: .destructive, action: onRemove)
                        .font(Typography.errorCaption.weight(.semibold))
                        .foregroundStyle(Palette.negativeRed)
                }
                content
            }
        }
        .task(id: fileID) { await load() }
        .onChange(of: pendingData) { _, _ in Task { await load() } }
        .fullScreenCover(isPresented: $isViewing) {
            if let image {
                ReceiptViewer(image: image)
            }
        }
    }

    /// The thumbnail, or what stands in for it.
    @ViewBuilder
    private var content: some View {
        if let image {
            Button { isViewing = true } label: {
                HStack(alignment: .center, spacing: 12) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 84)
                        .clipShape(.rect(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Palette.borderSubtle, lineWidth: 1)
                        }
                    Text("Tap to view")
                        .font(Typography.rowSecondary)
                        .foregroundStyle(Palette.brandPurple)
                    Spacer()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View the attached receipt")
        } else if isLoading {
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading the receipt…")
                    .font(Typography.rowSecondary)
                    .foregroundStyle(Palette.textSecondary)
            }
        } else {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.circle").accessibilityHidden(true)
                Text("The receipt is attached but could not be loaded right now.")
            }
            .font(Typography.errorCaption)
            .foregroundStyle(Palette.attentionAmber)
        }
    }

    /// Loads the image, preferring bytes captured in this session.
    private func load() async {
        if let pendingData, let decoded = UIImage(data: pendingData) {
            image = decoded
            return
        }
        guard let fileID, let storage else { return }
        isLoading = true
        defer { isLoading = false }
        guard let data = await storage.image(for: fileID) else { return }
        image = UIImage(data: data)
    }
}

/// A stored receipt, full screen and zoomable.
///
/// Receipt print is small, and a thumbnail is not enough to check a total against
/// what the form says — so the viewer has to magnify.
struct ReceiptViewer: View {
    /// The image to show.
    let image: UIImage

    /// Dismisses the viewer.
    @Environment(\.dismiss) private var dismiss
    /// The current zoom factor.
    @State private var scale: CGFloat = 1
    /// The zoom factor when the current gesture began.
    @State private var committedScale: CGFloat = 1

    /// The view body.
    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    // Sized against the viewport rather than left to its intrinsic
                    // size: a 1600px capture inside a scroll view is proposed an
                    // unbounded width and opens magnified past the page edges.
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: proxy.size.width * scale,
                            height: proxy.size.height * scale
                        )
                        .gesture(zoom)
                }
            }
            .background(Palette.appBackground)
            .navigationTitle("Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Pinch to zoom, bounded so the image cannot be lost off-screen.
    private var zoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(6, max(1, committedScale * value.magnification))
            }
            .onEnded { _ in committedScale = scale }
    }
}
