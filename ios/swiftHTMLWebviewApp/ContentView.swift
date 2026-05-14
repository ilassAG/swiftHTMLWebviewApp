//
//  ContentView.swift
//  swiftHTMLWebviewApp
//
//  This file defines the main view of the application, managing the WebView and interactions
//  with native features like camera and document scanning. It's the entry point for the UI.
//

import SwiftUI
@preconcurrency import WebKit // Korrektur: @preconcurrency
import VisionKit
import PDFKit
import Vision // <--- Hinzugefügt für BarcodeUtils/TextRecognizer

private struct TapToPayTransitionState {
    var isVisible = false
    var isBlackout = false
    var title = ""
    var subtitle = ""
}

private struct TapToPayTransitionOverlay: View {
    let state: TapToPayTransitionState

    var body: some View {
        ZStack {
            Color.black
                .opacity(state.isBlackout ? 1 : 0.78)
                .ignoresSafeArea()

            if !state.isBlackout {
                VStack(spacing: 18) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.15)

                    VStack(spacing: 8) {
                        Text(state.title)
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)

                        Text(state.subtitle)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.76))
                            .lineSpacing(2)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 30)
                .frame(maxWidth: 340)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.black.opacity(0.52))
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(.white.opacity(0.16), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 18)
                )
                .padding(24)
            }
        }
        .allowsHitTesting(true)
    }
}

// Korrektur: ContentView als @MainActor markieren
@MainActor
struct ContentView: View {
    // Korrektur: Stelle sicher, dass Store @MainActor ist
    @StateObject var webViewStore = WebViewStore()
    @StateObject private var tapToPayBridge = TapToPayBridge()
    @Environment(\.scenePhase) private var scenePhase // Für App Lifecycle Events

    @State private var showDocumentScanner = false
    @State private var showImagePicker = false
    @State private var showBarcodeScanner = false
    @State private var currentRequest: [String: Any]? = nil
    @State private var tapToPayTransition = TapToPayTransitionState()

