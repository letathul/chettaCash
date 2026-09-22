import Foundation

/// Which of `03/09/2026`'s first two numbers is the month (§9.7).
///
/// **There is no way to tell from one line.** `03/09` is the third of September in most of the
/// world and the ninth of March in North America, and a statement is internally consistent —
/// so guessing per line would scatter a month's purchases across two schemes. It is settled
/// once for the whole file instead.
public enum StatementDateOrder: String, Sendable, Equatable, CaseIterable {
    /// `MM/DD`, which North American card statements print.
    case monthFirst
    /// `DD/MM`, which most of the rest of the world prints.
    case dayFirst

    /// What to call this in a picker.
    public var title: String {
        switch self {
        case .monthFirst: return "Month first (03/09 is 9 March)"
        case .dayFirst: return "Day first (03/09 is 3 September)"
        }
    }
}

/// Working out which order a file's dates are printed in.
public enum StatementDateOrderReader {

    /// Reads the order off a file's own dates.
    ///
    /// **Evidence, not assumption.** A first number above twelve can only be a day, so one
    /// such date settles the file — `25/12/2026` is unambiguous, and a file printing it prints
    /// `03/09` the same way. Failing that the commoner North American convention stands,
    /// which is what the parser assumed unconditionally before.
    ///
    /// - Parameter texts: The date cells, exactly as the file printed them.
    /// - Returns: The order to read the file under.
    public static func infer(from texts: [String]) -> StatementDateOrder {
        for text in texts {
            guard let parts = numericParts(of: text), parts.count >= 2 else { continue }
            // A second number above twelve settles it the other way, and is checked first:
            // a file where both are above twelve is not dates at all.
            if parts[1] > 12, parts[0] <= 12 { return .monthFirst }
            if parts[0] > 12, parts[1] <= 12 { return .dayFirst }
        }
        return .monthFirst
    }

    /// The numbers in a slash-, dash- or dot-separated date.
    /// - Parameter text: The candidate text.
    /// - Returns: The numbers, or `nil` when the text is not that shape.
    static func numericParts(of text: String) -> [Int]? {
        let parts = text
            .trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { $0 == "/" || $0 == "-" || $0 == "." })
            .map(String.init)
        guard (2...3).contains(parts.count), parts.allSatisfy({ $0.allSatisfy(\.isNumber) })
        else { return nil }
        return parts.compactMap(Int.init)
    }
}
