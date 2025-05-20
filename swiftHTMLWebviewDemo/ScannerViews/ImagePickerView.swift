//
//  ScannerViews/ImagePickerView.swift
//  swiftHTMLWebviewDemo
//
//  Created by KI-Generiert am 05.10.2023.
//

import SwiftUI
import UIKit

struct ImagePickerView: UIViewControllerRepresentable {
    // Korrektur: isPresented Binding wird beim Aufruf übergeben
    @Binding var isPresented: Bool
    var cameraDevice: UIImagePickerController.CameraDevice
    var completion: (Result<UIImage, AppError>) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera

        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            print("Error: Camera source type is not available on this device.")
            DispatchQueue.main.async {
                 completion(.failure(.featureNotAvailable(NSLocalizedString("error.featureNotAvailable.camera", comment: "Feature name: Camera"))))
                 isPresented = false
            }
            return picker
        }

        if UIImagePickerController.isCameraDeviceAvailable(cameraDevice) {
            picker.cameraDevice = cameraDevice
        } else {
            let fallbackDevice: UIImagePickerController.CameraDevice = (cameraDevice == .front) ? .rear : .front
            if UIImagePickerController.isCameraDeviceAvailable(fallbackDevice) {
                print("Warning: Requested camera (\(cameraDevice)) not available, using \(fallbackDevice).")
                picker.cameraDevice = fallbackDevice
            } else {
                print("Warning: Neither front nor rear camera seems available. Using default.")
            }
        }
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator
    // Korrektur: Markierung als @MainActor
    @MainActor
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: ImagePickerView

        init(_ parent: ImagePickerView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                print("Image picked successfully.")
                parent.completion(.success(image))
            } else {
                print("Error: Could not retrieve original image from picker.")
                parent.completion(.failure(.internalError(NSLocalizedString("error.internalError.imageNotReceived", comment: "Image not received from camera error"))))
            }
            parent.isPresented = false // Schließen
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            print("Image picker cancelled by user.")
            parent.completion(.failure(.userCancelled))
            parent.isPresented = false // Schließen
        }
    }
}