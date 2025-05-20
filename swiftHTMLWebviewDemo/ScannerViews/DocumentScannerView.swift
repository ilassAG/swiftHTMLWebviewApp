//
//  ScannerViews/DocumentScannerView.swift
//  swiftHTMLWebviewDemo
//
//  Created by KI-Generiert am 05.10.2023.
//  Korrektur: 02.04.2025 (@MainActor vom Coordinator entfernt)
//

import SwiftUI
import VisionKit

struct DocumentScannerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var completion: (Result<VNDocumentCameraScan, AppError>) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scannerVC = VNDocumentCameraViewController()
        scannerVC.delegate = context.coordinator
        return scannerVC
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator
    // Korrektur: @MainActor entfernt, Dispatch manuell durchführen
    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        var parent: DocumentScannerView

        init(_ parent: DocumentScannerView) {
            self.parent = parent
        }

        // Wichtig: Diese Delegate-Methoden werden nicht unbedingt auf dem Main Thread aufgerufen!
        // UI-Updates und das Aufrufen des SwiftUI-Callbacks müssen auf den Main Thread verschoben werden.

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            print("Document scan finished successfully with \(scan.pageCount) pages.")
            // Korrektur: Dispatch auf Main Actor
            Task { @MainActor in
                parent.completion(.success(scan))
                parent.isPresented = false
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            print("Document scan cancelled by user.")
            // Korrektur: Dispatch auf Main Actor
            Task { @MainActor in
                parent.completion(.failure(.userCancelled))
                parent.isPresented = false
            }
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            print(String(format: NSLocalizedString("error.documentScan.failed", comment: "Document scan failed error format"), error.localizedDescription))
            // Korrektur: Dispatch auf Main Actor
            Task { @MainActor in
                parent.completion(.failure(.internalError(String(format: NSLocalizedString("error.internalError.documentScanFailed", comment: "Document scan failed internal error format"), error.localizedDescription))))
                parent.isPresented = false
            }
        }
    }
}