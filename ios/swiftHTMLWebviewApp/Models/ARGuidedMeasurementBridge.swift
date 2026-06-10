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

    func confirmStart(frame: ARFrame) {
        guard !confirmed else { return }
        confirmed = true
        var response = positionResponse(frame: frame, action: "arGuidedStartAnchorConfirmed")
        response["startAnchor"] = startAnchorPayload()
        response["anchor"] = startAnchorPayload()
        response["anchorId"] = stringValue(startAnchorPayload()?["id"])
        response["startAnchorId"] = stringValue(startAnchorPayload()?["id"])
        eventHandler?(response)
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
        ZStack(alignment: .top) {
            ARGuidedMeasurementRepresentable(bridge: bridge)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button("Schliessen") {
                        _ = bridge.stop(request: ["action": "arGuidedMeasurementStop"])
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)

                    Spacer()

                    Text("Startpfeil antippen")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.58), in: Capsule())

                    Spacer()

                    Button("Messpunkt") {
                        if let frame = bridge.controller?.currentFrame {
                            bridge.captureAnchor(frame: frame)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)

                Text("Stell dich auf die Admin-Position, halte das iPhone in Pfeilrichtung und tippe den Pfeil.")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.86))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 18)
            }
        }
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
    private weak var bridge: ARGuidedMeasurementBridge?
    private var arrowNode: SCNNode?
    private var arrowPlacedInWorld = false
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
        sceneView.addGestureRecognizer(tap)
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
        guard tappedArrow || hits.isEmpty else { return }
        if let frame = sceneView.session.currentFrame {
            bridge?.confirmStart(frame: frame)
        }
    }

    private func placeStartArrowInWorldIfNeeded(frame: ARFrame) {
        guard !arrowPlacedInWorld, let arrowNode, arrowNode.parent != nil else { return }
        arrowNode.simdPosition = startArrowWorldPosition(frame: frame)
        arrowNode.eulerAngles = SCNVector3(0, startArrowWorldYaw(frame: frame), 0)
        arrowNode.isHidden = false
        arrowPlacedInWorld = true
    }

    // The start arrow must be a fixed AR world marker. It is placed once near
    // the detected floor, then remains stationary while the user walks/turns.
    private func startArrowWorldPosition(frame: ARFrame) -> SIMD3<Float> {
        let center = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
        if let query = sceneView.raycastQuery(from: center, allowing: .estimatedPlane, alignment: .horizontal),
           let result = sceneView.session.raycast(query).first {
            let position = result.worldTransform.columns.3
            return SIMD3<Float>(position.x, position.y + 0.02, position.z)
        }

        let cameraTransform = frame.camera.transform
        let cameraPosition = cameraTransform.columns.3
        let forward = simd_normalize(-SIMD3<Float>(cameraTransform.columns.2.x, cameraTransform.columns.2.y, cameraTransform.columns.2.z))
        return SIMD3<Float>(cameraPosition.x, cameraPosition.y - 1.15, cameraPosition.z) + forward * 1.1
    }

    private func startArrowWorldYaw(frame: ARFrame) -> Float {
        let anchorYaw = Float(doubleValue(bridge?.startAnchorPayload()?["yawRadians"]) ?? 0)
        return frame.camera.eulerAngles.y + Float.pi / 2 + anchorYaw
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