    var body: some View {
        ZStack {
            if webViewStore.isLoading {
                VStack(spacing: 20) {
                    Spacer()
                    Image("512")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 132, height: 132)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
                    ProgressView()
                        .tint(.gray)
                    Text(String(format: NSLocalizedString("loading.url", comment: "Loading URL message"), webViewStore.currentURLString ?? ""))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
                .ignoresSafeArea()
            } else {
                // Korrektur: Stelle sicher, dass webViewStore an WebView übergeben wird
                WebView(webViewStore: webViewStore, onScriptMessage: handleScriptMessage)
                    .ignoresSafeArea()
            }

            if tapToPayTransition.isVisible {
                TapToPayTransitionOverlay(state: tapToPayTransition)
                    .transition(.opacity)
                    .zIndex(100)
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

        case "launchConfetti":
            guard let burstCount = ConfettiOverlayPresenter.shared.launchBurst() else {
                webViewStore.sendErrorToWebView(action: action, error: AppError.internalError("Confetti overlay could not be attached."))
                currentRequest = nil
                return
            }
            let response: [String: Any] = [
                "action": action,
                "launched": true,
                "burstCount": burstCount
            ]
            webViewStore.sendResultToWebView(result: response)
            currentRequest = nil

        case "tapToPayAvailability":
            webViewStore.sendResultToWebView(result: tapToPayBridge.availabilityPayload(request: message))
            currentRequest = nil

        case "tapToPayCollect":
            currentRequest = nil
            tapToPayBridge.collect(
                request: message,
                onPhase: { phase in
                    Task { @MainActor in
                        showTapToPayTransition(phase)
                    }
                }
            ) { result in
                Task { @MainActor in
                    hideTapToPayTransition()
                    webViewStore.sendResultToWebView(result: result)
                }
            }

        default:
            print("Error: Received unknown action from JS: \(action)")
            // Korrektur: AppError Instanz übergeben
            webViewStore.sendErrorToWebView(action: action, error: AppError.invalidRequest(String(format: NSLocalizedString("error.invalidRequest.unknownAction", comment: "Unknown action error format"), action)))
            currentRequest = nil
        }
    }

    private func showTapToPayTransition(_ phase: TapToPayBridge.Phase) {
        var next = TapToPayTransitionState(isVisible: true)

        switch phase {
        case .preparing:
            next.title = "Tap to Pay is preparing"
            next.subtitle = "The payment is being activated on this iPhone."
        case .connecting:
            next.title = "Activating iPhone reader"
            next.subtitle = "This can take a moment the first time."
        case .ready:
            next.title = "Loading payment"
            next.subtitle = "The secure Stripe flow will open shortly."
        case .presenting:
            next.isBlackout = true
        case .processing:
            next.title = "Processing payment"
            next.subtitle = "Please wait a moment."
        }

        let duration = phase == .presenting ? 0.26 : 0.18
        withAnimation(.easeInOut(duration: duration)) {
            tapToPayTransition = next
        }
    }

    private func hideTapToPayTransition() {
        withAnimation(.easeOut(duration: 0.2)) {
            tapToPayTransition = TapToPayTransitionState()
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
            let shouldRemoveBackground = currentRequest?["removeBackground"] as? Bool ?? false
            let cropTransparent = currentRequest?["cropTransparent"] as? Bool ?? false
            let backgroundStyle = BackgroundRemoval.BackgroundStyle(
                backgroundMode: currentRequest?["background"] as? String,
                backgroundColorHex: currentRequest?["backgroundColor"] as? String
            )

            guard shouldRemoveBackground else {
                sendPhotoResult(action: action, image: image, requestedOutputType: outputType, backgroundRemoved: false, backgroundStyle: backgroundStyle, cropped: false)
                currentRequest = nil
                return
            }

            guard BackgroundRemoval.isSupported else {
                webViewStore.sendErrorToWebView(action: action, error: AppError.featureNotAvailable("Background Removal"))
                currentRequest = nil
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let processedImage = try BackgroundRemoval.removeBackground(from: image, style: backgroundStyle, cropTransparent: cropTransparent)
                    DispatchQueue.main.async {
                        self.sendPhotoResult(
                            action: action,
                            image: processedImage,
                            requestedOutputType: outputType,
                            backgroundRemoved: true,
                            backgroundStyle: backgroundStyle,
                            cropped: cropTransparent && backgroundStyle.isTransparent
                        )
                        self.currentRequest = nil
                    }
                } catch {
                    let appError: AppError
                    if let knownError = error as? AppError {
                        appError = knownError
                    } else {
                        appError = .internalError("Background removal failed: \(error.localizedDescription)")
                    }

                    DispatchQueue.main.async {
                        self.webViewStore.sendErrorToWebView(action: action, error: appError)
                        self.currentRequest = nil
                    }
                }
            }

        case .failure(let error):
            print("Photo capture failed: \(error.localizedDescription)")
            webViewStore.sendErrorToWebView(action: action, error: error)
            currentRequest = nil
        }
    }

    private func sendPhotoResult(action: String, image: UIImage, requestedOutputType: String, backgroundRemoved: Bool, backgroundStyle: BackgroundRemoval.BackgroundStyle, cropped: Bool) {
        let outputTypeLower = requestedOutputType.lowercased()
        let imageFormat: ImageConverter.ImageFormat

        // Transparenter Hintergrund funktioniert nur mit PNG.
        if backgroundRemoved && backgroundStyle.isTransparent {
            imageFormat = .png
        } else {
            imageFormat = (outputTypeLower == "png") ? .png : .jpeg()
        }

        if let imageDataURL = ImageConverter.convertImageToDataURL(image: image, format: imageFormat) {
            var response: [String: Any] = [
                "action": action,
                "imageData": imageDataURL,
                "format": (imageFormat == .png) ? "png" : "jpeg"
            ]

            if backgroundRemoved {
                response["backgroundRemoved"] = true
                response["background"] = backgroundStyle.responseMode
                response["cropped"] = cropped
                if let colorHex = backgroundStyle.responseColorHex {
                    response["backgroundColor"] = colorHex
                }
            }

            webViewStore.sendResultToWebView(result: response)
        } else {
            webViewStore.sendErrorToWebView(
                action: action,
                error: AppError.imageConversionFailed(
                    String(
                        format: NSLocalizedString("error.imageConversionFailed.specificType", comment: "Image could not be converted to specific type error format"),
                        requestedOutputType
                    )
                )
            )
        }
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
