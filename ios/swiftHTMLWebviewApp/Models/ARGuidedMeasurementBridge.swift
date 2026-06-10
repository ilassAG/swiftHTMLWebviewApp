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

    func updateStats(request: [String: Any]) -> [String: Any] {
        controller?.updateMeasurementStats(request)
        var response = baseResponse(request: request, action: "arGuidedMeasurementUpdateStats")
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

    func floorPlanPlanPayload() -> [String: Any]? {
        if let plan = latestRequest["floorPlanPlanJson"] as? [String: Any] {
            return plan
        }
        if let plan = latestRequest["normalizedPlan"] as? [String: Any] {
            return plan
        }
        if let floorPlan = latestRequest["floorPlan"] as? [String: Any],
           let plan = floorPlan["planJson"] as? [String: Any] {
            return plan
        }
        return nil
    }

    func requestedWorldMapBase64() -> String {
        stringValue(latestRequest["worldMapBase64"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func requestedWorldMapURL() -> URL? {
        let raw = stringValue(latestRequest["worldMapUrl"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    func requestedWorldMapAvailable() -> Bool {
        if boolValue(latestRequest["worldMapAvailable"]) == true {
            return true
        }
        return !requestedWorldMapBase64().isEmpty || requestedWorldMapURL() != nil
    }

    func emitRelocalizationState(action: String, state: String, message: String, frame: ARFrame? = nil) {
        var response = baseResponse(request: latestRequest, action: action)
        response["success"] = true
        response["source"] = "arkit-guided"
        response["state"] = state
        response["message"] = message
        response["worldMapAvailable"] = requestedWorldMapAvailable()
        if let frame {
            let tracking = trackingStatePayload(frame.camera.trackingState)
            response["trackingState"] = tracking.state
            if !tracking.reason.isEmpty {
                response["trackingReason"] = tracking.reason
            }
            response["worldMappingStatus"] = worldMappingStatusName(frame.worldMappingStatus)
        }
        eventHandler?(response)
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
        response["worldMapAvailable"] = requestedWorldMapAvailable()

        let tracking = trackingStatePayload(frame.camera.trackingState)
        response["trackingState"] = tracking.state
        if !tracking.reason.isEmpty {
            response["trackingReason"] = tracking.reason
        }
        response["worldMappingStatus"] = worldMappingStatusName(frame.worldMappingStatus)

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
            "headingYaw": Double(arHeadingYaw(frame: frame)),
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
        response["worldMapAvailable"] = requestedWorldMapAvailable()
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

    private func horizontalForwardVector(_ transform: simd_float4x4) -> SIMD3<Float> {
        let rawForward = -SIMD3<Float>(transform.columns.2.x, 0, transform.columns.2.z)
        if simd_length(rawForward) > 0.001 {
            return simd_normalize(rawForward)
        }
        return SIMD3<Float>(0, 0, -1)
    }

    private func arHeadingYaw(frame: ARFrame) -> Float {
        let forward = horizontalForwardVector(frame.camera.transform)
        return atan2(forward.z, forward.x)
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

private func worldMappingStatusName(_ status: ARFrame.WorldMappingStatus) -> String {
    switch status {
    case .notAvailable:
        return "notAvailable"
    case .limited:
        return "limited"
    case .extending:
        return "extending"
    case .mapped:
        return "mapped"
    @unknown default:
        return "unknown"
    }
}

private enum ARGuidedMeasurementError: LocalizedError {
    case worldMapMissing
    case worldMapDecodeFailed

    var errorDescription: String? {
        switch self {
        case .worldMapMissing:
            return "Keine ARWorldMap im Start-Request."
        case .worldMapDecodeFailed:
            return "ARWorldMap konnte nicht dekodiert werden."
        }
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
    private let coachingOverlay = ARCoachingOverlayView(frame: .zero)
    private let overlayView = UIView(frame: .zero)
    private let statusLabel = UILabel(frame: .zero)
    private let detailLabel = UILabel(frame: .zero)
    private let statsStack = UIStackView(frame: .zero)
    private let counterValueLabel = UILabel(frame: .zero)
    private let rttValueLabel = UILabel(frame: .zero)
    private let errorsValueLabel = UILabel(frame: .zero)
    private let wifiValueLabel = UILabel(frame: .zero)
    private let confirmButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let pointButton = UIButton(type: .system)
    private weak var bridge: ARGuidedMeasurementBridge?
    private var arrowNode: SCNNode?
    private var roomPlanNode: SCNNode?
    private var arrowPlacedInWorld = false
    private var arrowDesiredHeadingYaw: Float?
    private var alignmentStartTime: TimeInterval?
    private var lastAlignmentStatusTime: TimeInterval = 0
    private var statsHeightConstraint: NSLayoutConstraint?
    private var initialWorldMap: ARWorldMap?
    private var requiresWorldMapRelocalization = false
    private var worldMapRelocalized = false
    private var runTask: Task<Void, Never>?

    private enum AlignmentThresholds {
        static let horizontalDistanceMeters: Float = 0.16
        static let yawRadians: Float = 0.35
        static let requiredStableSeconds: TimeInterval = 0.85
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
        configureCoachingOverlay()
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
        runTask?.cancel()
        runTask = Task { [weak self] in
            await self?.runSessionAfterWorldMapLoad()
        }
    }

    func stopSession() {
        runTask?.cancel()
        runTask = nil
        sceneView.session.pause()
    }

    private func runSessionAfterWorldMapLoad() async {
        initialWorldMap = nil
        requiresWorldMapRelocalization = false
        worldMapRelocalized = false

        if bridge?.requestedWorldMapAvailable() == true {
            showRelocalizingStatus("AR-Raumkarte wird geladen.")
            do {
                initialWorldMap = try await loadInitialWorldMap()
                requiresWorldMapRelocalization = true
                bridge?.emitRelocalizationState(
                    action: "arGuidedRelocalizing",
                    state: "loading",
                    message: "AR-Raumkarte geladen. Raum langsam mit dem iPhone wiedererkennen."
                )
            } catch {
                bridge?.emitError("AR-Raumkarte konnte nicht geladen werden: \(error.localizedDescription)")
                showRelocalizingStatus("AR-Raumkarte konnte nicht geladen werden.")
                return
            }
        }

        guard !Task.isCancelled else { return }
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.initialWorldMap = initialWorldMap
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        if requiresWorldMapRelocalization {
            showRelocalizingStatus("Raum langsam scannen, bis ARKit die gespeicherte Position erkennt.")
            bridge?.emitRelocalizationState(
                action: "arGuidedRelocalizing",
                state: "relocalizing",
                message: "Raum langsam scannen, bis der gespeicherte Startpfeil erscheint."
            )
        }
        bridge?.emitReadyFromController()
    }

    private func loadInitialWorldMap() async throws -> ARWorldMap {
        if let base64 = bridge?.requestedWorldMapBase64(), !base64.isEmpty {
            let encoded = base64.contains(",") ? String(base64.split(separator: ",", maxSplits: 1).last ?? "") : base64
            guard let data = Data(base64Encoded: encoded) else {
                throw ARGuidedMeasurementError.worldMapDecodeFailed
            }
            return try decodeWorldMap(data)
        }
        if let url = bridge?.requestedWorldMapURL() {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try decodeWorldMap(data)
        }
        throw ARGuidedMeasurementError.worldMapMissing
    }

    private func decodeWorldMap(_ data: Data) throws -> ARWorldMap {
        guard let worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) else {
            throw ARGuidedMeasurementError.worldMapDecodeFailed
        }
        return worldMap
    }

    func updateMeasurementStats(_ stats: [String: Any]) {
        let rest = intValue(stats["restSequence"]) ?? 0
        let websocket = intValue(stats["websocketSequence"]) ?? 0
        let counter = intValue(stats["counter"]) ?? (rest + websocket)
        counterValueLabel.text = "\(counter) | R \(rest) W \(websocket)"

        if let rtt = doubleValue(stats["lastRttMs"]) {
            let protocolName = stringValue(stats["lastProtocol"]).isEmpty ? "RTT" : stringValue(stats["lastProtocol"])
            rttValueLabel.text = "\(protocolName) \(Int(rtt.rounded())) ms"
        } else {
            rttValueLabel.text = "-"
        }

        errorsValueLabel.text = "\(intValue(stats["errors"]) ?? 0)"
        wifiValueLabel.text = wifiStatsText(stats)

        if let eventText = nonEmpty(stringValue(stats["eventText"])) {
            detailLabel.text = eventText
        }
    }

    func refreshStartArrow(resetPlacement: Bool = false) {
        if resetPlacement {
            arrowPlacedInWorld = false
            alignmentStartTime = nil
            roomPlanNode?.removeFromParentNode()
            roomPlanNode = nil
            arrowNode?.removeFromParentNode()
            arrowNode = nil
            arrowDesiredHeadingYaw = nil
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
            self.updateRelocalizationState(frame: frame)
            if self.canUseWorldAnchors {
                self.placeWorldMapRoomPlanOverlayIfNeeded(frame: frame)
                self.placeStartArrowInWorldIfNeeded(frame: frame)
                self.evaluateStartAlignment(frame: frame)
            }
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
        guard let arrowNode else { return }
        let alignment = startAlignment(frame: frame, arrowNode: arrowNode)
        guard alignment.aligned else {
            alignmentStartTime = nil
            updateAlignmentStatus(frame: frame, distance: alignment.distance, yawDelta: alignment.yawDelta, prefix: "Noch nicht am Pfeil")
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        if bridge?.confirmStart(frame: frame, source: source) == true {
            placeRoomPlanOverlay(forConfirmedFrame: frame)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        showConfirmedStatus()
    }

    private func showConfirmedStatus() {
        arrowNode?.isHidden = true
        statusLabel.text = "Messung läuft"
        detailLabel.text = "Start bestätigt. Messung beginnt, Live-Werte erscheinen hier."
        confirmButton.isEnabled = false
        confirmButton.alpha = 0.55
        var configuration = confirmButton.configuration
        configuration?.title = "Start bestätigt"
        confirmButton.configuration = configuration
        pointButton.isEnabled = true
        pointButton.alpha = 1
        statsStack.isHidden = false
        statsHeightConstraint?.constant = 52
    }

    private func showRunningStatus(_ detail: String) {
        statusLabel.text = bridge?.startConfirmed == true ? "Messung läuft" : "Startpfeil"
        detailLabel.text = detail
    }

    private func configureCoachingOverlay() {
        coachingOverlay.translatesAutoresizingMaskIntoConstraints = false
        coachingOverlay.session = sceneView.session
        coachingOverlay.goal = .tracking
        coachingOverlay.activatesAutomatically = true
        coachingOverlay.setActive(true, animated: false)
        view.addSubview(coachingOverlay)
        NSLayoutConstraint.activate([
            coachingOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            coachingOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            coachingOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            coachingOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
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
        detailLabel.text = "Auf dem Planpfeil stehen, iPhone in Pfeilrichtung halten. Start wird automatisch bestätigt."
        detailLabel.textColor = UIColor.white.withAlphaComponent(0.86)
        detailLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        detailLabel.numberOfLines = 2

        configureStatsStack()
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
        overlayView.addSubview(statsStack)
        overlayView.addSubview(buttonStack)
        view.addSubview(overlayView)
        view.bringSubviewToFront(overlayView)

        let statsHeightConstraint = statsStack.heightAnchor.constraint(equalToConstant: 0)
        self.statsHeightConstraint = statsHeightConstraint
        NSLayoutConstraint.activate([
            overlayView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            overlayView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            overlayView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),

            textStack.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor, constant: -14),
            textStack.topAnchor.constraint(equalTo: overlayView.topAnchor, constant: 12),

            statsStack.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor, constant: 10),
            statsStack.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor, constant: -10),
            statsStack.topAnchor.constraint(equalTo: textStack.bottomAnchor, constant: 10),
            statsHeightConstraint,

            buttonStack.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor, constant: 10),
            buttonStack.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor, constant: -10),
            buttonStack.topAnchor.constraint(equalTo: statsStack.bottomAnchor, constant: 10),
            buttonStack.bottomAnchor.constraint(equalTo: overlayView.bottomAnchor, constant: -10),
            buttonStack.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func configureStatsStack() {
        statsStack.translatesAutoresizingMaskIntoConstraints = false
        statsStack.axis = .horizontal
        statsStack.spacing = 6
        statsStack.distribution = .fillEqually
        statsStack.isHidden = true
        counterValueLabel.text = "0 | R 0 W 0"
        rttValueLabel.text = "-"
        errorsValueLabel.text = "0"
        wifiValueLabel.text = "-"
        statsStack.addArrangedSubview(makeStatView(title: "Zähler", valueLabel: counterValueLabel))
        statsStack.addArrangedSubview(makeStatView(title: "RTT", valueLabel: rttValueLabel))
        statsStack.addArrangedSubview(makeStatView(title: "Fehler", valueLabel: errorsValueLabel))
        statsStack.addArrangedSubview(makeStatView(title: "WLAN/AP", valueLabel: wifiValueLabel))
    }

    private func makeStatView(title: String, valueLabel: UILabel) -> UIView {
        let titleLabel = UILabel(frame: .zero)
        titleLabel.text = title
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.62)
        titleLabel.font = .systemFont(ofSize: 10, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1

        valueLabel.textColor = .white
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        valueLabel.textAlignment = .center
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.68
        valueLabel.numberOfLines = 1

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 3

        let container = UIView(frame: .zero)
        container.backgroundColor = UIColor.white.withAlphaComponent(0.09)
        container.layer.cornerRadius = 10
        container.layer.cornerCurve = .continuous
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 5),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -5),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
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

    private var canUseWorldAnchors: Bool {
        !requiresWorldMapRelocalization || worldMapRelocalized
    }

    private func updateRelocalizationState(frame: ARFrame) {
        guard requiresWorldMapRelocalization, !worldMapRelocalized else { return }
        switch frame.camera.trackingState {
        case .normal:
            worldMapRelocalized = true
            statusLabel.text = "Raum erkannt"
            detailLabel.text = "Startpfeil ist jetzt an der gespeicherten Position."
            confirmButton.isEnabled = true
            confirmButton.alpha = 1
            bridge?.emitRelocalizationState(
                action: "arGuidedRelocalized",
                state: "relocalized",
                message: "ARKit hat die gespeicherte Raumkarte wiedererkannt.",
                frame: frame
            )
        case .limited, .notAvailable:
            guard frame.timestamp - lastAlignmentStatusTime >= AlignmentThresholds.statusIntervalSeconds else { return }
            lastAlignmentStatusTime = frame.timestamp
            showRelocalizingStatus("Raum langsam links/rechts scannen. Der Pfeil erscheint erst nach Wiedererkennung.")
            bridge?.emitRelocalizationState(
                action: "arGuidedRelocalizing",
                state: "relocalizing",
                message: "ARKit sucht die gespeicherte Raumkarte.",
                frame: frame
            )
        }
    }

    private func showRelocalizingStatus(_ detail: String) {
        statusLabel.text = "Raum wiedererkennen"
        detailLabel.text = detail
        confirmButton.isEnabled = false
        confirmButton.alpha = 0.55
        pointButton.isEnabled = false
        pointButton.alpha = 0.55
    }

    private func evaluateStartAlignment(frame: ARFrame) {
        guard bridge?.startConfirmed != true, arrowPlacedInWorld, let arrowNode else { return }

        let alignment = startAlignment(frame: frame, arrowNode: arrowNode)

        if alignment.aligned {
            if alignmentStartTime == nil {
                alignmentStartTime = frame.timestamp
            }
            let stableSeconds = frame.timestamp - (alignmentStartTime ?? frame.timestamp)
            if stableSeconds >= AlignmentThresholds.requiredStableSeconds {
                confirmCurrentFrame(source: "autoAlignment")
                return
            }
            updateAlignmentStatus(frame: frame, distance: alignment.distance, yawDelta: alignment.yawDelta, prefix: "Position erkannt")
        } else {
            alignmentStartTime = nil
            updateAlignmentStatus(frame: frame, distance: alignment.distance, yawDelta: alignment.yawDelta, prefix: "Zum Pfeil ausrichten")
        }
    }

    private func startAlignment(frame: ARFrame, arrowNode: SCNNode) -> (aligned: Bool, distance: Float, yawDelta: Float) {
        let distance = horizontalDistance(from: cameraPosition(frame), to: arrowNode.simdWorldPosition)
        let yawDelta = abs(normalizedAngle(arHeadingYaw(frame: frame) - desiredCameraHeadingYaw(for: arrowNode)))
        return (
            distance <= AlignmentThresholds.horizontalDistanceMeters && yawDelta <= AlignmentThresholds.yawRadians,
            distance,
            yawDelta
        )
    }

    private func updateAlignmentStatus(frame: ARFrame, distance: Float, yawDelta: Float, prefix: String) {
        guard frame.timestamp - lastAlignmentStatusTime >= AlignmentThresholds.statusIntervalSeconds else { return }
        lastAlignmentStatusTime = frame.timestamp
        let centimeters = max(0, Int(distance * 100))
        let degrees = max(0, Int(yawDelta * 180 / .pi))
        detailLabel.text = "\(prefix): \(centimeters) cm / \(degrees) Grad. Stehen bleiben, Richtung halten."
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
        let desiredHeading = startArrowDesiredHeading(frame: frame)
        arrowNode.eulerAngles = SCNVector3(0, sceneKitYaw(forHeadingYaw: desiredHeading), 0)
        arrowDesiredHeadingYaw = desiredHeading
        arrowNode.isHidden = false
        arrowPlacedInWorld = true
    }

    // The start arrow is a working-height direction marker, not the physical
    // plan coordinate. The current iPhone camera pose becomes the calibrated
    // plan start when the user is already standing on the plan arrow.
    private func startArrowWorldPosition(frame: ARFrame) -> SIMD3<Float> {
        if initialWorldMap != nil, let startAnchor = bridge?.startAnchorPayload() {
            let x = Float(doubleValue(startAnchor["planX"]) ?? 0)
            let z = Float(doubleValue(startAnchor["planY"]) ?? 0)
            return SIMD3<Float>(x, workingHeightMeters(startAnchor: startAnchor), z)
        }
        let cameraTransform = frame.camera.transform
        let cameraPosition = cameraTransform.columns.3
        return SIMD3<Float>(cameraPosition.x, cameraPosition.y, cameraPosition.z) + horizontalForwardVector(cameraTransform) * 0.35
    }

    private func startArrowDesiredHeading(frame: ARFrame) -> Float {
        let anchorYaw = Float(doubleValue(bridge?.startAnchorPayload()?["yawRadians"]) ?? 0)
        if initialWorldMap != nil {
            return anchorYaw
        }
        return arHeadingYaw(frame: frame) + anchorYaw
    }

    private func sceneKitYaw(forHeadingYaw headingYaw: Float) -> Float {
        -headingYaw
    }

    private func workingHeightMeters(startAnchor: [String: Any]) -> Float {
        let planZ = Float(doubleValue(startAnchor["planZ"]) ?? 0)
        return planZ > 0.2 ? planZ : 1.4
    }

    private func cameraPosition(_ frame: ARFrame) -> SIMD3<Float> {
        let position = frame.camera.transform.columns.3
        return SIMD3<Float>(position.x, position.y, position.z)
    }

    private func horizontalDistance(from first: SIMD3<Float>, to second: SIMD3<Float>) -> Float {
        simd_length(SIMD2<Float>(first.x - second.x, first.z - second.z))
    }

    private func desiredCameraHeadingYaw(for arrowNode: SCNNode) -> Float {
        if let arrowDesiredHeadingYaw {
            return arrowDesiredHeadingYaw
        }
        return -arrowNode.eulerAngles.y
    }

    private func normalizedAngle(_ angle: Float) -> Float {
        atan2(sin(angle), cos(angle))
    }

    private func placeRoomPlanOverlay(forConfirmedFrame frame: ARFrame) {
        if initialWorldMap != nil {
            placeWorldMapRoomPlanOverlayIfNeeded(frame: frame)
            return
        }
        guard roomPlanNode == nil,
              let plan = bridge?.floorPlanPlanPayload(),
              let startAnchor = bridge?.startAnchorPayload() else { return }
        let walls = plan["walls"] as? [[String: Any]] ?? []
        guard !walls.isEmpty else { return }

        let startPlanX = Float(doubleValue(startAnchor["planX"]) ?? 0)
        let startPlanY = Float(doubleValue(startAnchor["planY"]) ?? 0)
        let axes = planWorldAxes(frame: frame, startAnchor: startAnchor)
        let base = cameraPosition(frame)
        let overlay = SCNNode()
        overlay.name = "roomPlanOverlay"

        for wall in walls {
            guard let line = roomPlanWallLineNode(wall: wall, startPlanX: startPlanX, startPlanY: startPlanY, base: base, xAxis: axes.xAxis, yAxis: axes.yAxis) else {
                continue
            }
            overlay.addChildNode(line)
        }

        sceneView.scene.rootNode.addChildNode(overlay)
        roomPlanNode = overlay
    }

    private func placeWorldMapRoomPlanOverlayIfNeeded(frame: ARFrame) {
        guard initialWorldMap != nil,
              worldMapRelocalized,
              roomPlanNode == nil,
              let plan = bridge?.floorPlanPlanPayload() else { return }
        let walls = plan["walls"] as? [[String: Any]] ?? []
        guard !walls.isEmpty else { return }

        let overlay = SCNNode()
        overlay.name = "roomPlanOverlay"
        let y = cameraPosition(frame).y - 0.32
        for wall in walls {
            guard let line = worldMapRoomPlanWallLineNode(wall: wall, y: y) else { continue }
            overlay.addChildNode(line)
        }

        sceneView.scene.rootNode.addChildNode(overlay)
        roomPlanNode = overlay
    }

    private func worldMapRoomPlanWallLineNode(wall: [String: Any], y: Float) -> SCNNode? {
        guard let x1 = doubleValue(wall["x1"]),
              let y1 = doubleValue(wall["y1"]),
              let x2 = doubleValue(wall["x2"]),
              let y2 = doubleValue(wall["y2"]) else { return nil }
        let start = SIMD3<Float>(Float(x1), y, Float(y1))
        let end = SIMD3<Float>(Float(x2), y, Float(y2))
        return lineNode(from: start, to: end, radius: 0.012, color: UIColor.systemCyan.withAlphaComponent(0.82))
    }

    private func planWorldAxes(frame: ARFrame, startAnchor: [String: Any]) -> (xAxis: SIMD3<Float>, yAxis: SIMD3<Float>) {
        let planYaw = Float(doubleValue(startAnchor["yawRadians"]) ?? 0)
        let rotation = planYaw - arHeadingYaw(frame: frame)
        let cosine = cos(rotation)
        let sine = sin(rotation)
        let xAxis = simd_normalize(SIMD3<Float>(cosine, 0, -sine))
        let yAxis = simd_normalize(SIMD3<Float>(sine, 0, cosine))
        return (xAxis, yAxis)
    }

    private func roomPlanWallLineNode(wall: [String: Any], startPlanX: Float, startPlanY: Float, base: SIMD3<Float>, xAxis: SIMD3<Float>, yAxis: SIMD3<Float>) -> SCNNode? {
        guard let x1 = doubleValue(wall["x1"]),
              let y1 = doubleValue(wall["y1"]),
              let x2 = doubleValue(wall["x2"]),
              let y2 = doubleValue(wall["y2"]) else { return nil }
        let start = worldPosition(planX: Float(x1), planY: Float(y1), startPlanX: startPlanX, startPlanY: startPlanY, base: base, xAxis: xAxis, yAxis: yAxis)
        let end = worldPosition(planX: Float(x2), planY: Float(y2), startPlanX: startPlanX, startPlanY: startPlanY, base: base, xAxis: xAxis, yAxis: yAxis)
        return lineNode(from: start, to: end, radius: 0.012, color: UIColor.systemCyan.withAlphaComponent(0.82))
    }

    private func worldPosition(planX: Float, planY: Float, startPlanX: Float, startPlanY: Float, base: SIMD3<Float>, xAxis: SIMD3<Float>, yAxis: SIMD3<Float>) -> SIMD3<Float> {
        let deltaX = planX - startPlanX
        let deltaY = planY - startPlanY
        var position = base + xAxis * deltaX + yAxis * deltaY
        position.y = base.y - 0.32
        return position
    }

    private func lineNode(from start: SIMD3<Float>, to end: SIMD3<Float>, radius: CGFloat, color: UIColor) -> SCNNode? {
        let vector = end - start
        let length = simd_length(vector)
        guard length > 0.01 else { return nil }

        let geometry = SCNCylinder(radius: radius, height: CGFloat(length))
        geometry.firstMaterial?.diffuse.contents = color
        geometry.firstMaterial?.emission.contents = color.withAlphaComponent(0.2)
        geometry.firstMaterial?.isDoubleSided = true

        let node = SCNNode(geometry: geometry)
        node.name = "roomPlanWall"
        node.simdPosition = (start + end) / 2
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(vector))
        return node
    }

    private func wifiStatsText(_ stats: [String: Any]) -> String {
        if boolValue(stats["apChanged"]) == true {
            return "AP Wechsel"
        }
        if boolValue(stats["wifiChanged"]) == true {
            return "WLAN Wechsel"
        }
        let bssid = stringValue(stats["bssid"])
        if !bssid.isEmpty {
            return "AP \(shortBSSID(bssid))"
        }
        let ssid = stringValue(stats["ssid"])
        if !ssid.isEmpty {
            return ssid
        }
        let apChanges = intValue(stats["apChanges"]) ?? 0
        let wifiChanges = intValue(stats["wifiChanges"]) ?? 0
        if apChanges > 0 || wifiChanges > 0 {
            return "W \(wifiChanges) / AP \(apChanges)"
        }
        return "-"
    }

    private func shortBSSID(_ value: String) -> String {
        let parts = value.split(separator: ":")
        if parts.count >= 2 {
            return parts.suffix(2).joined(separator: ":")
        }
        return String(value.suffix(5))
    }

    private func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func horizontalForwardVector(_ transform: simd_float4x4) -> SIMD3<Float> {
        let rawForward = -SIMD3<Float>(transform.columns.2.x, 0, transform.columns.2.z)
        if simd_length(rawForward) > 0.001 {
            return simd_normalize(rawForward)
        }
        return SIMD3<Float>(0, 0, -1)
    }

    private func arHeadingYaw(frame: ARFrame) -> Float {
        let forward = horizontalForwardVector(frame.camera.transform)
        return atan2(forward.z, forward.x)
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
