//
//  ScannerViews/PortraitCaptureView.swift
//  swiftHTMLWebviewApp
//

import AVFoundation
import SwiftUI
import UIKit
import Vision

struct PortraitCaptureResult {
    let image: UIImage
    let selectedIndex: Int
    let variantsCaptured: Int
    let detectedFaces: Int
}

struct PortraitCaptureView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let request: PortraitCaptureRequest
    let completion: (Result<PortraitCaptureResult, AppError>) -> Void

    func makeUIViewController(context: Context) -> PortraitCaptureViewController {
        PortraitCaptureViewController(request: request) { result in
            isPresented = false
            completion(result)
        }
    }

    func updateUIViewController(_ uiViewController: PortraitCaptureViewController, context: Context) {
    }
}

final class PortraitCaptureViewController: UIViewController {
    private final class PreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }

    private struct Variant {
        let image: UIImage
        let faceCount: Int
    }

    private let request: PortraitCaptureRequest
    private let completion: (Result<PortraitCaptureResult, AppError>) -> Void
    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "PortraitCapture.session")
    private let videoQueue = DispatchQueue(label: "PortraitCapture.video")
    private let visionOrientationLock = NSLock()
    private let previewView = PreviewView()
    private let statusLabel = UILabel()
    private let countdownLabel = UILabel()
    private let captureButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let selectionOverlay = UIView()
    private let selectionStack = UIStackView()
    private let selectionActions = UIStackView()
    private let selectionContent = UIStackView()
    private let retakeButton = UIButton(type: .system)
    private let useButton = UIButton(type: .system)

    private var countdownTimer: Timer?
    private var captureTimers: [Timer] = []
    private var countdownRemaining: TimeInterval = 0
    private var countdownTargetDate: Date?
    private var isCountingDown = false
    private var isBurstCapturing = false
    private var latestFaceCount = 0
    private var variants: [Variant] = []
    private var photoDelegates: [PhotoDelegate] = []
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var currentVisionOrientation: CGImagePropertyOrientation = .right
    private var selectionButtonSizeConstraints: [NSLayoutConstraint] = []
    private var lastSelectionColumnCount = 0
    private var selectedIndex = 0
    private var didComplete = false

    init(request: PortraitCaptureRequest, completion: @escaping (Result<PortraitCaptureResult, AppError>) -> Void) {
        self.request = request
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureUI()
        requestCameraAccessAndStart()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateVideoConnections()
        updateVisibleSelectionGridIfNeeded()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.updateVideoConnections()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopTimers()
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func configureUI() {
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.previewLayer.videoGravity = .resizeAspectFill
        view.addSubview(previewView)

        let overlay = UIStackView(arrangedSubviews: [statusLabel, countdownLabel, captureButton])
        overlay.axis = .vertical
        overlay.alignment = .center
        overlay.spacing = 14
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)

        statusLabel.textColor = .white
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 26, weight: .bold)

        countdownLabel.textColor = .white
        countdownLabel.textAlignment = .center
        countdownLabel.font = .monospacedDigitSystemFont(ofSize: 68, weight: .heavy)
        countdownLabel.text = ""

        var captureButtonConfiguration = UIButton.Configuration.filled()
        captureButtonConfiguration.image = UIImage(systemName: "camera.fill")
        captureButtonConfiguration.baseForegroundColor = .black
        captureButtonConfiguration.baseBackgroundColor = .white
        captureButtonConfiguration.cornerStyle = .capsule
        captureButtonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 17, leading: 34, bottom: 17, trailing: 34)
        captureButton.configuration = captureButtonConfiguration
        captureButton.addTarget(self, action: #selector(startCountdown), for: .touchUpInside)

        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        cancelButton.tintColor = .white
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        view.addSubview(cancelButton)

        configureSelectionOverlay()

        NSLayoutConstraint.activate([
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            cancelButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            cancelButton.widthAnchor.constraint(equalToConstant: 44),
            cancelButton.heightAnchor.constraint(equalToConstant: 44),

            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            overlay.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28)
        ])

        updateStatus()
    }

    private func configureSelectionOverlay() {
        selectionOverlay.translatesAutoresizingMaskIntoConstraints = false
        selectionOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.9)
        selectionOverlay.isHidden = true
        view.addSubview(selectionOverlay)

        selectionStack.axis = .vertical
        selectionStack.spacing = 12

        selectionActions.addArrangedSubview(retakeButton)
        selectionActions.addArrangedSubview(useButton)
        selectionActions.axis = .horizontal
        selectionActions.spacing = 12
        selectionActions.distribution = .fillEqually

        retakeButton.setImage(UIImage(systemName: "arrow.counterclockwise"), for: .normal)
        retakeButton.imageView?.contentMode = .scaleAspectFit
        retakeButton.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        retakeButton.tintColor = .white
        retakeButton.layer.cornerRadius = 12
        retakeButton.addTarget(self, action: #selector(retake), for: .touchUpInside)

        useButton.setImage(UIImage(systemName: "checkmark"), for: .normal)
        useButton.imageView?.contentMode = .scaleAspectFit
        useButton.backgroundColor = .white
        useButton.tintColor = .black
        useButton.layer.cornerRadius = 12
        useButton.addTarget(self, action: #selector(useSelectedPhoto), for: .touchUpInside)

        selectionContent.addArrangedSubview(selectionStack)
        selectionContent.addArrangedSubview(selectionActions)
        selectionContent.axis = .vertical
        selectionContent.alignment = .fill
        selectionContent.spacing = 20
        selectionContent.translatesAutoresizingMaskIntoConstraints = false
        selectionOverlay.addSubview(selectionContent)

        NSLayoutConstraint.activate([
            selectionOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            selectionOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            selectionOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            selectionOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            selectionContent.leadingAnchor.constraint(greaterThanOrEqualTo: selectionOverlay.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            selectionContent.trailingAnchor.constraint(lessThanOrEqualTo: selectionOverlay.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            selectionContent.topAnchor.constraint(greaterThanOrEqualTo: selectionOverlay.safeAreaLayoutGuide.topAnchor, constant: 18),
            selectionContent.bottomAnchor.constraint(lessThanOrEqualTo: selectionOverlay.safeAreaLayoutGuide.bottomAnchor, constant: -18),
            selectionContent.centerXAnchor.constraint(equalTo: selectionOverlay.safeAreaLayoutGuide.centerXAnchor),
            selectionContent.centerYAnchor.constraint(equalTo: selectionOverlay.safeAreaLayoutGuide.centerYAnchor),
            selectionActions.heightAnchor.constraint(equalToConstant: 52),
            selectionActions.widthAnchor.constraint(greaterThanOrEqualToConstant: 220)
        ])
    }

    private func requestCameraAccessAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.configureSession() : self?.finish(.failure(.userCancelled))
                }
            }
        default:
            finish(.failure(.featureNotAvailable("Camera permission is required.")))
        }
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            do {
                guard let device = self.cameraDevice() else {
                    throw AppError.featureNotAvailable("Camera")
                }
                let input = try AVCaptureDeviceInput(device: device)
                guard self.session.canAddInput(input) else {
                    throw AppError.featureNotAvailable("Camera input")
                }
                self.session.addInput(input)

                guard self.session.canAddOutput(self.photoOutput) else {
                    throw AppError.featureNotAvailable("Photo output")
                }
                self.session.addOutput(self.photoOutput)

                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
                guard self.session.canAddOutput(self.videoOutput) else {
                    throw AppError.featureNotAvailable("Video output")
                }
                self.session.addOutput(self.videoOutput)

                if let connection = self.videoOutput.connection(with: .video), connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = self.request.cameraPosition == .front
                }

                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.rotationCoordinator = AVCaptureDevice.RotationCoordinator(
                        device: device,
                        previewLayer: self.previewView.previewLayer
                    )
                    self.previewView.previewLayer.session = self.session
                    self.updateVideoConnections()
                }
                self.session.startRunning()
            } catch {
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.finish(.failure((error as? AppError) ?? .internalError(error.localizedDescription)))
                }
            }
        }
    }

    private func cameraDevice() -> AVCaptureDevice? {
        let position: AVCaptureDevice.Position = request.cameraPosition == .front ? .front : .back
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(for: .video)
    }

    private func updateVideoConnections() {
        previewView.previewLayer.frame = previewView.bounds
        let previewAngle = rotationCoordinator?.videoRotationAngleForHorizonLevelPreview ?? 0
        let captureAngle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? previewAngle
        configureVideoConnection(previewView.previewLayer.connection, rotationAngle: previewAngle)
        configureVideoConnection(photoOutput.connection(with: .video), rotationAngle: captureAngle)
        configureMirroring(for: videoOutput.connection(with: .video))
        setCurrentVisionOrientation(Self.visionOrientation(
            forRotationAngle: captureAngle,
            cameraPosition: request.cameraPosition
        ))
    }

    private func configureVideoConnection(_ connection: AVCaptureConnection?, rotationAngle: CGFloat) {
        guard let connection else { return }
        if connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }
        configureMirroring(for: connection)
    }

    private func configureMirroring(for connection: AVCaptureConnection?) {
        guard let connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = request.cameraPosition == .front
    }

    private func setCurrentVisionOrientation(_ orientation: CGImagePropertyOrientation) {
        visionOrientationLock.lock()
        currentVisionOrientation = orientation
        visionOrientationLock.unlock()
    }

    private func lockedVisionOrientation() -> CGImagePropertyOrientation {
        visionOrientationLock.lock()
        let orientation = currentVisionOrientation
        visionOrientationLock.unlock()
        return orientation
    }

    @objc private func startCountdown() {
        guard latestFaceCount == request.requiredFaces, !isCountingDown, !isBurstCapturing else {
            return
        }
        variants.removeAll()
        selectedIndex = 0
        countdownRemaining = request.countdownSeconds
        countdownTargetDate = Date().addingTimeInterval(countdownRemaining)
        isCountingDown = true
        captureButton.isEnabled = false
        startCountdownTimer()
    }

    private func startCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tickCountdown()
        }
    }

    private func tickCountdown() {
        guard isCountingDown, !isBurstCapturing else { return }

        if latestFaceCount != request.requiredFaces {
            resetCountdownForFaceMismatch()
            return
        }

        let remaining = max(0, countdownTargetDate?.timeIntervalSinceNow ?? 0)
        countdownRemaining = remaining
        countdownLabel.text = remaining > 0 ? String(Int(ceil(remaining))) : "0"

        if remaining <= preCaptureLeadSeconds {
            countdownTimer?.invalidate()
            countdownTimer = nil
            isCountingDown = false
            beginBurstCapture()
        }
    }

    private func resetCountdownForFaceMismatch() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        isCountingDown = false
        countdownRemaining = request.countdownSeconds
        countdownTargetDate = nil
        countdownLabel.text = ""
        statusLabel.text = "\(latestFaceCount)/\(request.requiredFaces)"
        statusLabel.textColor = .systemYellow
        captureButton.isEnabled = latestFaceCount == request.requiredFaces
    }

    private func resumeCountdownIfNeeded() {
        guard !isCountingDown, !isBurstCapturing, countdownRemaining > 0, latestFaceCount == request.requiredFaces, selectionOverlay.isHidden else {
            return
        }
        isCountingDown = true
        countdownTargetDate = Date().addingTimeInterval(countdownRemaining)
        captureButton.isEnabled = false
        startCountdownTimer()
    }

    private func beginBurstCapture() {
        guard latestFaceCount == request.requiredFaces else {
            resetCountdownForFaceMismatch()
            return
        }

        isBurstCapturing = true
        countdownLabel.text = "0"
        statusLabel.text = "\(latestFaceCount)/\(request.requiredFaces)"

        let offsets = captureOffsets()
        for (index, offset) in offsets.enumerated() {
            let timer = Timer.scheduledTimer(withTimeInterval: max(0, offset), repeats: false) { [weak self] _ in
                self?.captureVariant(expectedIndex: index, expectedCount: offsets.count)
            }
            captureTimers.append(timer)
        }
    }

    private func captureVariant(expectedIndex: Int, expectedCount: Int) {
        guard latestFaceCount == request.requiredFaces else {
            resetAfterInvalidBurst()
            return
        }

        updateVideoConnections()
        let settings = AVCapturePhotoSettings()
        let delegate = PhotoDelegate { [weak self] result in
            DispatchQueue.main.async {
                self?.handleCapturedPhoto(result, expectedIndex: expectedIndex, expectedCount: expectedCount)
            }
        }
        photoDelegates.append(delegate)
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }

    private func handleCapturedPhoto(_ result: Result<UIImage, AppError>, expectedIndex: Int, expectedCount: Int) {
        switch result {
        case .success(let image):
            variants.append(Variant(image: image, faceCount: latestFaceCount))
        if variants.count >= expectedCount {
            photoDelegates.removeAll()
            showSelection()
        }
        case .failure(let error):
            finish(.failure(error))
        }
    }

    private func resetAfterInvalidBurst() {
        stopCaptureTimers()
        isBurstCapturing = false
        variants.removeAll()
        photoDelegates.removeAll()
        countdownLabel.text = ""
        countdownRemaining = request.countdownSeconds
        updateStatus()
    }

    private func showSelection() {
        stopCaptureTimers()
        isBurstCapturing = false
        selectedIndex = min(1, max(0, variants.count - 1))
        lastSelectionColumnCount = 0
        updateSelectionGrid()
        selectionOverlay.isHidden = false
        countdownLabel.text = ""
    }

    private func updateSelectionGrid() {
        NSLayoutConstraint.deactivate(selectionButtonSizeConstraints)
        selectionButtonSizeConstraints.removeAll()
        selectionStack.arrangedSubviews.forEach { view in
            selectionStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let columnCount = currentSelectionColumnCount()
        let thumbnailSize = currentSelectionThumbnailSize(columns: columnCount)
        lastSelectionColumnCount = columnCount
        selectionStack.axis = .vertical
        selectionStack.alignment = .center
        selectionStack.spacing = isLandscapeLayout ? 10 : 12
        selectionContent.spacing = isLandscapeLayout ? 14 : 20

        let rows = variants.chunked(into: columnCount)
        var flatIndex = 0
        for rowItems in rows {
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .center
            row.spacing = isLandscapeLayout ? 10 : 12
            row.distribution = .equalSpacing
            for variant in rowItems {
                let button = UIButton(type: .custom)
                button.tag = flatIndex
                button.layer.cornerRadius = 12
                button.layer.masksToBounds = true
                button.layer.borderWidth = flatIndex == selectedIndex ? 4 : 1
                button.layer.borderColor = (flatIndex == selectedIndex ? UIColor.white : UIColor.white.withAlphaComponent(0.28)).cgColor
                button.imageView?.contentMode = .scaleAspectFill
                button.setImage(variant.image, for: .normal)
                button.addTarget(self, action: #selector(selectVariant(_:)), for: .touchUpInside)
                row.addArrangedSubview(button)
                let width = button.widthAnchor.constraint(equalToConstant: thumbnailSize)
                let height = button.heightAnchor.constraint(equalToConstant: thumbnailSize)
                selectionButtonSizeConstraints.append(contentsOf: [width, height])
                flatIndex += 1
            }
            selectionStack.addArrangedSubview(row)
        }
        NSLayoutConstraint.activate(selectionButtonSizeConstraints)
    }

    private func updateVisibleSelectionGridIfNeeded() {
        guard !selectionOverlay.isHidden, !variants.isEmpty else { return }
        if currentSelectionColumnCount() != lastSelectionColumnCount {
            updateSelectionGrid()
        }
    }

    private func currentSelectionColumnCount() -> Int {
        guard isLandscapeLayout else { return 2 }
        return max(1, min(variants.count, 4))
    }

    private func currentSelectionThumbnailSize(columns: Int) -> CGFloat {
        let safeBounds = selectionOverlay.safeAreaLayoutGuide.layoutFrame
        let bounds = safeBounds.isEmpty ? view.bounds : safeBounds
        let horizontalSpacing = CGFloat(max(0, columns - 1)) * (isLandscapeLayout ? 10 : 12)
        let availableWidth = max(160, bounds.width - 36 - horizontalSpacing)
        let rows = CGFloat(max(1, Int(ceil(Double(max(1, variants.count)) / Double(max(1, columns))))))
        let verticalSpacing = CGFloat(max(0, Int(rows) - 1)) * (isLandscapeLayout ? 10 : 12)
        let actionHeight: CGFloat = 52
        let contentSpacing: CGFloat = isLandscapeLayout ? 14 : 20
        let availableHeight = max(120, bounds.height - 36 - actionHeight - contentSpacing - verticalSpacing)
        let widthBound = availableWidth / CGFloat(max(1, columns))
        let heightBound = availableHeight / rows
        let maxSize: CGFloat = isLandscapeLayout ? 132 : 220
        let minSize: CGFloat = isLandscapeLayout ? 72 : 96
        return min(maxSize, max(minSize, min(widthBound, heightBound)))
    }

    private var isLandscapeLayout: Bool {
        view.bounds.width > view.bounds.height
    }

    @objc private func selectVariant(_ sender: UIButton) {
        selectedIndex = sender.tag
        updateSelectionGrid()
    }

    @objc private func retake() {
        selectionOverlay.isHidden = true
        variants.removeAll()
        countdownRemaining = 0
        selectedIndex = 0
        updateStatus()
    }

    @objc private func useSelectedPhoto() {
        guard variants.indices.contains(selectedIndex) else {
            finish(.failure(.internalError("No portrait variant selected.")))
            return
        }

        let selected = variants[selectedIndex]
        finish(.success(PortraitCaptureResult(
            image: selected.image,
            selectedIndex: selectedIndex,
            variantsCaptured: variants.count,
            detectedFaces: selected.faceCount
        )))
    }

    @objc private func cancel() {
        finish(.failure(.userCancelled))
    }

    private func finish(_ result: Result<PortraitCaptureResult, AppError>) {
        guard !didComplete else { return }
        didComplete = true
        stopTimers()
        completion(result)
    }

    private func stopTimers() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        stopCaptureTimers()
    }

    private func stopCaptureTimers() {
        captureTimers.forEach { $0.invalidate() }
        captureTimers.removeAll()
    }

    private func updateStatus() {
        let valid = latestFaceCount == request.requiredFaces
        statusLabel.text = "\(latestFaceCount)/\(request.requiredFaces)"
        statusLabel.textColor = valid ? .systemGreen : .systemYellow
        captureButton.isEnabled = valid && !isCountingDown && !isBurstCapturing && selectionOverlay.isHidden
        captureButton.alpha = captureButton.isEnabled ? 1 : 0.48
    }

    private var preCaptureLeadSeconds: TimeInterval {
        request.variationCount > 1 ? request.captureIntervalSeconds : 0
    }

    private func captureOffsets() -> [TimeInterval] {
        (0..<request.variationCount).map { TimeInterval($0) * request.captureIntervalSeconds }
    }

    private static func statusFaceCount(in observations: [VNFaceObservation]) -> Int {
        let completeCount = observations.filter(isCompleteFace).count
        if completeCount == observations.count {
            return completeCount
        }
        return completeCount > 0 ? observations.count : 0
    }

    private static func isCompleteFace(_ observation: VNFaceObservation) -> Bool {
        let frameInset = completeFaceFrameInset
        let box = observation.boundingBox
        guard box.minX >= frameInset,
              box.minY >= frameInset,
              box.maxX <= 1 - frameInset,
              box.maxY <= 1 - frameInset,
              box.width >= minimumCompleteFaceSize,
              box.height >= minimumCompleteFaceSize else {
            return false
        }

        guard let landmarks = observation.landmarks else { return false }
        let hasEyes = (landmarks.leftEye?.pointCount ?? 0) > 0
            && (landmarks.rightEye?.pointCount ?? 0) > 0
        let hasNose = (landmarks.nose?.pointCount ?? 0) > 0
            || (landmarks.noseCrest?.pointCount ?? 0) > 0
        let hasMouth = (landmarks.outerLips?.pointCount ?? 0) > 0
            || (landmarks.innerLips?.pointCount ?? 0) > 0
        return hasEyes && hasNose && hasMouth
    }

    private static func visionOrientation(
        forRotationAngle rotationAngle: CGFloat,
        cameraPosition: PortraitCaptureCameraPosition
    ) -> CGImagePropertyOrientation {
        let isFrontCamera = cameraPosition == .front
        switch normalizedRotationAngle(rotationAngle) {
        case 0:
            return isFrontCamera ? .downMirrored : .up
        case 90:
            return isFrontCamera ? .leftMirrored : .right
        case 180:
            return isFrontCamera ? .upMirrored : .down
        case 270:
            return isFrontCamera ? .rightMirrored : .left
        default:
            return isFrontCamera ? .leftMirrored : .right
        }
    }

    private static func normalizedRotationAngle(_ angle: CGFloat) -> Int {
        let rounded = Int(angle.rounded()) % 360
        return rounded >= 0 ? rounded : rounded + 360
    }

    private static let completeFaceFrameInset: CGFloat = 0.04
    private static let minimumCompleteFaceSize: CGFloat = 0.12
}

