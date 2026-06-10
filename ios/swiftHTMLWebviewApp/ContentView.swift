//
//  ContentView.swift
//  swiftHTMLWebviewApp
//
//  This file defines the main view of the application, managing the WebView and interactions
//  with native features like camera and document scanning. It's the entry point for the UI.
//

import SwiftUI
@preconcurrency import WebKit
import VisionKit
import PDFKit
import Vision

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

@MainActor
struct ContentView: View {
    @StateObject var webViewStore = WebViewStore()
    @StateObject private var tapToPayBridge = TapToPayBridge()
    @StateObject private var printerBridge = PrinterBridge()
    @StateObject private var beaconBridge = BeaconBridge()
    @StateObject private var beaconAdvertiserBridge = BeaconAdvertiserBridge()
    @StateObject private var deviceBridge = DeviceBridge()
    @StateObject private var idleTimerBridge = IdleTimerBridge()
    @StateObject private var locationBridge = LocationBridge()
    @StateObject private var arPositionBridge = ARPositionBridge()
    @StateObject private var arGuidedMeasurementBridge = ARGuidedMeasurementBridge()
    @StateObject private var roomPlanBridge = RoomPlanBridge()
    @StateObject private var screenStreamBridge = ScreenStreamBridge()
    @StateObject private var sensorBridge = SensorBridge()
    @StateObject private var configPairingBridge = ConfigPairingBridge()
    @StateObject private var nfcTagReaderBridge = NFCTagReaderBridge()
    @StateObject private var notificationBridge = NotificationBridge.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var showDocumentScanner = false
    @State private var showImagePicker = false
    @State private var showBarcodeScanner = false
    @State private var currentRequest: [String: Any]? = nil
    @State private var tapToPayTransition = TapToPayTransitionState()
    @State private var continuousScannerConfig: ContinuousBarcodeScannerConfig?

