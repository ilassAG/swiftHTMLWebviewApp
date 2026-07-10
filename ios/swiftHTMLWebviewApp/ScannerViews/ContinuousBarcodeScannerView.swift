//
//  ContinuousBarcodeScannerView.swift
//  swiftHTMLWebviewApp
//
//  Embedded AVCapture barcode scanner for long-running web bridge sessions.
//

import AVFoundation
import SwiftUI

struct ContinuousBarcodeScannerConfig {
    var action = "continuousScanStart"
    var mode = "data"
    var purpose = ""
    var camera = "back"
    var types: [String] = ["qr", "ean13", "ean8", "code128", "datamatrix"]
    var repeatDelaySeconds: TimeInterval = 1.5
    var previewRect = CGRect(x: 0.1, y: 0.18, width: 0.8, height: 0.36)
    var showCloseButton = true
    var showFlipButton = false

    var isConfigPairing: Bool {
        purpose == "configPairing"
    }
}

struct ContinuousBarcodeScannerView: UIViewRepresentable {
    let config: ContinuousBarcodeScannerConfig
    let onResult: ([String: Any]) -> Void
    let onError: (String) -> Void

    func makeUIView(context: Context) -> ContinuousBarcodeScannerUIView {
        let view = ContinuousBarcodeScannerUIView()
        view.configure(config: config, onResult: onResult, onError: onError)
        return view
    }

    func updateUIView(_ uiView: ContinuousBarcodeScannerUIView, context: Context) {
        uiView.configure(config: config, onResult: onResult, onError: onError)
    }

    static func dismantleUIView(_ uiView: ContinuousBarcodeScannerUIView, coordinator: ()) {
        uiView.stop()
    }
}

final class ContinuousBarcodeScannerUIView: UIView, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.ilass.swiftHTMLWebviewApp.continuousScanner")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var currentConfig: ContinuousBarcodeScannerConfig?
    private var onResult: (([String: Any]) -> Void)?
    private var onError: ((String) -> Void)?
    private var lastSeenByCode: [String: Date] = [:]
    private var isConfigured = false
    private var cameraPosition: AVCaptureDevice.Position = .back

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        layer.cornerRadius = 12
        previewLayer = layer as? AVCaptureVideoPreviewLayer
        previewLayer?.videoGravity = .resizeAspectFill
        previewLayer?.session = session
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOrientationChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
        updatePreviewOrientation()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updatePreviewOrientation()
    }

    func configure(
        config: ContinuousBarcodeScannerConfig,
        onResult: @escaping ([String: Any]) -> Void,
        onError: @escaping (String) -> Void
    ) {
        self.onResult = onResult
        self.onError = onError

        guard currentConfig?.camera != config.camera || currentConfig?.types != config.types || !isConfigured else {
            currentConfig = config
            return
        }

        currentConfig = config
        start(config: config)
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }
            self.isConfigured = false
        }
    }

    private func start(config: ContinuousBarcodeScannerConfig) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession(config: config)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self = self else { return }
                if granted {
                    self.configureSession(config: config)
                } else {
                    DispatchQueue.main.async {
                        self.onError?("Camera permission was denied.")
                    }
                }
            }
        default:
            onError?("Camera permission is not available.")
        }
    }

    private func configureSession(config: ContinuousBarcodeScannerConfig) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            self.session.beginConfiguration()
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }

            let position: AVCaptureDevice.Position = config.camera.lowercased() == "front" ? .front : .back
            self.cameraPosition = position
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
                self.finishConfigurationWithError("Requested camera is not available.")
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard self.session.canAddInput(input) else {
                    self.finishConfigurationWithError("Camera input could not be added.")
                    return
                }
                self.session.addInput(input)
            } catch {
                self.finishConfigurationWithError("Camera input failed: \(error.localizedDescription)")
                return
            }

            let output = AVCaptureMetadataOutput()
            guard self.session.canAddOutput(output) else {
                self.finishConfigurationWithError("Barcode output could not be added.")
                return
            }

            self.session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            let supportedTypes = Self.metadataTypes(for: config.types).filter { output.availableMetadataObjectTypes.contains($0) }
            output.metadataObjectTypes = supportedTypes.isEmpty ? output.availableMetadataObjectTypes : supportedTypes

            self.session.commitConfiguration()
            self.isConfigured = true
            DispatchQueue.main.async { [weak self] in
                self?.updatePreviewOrientation()
            }

            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    @objc private func handleOrientationChange() {
        setNeedsLayout()
        updatePreviewOrientation()
    }

    private func updatePreviewOrientation() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.updatePreviewOrientation()
            }
            return
        }
        guard let connection = previewLayer?.connection else { return }

        if connection.isVideoOrientationSupported {
            connection.videoOrientation = currentVideoOrientation()
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = cameraPosition == .front
        }
    }

    private func currentVideoOrientation() -> AVCaptureVideoOrientation {
        let interfaceOrientation = window?.windowScene?.interfaceOrientation
        switch interfaceOrientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        default:
            switch UIDevice.current.orientation {
            case .portrait:
                return .portrait
            case .portraitUpsideDown:
                return .portraitUpsideDown
            case .landscapeLeft:
                return .landscapeRight
            case .landscapeRight:
                return .landscapeLeft
            default:
                return .portrait
            }
        }
    }

    private func finishConfigurationWithError(_ message: String) {
        session.commitConfiguration()
        DispatchQueue.main.async { [weak self] in
            self?.onError?(message)
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let config = currentConfig else { return }

        for object in metadataObjects {
            guard let readableObject = object as? AVMetadataMachineReadableCodeObject,
                  let code = readableObject.stringValue else {
                continue
            }

            let now = Date()
            if let lastSeen = lastSeenByCode[code], now.timeIntervalSince(lastSeen) < config.repeatDelaySeconds {
                continue
            }
            lastSeenByCode[code] = now

            onResult?(
                ContinuousScannerEventBuilder.event(
                    config: config,
                    code: code,
                    format: Self.displayName(for: readableObject.type),
                    date: now
                )
            )
        }
    }

    private static func metadataTypes(for types: [String]) -> [AVMetadataObject.ObjectType] {
        let mapped = types.compactMap { type -> AVMetadataObject.ObjectType? in
            switch type.lowercased() {
            case "qr": return .qr
            case "ean13": return .ean13
            case "ean8": return .ean8
            case "code128": return .code128
            case "code39": return .code39
            case "code93": return .code93
            case "upce": return .upce
            case "pdf417": return .pdf417
            case "aztec": return .aztec
            case "datamatrix": return .dataMatrix
            case "itf14": return .itf14
            case "interleaved2of5", "itf": return .interleaved2of5
            default: return nil
            }
        }
        return mapped.isEmpty ? [.qr, .ean13, .ean8, .code128, .dataMatrix] : mapped
    }

    private static func displayName(for type: AVMetadataObject.ObjectType) -> String {
        switch type {
        case .qr: return "qr"
        case .ean13: return "ean13"
        case .ean8: return "ean8"
        case .code128: return "code128"
        case .code39: return "code39"
        case .code93: return "code93"
        case .upce: return "upce"
        case .pdf417: return "pdf417"
        case .aztec: return "aztec"
        case .dataMatrix: return "datamatrix"
        case .itf14: return "itf14"
        case .interleaved2of5: return "interleaved2of5"
        default: return type.rawValue
        }
    }
}
