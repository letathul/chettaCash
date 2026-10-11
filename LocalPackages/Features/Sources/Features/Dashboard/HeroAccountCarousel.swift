import SwiftUI
import Domain

/// The Dashboard's hero carousel: one page per open account, behind "All accounts" (§7.1).
///
/// Built on the scroll-target API rather than a paged `TabView`, which fights the
/// Dashboard's own vertical `ScrollView` for the drag and needs a fixed height that
/// clips at accessibility text sizes.
///
/// Swiping *is* the focused-account picker: the visible page writes through to
/// ``Domain/AppSettings/focusedAccountID``, so the choice persists and the Today list
/// below rescopes to match.
struct HeroAccountCarousel: View {
    /// The pages to show, "All accounts" first.
    let pages: [HeroPageModel]
    /// What needs attention today, shown on the "All accounts" page.
    let digest: TodayDigest
    /// The display currency.
    let currencyCode: String
    /// The account the Dashboard is scoped to, or `nil` for "All accounts".
    @Binding var focusedAccountID: UUID?
    /// Opens the Today sheet.
    let onOpenToday: () -> Void

    /// Which page the carousel has scrolled to, as that page's identity.
    @State private var scrolledID: UUID?

    /// The view body.
    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(pages) { page in
                        HeroAccountPage(
                            page: page,
                            digest: page.accountID == nil ? digest : nil,
                            currencyCode: currencyCode,
                            onOpenToday: onOpenToday
                        )
                        .containerRelativeFrame(.horizontal)
                        .id(page.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $scrolledID)
            if pages.count > 1 { dots }
        }
        .onAppear { scrolledID = selectedID }
        .onChange(of: focusedAccountID) { scrolledID = selectedID }
        .onChange(of: scrolledID) { _, newValue in
            guard let page = pages.first(where: { $0.id == newValue }),
                  page.accountID != focusedAccountID else { return }
            focusedAccountID = page.accountID
        }
    }

    /// The identity of the page the focused account corresponds to.
    private var selectedID: UUID? {
        pages.first { $0.accountID == focusedAccountID }?.id ?? pages.first?.id
    }

    /// The page indicator.
    ///
    /// Labelled for VoiceOver rather than left as decoration, since it is the only
    /// thing that says how many accounts the carousel holds.
    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(pages) { page in
                Circle()
                    .fill(
                        page.id == scrolledID
                            ? Palette.brandPurple
                            : Palette.textSecondary.opacity(0.35)
                    )
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pages.count) pages")
    }
}
