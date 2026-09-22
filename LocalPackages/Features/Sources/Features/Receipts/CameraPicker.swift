import SwiftUI
import UIKit

/// The system camera, as a still-photo capture (§9.7).
///
/// §9.7 permits either a live scanner or a still photo. A still is used here: it is
/// sharper on the small, dense print a receipt carries, and it is the only one of the
/// two that works in the Simulator, so the pipeline stays verifiable.
struct CameraPicker: UIViewControllerRepresentable {
    /// Called with the captured photo, or `nil` if the user cancelled.
    let onFinish: (UIImage?) -> Void

    /// Whether this device has a camera at all.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    /// Builds the camera controller.
    /// - Parameter context: The representable context.
    /// - Returns: The controller.
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }

    /// Nothing to update: the controller is configured once.
    /// - Parameters:
    ///   - uiViewController: The controller.
    ///   - context: The representable context.
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    /// Builds the delegate.
    /// - Returns: The coordinator.
    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    /// Bridges the picker's delegate callbacks back into SwiftUI.
    final class Coordinator: NSObject, UIImagePickerControllerDelegate,
                             UINavigationControllerDelegate {
        /// Called with the captured photo, or `nil` if the user cancelled.
        private let onFinish: (UIImage?) -> Void

        /// Creates the coordinator.
        /// - Parameter onFinish: Called with the captured photo.
        init(onFinish: @escaping (UIImage?) -> Void) {
            self.onFinish = onFinish
        }

        /// Reports the captured photo.
        /// - Parameters:
        ///   - picker: The picker.
        ///   - info: The captured media.
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onFinish(info[.originalImage] as? UIImage)
        }

        /// Reports the cancellation.
        /// - Parameter picker: The picker.
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
