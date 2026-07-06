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
import Darwin

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

private struct KioskReloadControlConfig {
    var enabled = false
    var opacity = 0.10
    var longPressSeconds = 2.0
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
    @StateObject private var arOverlayBridge = AROverlayBridge()
    @StateObject private var roomPlanBridge = RoomPlanBridge()
    @StateObject private var screenStreamBridge = ScreenStreamBridge()
    @StateObject private var sensorBridge = SensorBridge()
    @StateObject private var configPairingBridge = ConfigPairingBridge()
    @StateObject private var nfcTagReaderBridge = NFCTagReaderBridge()
    @StateObject private var natsBridge = NATSBridge()
    @StateObject private var notificationBridge = NotificationBridge.shared
    @Environment(\.scenePhase) private var scenePhase
    private let settingsBridge = SettingsBridge()
    private let nativeStorageBridge = NativeStorageBridge()
    private let nativeFilesystemBridge = NativeFilesystemBridge()
    private let nativeSQLiteBridge = NativeSQLiteBridge()
    private let recoveryBarcodeHandler = RecoveryBarcodeHandler(
        invalidMessage: AppSettings.shared.recoveryInvalidQRMessage,
        applyConfiguration: { values in AppSettings.shared.applyConfiguration(values) }
    )

    @State private var showDocumentScanner = false
    @State private var showImagePicker = false
    @State private var showPortraitCapture = false
    @State private var showBarcodeScanner = false
    @State private var currentRequest: [String: Any]? = nil
    @State private var tapToPayTransition = TapToPayTransitionState()
    @State private var continuousScannerConfig: ContinuousBarcodeScannerConfig?
    @State private var configPairingScannerCamera = "front"
    @State private var bridgeRouter: BridgeRouter?
    @State private var kioskReloadControl = KioskReloadControlConfig()
    @State private var postWifiReloadGeneration = UUID()
    @State private var natsTelemetryTimer: Timer?

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
            kioskReloadControlOverlay