extension PortraitCaptureViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectFaceLandmarksRequest { [weak self] request, _ in
            let observations = request.results as? [VNFaceObservation] ?? []
            let count = PortraitCaptureViewController.statusFaceCount(in: observations)
            DispatchQueue.main.async {
                guard let self else { return }
                let previousFaceCount = self.latestFaceCount
                self.latestFaceCount = count
                if self.isCountingDown, count != previousFaceCount {
                    self.resetCountdownForFaceMismatch()
                    return
                }
                if self.isCountingDown {
                    self.resumeCountdownIfNeeded()
                } else {
                    self.updateStatus()
                    self.resumeCountdownIfNeeded()
                }
            }
        }

        let orientation = lockedVisionOrientation()
        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:]).perform([request])
    }
}

private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<UIImage, AppError>) -> Void

    init(completion: @escaping (Result<UIImage, AppError>) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            completion(.failure(.internalError("Photo capture failed: \(error.localizedDescription)")))
            return
        }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            completion(.failure(.imageConversionFailed("Photo capture returned no image data.")))
            return
        }
        completion(.success(image))
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        var chunks: [[Element]] = []
        var index = startIndex
        while index < endIndex {
            let end = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(Array(self[index..<end]))
            index = end
        }
        return chunks
    }
}
