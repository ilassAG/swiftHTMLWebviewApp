//
//  ARGuidedMeasurementBridge.swift
//  swiftHTMLWebviewApp
//
//  ARKit guided measurement bridge with a tappable 3D start arrow.
//

import ARKit
import AVFoundation
import Foundation
import SceneKit
import SwiftUI
import UIKit
import simd

@MainActor
final class ARGuidedMeasurementBridge: ObservableObject {
    @Published var viewVisible = false

    private var eventHandler: (([String: Any]) -> Void)?
    private var latestRequest: [String: Any] = [:]
    private var intervalSeconds: TimeInterval = 0.5
    private var lastEmitTime: TimeInterval = 0
    private var startedAt = Date()
    private var streamToken = UUID()
    private var confirmed = false
    fileprivate weak var controller: ARGuidedMeasurementViewController?
    fileprivate var startConfirmed: Bool { confirmed }

    nonisolated static func isSupported() -> Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    func start(request: [String: Any], eventHandler: @escaping ([String: Any]) -> Void) -> [String: Any] {
        stopInternal(hideView: false)
        latestRequest = request
        self.eventHandler = eventHandler
        intervalSeconds = max(0.1, min(2.0, (doubleValue(request["intervalMs"]) ?? 500) / 1000.0))
        confirmed = false
        let token = UUID()
        streamToken = token

        guard Self.isSupported() else {
            return errorResponse(request: request, action: "arGuidedMeasurementStart", error: "ARKit world tracking is not supported on this device.")
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            viewVisible = true
            return readyResponse(request: request, action: "arGuidedMeasurementStart")
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self, self.streamToken == token else { return }
                    if granted {
                        self.viewVisible = true
                        self.eventHandler?(self.readyResponse(request: request, action: "arGuidedReady"))
                    } else {
                        self.eventHandler?(self.errorResponse(request: request, action: "arGuidedError", error: "Camera permission was denied."))
                    }
                }
            }
            var response = baseResponse(request: request, action: "arGuidedMeasurementStart")
            response["success"] = false
            response["pendingPermission"] = true
            response["supported"] = true
            response["source"] = "arkit-guided"
            response["coordinateSystem"] = "arkit-gravity-local"
            response["intervalMs"] = Int(intervalSeconds * 1000)
            return response
        case .denied, .restricted:
            return errorResponse(request: request, action: "arGuidedMeasurementStart", error: "Camera permission is required for ARKit tracking.")
        @unknown default:
            return errorResponse(request: request, action: "arGuidedMeasurementStart", error: "Unknown camera authorization state.")
        }
    }

    func setAnchors(request: [String: Any]) -> [String: Any] {
        latestRequest = mergeAnchors(into: latestRequest, from: request)
        controller?.refreshStartArrow(resetPlacement: true)
        var response = baseResponse(request: request, action: "arGuidedMeasurementSetAnchors")
        response["success"] = true
        response["source"] = "arkit-guided"
        return response
    }

    func stop(request: [String: Any]) -> [String: Any] {
        stopInternal(hideView: true)
        var response = baseResponse(request: request, action: "arGuidedMeasurementStop")
        response["success"] = true
        response["source"] = "arkit-guided"
        return response
    }

    func closeFromController() {
        if confirmed {
            var response = baseResponse(request: latestRequest, action: "arGuidedMeasurementStop")
            response["success"] = true
            response["source"] = "arkit-guided"
            eventHandler?(response)
        } else {
            eventHandler?(errorResponse(request: latestRequest, action: "arGuidedError", error: "AR Start abgebrochen."))
        }
        stopInternal(hideView: true)
    }

    func shutdown() {
        stopInternal(hideView: true)
    }

    func bind(controller: ARGuidedMeasurementViewController) {
        self.controller = controller
    }

    func emitReadyFromController() {
        eventHandler?(readyResponse(request: latestRequest, action: "arGuidedReady"))
    }

    func emitError(_ message: String) {
        eventHandler?(errorResponse(request: latestRequest, action: "arGuidedError", error: message))
    }

    func emitPosition(frame: ARFrame) {
        if lastEmitTime > 0, frame.timestamp - lastEmitTime < intervalSeconds {
            return
        }
        lastEmitTime = frame.timestamp
        eventHandler?(positionResponse(frame: frame, action: "arGuidedPosition"))
    }

    @discardableResult
    func confirmStart(frame: ARFrame, source: String = "tap") -> Bool {
        guard !confirmed else { return false }
        confirmed = true
        var response = positionResponse(frame: frame, action: "arGuidedStartAnchorConfirmed")
        response["startAnchor"] = startAnchorPayload()
        response["anchor"] = startAnchorPayload()
        response["anchorId"] = stringValue(startAnchorPayload()?["id"])
        response["startAnchorId"] = stringValue(startAnchorPayload()?["id"])
        response["confirmationSource"] = source
        eventHandler?(response)
        return true
    }

    func captureAnchor(frame: ARFrame, label: String = "AR Messpunkt") {
        var response = positionResponse(frame: frame, action: "arGuidedAnchorCaptured")
        response["label"] = label
        response["startAnchorId"] = stringValue(startAnchorPayload()?["id"])
        eventHandler?(response)
    }

    func startAnchorPayload() -> [String: Any]? {
        if let anchor = latestRequest["startAnchor"] as? [String: Any] {
            return anchor
        }
        if let anchors = latestRequest["anchors"] as? [[String: Any]] {
            return anchors.first { stringValue($0["kind"]) == "start" }
        }
        return nil
    }

    private func positionResponse(frame: ARFrame, action: String) -> [String: Any] {
        var response = baseResponse(request: latestRequest, action: action)
        response["success"] = true
        response["source"] = "arkit-guided"
        response["coordinateSystem"] = "arkit-gravity-local"
        response["timestampMs"] = Int(Date().timeIntervalSince1970 * 1000)
        response["arTimestampSeconds"] = frame.timestamp
        response["elapsedSeconds"] = Date().timeIntervalSince(startedAt)
        response["supported"] = true

        let tracking = trackingStatePayload(frame.camera.trackingState)
        response["trackingState"] = tracking.state
        if !tracking.reason.isEmpty {
            response["trackingReason"] = tracking.reason
        }

        let transform = frame.camera.transform
        let position = transform.columns.3
        response["position"] = [
            "x": Double(position.x),
            "y": Double(position.y),
            "z": Double(position.z),
            "unit": "meters"
        ]
        response["orientation"] = [
            "pitch": Double(frame.camera.eulerAngles.x),
            "yaw": Double(frame.camera.eulerAngles.y),
            "roll": Double(frame.camera.eulerAngles.z),
            "unit": "radians"
        ]
        response["transform"] = transformPayload(transform)
        if let anchor = startAnchorPayload() {
            response["startAnchorId"] = stringValue(anchor["id"])
        }
        return response
    }

    private func readyResponse(request: [String: Any], action: String) -> [String: Any] {
        startedAt = Date()
        lastEmitTime = 0
        var response = baseResponse(request: request, action: action)
        response["success"] = true
        response["supported"] = true
        response["source"] = "arkit-guided"
        response["coordinateSystem"] = "arkit-gravity-local"
        response["intervalMs"] = Int(intervalSeconds * 1000)
        response["startAnchor"] = startAnchorPayload()
        return response
    }

    private func stopInternal(hideView: Bool) {
        controller?.stopSession()
        controller = nil
        lastEmitTime = 0
        streamToken = UUID()
        if hideView {
            viewVisible = false
            eventHandler = nil
        }
    }

    private func mergeAnchors(into current: [String: Any], from request: [String: Any]) -> [String: Any] {
        var next = current
        if let startAnchor = request["startAnchor"] {
            next["startAnchor"] = startAnchor
        }
        if let anchors = request["anchors"] {
            next["anchors"] = anchors
        }
        if let bounds = request["bounds"] {
            next["bounds"] = bounds
        }
        return next
    }

    private func trackingStatePayload(_ trackingState: ARCamera.TrackingState) -> (state: String, reason: String) {
        switch trackingState {
        case .normal:
            return ("normal", "")
        case .notAvailable:
            return ("notAvailable", "")
        case .limited(let reason):
            switch reason {
            case .excessiveMotion:
                return ("limited", "excessiveMotion")
            case .insufficientFeatures:
                return ("limited", "insufficientFeatures")
            case .initializing:
                return ("limited", "initializing")
            case .relocalizing:
                return ("limited", "relocalizing")
            @unknown default:
                return ("limited", "unknown")
            }
        }
    }

    private func transformPayload(_ transform: simd_float4x4) -> [Double] {
        [
            Double(transform.columns.0.x), Double(transform.columns.0.y), Double(transform.columns.0.z), Double(transform.columns.0.w),
            Double(transform.columns.1.x), Double(transform.columns.1.y), Double(transform.columns.1.z), Double(transform.columns.1.w),
            Double(transform.columns.2.x), Double(transform.columns.2.y), Double(transform.columns.2.z), Double(transform.columns.2.w),
            Double(transform.columns.3.x), Double(transform.columns.3.y), Double(transform.columns.3.z), Double(transform.columns.3.w)
        ]
    }

    private func baseResponse(request: [String: Any], action: String) -> [String: Any] {
        var response: [String: Any] = [
            "platform": "ios",
            "action": action
        ]
        if let requestId = request["requestId"] {
            response["requestId"] = requestId
        }
        return response
    }

    private func errorResponse(request: [String: Any], action: String, error: String) -> [String: Any] {
        var response = baseResponse(request: request, action: action)
        response["success"] = false
        response["supported"] = Self.isSupported()
        response["source"] = "arkit-guided"
        response["error"] = error
        return response
    }
}

