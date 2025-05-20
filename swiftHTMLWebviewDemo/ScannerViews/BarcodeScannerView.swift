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
                        print(NSLocalizedString("error.dataScanner.notAvailable", comment: "DataScanner not available error"))
                        completion(.failure(.cameraPermissionDenied))
                        isPresented = false
                        return
                    }
                    do {
                        try uiViewController.startScanning()
                        print("BarcodeScanner started scanning.")
                    } catch {
                        print(String(format: NSLocalizedString("error.dataScanner.startFailed", comment: "DataScanner start failed error format"), error.localizedDescription))
                        completion(.failure(.internalError(String(format: NSLocalizedString("error.dataScanner.startFailed", comment: "DataScanner start failed error format"), error.localizedDescription))))
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
                        print(String(format: NSLocalizedString("status.barcodeRecognized", comment: "Barcode recognized status format"), code, formatString))

                        // JSON-Verarbeitung für Konfigurationsänderung
                        if let jsonData = code.data(using: .utf8) {
                            do {
                                if let json = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {
                                    if let toolmode = json["toolmode"] as? String, toolmode == "changeConfig",
                                       let scannedToken = json["securityToken"] as? String,
                                       let newUrl = json["defaultServerUrl"] as? String, !newUrl.isEmpty {

                                        let storedToken = AppSettings.shared.securityToken
                                        if scannedToken == storedToken {
                                            print(String(format: NSLocalizedString("status.securityToken.match", comment: "Security token match status format"), newUrl))
                                            AppSettings.shared.serverURL = newUrl
                                            // Die completion wird hier nicht direkt mit dem Code aufgerufen,
                                            // da die ContentView das Neuladen der WebView übernimmt.
                                            // Wir signalisieren Erfolg, aber ohne den Barcode-Inhalt direkt weiterzugeben,
                                            // da die Aktion (URL-Änderung) wichtiger ist.
                                            // Alternativ könnte man einen speziellen Erfolgstyp für "configChanged" einführen.
                                            // Fürs Erste rufen wir die normale completion auf, aber ContentView wird
                                            // durch die Änderung in AppSettings.shared.serverURL getriggert,
                                            // die WebView neu zu laden (via scenePhase oder einen direkteren Mechanismus).
                                            // Um das Neuladen explizit anzustoßen, könnte man hier eine Notification posten
                                            // oder direkt auf den webViewStore zugreifen, falls er hier verfügbar wäre.
                                            // Da der Coordinator keinen direkten Zugriff auf den webViewStore in ContentView hat,
                                            // verlassen wir uns auf den bestehenden Mechanismus in ContentView (scenePhase)
                                            // oder fügen später einen dedizierten Notification-Handler in ContentView hinzu.

                                            hasCompleted = true
                                            scanner.stopScanning()
                                            Task { @MainActor in
                                                // Wir signalisieren Erfolg, aber die ContentView muss das Neuladen handhaben.
                                                // Wir könnten hier einen speziellen Wert oder eine leere Zeichenkette zurückgeben,
                                                // um anzuzeigen, dass die Konfiguration geändert wurde.
                                                // Fürs Erste geben wir den ursprünglichen Code zurück, aber die Hauptaktion ist die URL-Änderung.
                                                parent.completion(.success((code: "configChanged", format: "JSONConfig")))
                                                parent.isPresented = false
                                            }
                                            return
                                        } else {
                                            print(String(format: NSLocalizedString("error.securityToken.mismatch", comment: "Security token mismatch error format"), scannedToken, storedToken))
                                            // Fehlerbehandlung für Token-Mismatch
                                            hasCompleted = true
                                            scanner.stopScanning()
                                            Task { @MainActor in
                                                parent.completion(.failure(.invalidConfiguration(NSLocalizedString("error.invalidConfiguration.invalidToken", comment: "Invalid security token error"))))
                                                parent.isPresented = false
                                            }
                                            return
                                        }
                                    }
                                }
                            } catch {
                                print(String(format: NSLocalizedString("error.qr.jsonParseFailed", comment: "QR JSON parse failed error format"), error.localizedDescription))
                                // Kein kritischer Fehler, wenn JSON nicht geparst werden kann, fahre mit normaler Barcode-Verarbeitung fort.
                            }
                        }

                        // Normale Barcode-Verarbeitung, wenn keine Konfigurationsänderung
                        hasCompleted = true
                        scanner.stopScanning()

                        Task { @MainActor in
                            parent.completion(.success((code: code, format: formatString)))
                            parent.isPresented = false
                        }
                        return
                    } else {
                         print(NSLocalizedString("warning.barcode.noStringValue", comment: "Barcode has no string value warning"))
                    }
                case .text:
                    continue
                @unknown default:
                    print(NSLocalizedString("warning.dataScanner.unrecognizedItem", comment: "Unrecognized item type warning"))
                    continue
                }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
             guard !hasCompleted else { return }
             print(String(format: NSLocalizedString("error.dataScanner.unavailable", comment: "DataScanner unavailable error format"), error.localizedDescription))
             hasCompleted = true
             let appError: AppError

             switch error {
             case .cameraRestricted:
                 appError = .cameraPermissionDenied
             case .unsupported:
                 appError = .internalError(String(format: NSLocalizedString("error.internalError.scannerNotSupported", comment: "Scanner not supported error format"), error.localizedDescription))
             @unknown default:
                 appError = .internalError(String(format: NSLocalizedString("error.internalError.unknownScannerError", comment: "Unknown scanner error format"), error.localizedDescription))
             }

             Task { @MainActor in
                 parent.completion(.failure(appError))
                 parent.isPresented = false
             }
        }
    }
}
