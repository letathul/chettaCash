import Foundation
import Testing
@testable import Domain

/// The rules a newly created category label must satisfy (§4.8).
///
/// The cap exists so a label stays readable in a chip; the emoji ban exists because a
/// stripped label is a label nobody typed. Both apply only to *creation*, which is why
/// nothing here reaches for an existing category.
@Suite("Category naming")
struct CategoryNamingTests {

    // MARK: - Length

    @Test("A label at the cap is accepted")
    func acceptsTheCap() throws {
        let label = String(repeating: "a", count: CategoryNaming.maxLength)

        let validated = try CategoryNaming.validated(label)

        #expect(validated == label)
    }

    @Test("A label one character over the cap is refused")
    func refusesOverTheCap() {
        let label = String(repeating: "a", count: CategoryNaming.maxLength + 1)

        #expect(throws: CategoryNaming.Problem.tooLong(CategoryNaming.maxLength + 1)) {
            try CategoryNaming.validated(label)
        }
    }

    @Test("Padding is trimmed rather than counted")
    func trimsPadding() throws {
        let validated = try CategoryNaming.validated("   Groceries   ")

        #expect(validated == "Groceries", "space the user cannot see must not fail a label")
    }

    @Test("Internal whitespace runs collapse to one space")
    func collapsesInternalWhitespace() throws {
        let validated = try CategoryNaming.validated("Food    court")

        #expect(validated == "Food court")
    }

    @Test("Length counts characters the user sees, not UTF-16 units")
    func countsGraphemeClusters() throws {
        // Each "é" written as e + combining acute is two scalars but one character.
        let label = String(repeating: "e\u{301}", count: CategoryNaming.maxLength)

        let validated = try CategoryNaming.validated(label)

        #expect(validated.count == CategoryNaming.maxLength)
    }

    @Test("A label that is only whitespace is refused as empty")
    func refusesBlank() {
        #expect(throws: CategoryNaming.Problem.empty) {
            try CategoryNaming.validated("   \n  ")
        }
    }

    // MARK: - Emoji

    @Test("An emoji label is refused", arguments: [
        "Coffee ☕️",
        "☕️",
        "Food 🍔",
        "Family 👨‍👩‍👧",
        "Travel 🇨🇦",
        "Wave 👋🏽"
    ])
    func refusesEmoji(label: String) {
        #expect(throws: CategoryNaming.Problem.containsEmoji) {
            try CategoryNaming.validated(label)
        }
    }

    @Test("Digits and punctuation are not emoji", arguments: [
        "Cafe 24",
        "Bills #1",
        "Rent *",
        "Food & drink",
        "Cafe\u{301} Ole\u{301}"
    ])
    func acceptsDigitsAndPunctuation(label: String) throws {
        let validated = try CategoryNaming.validated(label)

        #expect(!validated.isEmpty, "a keycap base is still an ordinary character")
    }

    @Test("Emoji is refused before length, so the message names the real problem")
    func emojiBeatsLength() {
        let label = String(repeating: "a", count: CategoryNaming.maxLength + 5) + "☕️"

        #expect(throws: CategoryNaming.Problem.containsEmoji) {
            try CategoryNaming.validated(label)
        }
    }
}