struct ARGuidedMeasurementSheet: View {
    @ObservedObject var bridge: ARGuidedMeasurementBridge
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ARGuidedMeasurementRepresentable(bridge: bridge)
            .ignoresSafeArea()
        .onChange(of: bridge.viewVisible) { _, visible in
            if !visible {
                dismiss()
            }
        }
    }
}

private struct ARGuidedMeasurementRepresentable: UIViewControllerRepresentable {
    let bridge: ARGuidedMeasurementBridge

    func makeUIViewController(context: Context) -> ARGuidedMeasurementViewController {
        let controller = ARGuidedMeasurementViewController(bridge: bridge)
        bridge.bind(controller: controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: ARGuidedMeasurementViewController, context: Context) {
        uiViewController.refreshStartArrow()
    }
}

final class ARGuidedMeasurementViewController: UIViewController, ARSessionDelegate {
    private let sceneView = ARSCNView(frame: .zero)
    private let overlayView = UIView(frame: .zero)
    private let statusLabel = UILabel(frame: .zero)
    private let detailLabel = UILabel(frame: .zero)
    private let confirmButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let pointButton = UIButton(type: .system)
    private weak var bridge: ARGuidedMeasurementBridge?
    private var arrowNode: SCNNode?
    private var arrowPlacedInWorld = false
    private var alignmentStartTime: TimeInterval?
    private var lastAlignmentStatusTime: TimeInterval = 0

