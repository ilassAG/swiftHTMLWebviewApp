//
//  ScannerViews/BarcodeScannerView.swift
//  swiftHTMLWebviewDemo
//
//  Created by KI-Generiert am 05.10.2023.
//  Korrektur: 02.04.2025 (Letzter Versuch mit Kurzform für Enum Cases)
//

import SwiftUI
import VisionKit
import Vision

struct BarcodeScannerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let recognizedDataTypes: Set<DataScannerViewController.RecognizedDataType>
    let completion: (Result<(code: String, format: String), AppError>) -> Void

    static var isSupported: Bool { DataScannerViewController.isSupported }
    static var isAvailable: Bool { DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scannerVC = DataScannerViewController(
            recognizedDataTypes: recognizedDataTypes,
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scannerVC.delegate = context.coordinator
        return scannerVC
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        Task { @MainActor in
            if isPresented {
                if !uiViewController.isScanning {
                    guard BarcodeScannerView.isAvailable else {
                        print("Error: DataScanner is not available (likely missing camera permission).")
                        completion(.failure(.cameraPermissionDenied))
                        isPresented = false
                        return
                    }
                    do {
                        try uiViewController.startScanning()
                        print("BarcodeScanner started scanning.")
                    } catch {
                        print("Error starting barcode scanner: \(error.localizedDescription)")
                        completion(.failure(.internalError("Scanner konnte nicht gestartet werden: \(error.localizedDescription)")))
                        isPresented = false
                    }
                }
            } else {
                if uiViewController.isScanning {
                    uiViewController.stopScanning()
                    print("BarcodeScanner stopped scanning.")
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: BarcodeScannerView
        private var hasCompleted = false

        init(_ parent: BarcodeScannerView) {
            self.parent = parent
        }

        func reset() {
            hasCompleted = false
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            processItems(items: addedItems, scanner: scanner)
        }

        func dataScanner(_ scanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            processItems(items: [item], scanner: scanner)
        }

        private func processItems(items: [RecognizedItem], scanner: DataScannerViewController) {
            guard !hasCompleted else { return }

            for item in items {
                switch item {
                case .barcode(let barcode):
                    let observation = barcode.observation
                    let symbology: VNBarcodeSymbology = observation.symbology

                    if let code = barcode.payloadStringValue {
                        let formatString = BarcodeUtils.mapSymbologyToDisplayName(symbology)
                        print("Barcode recognized: \(code) (Format: \(formatString))")

                        hasCompleted = true
                        scanner.stopScanning()

                        Task { @MainActor in
                            parent.completion(.success((code: code, format: formatString)))
                            parent.isPresented = false
                        }
                        return
                    } else {
                         print("Warning: Recognized barcode has no string value.")
                    }
                case .text:
                    continue
                @unknown default:
                    print("Warning: Unrecognized item type detected.")
                    continue
                }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
             guard !hasCompleted else { return }
             print("DataScanner became unavailable with error object: \(error)")
             hasCompleted = true
             let appError: AppError

             switch error {
             case .cameraRestricted:
                 appError = .cameraPermissionDenied
             case .unsupported:
                 appError = .internalError("Scanner wird auf diesem Gerät nicht unterstützt: \(error.localizedDescription)")
             @unknown default:
                 appError = .internalError("Unbekannter Scanner-Fehler: \(error.localizedDescription)")
             }

             Task { @MainActor in
                 parent.completion(.failure(appError))
                 parent.isPresented = false
             }
        }
    }
}