    var body: some View {
        ZStack {
            // Keep the WKWebView in the hierarchy while loading. If the loader
            // replaces it, local file loads can never finish and clear isLoading.
            WebView(webViewStore: webViewStore, onScriptMessage: handleScriptMessage)
                .ignoresSafeArea()

            continuousScannerOverlay
            TwoFingerConfigGestureInstaller(webView: webViewStore.webView) {
                showConfigPairingFromGesture()
            }
            .frame(width: 0, height: 0)

            configPairingOverlay

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
            }

            if tapToPayTransition.isVisible {
                TapToPayTransitionOverlay(state: tapToPayTransition)
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .onAppear {
            configureConfigPairingBridge()
            configureNotificationBridge()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                print("App became active. Checking for URL updates.")
                webViewStore.reloadCurrentOrNewURL()
            }
        }
        .onDisappear {
            idleTimerBridge.shutdown()
            locationBridge.shutdown()
            arPositionBridge.shutdown()
            arGuidedMeasurementBridge.shutdown()
            roomPlanBridge.shutdown()
            screenStreamBridge.shutdown()
            sensorBridge.shutdown()
            _ = configPairingBridge.stopTargetSession(request: ["action": "configPairingStop"])
            nfcTagReaderBridge.shutdown()
            beaconAdvertiserBridge.shutdown()
        }
        .sheet(isPresented: $showDocumentScanner, onDismiss: handleSheetDismiss) {
            DocumentScannerView(isPresented: $showDocumentScanner) { result in
                handleDocumentScanResult(result)
            }
        }
        .sheet(isPresented: $showImagePicker, onDismiss: handleSheetDismiss) {
            let requestedCamera = currentRequest?["camera"] as? String
            let cameraDevice: UIImagePickerController.CameraDevice = (requestedCamera == "front") ? .front : .rear

            ImagePickerView(isPresented: $showImagePicker, cameraDevice: cameraDevice) { result in
                handleImagePickerResult(result)
            }
        }
        .sheet(isPresented: $showBarcodeScanner, onDismiss: handleSheetDismiss) {
            if BarcodeScannerView.isSupported {
                let requestedTypes = currentRequest?["types"] as? [String]
                let scanTypes = BarcodeUtils.mapStringToDataTypes(requestedTypes)

                BarcodeScannerView(isPresented: $showBarcodeScanner, recognizedDataTypes: scanTypes) { result in
                    handleBarcodeScanResult(result)
                }
            } else {
                Text(NSLocalizedString("error.barcodeScannerNotSupported.message", comment: "Barcode scanner not supported message"))
                    .padding()
                    .onAppear {
                        let action = currentRequest?["action"] as? String
                        webViewStore.sendErrorToWebView(action: action, error: AppError.featureNotAvailable(NSLocalizedString("error.featureNotAvailable.barcodeScanner", comment: "Feature name: Barcode Scanner")))
                        showBarcodeScanner = false
                }
            }
        }
        .sheet(isPresented: $roomPlanBridge.scannerVisible) {
            if #available(iOS 16.0, *) {
                RoomPlanScannerSheet(bridge: roomPlanBridge)
            } else {
                Text("RoomPlan requires iOS 16 or newer.")
                    .padding()
                    .onAppear {
                        webViewStore.sendResultToWebView(result: [
                            "platform": "ios",
                            "action": "roomPlanScanError",
                            "success": false,
                            "supported": false,
                            "source": "roomplan",
                            "error": "RoomPlan requires iOS 16 or newer."
                        ])
                        roomPlanBridge.scannerVisible = false
                    }
            }
        }
        .sheet(isPresented: $arGuidedMeasurementBridge.viewVisible) {
            ARGuidedMeasurementSheet(bridge: arGuidedMeasurementBridge)
        }
    }

    // MARK: - JavaScript Message Handling
    private func handleScriptMessage(_ message: [String: Any]) {
        guard let action = message["action"] as? String else {
            print("Error: Received message from JS without 'action' key.")

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

                 webViewStore.sendErrorToWebView(action: action, error: AppError.featureNotAvailable(NSLocalizedString("error.featureNotAvailable.camera", comment: "Feature name: Camera")))
                 currentRequest = nil
                 return
             }
            self.showImagePicker = true

        case "scanBarcode":
            guard BarcodeScannerView.isSupported else {
                 print("Error: DataScanner is not supported on this device.")

                 webViewStore.sendErrorToWebView(action: action, error: AppError.featureNotAvailable(NSLocalizedString("error.featureNotAvailable.barcodeScanner", comment: "Feature name: Barcode Scanner")))
                 currentRequest = nil
                 return
             }
            self.showBarcodeScanner = true

        case "nfcTagRead":
            currentRequest = nil
            nfcTagReaderBridge.read(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }

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

        case "deviceInfoGet":
            webViewStore.sendResultToWebView(result: deviceBridge.deviceInfo(request: message))
            currentRequest = nil

        case "screenOrientationGet":
            webViewStore.sendResultToWebView(result: OrientationController.shared.statusPayload(request: message))
            currentRequest = nil

        case "screenOrientationSet":
            let mode = stringValue(message["mode"]).isEmpty ? stringValue(message["orientation"]) : stringValue(message["mode"])
            var response = OrientationController.shared.setMode(mode.isEmpty ? "unlocked" : mode)
            if let requestId = message["requestId"] {
                response["requestId"] = requestId
            }
            webViewStore.sendResultToWebView(result: response)
            currentRequest = nil

        case "wifiStatusGet":
            currentRequest = nil
            deviceBridge.wifiStatus(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }

        case "wifiConfigure":
            currentRequest = nil
            deviceBridge.configureWifi(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }

        case "screenshotGet":
            currentRequest = nil
            deviceBridge.screenshot(request: message, webView: webViewStore.webView) { result in
                webViewStore.sendResultToWebView(result: result)
            }

        case "geoLocationGet":
            currentRequest = nil
            locationBridge.get(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }

        case "geoLocationStart":
            webViewStore.sendResultToWebView(result: locationBridge.start(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            })
            currentRequest = nil

        case "geoLocationStop":
            webViewStore.sendResultToWebView(result: locationBridge.stop(request: message))
            currentRequest = nil

        case "arPositionStart":
            webViewStore.sendResultToWebView(result: arPositionBridge.start(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            })
            currentRequest = nil

        case "arPositionStop":
            webViewStore.sendResultToWebView(result: arPositionBridge.stop(request: message))
            currentRequest = nil

        case "arGuidedMeasurementStart":
            webViewStore.sendResultToWebView(result: arGuidedMeasurementBridge.start(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            })
            currentRequest = nil

        case "arGuidedMeasurementSetAnchors":
            webViewStore.sendResultToWebView(result: arGuidedMeasurementBridge.setAnchors(request: message))
            currentRequest = nil

        case "arGuidedMeasurementStop":
            webViewStore.sendResultToWebView(result: arGuidedMeasurementBridge.stop(request: message))
            currentRequest = nil

        case "roomPlanScanStart":
            webViewStore.sendResultToWebView(result: roomPlanBridge.start(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            })
            currentRequest = nil

        case "roomPlanScanStop":
            webViewStore.sendResultToWebView(result: roomPlanBridge.stop(request: message))
            currentRequest = nil

        case "roomPlanScanExport":
            webViewStore.sendResultToWebView(result: roomPlanBridge.export(request: message))
            currentRequest = nil

        case "soundPlay":
            webViewStore.sendResultToWebView(result: deviceBridge.playSound(request: message))
            currentRequest = nil

        case "notificationPermissionGet":
            currentRequest = nil
            notificationBridge.permissionStatus(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }

        case "notificationPermissionRequest":
            currentRequest = nil
            notificationBridge.requestPermission(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }

        case "notificationShow":
            currentRequest = nil
            notificationBridge.show(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }

        case "notificationSchedule":
            currentRequest = nil
            notificationBridge.schedule(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }

        case "notificationCancel":
            webViewStore.sendResultToWebView(result: notificationBridge.cancel(request: message))
            currentRequest = nil

        case "notificationCancelAll":
            webViewStore.sendResultToWebView(result: notificationBridge.cancelAll(request: message))
            currentRequest = nil

        case "notificationList":
            currentRequest = nil
            notificationBridge.list(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }

        case "idleTimerStart":
            webViewStore.sendResultToWebView(result: idleTimerBridge.start(request: message, webView: webViewStore.webView) { result in
                webViewStore.sendResultToWebView(result: result)
            })
            currentRequest = nil

        case "idleTimerStop":
            webViewStore.sendResultToWebView(result: idleTimerBridge.stop(request: message))
            currentRequest = nil

        case "idleTimerReset":
            webViewStore.sendResultToWebView(result: idleTimerBridge.reset(request: message))
            currentRequest = nil

        case "idleActivity":
            idleTimerBridge.recordActivity()
            currentRequest = nil

        case "screenStreamStart":
            webViewStore.sendResultToWebView(result: screenStreamBridge.start(request: message, webView: webViewStore.webView) { result in
                webViewStore.sendResultToWebView(result: result)
            })
            currentRequest = nil

        case "screenStreamStop":
            webViewStore.sendResultToWebView(result: screenStreamBridge.stop(request: message))
            currentRequest = nil

        case "sensorCapabilitiesGet":
            webViewStore.sendResultToWebView(result: sensorBridge.capabilities(request: message))
            currentRequest = nil

        case "sensorStreamStart":
            webViewStore.sendResultToWebView(result: sensorBridge.start(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            })
            currentRequest = nil

        case "sensorStreamStop":
            webViewStore.sendResultToWebView(result: sensorBridge.stop(request: message))
            currentRequest = nil

        case "configPairingShow":
            configureConfigPairingBridge()
            webViewStore.sendResultToWebView(result: configPairingBridge.startTargetSession(request: message))
            currentRequest = nil

        case "configPairingStop":
            webViewStore.sendResultToWebView(result: configPairingBridge.stopTargetSession(request: message))
            currentRequest = nil

        case "configPairingConnect":
            configureConfigPairingBridge()
            webViewStore.sendResultToWebView(result: configPairingBridge.connect(request: message))
            currentRequest = nil

        case "configPairingDisconnect":
            webViewStore.sendResultToWebView(result: configPairingBridge.disconnect(request: message))
            currentRequest = nil

        case "configPairingSend":
            webViewStore.sendResultToWebView(result: configPairingBridge.send(request: message))
            currentRequest = nil

        case "settingsGet":
            webViewStore.sendResultToWebView(result: settingsGetResponse(request: message))
            currentRequest = nil

        case "settingsSet":
            webViewStore.sendResultToWebView(result: settingsSetResponse(request: message))
            currentRequest = nil

        case "continuousScanStart", "dataScanStart", "loginScanStart":
            startContinuousScanner(action: action, request: message)

        case "continuousScanStop", "dataScanEnd", "loginScanEnd":
            stopContinuousScanner(action: action, request: message)

        case "previewBoxLocationUpdate":
            updateContinuousScannerPreviewRect(action: action, request: message)

        case "beaconsStart":
            let response = beaconBridge.start(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }
            webViewStore.sendResultToWebView(result: response)
            currentRequest = nil

        case "beaconsStop":
            webViewStore.sendResultToWebView(result: beaconBridge.stop(request: message))
            currentRequest = nil

        case "beaconAdvertiseStart":
            let response = beaconAdvertiserBridge.start(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }
            webViewStore.sendResultToWebView(result: response)
            currentRequest = nil

        case "beaconAdvertiseStop":
            webViewStore.sendResultToWebView(result: beaconAdvertiserBridge.stop(request: message))
            currentRequest = nil

        case "printerEpsonHelloWorld":
            currentRequest = nil
            printerBridge.printEpsonHelloWorld(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }

        case "printerHelloWorld":
            currentRequest = nil
            printerBridge.printHelloWorld(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }

        case "printerDiscover":
            currentRequest = nil
            printerBridge.discoverPrinters(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }

        default:
            print("Error: Received unknown action from JS: \(action)")

            webViewStore.sendErrorToWebView(action: action, error: AppError.invalidRequest(String(format: NSLocalizedString("error.invalidRequest.unknownAction", comment: "Unknown action error format"), action)))
            currentRequest = nil
        }
    }

    private var configPairingOverlay: some View {
        Group {
            if let payload = configPairingBridge.targetPayload,
               let qrImage = configPairingBridge.targetQRCode {
                ZStack {
                    Color.black.opacity(0.68)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        Text("Config Pairing")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 260, height: 260)
                            .padding(14)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                        Text(configPairingBridge.targetAdvertising ? "BLE aktiv" : "BLE startet")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.82))

                        Text(payload)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(4)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)

                        Button {
                            webViewStore.sendResultToWebView(result: configPairingBridge.stopTargetSession(request: ["action": "configPairingStop"]))
                        } label: {
                            Text("Schliessen")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(22)
                    .frame(maxWidth: 360)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.black.opacity(0.78))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                    )
                    .padding(24)
                }
                .zIndex(90)
            }
        }
    }

    private func configureConfigPairingBridge() {
        let webViewStore = webViewStore
        let deviceBridge = deviceBridge
        configPairingBridge.configure(
            eventHandler: { result in
                webViewStore.sendResultToWebView(result: result)
            },
            settingsProvider: {
                AppSettings.shared.configurationSnapshot()
            },
            settingsApplier: { values in
                AppSettings.shared.applyConfiguration(values)
            },
            wifiConfigurator: { request, completion in
                deviceBridge.configureWifi(request: request, completion: completion)
            },
            reloadHandler: {
                webViewStore.reloadCurrentOrNewURL()
            },
            deviceInfoProvider: {
                deviceBridge.deviceInfo(request: ["action": "deviceInfoGet"])
            }
        )
    }

    private func configureNotificationBridge() {
        notificationBridge.configure { result in
            webViewStore.sendResultToWebView(result: result)
        }
    }

    private func settingsGetResponse(request: [String: Any]) -> [String: Any] {
        var response = baseSettingsResponse(request: request, action: "settingsGet")
        response["success"] = true
        response["settings"] = AppSettings.shared.configurationSnapshot()
        return response
    }

    private func settingsSetResponse(request: [String: Any]) -> [String: Any] {
        let token = stringValue(request["token"] ?? request["securityToken"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token == AppSettings.shared.securityToken else {
            var response = baseSettingsResponse(request: request, action: "settingsSet")
            response["success"] = false
            response["error"] = "securityToken is required for settingsSet."
            return response
        }

        let values = (request["settings"] as? [String: Any]) ?? request
        let snapshot = AppSettings.shared.applyConfiguration(values)
        var response = baseSettingsResponse(request: request, action: "settingsSet")
        response["success"] = true
        response["settings"] = snapshot
        return response
    }

    private func baseSettingsResponse(request: [String: Any], action: String) -> [String: Any] {
        var response: [String: Any] = [
            "platform": "ios",
            "action": action
        ]
        if let requestId = request["requestId"] {
            response["requestId"] = requestId
        }
        return response
    }

    private func showConfigPairingFromGesture() {
        configureConfigPairingBridge()
        let response = configPairingBridge.startTargetSession(request: [
            "action": "configPairingShow",
            "source": "twoFingerHold"
        ])
        webViewStore.sendResultToWebView(result: response)
    }

    private var continuousScannerOverlay: some View {
        GeometryReader { proxy in
            if let config = continuousScannerConfig {
                let frame = scannerFrame(for: config.previewRect, in: proxy.size)
                ZStack(alignment: .topTrailing) {
                    ContinuousBarcodeScannerView(
                        config: config,
                        onResult: { result in
                            webViewStore.sendResultToWebView(result: result)
                        },
                        onError: { message in
                            webViewStore.sendResultToWebView(result: [
                                "platform": "ios",
                                "action": "continuousScanStart",
                                "success": false,
                                "error": message
                            ])
                            continuousScannerConfig = nil
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.yellow, lineWidth: 2)
                    )

                    Button {
                        stopContinuousScanner(action: "continuousScanStop", request: ["action": "continuousScanStop"])
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(radius: 3)
                            .padding(6)
                    }
                    .accessibilityLabel("Stop scanner")
                }
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .zIndex(40)
            }
        }
        .ignoresSafeArea()
    }

    private func startContinuousScanner(action: String, request: [String: Any]) {
        var config = continuousScannerConfig ?? ContinuousBarcodeScannerConfig()
        config.action = action
        config.mode = scannerMode(for: action, request: request)
        config.camera = scannerCamera(for: action, request: request)
        config.types = request["types"] as? [String] ?? config.types
        config.repeatDelaySeconds = numericValue(request["repeatDelaySeconds"])
            ?? numericValue(request["repeatDelay"])
            ?? config.repeatDelaySeconds
        config.previewRect = previewRect(from: request["previewRect"] as? [String: Any]) ?? config.previewRect
        continuousScannerConfig = config

        webViewStore.sendResultToWebView(result: [
            "platform": "ios",
            "action": action,
            "success": true,
            "mode": config.mode,
            "camera": config.camera,
            "types": config.types,
            "repeatDelaySeconds": config.repeatDelaySeconds,
            "previewRect": previewRectPayload(config.previewRect)
        ])
        currentRequest = nil
    }

    private func stopContinuousScanner(action: String, request: [String: Any]) {
        continuousScannerConfig = nil
        var response: [String: Any] = [
            "platform": "ios",
            "action": action,
            "success": true
        ]
        if let requestId = request["requestId"] {
            response["requestId"] = requestId
        }
        webViewStore.sendResultToWebView(result: response)
        currentRequest = nil
    }

    private func updateContinuousScannerPreviewRect(action: String, request: [String: Any]) {
        guard var config = continuousScannerConfig else {
            webViewStore.sendResultToWebView(result: [
                "platform": "ios",
                "action": action,
                "success": false,
                "error": "No continuous scanner is running."
            ])
            currentRequest = nil
            return
        }

        guard let previewRect = previewRect(from: request["previewRect"] as? [String: Any]) else {
            webViewStore.sendResultToWebView(result: [
                "platform": "ios",
                "action": action,
                "success": false,
                "error": "Invalid previewRect."
            ])
            currentRequest = nil
            return
        }

        config.previewRect = previewRect
        continuousScannerConfig = config
        webViewStore.sendResultToWebView(result: [
            "platform": "ios",
            "action": action,
            "success": true,
            "previewRect": previewRectPayload(previewRect)
        ])
        currentRequest = nil
    }

    private func scannerMode(for action: String, request: [String: Any]) -> String {
        if let mode = request["mode"] as? String, !mode.isEmpty {
            return mode
        }
        return action == "loginScanStart" ? "login" : "data"
    }

    private func scannerCamera(for action: String, request: [String: Any]) -> String {
        if let camera = request["camera"] as? String, camera == "front" || camera == "back" {
            return camera
        }
        return action == "loginScanStart" ? "front" : "back"
    }

    private func previewRect(from value: [String: Any]?) -> CGRect? {
        guard let value,
              let left = normalizedRectValue(value["left"] ?? value["x"]),
              let top = normalizedRectValue(value["top"] ?? value["y"]),
              let width = normalizedRectValue(value["width"]),
              let height = normalizedRectValue(value["height"]) else {
            return nil
        }

        let safeWidth = min(max(width, 0.1), 1)
        let safeHeight = min(max(height, 0.1), 1)
        let safeLeft = min(max(left, 0), 1 - safeWidth)
        let safeTop = min(max(top, 0), 1 - safeHeight)
        return CGRect(x: safeLeft, y: safeTop, width: safeWidth, height: safeHeight)
    }

    private func normalizedRectValue(_ value: Any?) -> CGFloat? {
        guard let rawValue = numericValue(value) else { return nil }
        let normalized = rawValue > 1 ? rawValue / 100 : rawValue
        return CGFloat(normalized)
    }

    private func numericValue(_ value: Any?) -> Double? {
        switch value {
        case let doubleValue as Double:
            return doubleValue
        case let intValue as Int:
            return Double(intValue)
        case let numberValue as NSNumber:
            return numberValue.doubleValue
        case let stringValue as String:
            return Double(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private func previewRectPayload(_ rect: CGRect) -> [String: Double] {
        [
            "left": Double(rect.minX),
            "top": Double(rect.minY),
            "width": Double(rect.width),
            "height": Double(rect.height)
        ]
    }

    private func scannerFrame(for rect: CGRect, in size: CGSize) -> CGRect {
        let width = max(size.width * rect.width, 120)
        let height = max(size.height * rect.height, 120)
        let x = min(max(size.width * rect.minX, 0), max(size.width - width, 0))
        let y = min(max(size.height * rect.minY, 0), max(size.height - height, 0))
        return CGRect(x: x, y: y, width: width, height: height)
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

                webViewStore.sendErrorToWebView(action: action, error: AppError.pdfCreationFailed)
                return
            }
        } else {
             let imageFormat: ImageConverter.ImageFormat = (outputType.lowercased() == "jpeg" || outputType.lowercased() == "jpg") ? .jpeg() : .png
             let imageDataURLs = ImageConverter.convertImagesToDataURLs(images: images, format: imageFormat)
             if !imageDataURLs.isEmpty {
                 response["images"] = imageDataURLs

                 response["format"] = (imageFormat == .png) ? "png" : "jpeg"
             } else {

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

             webViewStore.sendErrorToWebView(action: action, error: AppError.userCancelled)
             currentRequest = nil
        }
    }
}

private struct TwoFingerConfigGestureInstaller: UIViewRepresentable {
    let webView: WKWebView
    let onTrigger: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTrigger: onTrigger)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        context.coordinator.install(on: webView)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTrigger = onTrigger
        context.coordinator.install(on: webView)
    }

    final class Coordinator: NSObject {
        var onTrigger: () -> Void
        private weak var installedWebView: WKWebView?
        private var recognizer: UILongPressGestureRecognizer?

        init(onTrigger: @escaping () -> Void) {
            self.onTrigger = onTrigger
        }

        func install(on webView: WKWebView) {
            guard installedWebView !== webView else { return }
            if let recognizer, let installedWebView {
                installedWebView.removeGestureRecognizer(recognizer)
            }

            let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleGesture(_:)))
            recognizer.minimumPressDuration = 1.5
            recognizer.numberOfTouchesRequired = 2
            recognizer.cancelsTouchesInView = false
            webView.addGestureRecognizer(recognizer)

            self.recognizer = recognizer
            installedWebView = webView
        }

        @objc private func handleGesture(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let view = recognizer.view else { return }
            let location = recognizer.location(in: view)
            let centerRect = view.bounds.insetBy(dx: view.bounds.width * 0.25, dy: view.bounds.height * 0.25)
            guard centerRect.contains(location) else { return }
            onTrigger()
        }
    }
}

// MARK: - Preview
#Preview {

    ContentView()
}