            if webViewStore.isLoading {
                VStack(spacing: 20) {
                    Spacer()
                    Image(AppSettings.shared.loadingImageName)
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
            installBridgeRouterIfNeeded()
            configureConfigPairingBridge()
            configureNotificationBridge()
            configureNATSCommandExecutor()
            startNATSRuntime(reason: "appStart")
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                print("App became active. Checking for URL updates.")
                webViewStore.reloadCurrentOrNewURL()
                connectNATSIfConfigured(reason: "sceneActive")
                publishNATSTelemetry(reason: "sceneActive")
            }
        }
        .onDisappear {
            idleTimerBridge.shutdown()
            locationBridge.shutdown()
            arPositionBridge.shutdown()
            arGuidedMeasurementBridge.shutdown()
            arOverlayBridge.shutdown()
            roomPlanBridge.shutdown()
            screenStreamBridge.shutdown()
            sensorBridge.shutdown()
            _ = configPairingBridge.stopTargetSession(request: ["action": "configPairingStop"])
            nfcTagReaderBridge.shutdown()
            beaconAdvertiserBridge.shutdown()
            stopNATSTelemetry()
            _ = natsBridge.disconnect(request: ["action": "natsDisconnect"])
        }
        .sheet(isPresented: $showDocumentScanner, onDismiss: handleSheetDismiss) {
            DocumentScannerView(isPresented: $showDocumentScanner) { result in
                handleDocumentScanResult(result)
            }
        }
        .sheet(isPresented: $showImagePicker, onDismiss: handleSheetDismiss) {
            let cameraDevice = PhotoCaptureRequest(currentRequest).cameraDevice

            ImagePickerView(isPresented: $showImagePicker, cameraDevice: cameraDevice) { result in
                handleImagePickerResult(result)
            }
        }
        .sheet(isPresented: $showPortraitCapture, onDismiss: handleSheetDismiss) {
            PortraitCaptureView(isPresented: $showPortraitCapture, request: PortraitCaptureRequest(currentRequest)) { result in
                handlePortraitCaptureResult(result)
            }
        }
        .sheet(isPresented: $showBarcodeScanner, onDismiss: handleSheetDismiss) {
            if BarcodeScannerView.isSupported {
                let scanTypes = BarcodeUtils.mapStringToDataTypes(BarcodeCaptureRequest(currentRequest).types)

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
        .sheet(isPresented: $arOverlayBridge.viewVisible) {
            AROverlaySheet(bridge: arOverlayBridge)
        }
    }

    // MARK: - JavaScript Message Handling
    private func handleScriptMessage(_ message: [String: Any]) {
        installBridgeRouterIfNeeded()
        bridgeRouter?.postMessage(message)
    }

    private func installBridgeRouterIfNeeded() {
        guard bridgeRouter == nil else {
            return
        }
        bridgeRouter = makeBridgeRouter()
    }

    private func makeBridgeRouter() -> BridgeRouter {
        let router = BridgeRouter.Builder(
            resultHandler: { result in
                webViewStore.sendResultToWebView(result: result)
            },
            missingActionMessage: AppError.invalidRequest(NSLocalizedString("error.invalidRequest.missingAction", comment: "Missing action parameter error")).localizedDescription,
            unknownActionMessage: { action in
                AppError.invalidRequest(String(format: NSLocalizedString("error.invalidRequest.unknownAction", comment: "Unknown action error format"), action)).localizedDescription
            },
            unknownActionHandler: {
                currentRequest = nil
            }
        )
        .on("scanDocument") { message in
            currentRequest = message
            showDocumentScanner = true
        }
        .on("takePhoto") { message in
            let action = "takePhoto"
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                print("Error: Camera not available.")
                webViewStore.sendErrorToWebView(action: action, error: AppError.featureNotAvailable(NSLocalizedString("error.featureNotAvailable.camera", comment: "Feature name: Camera")))
                currentRequest = nil
                return
            }
            currentRequest = message
            showImagePicker = true
        }
        .on("portraitCapture") { message in
            let action = "portraitCapture"
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                print("Error: Camera not available.")
                webViewStore.sendErrorToWebView(action: action, error: AppError.featureNotAvailable(NSLocalizedString("error.featureNotAvailable.camera", comment: "Feature name: Camera")))
                currentRequest = nil
                return
            }
            currentRequest = message
            showPortraitCapture = true
        }
        .on("scanBarcode") { message in
            let action = "scanBarcode"
            guard BarcodeScannerView.isSupported else {
                print("Error: DataScanner is not supported on this device.")
                webViewStore.sendErrorToWebView(action: action, error: AppError.featureNotAvailable(NSLocalizedString("error.featureNotAvailable.barcodeScanner", comment: "Feature name: Barcode Scanner")))
                currentRequest = nil
                return
            }
            currentRequest = message
            showBarcodeScanner = true
        }
        .on("nfcTagRead") { message in
            currentRequest = nil
            nfcTagReaderBridge.read(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }
        }
        .on("launchConfetti") { message in
            let action = "launchConfetti"
            guard let burstCount = ConfettiOverlayPresenter.shared.launchBurst() else {
                webViewStore.sendErrorToWebView(action: action, error: AppError.internalError("Confetti overlay could not be attached."))
                currentRequest = nil
                return
            }
            webViewStore.sendResultToWebView(result: NativeCommandPayload.launchConfettiResponse(
                request: message,
                burstCount: burstCount
            ))
            currentRequest = nil
        }
        .on("tapToPayAvailability") { message in
            webViewStore.sendResultToWebView(result: tapToPayBridge.availabilityPayload(request: message))
            currentRequest = nil
        }
        .on("tapToPayCollect") { message in
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
        }
        .on("deviceInfoGet") { message in
            webViewStore.sendResultToWebView(result: deviceBridge.deviceInfo(request: message))
            currentRequest = nil
        }
        .on("screenOrientationGet") { message in
            webViewStore.sendResultToWebView(result: OrientationController.shared.statusPayload(request: message))
            currentRequest = nil
        }
        .on("screenOrientationSet") { message in
            webViewStore.sendResultToWebView(result: OrientationController.shared.setPayload(request: message))
            currentRequest = nil
        }
        .on("wifiStatusGet") { message in
            currentRequest = nil
            deviceBridge.wifiStatus(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }
        }
        .on("wifiConfigure") { message in
            currentRequest = nil
            deviceBridge.configureWifi(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }
        }
        .on("screenshotGet") { message in
            currentRequest = nil
            deviceBridge.screenshot(request: message, webView: webViewStore.webView) { result in
                webViewStore.sendResultToWebView(result: result)
            }
        }
        .on("geoLocationGet") { message in
            currentRequest = nil
            locationBridge.get(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }
        }
        .on("geoLocationStart") { message in
            webViewStore.sendResultToWebView(result: locationBridge.start(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            })
            currentRequest = nil
        }
        .on("geoLocationStop") { message in
            webViewStore.sendResultToWebView(result: locationBridge.stop(request: message))
            currentRequest = nil
        }
        .on("arPositionStart") { message in
            webViewStore.sendResultToWebView(result: arPositionBridge.start(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            })
            currentRequest = nil
        }
        .on("arPositionStop") { message in
            webViewStore.sendResultToWebView(result: arPositionBridge.stop(request: message))
            currentRequest = nil
        }
        .on("arGuidedMeasurementStart") { message in
            webViewStore.sendResultToWebView(result: arGuidedMeasurementBridge.start(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            })
            currentRequest = nil
        }
        .on("arGuidedMeasurementSetAnchors") { message in
            webViewStore.sendResultToWebView(result: arGuidedMeasurementBridge.setAnchors(request: message))
            currentRequest = nil
        }
        .on("arGuidedMeasurementUpdateStats") { message in
            webViewStore.sendResultToWebView(result: arGuidedMeasurementBridge.updateStats(request: message))
            currentRequest = nil
        }
        .on("arGuidedMeasurementStop") { message in
            webViewStore.sendResultToWebView(result: arGuidedMeasurementBridge.stop(request: message))
            currentRequest = nil
        }
        .onAll(BridgeActionCatalog.arOverlayOpenActions) { message in
            webViewStore.sendResultToWebView(result: arOverlayBridge.open(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            })
            currentRequest = nil
        }
        .onAll(BridgeActionCatalog.arOverlayCloseActions) { message in
            webViewStore.sendResultToWebView(result: arOverlayBridge.close(request: message))
            currentRequest = nil
        }
        .on("roomPlanScanStart") { message in
            webViewStore.sendResultToWebView(result: roomPlanBridge.start(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            })
            currentRequest = nil
        }
        .on("roomPlanScanStop") { message in
            webViewStore.sendResultToWebView(result: roomPlanBridge.stop(request: message))
            currentRequest = nil
        }
        .on("roomPlanScanExport") { message in
            webViewStore.sendResultToWebView(result: roomPlanBridge.export(request: message))
            currentRequest = nil
        }
        .on("soundPlay") { message in
            webViewStore.sendResultToWebView(result: deviceBridge.playSound(request: message))
            currentRequest = nil
        }
        .on("notificationPermissionGet") { message in
            currentRequest = nil
            notificationBridge.permissionStatus(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }
        }
        .on("notificationPermissionRequest") { message in
            currentRequest = nil
            notificationBridge.requestPermission(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }
        }
        .on("notificationShow") { message in
            currentRequest = nil
            notificationBridge.show(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }
        }
        .on("notificationSchedule") { message in
            currentRequest = nil
            notificationBridge.schedule(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }
        }
        .on("notificationCancel") { message in
            webViewStore.sendResultToWebView(result: notificationBridge.cancel(request: message))
            currentRequest = nil
        }
        .on("notificationCancelAll") { message in
            webViewStore.sendResultToWebView(result: notificationBridge.cancelAll(request: message))
            currentRequest = nil
        }
        .on("notificationList") { message in
            currentRequest = nil
            notificationBridge.list(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }
        }
        .on("idleTimerStart") { message in
            webViewStore.sendResultToWebView(result: idleTimerBridge.start(request: message, webView: webViewStore.webView) { result in
                webViewStore.sendResultToWebView(result: result)
            })
            currentRequest = nil
        }
        .on("idleTimerStop") { message in
            webViewStore.sendResultToWebView(result: idleTimerBridge.stop(request: message))
            currentRequest = nil
        }
        .on("idleTimerReset") { message in
            webViewStore.sendResultToWebView(result: idleTimerBridge.reset(request: message))
            currentRequest = nil
        }
        .on("idleActivity") { _ in
            idleTimerBridge.recordActivity()
            currentRequest = nil
        }
        .on("screenStreamStart") { message in
            webViewStore.sendResultToWebView(result: screenStreamBridge.start(request: message, webView: webViewStore.webView) { result in
                webViewStore.sendResultToWebView(result: result)
            })
            currentRequest = nil
        }
        .on("screenStreamStop") { message in
            webViewStore.sendResultToWebView(result: screenStreamBridge.stop(request: message))
            currentRequest = nil
        }
        .on("natsProvision") { message in
            let response = natsBridge.provision(request: message)
            webViewStore.sendResultToWebView(result: response)
            if (response["success"] as? Bool) == true {
                startNATSRuntime(reason: "provisioned")
            }
            currentRequest = nil
        }
        .on("natsStatus") { message in
            webViewStore.sendResultToWebView(result: natsBridge.status(request: message))
            currentRequest = nil
        }
        .on("natsConnect") { message in
            webViewStore.sendResultToWebView(result: natsBridge.connect(request: message))
            currentRequest = nil
        }
        .on("natsDisconnect") { message in
            webViewStore.sendResultToWebView(result: natsBridge.disconnect(request: message))
            currentRequest = nil
        }
        .on("natsPublish") { message in
            webViewStore.sendResultToWebView(result: natsBridge.publish(request: message))
            currentRequest = nil
        }
        .on("sensorCapabilitiesGet") { message in
            webViewStore.sendResultToWebView(result: sensorBridge.capabilities(request: message))
            currentRequest = nil
        }
        .on("sensorStreamStart") { message in
            webViewStore.sendResultToWebView(result: sensorBridge.start(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            })
            currentRequest = nil
        }
        .on("sensorStreamStop") { message in
            webViewStore.sendResultToWebView(result: sensorBridge.stop(request: message))
            currentRequest = nil
        }
        .on("configPairingShow") { message in
            configureConfigPairingBridge()
            webViewStore.sendResultToWebView(result: configPairingBridge.startTargetSession(request: message))
            currentRequest = nil
        }
        .on("configPairingStop") { message in
            webViewStore.sendResultToWebView(result: configPairingBridge.stopTargetSession(request: message))
            currentRequest = nil
        }
        .on("configPairingConnect") { message in
            configureConfigPairingBridge()
            webViewStore.sendResultToWebView(result: configPairingBridge.connect(request: message))
            currentRequest = nil
        }
        .on("configPairingDisconnect") { message in
            webViewStore.sendResultToWebView(result: configPairingBridge.disconnect(request: message))
            currentRequest = nil
        }
        .on("configPairingSend") { message in
            webViewStore.sendResultToWebView(result: configPairingBridge.send(request: message))
            currentRequest = nil
        }
        .on("settingsGet") { message in
            webViewStore.sendResultToWebView(result: settingsGetResponse(request: message))
            currentRequest = nil
        }
        .on("settingsSet") { message in
            webViewStore.sendResultToWebView(result: settingsSetResponse(request: message))
            currentRequest = nil
        }
        .on("storageGet") { message in
            webViewStore.sendResultToWebView(result: nativeStorageBridge.get(request: message))
            currentRequest = nil
        }
        .on("storageSet") { message in
            webViewStore.sendResultToWebView(result: nativeStorageBridge.set(request: message))
            currentRequest = nil
        }
        .on("storageRemove") { message in
            webViewStore.sendResultToWebView(result: nativeStorageBridge.remove(request: message))
            currentRequest = nil
        }
        .on("storageClear") { message in
            webViewStore.sendResultToWebView(result: nativeStorageBridge.clear(request: message))
            currentRequest = nil
        }
        .on("filesystemWrite") { message in
            webViewStore.sendResultToWebView(result: nativeFilesystemBridge.write(request: message))
            currentRequest = nil
        }
        .on("filesystemRead") { message in
            webViewStore.sendResultToWebView(result: nativeFilesystemBridge.read(request: message))
            currentRequest = nil
        }
        .on("filesystemList") { message in
            webViewStore.sendResultToWebView(result: nativeFilesystemBridge.list(request: message))
            currentRequest = nil
        }
        .on("filesystemDelete") { message in
            webViewStore.sendResultToWebView(result: nativeFilesystemBridge.delete(request: message))
            currentRequest = nil
        }
        .on("sqliteExecute") { message in
            webViewStore.sendResultToWebView(result: nativeSQLiteBridge.execute(request: message))
            currentRequest = nil
        }
        .on("sqliteDeleteDatabase") { message in
            webViewStore.sendResultToWebView(result: nativeSQLiteBridge.deleteDatabase(request: message))
            currentRequest = nil
        }
        .on("kioskReloadControlSet") { message in
            webViewStore.sendResultToWebView(result: setKioskReloadControl(request: message))
            currentRequest = nil
        }
        .on("reload") { message in
            webViewStore.sendResultToWebView(result: NativeCommandPayload.reloadResponse(request: message))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                webViewStore.reloadCurrentOrNewURL()
            }
            currentRequest = nil
        }
        .onAll(BridgeActionCatalog.continuousScannerStartActions) { message in
            let action = BridgeDispatcher.action(from: message) ?? "continuousScanStart"
            startContinuousScanner(action: action, request: message)
        }
        .onAll(BridgeActionCatalog.continuousScannerStopActions) { message in
            let action = BridgeDispatcher.action(from: message) ?? "continuousScanStop"
            stopContinuousScanner(action: action, request: message)
        }
        .on("previewBoxLocationUpdate") { message in
            updateContinuousScannerPreviewRect(action: "previewBoxLocationUpdate", request: message)
        }
        .on("beaconsStart") { message in
            let response = beaconBridge.start(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }
            webViewStore.sendResultToWebView(result: response)
            currentRequest = nil
        }
        .on("beaconsStop") { message in
            webViewStore.sendResultToWebView(result: beaconBridge.stop(request: message))
            currentRequest = nil
        }
        .on("beaconAdvertiseStart") { message in
            let response = beaconAdvertiserBridge.start(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }
            webViewStore.sendResultToWebView(result: response)
            currentRequest = nil
        }
        .on("beaconAdvertiseStop") { message in
            webViewStore.sendResultToWebView(result: beaconAdvertiserBridge.stop(request: message))
            currentRequest = nil
        }
        .on("printerEpsonHelloWorld") { message in
            currentRequest = nil
            printerBridge.printEpsonHelloWorld(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }
        }
        .on("printerHelloWorld") { message in
            currentRequest = nil
            printerBridge.printHelloWorld(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }
        }
        .on("printerPrint") { message in
            currentRequest = nil
            webViewStore.sendResultToWebView(result: BridgeResponse.unavailable(
                request: message,
                action: "printerPrint",
                message: "printerPrint is only implemented for Android/Sunmi printer targets. Use printerHelloWorld or printerEpsonHelloWorld on iOS."
            ))
        }
        .on("printerDiscover") { message in
            currentRequest = nil
            printerBridge.discoverPrinters(request: message) { result in
                webViewStore.sendResultToWebView(result: result)
            }
        }
        .build()

        BridgeActionCatalog.assertRegisteredActions(router.actions)
        return router
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

                        let scannerConfig = configPairingOverlayScannerConfig
                        ContinuousBarcodeScannerView(
                            config: scannerConfig,
                            onResult: { result in
                                handleContinuousScannerResult(result, config: scannerConfig)
                            },
                            onError: { message in
                                webViewStore.sendResultToWebView(result: [
                                    "platform": "ios",
                                    "action": "continuousScanStart",
                                    "success": false,
                                    "error": message
                                ])
                            }
                        )
                        .frame(height: 190)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.green.opacity(0.82), lineWidth: 2)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Button {
                            configPairingScannerCamera = configPairingScannerCamera == "front" ? "back" : "front"
                        } label: {
                            Image(systemName: "camera.rotate.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 58, height: 44)
                                .background(.black.opacity(0.72), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Switch scanner camera")

                        Text(configPairingBridge.targetAdvertising ? "BLE active" : "BLE starting")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.82))

                        Text(payload)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(4)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)

                        HStack(spacing: 14) {
                            Button {
                                webViewStore.sendResultToWebView(result: configPairingBridge.stopTargetSession(request: ["action": "configPairingStop"]))
                                webViewStore.reloadCurrentOrNewURL()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityLabel("Reload")

                            Button {
                                webViewStore.sendResultToWebView(result: configPairingBridge.stopTargetSession(request: ["action": "configPairingStop"]))
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityLabel("Close")
                        }
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

    private var configPairingOverlayScannerConfig: ContinuousBarcodeScannerConfig {
        var config = ContinuousBarcodeScannerConfig()
        config.action = "continuousScanStart"
        config.mode = "configPairing"
        config.purpose = "configPairing"
        config.camera = configPairingScannerCamera
        config.types = ["qr"]
        config.repeatDelaySeconds = 1
        config.showFlipButton = true
        return config
    }

    private func configureConfigPairingBridge() {
        let webViewStore = webViewStore
        let deviceBridge = deviceBridge
        configPairingBridge.configure(
            eventHandler: { result in
                webViewStore.sendResultToWebView(result: result)
            },
            settingsProvider: {
                settingsSnapshotWithNATS()
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

    private func configureNATSCommandExecutor() {
        natsBridge.configureCommandExecutor { command, completion in
            executeNATSCommand(command, completion: completion)
        }
    }

    private func startNATSRuntime(reason: String) {
        connectNATSIfConfigured(reason: reason)
        scheduleNATSTelemetry()
        publishNATSTelemetry(reason: reason)
    }

    private func connectNATSIfConfigured(reason: String) {
        natsBridge.connectIfConfigured(reason: reason)
    }

    private func scheduleNATSTelemetry() {
        let settings = AppSettings.shared.natsConfiguration
        guard settings.telemetryEnabled else {
            stopNATSTelemetry()
            return
        }
        let interval = TimeInterval(max(5, settings.telemetryIntervalSeconds))
        if natsTelemetryTimer?.isValid == true,
           natsTelemetryTimer?.timeInterval == interval {
            return
        }
        stopNATSTelemetry()
        natsTelemetryTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                publishNATSTelemetry(reason: "interval")
            }
        }
    }

    private func stopNATSTelemetry() {
        natsTelemetryTimer?.invalidate()
        natsTelemetryTimer = nil
    }

    private func publishNATSTelemetry(reason: String) {
        connectNATSIfConfigured(reason: "telemetry-\(reason)")
        guard natsBridge.isConnected else { return }
        _ = natsBridge.publishTelemetry(payload: natsTelemetryPayload(reason: reason))
    }

    private func natsTelemetryPayload(reason: String) -> [String: Any] {
        var device = deviceBridge.deviceInfo(request: ["action": "deviceInfoGet", "source": "natsTelemetry"])
        device["nats"] = NSNull()
        let formatter = ISO8601DateFormatter()
        return [
            "type": "natsTelemetry",
            "action": "natsTelemetry",
            "platform": "ios",
            "timestamp": formatter.string(from: Date()),
            "reason": reason,
            "appUUID": AppSettings.shared.appUUIDString,
            "deviceName": AppSettings.shared.deviceName,
            "deviceUUID": AppSettings.shared.deviceUUIDString,
            "deviceLocation": AppSettings.shared.deviceLocation,
            "scenePhase": scenePhaseName(scenePhase),
            "idle": idleTimerBridge.telemetrySnapshot(),
            "screenStream": screenStreamBridge.telemetrySnapshot(),
            "nats": natsBridge.statusSnapshot(),
            "device": device
        ]
    }

    private func scenePhaseName(_ phase: ScenePhase) -> String {
        switch phase {
        case .active:
            return "active"
        case .inactive:
            return "inactive"
        case .background:
            return "background"
        @unknown default:
            return "unknown"
        }
    }

    private func natsQRScanImageResponse(request: [String: Any]) -> [String: Any] {
        var response = QRCodeImageScanner.response(request: request)
        response["workerAppUUID"] = AppSettings.shared.appUUIDString
        response["completedAt"] = ISO8601DateFormatter().string(from: Date())
        for key in ["jobId", "scanJobId", "taskId", "distributionId"] {
            let value = stringValue(request[key]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                response[key] = value
            }
        }
        return response
    }

    private func executeNATSCommand(_ command: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        var message = command
        let action = stringValue(message["action"]).trimmingCharacters(in: .whitespacesAndNewlines)
        message["action"] = action

        switch action {
        case "natsStatus":
            completion(natsBridge.status(request: message))
        case "deviceInfoGet":
            completion(deviceBridge.deviceInfo(request: message))
        case "settingsGet":
            completion(settingsGetResponse(request: message))
        case "settingsSet":
            completion(natsSettingsSetResponse(request: message))
        case "screenshotGet":
            if stringValue(message["maxWidth"]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                message["maxWidth"] = 720
            }
            if stringValue(message["quality"]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                message["quality"] = 65
            }
            deviceBridge.screenshot(request: message, webView: webViewStore.webView) { result in
                completion(result)
            }
        case "qrScanImage":
            completion(natsQRScanImageResponse(request: message))
        case "screenStreamStart":
            let natsRequest = natsScreenStreamRequest(from: message)
            let eventSubject = stringValue(natsRequest["eventSubject"]).trimmingCharacters(in: .whitespacesAndNewlines)
            let response = screenStreamBridge.start(
                request: natsRequest,
                webView: webViewStore.webView,
                eventHandler: { event in
                    guard !eventSubject.isEmpty else { return }
                    _ = natsBridge.publishJSON(subject: eventSubject, payload: event)
                },
                natsPublisher: { subject, payload in
                    natsBridge.publishData(subject: subject, payload: payload)
                }
            )
            completion(response)
        case "screenStreamStop":
            completion(screenStreamBridge.stop(request: message))
        case "reload":
            completion(NativeCommandPayload.reloadResponse(request: message))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                webViewStore.reloadCurrentOrNewURL()
            }
        default:
            completion(BridgeResponse.error(
                request: message,
                action: action.isEmpty ? "natsCommand" : action,
                message: "NATS command is not allowed: \(action)."
            ))
        }
    }

    private func natsScreenStreamRequest(from command: [String: Any]) -> [String: Any] {
        var request = command
        let prefix = AppSettings.shared.natsConfiguration.devicePrefix(appUUID: AppSettings.shared.appUUIDString)
        if stringValue(request["transport"]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request["transport"] = "nats"
        }
        if stringValue(request["subject"]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request["subject"] = "\(prefix).screen.frames"
        }
        if stringValue(request["metaSubject"]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request["metaSubject"] = "\(prefix).screen.meta"
        }
        if stringValue(request["eventSubject"]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request["eventSubject"] = "\(prefix).screen.events"
        }
        return request
    }

    private func natsSettingsSetResponse(request: [String: Any]) -> [String: Any] {
        let values = (request["settings"] as? [String: Any]) ?? request
        let snapshot = AppSettings.shared.applyConfiguration(values)
        var response = BridgeResponse.base(request: request, action: "settingsSet")
        response["success"] = true
        var settings = snapshot
        settings["nats"] = natsBridge.statusSnapshot()
        response["settings"] = settings
        return response
    }

    private func settingsGetResponse(request: [String: Any]) -> [String: Any] {
        var response = settingsBridge.getResponse(request: request)
        if var settings = response["settings"] as? [String: Any] {
            settings["nats"] = natsBridge.statusSnapshot()
            response["settings"] = settings
        }
        return response
    }

    private func settingsSetResponse(request: [String: Any]) -> [String: Any] {
        var response = settingsBridge.setResponse(request: request)
        if var settings = response["settings"] as? [String: Any] {
            settings["nats"] = natsBridge.statusSnapshot()
            response["settings"] = settings
        }
        return response
    }

    private func settingsSnapshotWithNATS() -> [String: Any] {
        var snapshot = AppSettings.shared.configurationSnapshot()
        snapshot["nats"] = natsBridge.statusSnapshot()
        return snapshot
    }

    private func showConfigPairingFromGesture() {
        configureConfigPairingBridge()
        let response = configPairingBridge.startTargetSession(request: [
            "action": "configPairingShow",
            "source": "twoFingerHold"
        ])
        webViewStore.sendResultToWebView(result: response)
    }

    private var kioskReloadControlOverlay: some View {
        Group {
            if kioskReloadControl.enabled {
                VStack {
                    Spacer()
                    HStack {
                        Button {
                            webViewStore.reloadCurrentOrNewURL()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(Color.black))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .opacity(kioskReloadControl.opacity)
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: kioskReloadControl.longPressSeconds)
                                .onEnded { _ in
                                    Darwin.exit(0)
                                }
                        )
                        .accessibilityIdentifier("kioskReloadControl")
                        Spacer()
                    }
                    Spacer()
                }
                .ignoresSafeArea()
                .zIndex(90)
            }
        }
    }

    private func setKioskReloadControl(request: [String: Any]) -> [String: Any] {
        if let enabled = boolValue(request["enabled"] ?? request["visible"]) {
            kioskReloadControl.enabled = enabled
        }
        if let opacity = request["opacity"].flatMap(doubleValue) {
            kioskReloadControl.opacity = min(1, max(0.02, opacity))
        }
        if let seconds = request["longPressSeconds"].flatMap(doubleValue) {
            kioskReloadControl.longPressSeconds = min(10, max(0.5, seconds))
        }
        var response = BridgeResponse.base(request: request, action: "kioskReloadControlSet")
        response["success"] = true
        response["enabled"] = kioskReloadControl.enabled
        response["opacity"] = kioskReloadControl.opacity
        response["longPressSeconds"] = kioskReloadControl.longPressSeconds
        return response
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Float { return Double(value) }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private var continuousScannerOverlay: some View {
        GeometryReader { proxy in
            if let config = continuousScannerConfig {
                let frame = ContinuousScannerResponseBuilder.scannerFrame(for: config.previewRect, in: proxy.size)
                ZStack(alignment: .topTrailing) {
                    ContinuousBarcodeScannerView(
                        config: config,
                        onResult: { result in
                            handleContinuousScannerResult(result, config: config)
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

                if config.showFlipButton {
                    Button {
                        flipContinuousScannerCamera()
                    } label: {
                        Image(systemName: "camera.rotate.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 54, height: 44)
                            .background(.black.opacity(0.72), in: Capsule())
                            .shadow(radius: 3)
                    }
                    .accessibilityLabel("Switch scanner camera")
                    .position(x: frame.midX, y: min(frame.maxY + 34, proxy.size.height - 34))
                    .zIndex(41)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func flipContinuousScannerCamera() {
        guard var config = continuousScannerConfig else { return }
        config.camera = config.camera == "front" ? "back" : "front"
        continuousScannerConfig = config
        webViewStore.sendResultToWebView(result: ContinuousScannerResponseBuilder.startResponse(
            action: config.action,
            config: config
        ))
    }

    private func startContinuousScanner(action: String, request: [String: Any]) {
        let config = ContinuousScannerResponseBuilder.config(
            action: action,
            request: request,
            current: continuousScannerConfig
        )
        continuousScannerConfig = config

        webViewStore.sendResultToWebView(result: ContinuousScannerResponseBuilder.startResponse(
            action: action,
            config: config
        ))
        currentRequest = nil
    }

    private func stopContinuousScanner(action: String, request: [String: Any]) {
        continuousScannerConfig = nil
        webViewStore.sendResultToWebView(result: ContinuousScannerResponseBuilder.stopResponse(
            action: action,
            request: request
        ))
        currentRequest = nil
    }

    private func updateContinuousScannerPreviewRect(action: String, request: [String: Any]) {
        guard var config = continuousScannerConfig else {
            webViewStore.sendResultToWebView(result: ContinuousScannerResponseBuilder.errorResponse(
                action: action,
                message: "No continuous scanner is running."
            ))
            currentRequest = nil
            return
        }

        guard let previewRect = ContinuousScannerResponseBuilder.previewRect(from: request["previewRect"] as? [String: Any]) else {
            webViewStore.sendResultToWebView(result: ContinuousScannerResponseBuilder.errorResponse(
                action: action,
                message: "Invalid previewRect."
            ))
            currentRequest = nil
            return
        }

        config.previewRect = previewRect
        continuousScannerConfig = config
        webViewStore.sendResultToWebView(result: ContinuousScannerResponseBuilder.previewUpdateResponse(
            action: action,
            previewRect: previewRect
        ))
        currentRequest = nil
    }

    private func handleContinuousScannerResult(_ result: [String: Any], config: ContinuousBarcodeScannerConfig) {
        guard config.isConfigPairing else {
            webViewStore.sendResultToWebView(result: result)
            return
        }

        let code = stringValue(result["code"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            return
        }

        let request: [String: Any] = [
            "action": config.action,
            "purpose": "configPairing",
            "source": "configPairing"
        ]

        switch recoveryBarcodeHandler.handleConfigPairing(
            code: code,
            action: config.action,
            storedToken: AppSettings.shared.securityToken,
            invalidTokenMessage: NSLocalizedString("error.invalidConfiguration.invalidToken", comment: "Invalid security token error")
        ) {
        case .applied(let snapshot, let wifiRequest):
            applyContinuousConfigScanResult(
                request: request,
                settings: snapshot,
                wifiRequest: wifiRequest
            )
        case .invalid(let response):
            webViewStore.sendResultToWebView(result: response)
        }
    }

    private func applyContinuousConfigScanResult(
        request: [String: Any],
        settings: [String: Any],
        wifiRequest: [String: Any]?
    ) {
        continuousScannerConfig = nil
        _ = configPairingBridge.stopTargetSession(request: ["action": "configPairingStop"])
        webViewStore.sendResultToWebView(result: BarcodeResponseBuilder.configChangedResponse(
            request: request,
            settings: settings
        ))

        guard var wifiRequest else {
            reloadConfiguredURLSoon()
            return
        }

        wifiRequest["requestId"] = stringValue(request["requestId"])
        deviceBridge.configureWifi(request: wifiRequest) { result in
            webViewStore.sendResultToWebView(result: result)
            reloadWhenWifiIsReady(wifiRequest: wifiRequest, wifiResult: result)
        }
    }

    private func reloadConfiguredURLSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            webViewStore.reloadCurrentOrNewURL()
        }
    }

    private func reloadWhenWifiIsReady(wifiRequest: [String: Any], wifiResult: [String: Any]) {
        guard boolValue(wifiResult["success"]) == true else {
            reloadConfiguredURLSoon()
            return
        }

        let generation = UUID()
        postWifiReloadGeneration = generation
        let deadline = Date().addingTimeInterval(90)
        let ssid = stringValue(wifiRequest["ssid"])

        deviceBridge.waitForWifiReady(ssid: ssid, timeout: 90) { readiness in
            guard postWifiReloadGeneration == generation else { return }
            webViewStore.sendResultToWebView(result: readiness)
            if boolValue(readiness["success"]) == true {
                webViewStore.reloadCurrentOrNewURL()
            }
        }

        schedulePostWifiReloadAttempt(generation: generation, deadline: deadline, delay: 2)
    }

    private func schedulePostWifiReloadAttempt(generation: UUID, deadline: Date, delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard postWifiReloadGeneration == generation, Date() < deadline else {
                return
            }
            webViewStore.reloadCurrentOrNewURL()
            schedulePostWifiReloadCheck(generation: generation, deadline: deadline)
        }
    }

    private func schedulePostWifiReloadCheck(generation: UUID, deadline: Date) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            guard postWifiReloadGeneration == generation, Date() < deadline else {
                return
            }

            if webViewStore.isShowingRecoveryPage {
                schedulePostWifiReloadAttempt(generation: generation, deadline: deadline, delay: 0)
            } else if webViewStore.isLoading {
                schedulePostWifiReloadCheck(generation: generation, deadline: deadline)
            }
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
        let captureRequest = DocumentCaptureRequest(currentRequest)
        let action = captureRequest.action
        switch result {
        case .success(let scan):
            print("Document scan successful. Processing \(scan.pageCount) pages.")

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

            if captureRequest.requiresOCR {
                let recognizer = TextRecognizer(cameraScan: scan)
                recognizer.recognizeText { ocrResult in
                    switch ocrResult {
                    case .success(let recognizedText):
                        print("OCR successful.")
                        createAndSendDocumentResponse(action: action, images: images, text: recognizedText, outputType: captureRequest.outputType, pageCount: scan.pageCount)
                    case .failure(let ocrError):
                        print("OCR failed: \(ocrError.localizedDescription)")
                        // ocrError ist bereits ein AppError und somit lokalisiert
                        webViewStore.sendErrorToWebView(action: action, error: ocrError)
                    }
                     currentRequest = nil // Reset nach Abschluss der asynchronen Operation
                }
            } else {
                createAndSendDocumentResponse(action: action, images: images, text: nil, outputType: captureRequest.outputType, pageCount: scan.pageCount)
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
        if outputType.lowercased() == "pdf" {
            if let pdfDataURL = PDFGenerator.generatePDFDataURL(from: images) {
                let response = DocumentCaptureResponseBuilder.pdfResponse(
                    action: action,
                    pageCount: pageCount,
                    text: text,
                    pdfDataURL: pdfDataURL
                )
                webViewStore.sendResultToWebView(result: response)
            } else {

                webViewStore.sendErrorToWebView(action: action, error: AppError.pdfCreationFailed)
                return
            }
        } else {
             let imageFormat = DocumentCaptureRequest.imageFormat(for: outputType)
             let imageDataURLs = ImageConverter.convertImagesToDataURLs(images: images, format: imageFormat)
             if !imageDataURLs.isEmpty {
                 let response = DocumentCaptureResponseBuilder.imageResponse(
                    action: action,
                    pageCount: pageCount,
                    text: text,
                    imageDataURLs: imageDataURLs,
                    format: DocumentCaptureRequest.responseFormat(for: outputType)
                 )
                 webViewStore.sendResultToWebView(result: response)
             } else {

                 webViewStore.sendErrorToWebView(action: action, error: AppError.imageConversionFailed(NSLocalizedString("error.imageConversionFailed.noImagesConverted", comment: "No images could be converted error")))
                 return
             }
        }
    }

    private func handleImagePickerResult(_ result: Result<UIImage, AppError>) {
        let captureRequest = PhotoCaptureRequest(currentRequest)
        let action = captureRequest.action
        switch result {
        case .success(let image):
            print("Photo capture successful.")

            guard captureRequest.shouldRemoveBackground else {
                sendPhotoResult(request: captureRequest, image: image, backgroundRemoved: false, cropped: false)
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
                    let processedImage = try BackgroundRemoval.removeBackground(from: image, style: captureRequest.backgroundStyle, cropTransparent: captureRequest.cropTransparent)
                    DispatchQueue.main.async {
                        self.sendPhotoResult(
                            request: captureRequest,
                            image: processedImage,
                            backgroundRemoved: true,
                            cropped: captureRequest.cropTransparent && captureRequest.backgroundStyle.isTransparent
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

    private func sendPhotoResult(request: PhotoCaptureRequest, image: UIImage, backgroundRemoved: Bool, cropped: Bool) {
        let imageFormat = request.imageFormat(backgroundRemoved: backgroundRemoved)

        if let imageDataURL = ImageConverter.convertImageToDataURL(image: image, format: imageFormat) {
            let response = PhotoCaptureResponseBuilder.response(
                action: request.action,
                imageDataURL: imageDataURL,
                format: request.responseFormat(backgroundRemoved: backgroundRemoved),
                backgroundRemoved: backgroundRemoved,
                backgroundMode: request.backgroundStyle.responseMode,
                cropped: cropped,
                backgroundColorHex: request.backgroundStyle.responseColorHex
            )

            webViewStore.sendResultToWebView(result: response)
        } else {
            webViewStore.sendErrorToWebView(
                action: request.action,
                error: AppError.imageConversionFailed(
                    String(
                        format: NSLocalizedString("error.imageConversionFailed.specificType", comment: "Image could not be converted to specific type error format"),
                        request.outputType
                    )
                )
            )
        }
    }

    private func handlePortraitCaptureResult(_ result: Result<PortraitCaptureResult, AppError>) {
        let captureRequest = PortraitCaptureRequest(currentRequest)
        let action = captureRequest.action

        switch result {
        case .success(let captureResult):
            guard !captureRequest.shouldRemoveBackground || BackgroundRemoval.isSupported else {
                webViewStore.sendErrorToWebView(action: action, error: AppError.featureNotAvailable("Background Removal"))
                currentRequest = nil
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let cropResult: (image: UIImage, faceCount: Int)
                    if captureRequest.faceCenteredCrop {
                        cropResult = try PortraitImageProcessor.faceCenteredSquareCrop(captureResult.image, requiredFaces: captureRequest.requiredFaces)
                    } else {
                        cropResult = (captureResult.image, captureResult.detectedFaces)
                    }

                    let processedImage: UIImage
                    let backgroundRemoved: Bool
                    if captureRequest.shouldRemoveBackground {
                        processedImage = try BackgroundRemoval.removeBackground(
                            from: cropResult.image,
                            style: captureRequest.backgroundStyle,
                            cropTransparent: captureRequest.cropTransparent
                        )
                        backgroundRemoved = true
                    } else {
                        processedImage = cropResult.image
                        backgroundRemoved = false
                    }

                    DispatchQueue.main.async {
                        self.sendPortraitResult(
                            request: captureRequest,
                            captureResult: captureResult,
                            image: processedImage,
                            detectedFaces: cropResult.faceCount,
                            backgroundRemoved: backgroundRemoved,
                            cropped: captureRequest.faceCenteredCrop || (captureRequest.cropTransparent && captureRequest.backgroundStyle.isTransparent && backgroundRemoved)
                        )
                        self.currentRequest = nil
                    }
                } catch {
                    let appError = (error as? AppError) ?? AppError.internalError(error.localizedDescription)
                    DispatchQueue.main.async {
                        self.webViewStore.sendErrorToWebView(action: action, error: appError)
                        self.currentRequest = nil
                    }
                }
            }

        case .failure(let error):
            print("Portrait capture failed: \(error.localizedDescription)")
            webViewStore.sendErrorToWebView(action: action, error: error)
            currentRequest = nil
        }
    }

    private func sendPortraitResult(
        request: PortraitCaptureRequest,
        captureResult: PortraitCaptureResult,
        image: UIImage,
        detectedFaces: Int,
        backgroundRemoved: Bool,
        cropped: Bool
    ) {
        let imageFormat = request.imageFormat(backgroundRemoved: backgroundRemoved)

        if let imageDataURL = ImageConverter.convertImageToDataURL(image: image, format: imageFormat) {
            let response = PortraitCaptureResponseBuilder.response(
                action: request.action,
                imageDataURL: imageDataURL,
                format: request.responseFormat(backgroundRemoved: backgroundRemoved),
                selectedIndex: captureResult.selectedIndex,
                variantsCaptured: captureResult.variantsCaptured,
                requiredFaces: request.requiredFaces,
                detectedFaces: detectedFaces,
                faceCentered: request.faceCenteredCrop,
                backgroundRemoved: backgroundRemoved,
                backgroundMode: request.backgroundStyle.responseMode,
                cropped: cropped,
                backgroundColorHex: request.backgroundStyle.responseColorHex
            )

            webViewStore.sendResultToWebView(result: response)
        } else {
            webViewStore.sendErrorToWebView(
                action: request.action,
                error: AppError.imageConversionFailed(
                    String(
                        format: NSLocalizedString("error.imageConversionFailed.specificType", comment: "Image could not be converted to specific type error format"),
                        request.outputType
                    )
                )
            )
        }
    }

    private func handleBarcodeScanResult(_ result: Result<BarcodeScannerResult, AppError>) {
        let action = BarcodeCaptureRequest(currentRequest).action
        switch result {
        case .success(let scanResult):
            if isRecoveryBarcodeRequest {
                handleRecoveryBarcodeScan(code: scanResult.code, action: action)
            } else if scanResult.code == "configChanged" && scanResult.format == "JSONConfig" {
                handleConfigBarcodeScanResult(scanResult, action: action)
            } else {
                print(String(format: NSLocalizedString("status.barcodeScan.success", comment: "Barcode scan successful status format"), scanResult.code, scanResult.format))
                let response = BarcodeResponseBuilder.response(
                    action: action,
                    code: scanResult.code,
                    format: scanResult.format
                )
                webViewStore.sendResultToWebView(result: response)
            }

        case .failure(let error):
            print(String(format: NSLocalizedString("error.barcodeScan.failed", comment: "Barcode scan failed error format"), error.localizedDescription))
            webViewStore.sendErrorToWebView(action: action, error: error)
        }
        currentRequest = nil
    }

    private func handleConfigBarcodeScanResult(_ scanResult: BarcodeScannerResult, action: String) {
        print(NSLocalizedString("status.configurationChanged.reloading", comment: "Configuration changed, reloading webview status"))
        webViewStore.sendResultToWebView(result: BarcodeResponseBuilder.configChangedResponse(
            request: currentRequest ?? ["action": action],
            settings: scanResult.settings ?? AppSettings.shared.configurationSnapshot()
        ))

        guard var wifiRequest = scanResult.wifiRequest else {
            reloadConfiguredURLSoon()
            return
        }

        wifiRequest["requestId"] = stringValue(currentRequest?["requestId"])
        deviceBridge.configureWifi(request: wifiRequest) { result in
            webViewStore.sendResultToWebView(result: result)
            reloadWhenWifiIsReady(wifiRequest: wifiRequest, wifiResult: result)
        }
    }

    private var isRecoveryBarcodeRequest: Bool {
        RecoveryBarcodeHandler.isRecoveryRequest(currentRequest)
    }

    private func handleRecoveryBarcodeScan(code: String, action: String) {
        switch recoveryBarcodeHandler.handle(code: code, action: action) {
        case .invalid(let response):
            webViewStore.sendResultToWebView(result: response)
        case .applied(let serverURL, let snapshot):
            print("Recovery QR updated server URL: \(snapshot["serverURL"] ?? serverURL)")
            webViewStore.reloadCurrentOrNewURL()
        }
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
