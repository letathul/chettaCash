import SwiftUI

/// Raising and dismissing the software keyboard (§7.11).
///
/// Two pieces the whole app shares, so timing and wording stay identical everywhere.
extension View {

    /// Raises the keyboard on a field once the presentation transition has settled.
    ///
    /// The delay is deliberate. Requesting first responder while a sheet is still
    /// animating in makes the keyboard race the transition: it either appears late,
    /// having been dropped and re-requested, or it shoves the layout mid-slide. Waiting
    /// for the transition to finish is what makes it look immediate.
    ///
    /// - Parameter focus: The screen's focus binding.
    /// - Returns: The view, focused shortly after it appears.
    func autoFocus(_ focus: FocusState<Bool>.Binding) -> some View {
        onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.focusDelay) {
                focus.wrappedValue = true
            }
        }
    }

    /// Raises the keyboard on one field of a multi-field form.
    ///
    /// Passing `nil` declines focus, for a screen that is conditionally read-only.
    ///
    /// - Parameters:
    ///   - focus: The screen's focus binding.
    ///   - field: The field to open on, or `nil` to leave the keyboard down.
    /// - Returns: The view, focused shortly after it appears.
    func autoFocus<Field: Hashable>(
        _ focus: FocusState<Field?>.Binding,
        on field: Field?
    ) -> some View {
        onAppear {
            guard let field else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.focusDelay) {
                focus.wrappedValue = field
            }
        }
    }

    /// Puts a Done button above the keyboard.
    ///
    /// Money fields use `.decimalPad`, which has no return key — without this there is
    /// no way to put the keyboard away except scrolling or tapping elsewhere.
    ///
    /// - Parameter focus: The screen's focus binding, cleared by the button.
    /// - Returns: The view, with a keyboard toolbar.
    func keyboardDoneToolbar<Field: Hashable>(
        _ focus: FocusState<Field?>.Binding
    ) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus.wrappedValue = nil }
            }
        }
    }

    /// Puts a Done button above the keyboard, with an action of the screen's own beside it.
    ///
    /// The transaction form uses this to keep "Add Product" within reach while the
    /// keyboard is up (§7.8): the alternative is dismissing the keyboard and scrolling to
    /// the Products card for what should be a two-second action.
    ///
    /// - Parameters:
    ///   - focus: The screen's focus binding, cleared by the Done button.
    ///   - leading: The screen's own action, drawn to the left of the Done button.
    /// - Returns: The view, with a keyboard toolbar.
    func keyboardToolbar<Field: Hashable, Leading: View>(
        _ focus: FocusState<Field?>.Binding,
        @ViewBuilder leading: () -> Leading
    ) -> some View {
        let leadingItem = leading()
        return toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                leadingItem
                Spacer()
                Button("Done") { focus.wrappedValue = nil }
            }
        }
    }

    /// How long to wait for a presentation transition before asking for focus.
    fileprivate static var focusDelay: TimeInterval { 0.15 }
}
