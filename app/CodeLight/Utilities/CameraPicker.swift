import SwiftUI
import UIKit

/// SwiftUI wrapper for `UIImagePickerController` with `sourceType = .camera`.
/// Used by ChatView's attachment menu to take a photo with the device camera.
///
/// Apple compliance notes:
/// - Requires `NSCameraUsageDescription` in Info.plist (set via
///   `INFOPLIST_KEY_NSCameraUsageDescription` in project.pbxproj).
/// - The camera prompt appears on first use; iOS handles the authorization
///   flow automatically when we set `sourceType = .camera`.
/// - We only capture a single photo at a time — matches the tap-to-snap UX.
struct CameraPicker: UIViewControllerRepresentable {
    /// Called with the captured image. nil means the user cancelled.
    let onImage: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage?) -> Void

        init(onImage: @escaping (UIImage?) -> Void) {
            self.onImage = onImage
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            picker.dismiss(animated: true) { [onImage] in onImage(image) }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) { [onImage] in onImage(nil) }
        }
    }

    /// Convenience: returns true if the current device has a usable camera.
    /// Used to hide the "Take Photo" option on simulators / devices without camera.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }
}