    private enum AlignmentThresholds {
        static let horizontalDistanceMeters: Float = 0.36
        static let yawRadians: Float = 0.44
        static let requiredStableSeconds: TimeInterval = 0.7
        static let statusIntervalSeconds: TimeInterval = 0.35
    }

    var currentFrame: ARFrame? {
        sceneView.session.currentFrame
    }

    init(bridge: ARGuidedMeasurementBridge) {
        self.bridge = bridge
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        sceneView.automaticallyUpdatesLighting = true
        sceneView.autoenablesDefaultLighting = true
        sceneView.scene = SCNScene()
        sceneView.session.delegate = self
        view.addSubview(sceneView)
        NSLayoutConstraint.activate([
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        sceneView.addGestureRecognizer(tap)
        configureOverlay()
        refreshStartArrow()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        runSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    func runSession() {
        guard ARGuidedMeasurementBridge.isSupported() else {
            bridge?.emitError("ARKit world tracking is not supported on this device.")
            return
        }
        refreshStartArrow(resetPlacement: true)
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = [.horizontal]
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        bridge?.emitReadyFromController()
    }

    func stopSession() {
        sceneView.session.pause()
    }

    func refreshStartArrow(resetPlacement: Bool = false) {
        if resetPlacement {
            arrowPlacedInWorld = false
            alignmentStartTime = nil
            arrowNode?.removeFromParentNode()
            arrowNode = nil
        }
        guard arrowNode == nil else { return }
        let node = makeArrowNode()
        node.isHidden = true
        arrowNode = node
        sceneView.scene.rootNode.addChildNode(node)
        if !resetPlacement, let frame = sceneView.session.currentFrame {
            placeStartArrowInWorldIfNeeded(frame: frame)
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor in
            self.placeStartArrowInWorldIfNeeded(frame: frame)
            self.evaluateStartAlignment(frame: frame)
            self.bridge?.emitPosition(frame: frame)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.bridge?.emitError(error.localizedDescription)
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in
            self.bridge?.emitError("AR session was interrupted.")
        }
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: sceneView)
        let hits = sceneView.hitTest(point, options: nil)
        let tappedArrow = hits.contains { nodeHit in
            var node: SCNNode? = nodeHit.node
            while let current = node {
                if current.name == "startArrow" {
                    return true
                }
                node = current.parent
            }
            return false
        }
        guard tappedArrow || isTapNearStartArrow(point) || hits.isEmpty else { return }
        confirmCurrentFrame(source: tappedArrow ? "arrowTap" : "sceneTap")
    }

    @objc private func confirmButtonPressed() {
        confirmCurrentFrame(source: "button")
    }

    @objc private func closeButtonPressed() {
        bridge?.closeFromController()
    }

    @objc private func pointButtonPressed() {
        guard let frame = sceneView.session.currentFrame else { return }
        bridge?.captureAnchor(frame: frame)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showRunningStatus("Messpunkt gespeichert.")
    }

    private func confirmCurrentFrame(source: String) {
        guard let frame = sceneView.session.currentFrame else { return }
        if bridge?.confirmStart(frame: frame, source: source) == true {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        showConfirmedStatus()
    }

    private func showConfirmedStatus() {
        statusLabel.text = "Messung läuft"
        detailLabel.text = "Startposition bestätigt. ARKit zeichnet die Messpunkte weiter auf."
        confirmButton.isEnabled = false
        confirmButton.alpha = 0.55
        var configuration = confirmButton.configuration
        configuration?.title = "Start bestätigt"
        confirmButton.configuration = configuration
        pointButton.isEnabled = true
        pointButton.alpha = 1
    }

    private func showRunningStatus(_ detail: String) {
        statusLabel.text = bridge?.startConfirmed == true ? "Messung läuft" : "Startpfeil"
        detailLabel.text = detail
    }

    private func configureOverlay() {
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        overlayView.layer.cornerRadius = 18
        overlayView.layer.cornerCurve = .continuous
        overlayView.isUserInteractionEnabled = true

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "Startpfeil"
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 18, weight: .bold)
        statusLabel.numberOfLines = 1

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.text = "Zum Pfeil gehen, in Pfeilrichtung schauen oder Start bestätigen antippen."
        detailLabel.textColor = UIColor.white.withAlphaComponent(0.86)
        detailLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        detailLabel.numberOfLines = 2

        configureButton(confirmButton, title: "Start bestätigen", color: .systemGreen, action: #selector(confirmButtonPressed))
        configureButton(closeButton, title: "Schliessen", color: .systemRed, action: #selector(closeButtonPressed))
        configureButton(pointButton, title: "Messpunkt", color: .systemBlue, action: #selector(pointButtonPressed))
        pointButton.isEnabled = false
        pointButton.alpha = 0.55

        let textStack = UIStackView(arrangedSubviews: [statusLabel, detailLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 4

        let buttonStack = UIStackView(arrangedSubviews: [closeButton, confirmButton, pointButton])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .horizontal
        buttonStack.spacing = 8
        buttonStack.distribution = .fillEqually

        overlayView.addSubview(textStack)
        overlayView.addSubview(buttonStack)
        view.addSubview(overlayView)
        view.bringSubviewToFront(overlayView)

        NSLayoutConstraint.activate([
            overlayView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            overlayView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            overlayView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),

            textStack.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor, constant: -14),
            textStack.topAnchor.constraint(equalTo: overlayView.topAnchor, constant: 12),

            buttonStack.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor, constant: 10),
            buttonStack.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor, constant: -10),
            buttonStack.topAnchor.constraint(equalTo: textStack.bottomAnchor, constant: 10),
            buttonStack.bottomAnchor.constraint(equalTo: overlayView.bottomAnchor, constant: -10),
            buttonStack.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func configureButton(_ button: UIButton, title: String, color: UIColor, action: Selector) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.baseBackgroundColor = color
        configuration.baseForegroundColor = .black
        configuration.cornerStyle = .medium
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 14, weight: .bold)
            return outgoing
        }
        button.configuration = configuration
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func evaluateStartAlignment(frame: ARFrame) {
        guard bridge?.startConfirmed != true, arrowPlacedInWorld, let arrowNode else { return }

        let distance = horizontalDistance(from: cameraPosition(frame), to: arrowNode.simdWorldPosition)
        let yawDelta = abs(normalizedAngle(frame.camera.eulerAngles.y - desiredCameraYaw(for: arrowNode)))
        let aligned = distance <= AlignmentThresholds.horizontalDistanceMeters && yawDelta <= AlignmentThresholds.yawRadians

        if aligned {
            if alignmentStartTime == nil {
                alignmentStartTime = frame.timestamp
            }
            let stableSeconds = frame.timestamp - (alignmentStartTime ?? frame.timestamp)
            if stableSeconds >= AlignmentThresholds.requiredStableSeconds {
                confirmCurrentFrame(source: "autoAlignment")
                return
            }
            updateAlignmentStatus(frame: frame, distance: distance, yawDelta: yawDelta, prefix: "Position erkannt")
        } else {
            alignmentStartTime = nil
            updateAlignmentStatus(frame: frame, distance: distance, yawDelta: yawDelta, prefix: "Zum Pfeil ausrichten")
        }
    }

    private func updateAlignmentStatus(frame: ARFrame, distance: Float, yawDelta: Float, prefix: String) {
        guard frame.timestamp - lastAlignmentStatusTime >= AlignmentThresholds.statusIntervalSeconds else { return }
        lastAlignmentStatusTime = frame.timestamp
        let centimeters = max(0, Int(distance * 100))
        let degrees = max(0, Int(yawDelta * 180 / .pi))
        detailLabel.text = "\(prefix): \(centimeters) cm / \(degrees) Grad. Antippen bestätigt sofort."
    }

    private func isTapNearStartArrow(_ point: CGPoint) -> Bool {
        guard let arrowNode, !arrowNode.isHidden else { return false }
        let projected = sceneView.projectPoint(arrowNode.worldPosition)
        guard projected.z >= 0, projected.z <= 1 else { return false }
        let center = CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
        let dx = center.x - point.x
        let dy = center.y - point.y
        return sqrt(dx * dx + dy * dy) <= 70
    }

    private func placeStartArrowInWorldIfNeeded(frame: ARFrame) {
        guard !arrowPlacedInWorld, let arrowNode, arrowNode.parent != nil else { return }
        arrowNode.simdPosition = startArrowWorldPosition(frame: frame)
        arrowNode.eulerAngles = SCNVector3(0, startArrowWorldYaw(frame: frame), 0)
        arrowNode.isHidden = false
        arrowPlacedInWorld = true
    }

    // The start arrow is a fixed working-height marker. The web app shows the
    // plan position first; when AR opens, the technician is expected to stand
    // at that spot and this marker confirms the current camera pose.
    private func startArrowWorldPosition(frame: ARFrame) -> SIMD3<Float> {
        let cameraTransform = frame.camera.transform
        let cameraPosition = cameraTransform.columns.3
        return SIMD3<Float>(cameraPosition.x, cameraPosition.y, cameraPosition.z) + horizontalForwardVector(cameraTransform) * 0.9
    }

    private func startArrowWorldYaw(frame: ARFrame) -> Float {
        let anchorYaw = Float(doubleValue(bridge?.startAnchorPayload()?["yawRadians"]) ?? 0)
        return frame.camera.eulerAngles.y + Float.pi / 2 + anchorYaw
    }

    private func cameraPosition(_ frame: ARFrame) -> SIMD3<Float> {
        let position = frame.camera.transform.columns.3
        return SIMD3<Float>(position.x, position.y, position.z)
    }

    private func horizontalDistance(from first: SIMD3<Float>, to second: SIMD3<Float>) -> Float {
        simd_length(SIMD2<Float>(first.x - second.x, first.z - second.z))
    }

    private func desiredCameraYaw(for arrowNode: SCNNode) -> Float {
        arrowNode.eulerAngles.y - Float.pi / 2
    }

    private func normalizedAngle(_ angle: Float) -> Float {
        atan2(sin(angle), cos(angle))
    }

    private func horizontalForwardVector(_ transform: simd_float4x4) -> SIMD3<Float> {
        let rawForward = -SIMD3<Float>(transform.columns.2.x, 0, transform.columns.2.z)
        if simd_length(rawForward) > 0.001 {
            return simd_normalize(rawForward)
        }
        return SIMD3<Float>(0, 0, -1)
    }

    private func makeArrowNode() -> SCNNode {
        let root = SCNNode()
        root.name = "startArrow"

        let shaft = SCNCylinder(radius: 0.035, height: 0.54)
        shaft.firstMaterial?.diffuse.contents = UIColor.systemGreen
        shaft.firstMaterial?.emission.contents = UIColor.systemGreen.withAlphaComponent(0.22)
        let shaftNode = SCNNode(geometry: shaft)
        shaftNode.name = "startArrow"
        shaftNode.eulerAngles.z = .pi / 2
        shaftNode.position.x = -0.1
        root.addChildNode(shaftNode)

        let head = SCNCone(topRadius: 0, bottomRadius: 0.12, height: 0.24)
        head.firstMaterial?.diffuse.contents = UIColor.systemGreen
        head.firstMaterial?.emission.contents = UIColor.systemGreen.withAlphaComponent(0.28)
        let headNode = SCNNode(geometry: head)
        headNode.name = "startArrow"
        headNode.eulerAngles.z = -.pi / 2
        headNode.position.x = 0.24
        root.addChildNode(headNode)

        let base = SCNTorus(ringRadius: 0.2, pipeRadius: 0.009)
        base.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.88)
        let baseNode = SCNNode(geometry: base)
        baseNode.name = "startArrow"
        baseNode.eulerAngles.x = .pi / 2
        baseNode.position.y = -0.08
        root.addChildNode(baseNode)

        root.scale = SCNVector3(1, 1, 1)
        return root
    }
}
