//
//  ContentView.swift
//  swiftHTMLWebviewDemo
//
//  Created by Peter Vogel on 02.04.25. (Original)
//  Updated by KI-Generiert am 05.10.2023.
//  Korrektur: 02.04.2025
//

import SwiftUI
@preconcurrency import WebKit // Korrektur: @preconcurrency
import VisionKit
import PDFKit
import Vision // <--- Hinzugefügt für BarcodeUtils/TextRecognizer

// Korrektur: ContentView als @MainActor markieren
@MainActor
struct ContentView: View {
    // Korrektur: Stelle sicher, dass Store @MainActor ist
    @StateObject var webViewStore = WebViewStore()
    @Environment(\.scenePhase) private var scenePhase // Für App Lifecycle Events

    @State private var showDocumentScanner = false
    @State private var showImagePicker = false
    @State private var showBarcodeScanner = false
    @State private var currentRequest: [String: Any]? = nil

    var body: some View {
        ZStack {
            if webViewStore.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text(String(format: NSLocalizedString("loading.url", comment: "Loading URL message"), webViewStore.currentURLString ?? ""))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(UIColor.systemBackground))
                .ignoresSafeArea()
            } else {
                // Korrektur: Stelle sicher, dass webViewStore an WebView übergeben wird
                WebView(webViewStore: webViewStore, onScriptMessage: handleScriptMessage)
                    .ignoresSafeArea()
            }
        }
        .onChange(of: scenePhase) { newPhase, oldPhase in // scenePhase direkt verwenden
            if newPhase == .active {
                print("App became active. Checking for URL updates.")
                webViewStore.reloadCurrentOrNewURL()
            }
        }
        .sheet(isPresented: $showDocumentScanner, onDismiss: handleSheetDismiss) {
                // Korrektur: Binding übergeben
                DocumentScannerView(isPresented: $showDocumentScanner) { result in
                    handleDocumentScanResult(result)
                }
            }
            .sheet(isPresented: $showImagePicker, onDismiss: handleSheetDismiss) {
                let requestedCamera = currentRequest?["camera"] as? String
                let cameraDevice: UIImagePickerController.CameraDevice = (requestedCamera == "front") ? .front : .rear
                // Korrektur: Binding übergeben
                ImagePickerView(isPresented: $showImagePicker, cameraDevice: cameraDevice) { result in
                    handleImagePickerResult(result)
                }
            }
            .sheet(isPresented: $showBarcodeScanner, onDismiss: handleSheetDismiss) {
                if BarcodeScannerView.isSupported {
                    let requestedTypes = currentRequest?["types"] as? [String]
                    let scanTypes = BarcodeUtils.mapStringToDataTypes(requestedTypes)
                    // Korrektur: Binding übergeben
                    BarcodeScannerView(isPresented: $showBarcodeScanner, recognizedDataTypes: scanTypes) { result in
                         handleBarcodeScanResult(result)
                    }
                } else {
                     Text(NSLocalizedString("error.barcodeScannerNotSupported.message", comment: "Barcode scanner not supported message"))
                         .padding()
                         .onAppear {
                             let action = currentRequest?["action"] as? String
                             // Korrektur: AppError Instanz übergeben
                             webViewStore.sendErrorToWebView(action: action, error: AppError.featureNotAvailable(NSLocalizedString("error.featureNotAvailable.barcodeScanner", comment: "Feature name: Barcode Scanner")))
                             showBarcodeScanner = false
                         }
                 }
            }
    }

    // MARK: - JavaScript Message Handling
    private func handleScriptMessage(_ message: [String: Any]) {
        guard let action = message["action"] as? String else {
            print("Error: Received message from JS without 'action' key.")
            // Korrektur: AppError Instanz übergeben
            webViewStore.sendErrorToWebView(action: nil, error: AppError.invalidRequest(NSLocalizedString("error.invalidRequest.missingAction", comment: "Missing action parameter error")))
            return
        }

        self.currentRequest = message
        print("Processing action: \(action)")

        switch action {
        case "scanDocument":
            self.showDocumentScanner = true

        case "takePhoto":
             guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                 print("Error: Camera not available.")
                 // Korrektur: AppError Instanz übergeben
                 webViewStore.sendErrorToWebView(action: action, error: AppError.featureNotAvailable(NSLocalizedString("error.featureNotAvailable.camera", comment: "Feature name: Camera")))
                 currentRequest = nil
                 return
             }
            self.showImagePicker = true

        case "scanBarcode":
            guard BarcodeScannerView.isSupported else {
                 print("Error: DataScanner is not supported on this device.")
                 // Korrektur: AppError Instanz übergeben
                 webViewStore.sendErrorToWebView(action: action, error: AppError.featureNotAvailable(NSLocalizedString("error.featureNotAvailable.barcodeScanner", comment: "Feature name: Barcode Scanner")))
                 currentRequest = nil
                 return
             }
            self.showBarcodeScanner = true

        default:
            print("Error: Received unknown action from JS: \(action)")
            // Korrektur: AppError Instanz übergeben
            webViewStore.sendErrorToWebView(action: action, error: AppError.invalidRequest(String(format: NSLocalizedString("error.invalidRequest.unknownAction", comment: "Unknown action error format"), action)))
            currentRequest = nil
        }
    }

    // MARK: - Result Handling
    private func handleDocumentScanResult(_ result: Result<VNDocumentCameraScan, AppError>) {
        let action = currentRequest?["action"] as? String ?? "scanDocument" // Hole Action aus Request
        switch result {
        case .success(let scan):
            print("Document scan successful. Processing \(scan.pageCount) pages.")
            let requiresOCR = currentRequest?["ocr"] as? Bool ?? false
            let outputType = currentRequest?["outputType"] as? String ?? "png"

            var images: [UIImage] = []
            for i in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: i))
            }
            guard !images.isEmpty else {
                print("Error: Document scan returned success but no images.")
                 // Korrektur: AppError Instanz übergeben
                webViewStore.sendErrorToWebView(action: action, error: AppError.internalError(NSLocalizedString("error.internalError.noImagesFromScanner", comment: "No images from scanner error")))
                currentRequest = nil // Reset nicht vergessen
                return
            }

            if requiresOCR {
                let recognizer = TextRecognizer(cameraScan: scan)
                recognizer.recognizeText { ocrResult in
                    switch ocrResult {
                    case .success(let recognizedText):
                        print("OCR successful.")
                        createAndSendDocumentResponse(action: action, images: images, text: recognizedText, outputType: outputType, pageCount: scan.pageCount)
                    case .failure(let ocrError):
                        print("OCR failed: \(ocrError.localizedDescription)")
                        // ocrError ist bereits ein AppError und somit lokalisiert
                        webViewStore.sendErrorToWebView(action: action, error: ocrError)
                    }
                     currentRequest = nil // Reset nach Abschluss der asynchronen Operation
                }
            } else {
                createAndSendDocumentResponse(action: action, images: images, text: nil, outputType: outputType, pageCount: scan.pageCount)
                currentRequest = nil // Reset nach synchroner Operation
            }

        case .failure(let error):
            print("Document scan failed: \(error.localizedDescription)")
            webViewStore.sendErrorToWebView(action: action, error: error) // Sende den empfangenen Fehler
            currentRequest = nil // Reset nach Fehler
        }
        // WICHTIG: Reset von currentRequest erfolgt jetzt innerhalb der Pfade (sync/async)
    }

    private func createAndSendDocumentResponse(action: String, images: [UIImage], text: String?, outputType: String, pageCount: Int) {
        var response: [String: Any] = ["action": action, "pages": pageCount]
        if let text = text, !text.isEmpty { // Nur hinzufügen, wenn Text vorhanden ist
            response["text"] = text
        }

        if outputType.lowercased() == "pdf" {
            if let pdfDataURL = PDFGenerator.generatePDFDataURL(from: images) {
                response["pdfData"] = pdfDataURL
                response["format"] = "pdf"
            } else {
                 // Korrektur: AppError Instanz übergeben
                webViewStore.sendErrorToWebView(action: action, error: AppError.pdfCreationFailed)
                return
            }
        } else {
             let imageFormat: ImageConverter.ImageFormat = (outputType.lowercased() == "jpeg" || outputType.lowercased() == "jpg") ? .jpeg() : .png
             let imageDataURLs = ImageConverter.convertImagesToDataURLs(images: images, format: imageFormat)
             if !imageDataURLs.isEmpty {
                 response["images"] = imageDataURLs
                  // Korrektur: Überprüfe den Enum-Wert für den Format-String
                 response["format"] = (imageFormat == .png) ? "png" : "jpeg"
             } else {
                 // Korrektur: AppError Instanz übergeben
                 webViewStore.sendErrorToWebView(action: action, error: AppError.imageConversionFailed(NSLocalizedString("error.imageConversionFailed.noImagesConverted", comment: "No images could be converted error")))
                 return
             }
        }
        webViewStore.sendResultToWebView(result: response)
    }

    private func handleImagePickerResult(_ result: Result<UIImage, AppError>) {
        let action = currentRequest?["action"] as? String ?? "takePhoto"
        switch result {
        case .success(let image):
            print("Photo capture successful.")
            let outputType = currentRequest?["outputType"] as? String ?? "jpeg"
            let imageFormat: ImageConverter.ImageFormat = (outputType.lowercased() == "png") ? .png : .jpeg()

            if let imageDataURL = ImageConverter.convertImageToDataURL(image: image, format: imageFormat) {
                let response: [String: Any] = [
                    "action": action,
                    "imageData": imageDataURL,
                    // Korrektur: Überprüfe den Enum-Wert für den Format-String
                    "format": (imageFormat == .png) ? "png" : "jpeg"
                ]
                webViewStore.sendResultToWebView(result: response)
            } else {
                 // Korrektur: AppError Instanz übergeben
                webViewStore.sendErrorToWebView(action: action, error: AppError.imageConversionFailed(String(format: NSLocalizedString("error.imageConversionFailed.specificType", comment: "Image could not be converted to specific type error format"), outputType)))
            }

        case .failure(let error):
            print("Photo capture failed: \(error.localizedDescription)")
            webViewStore.sendErrorToWebView(action: action, error: error)
        }
        currentRequest = nil
    }

    private func handleBarcodeScanResult(_ result: Result<(code: String, format: String), AppError>) {
        let action = currentRequest?["action"] as? String ?? "scanBarcode"
        switch result {
        case .success(let scanResult):
            if scanResult.code == "configChanged" && scanResult.format == "JSONConfig" {
                print(NSLocalizedString("status.configurationChanged.reloading", comment: "Configuration changed, reloading webview status"))
                // Die URL wurde bereits in AppSettings durch BarcodeScannerView geändert.
                // webViewStore.reloadCurrentOrNewURL() wird die neue URL laden.
                webViewStore.reloadCurrentOrNewURL()
                // Kein sendResultToWebView, da die Aktion das Neuladen der UI ist.
            } else {
                print(String(format: NSLocalizedString("status.barcodeScan.success", comment: "Barcode scan successful status format"), scanResult.code, scanResult.format))
                let response: [String: Any] = [
                    "action": action,
                    "code": scanResult.code,
                    "format": scanResult.format
                ]
                webViewStore.sendResultToWebView(result: response)
            }

        case .failure(let error):
            print(String(format: NSLocalizedString("error.barcodeScan.failed", comment: "Barcode scan failed error format"), error.localizedDescription))
            webViewStore.sendErrorToWebView(action: action, error: error)
        }
        currentRequest = nil
    }

    // MARK: - Sheet Dismiss Handling
    private func handleSheetDismiss() {
        // Wird aufgerufen, *nachdem* der Coordinator ggf. schon completion gerufen hat.
        // Wir müssen nur den Fall abfangen, dass *kein* Ergebnis kam (Abbruch durch User).
        // Wenn currentRequest noch gesetzt ist, wurde kein Ergebnis/Fehler vom Coordinator gemeldet.
        if let request = currentRequest, let action = request["action"] as? String {
             print(String(format: NSLocalizedString("warning.sheetDismissed.requestActive", comment: "Sheet dismissed while request active warning format"), action))
             // Korrektur: AppError Instanz übergeben
             webViewStore.sendErrorToWebView(action: action, error: AppError.userCancelled)
             currentRequest = nil
        }
    }
}

// MARK: - Preview
#Preview {
    // Korrektur: Preview benötigt einen StateObject
    ContentView()
}