//
//  AROverlayBridge.swift
//  swiftHTMLWebviewApp
//
//  Generic ARKit overlay bridge for product-defined 3D items and paths.
//

import ARKit
import AVFoundation
import Foundation
import SceneKit
import SwiftUI
import UIKit
import simd

@MainActor
final class AROverlayBridge: ObservableObject {
    @Published var viewVisible = false

    fileprivate weak var controller: AROverlayViewController?
    fileprivate var scene = AROverlayScene.empty
    private var eventHandler: (([String: Any]) -> Void)?
    private var latestRequest: [String: Any] = [:]
    private var streamToken = UUID()

    nonisolated static func isSupported() -> Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    func open(request: [String: Any], eventHandler: @escaping ([String: Any]) -> Void) -> [String: Any] {
        stopInternal(hideView: false)
        latestRequest = request
        scene = AROverlayScene(request: request)
        self.eventHandler = eventHandler
        let token = UUID()
        streamToken = token

        guard Self.isSupported() else {
            return errorResponse(request: request, action: AROverlayPayload.requestAction(request, defaultAction: "arOverlayOpen"), error: "ARKit world tracking is not supported on this device.")
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            viewVisible = true
            return readyResponse(request: request, action: AROverlayPayload.requestAction(request, defaultAction: "arOverlayOpen"))
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self, self.streamToken == token else { return }
                    if granted {
                        self.viewVisible = true
                        self.eventHandler?(self.readyResponse(request: request, action: "arOverlayReady"))
                    } else {
                        self.eventHandler?(self.errorResponse(request: request, action: "arOverlayError", error: "Camera permission was denied."))
                    }
                }
            }
            return AROverlayPayload.pendingPermissionResponse(
                request: request,
                action: AROverlayPayload.requestAction(request, defaultAction: "arOverlayOpen"),
                scene: scene,
                worldMapAvailable: requestedWorldMapAvailable()
            )
        case .denied, .restricted:
            return errorResponse(request: request, action: AROverlayPayload.requestAction(request, defaultAction: "arOverlayOpen"), error: "Camera permission is required for ARKit overlays.")
        @unknown default:
            return errorResponse(request: request, action: AROverlayPayload.requestAction(request, defaultAction: "arOverlayOpen"), error: "Unknown camera authorization state.")
        }
    }

    func close(request: [String: Any]) -> [String: Any] {
        stopInternal(hideView: true)
        return AROverlayPayload.closeResponse(
            request: request,
            action: AROverlayPayload.requestAction(request, defaultAction: "arOverlayClose")
        )
    }

    func shutdown() {
        stopInternal(hideView: true)
    }

    func bind(controller: AROverlayViewController) {
        self.controller = controller
    }

    func closeFromController() {
        eventHandler?(AROverlayPayload.closeResponse(request: latestRequest, action: "arOverlayClosed"))
        stopInternal(hideView: true)
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

    func emitReadyFromController() {
        eventHandler?(readyResponse(request: latestRequest, action: "arOverlayReady"))
    }

    func emitError(_ message: String) {
        eventHandler?(errorResponse(request: latestRequest, action: "arOverlayError", error: message))
    }

    func emitRelocalizationState(action: String, state: String, message: String, frame: ARFrame? = nil) {
        let tracking: (state: String, reason: String)?
        if let frame {
            tracking = trackingStatePayload(frame.camera.trackingState)
        } else {
            tracking = nil
        }
        eventHandler?(AROverlayPayload.relocalizationEvent(
            request: latestRequest,
            action: action,
            state: state,
            message: message,
            worldMapAvailable: requestedWorldMapAvailable(),
            trackingState: tracking?.state,
            trackingReason: tracking?.reason,
            worldMappingStatus: frame.map { arOverlayWorldMappingStatusName($0.worldMappingStatus) }
        ))
    }

    fileprivate func emitItemSelected(_ item: AROverlayItem) {
        eventHandler?(AROverlayPayload.itemSelectedEvent(request: latestRequest, item: item))
    }

    private func readyResponse(request: [String: Any], action: String) -> [String: Any] {
        AROverlayPayload.readyResponse(
            request: request,
            action: action,
            scene: scene,
            worldMapAvailable: requestedWorldMapAvailable()
        )
    }

    private func stopInternal(hideView: Bool) {
        controller?.stopSession()
        controller = nil
        streamToken = UUID()
        if hideView {
            viewVisible = false
            eventHandler = nil
        }
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

    private func errorResponse(request: [String: Any], action: String, error: String) -> [String: Any] {
        AROverlayPayload.errorResponse(
            request: request,
            action: action,
            error: error,
            supported: Self.isSupported()
        )
    }
}

struct AROverlaySheet: View {
    @ObservedObject var bridge: AROverlayBridge
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AROverlayRepresentable(bridge: bridge)
            .ignoresSafeArea()
            .onChange(of: bridge.viewVisible) { visible in
                if !visible {
                    dismiss()
                }
            }
    }
}

private struct AROverlayRepresentable: UIViewControllerRepresentable {
    let bridge: AROverlayBridge

    func makeUIViewController(context: Context) -> AROverlayViewController {
        let controller = AROverlayViewController(bridge: bridge)
        bridge.bind(controller: controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: AROverlayViewController, context: Context) {
        uiViewController.renderOverlayIfReady()
    }
}

final class AROverlayViewController: UIViewController, ARSessionDelegate {
    private let sceneView = ARSCNView(frame: .zero)
    private let coachingOverlay = ARCoachingOverlayView(frame: .zero)
    private let overlayView = UIView(frame: .zero)
    private let statusLabel = UILabel(frame: .zero)
    private let detailLabel = UILabel(frame: .zero)
    private let closeButton = UIButton(type: .system)
    private weak var bridge: AROverlayBridge?
    private var initialWorldMap: ARWorldMap?
    private var requiresWorldMapRelocalization = false
    private var worldMapRelocalized = false
    private var renderedSceneId = UUID()
    private var overlayRoot: SCNNode?
    private var itemByNodeName: [String: AROverlayItem] = [:]
    private var runTask: Task<Void, Never>?
    private var lastRelocalizationStatusTime: TimeInterval = 0

    init(bridge: AROverlayBridge) {
        self.bridge = bridge
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSceneView()
        configureCoachingOverlay()
        configureOverlay()
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
        guard AROverlayBridge.isSupported() else {
            bridge?.emitError("ARKit world tracking is not supported on this device.")
            return
        }
        renderedSceneId = UUID()
        removeOverlay()
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

    func renderOverlayIfReady() {
        guard canUseWorldAnchors else { return }
        renderOverlayIfNeeded()
    }

    private func configureSceneView() {
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
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.52)
        overlayView.layer.cornerRadius = 18
        overlayView.layer.cornerCurve = .continuous

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = bridge?.scene.title ?? "AR Overlay"
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 18, weight: .bold)
        statusLabel.numberOfLines = 1

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.text = "Raum scannen, bis die gespeicherte AR-Umgebung erkannt ist."
        detailLabel.textColor = UIColor.white.withAlphaComponent(0.86)
        detailLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        detailLabel.numberOfLines = 3

        var configuration = UIButton.Configuration.filled()
        configuration.title = "Schliessen"
        configuration.baseBackgroundColor = .systemRed
        configuration.baseForegroundColor = .black
        configuration.cornerStyle = .medium
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 14, weight: .bold)
            return outgoing
        }
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.configuration = configuration
        closeButton.addTarget(self, action: #selector(closeButtonPressed), for: .touchUpInside)

        let textStack = UIStackView(arrangedSubviews: [statusLabel, detailLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 4

        overlayView.addSubview(textStack)
        overlayView.addSubview(closeButton)
        view.addSubview(overlayView)
        view.bringSubviewToFront(overlayView)

        NSLayoutConstraint.activate([
            overlayView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            overlayView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            overlayView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),

            textStack.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor, constant: -14),
            textStack.topAnchor.constraint(equalTo: overlayView.topAnchor, constant: 12),

            closeButton.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor, constant: 10),
            closeButton.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor, constant: -10),
            closeButton.topAnchor.constraint(equalTo: textStack.bottomAnchor, constant: 10),
            closeButton.bottomAnchor.constraint(equalTo: overlayView.bottomAnchor, constant: -10),
            closeButton.heightAnchor.constraint(equalToConstant: 44)
        ])
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
                    action: "arOverlayRelocalizing",
                    state: "loading",
                    message: "AR-Raumkarte geladen. Raum langsam mit dem iPhone wiedererkennen."
                )
            } catch {
                let message = "AR-Raumkarte konnte nicht geladen werden: \(error.localizedDescription)"
                bridge?.emitError(message)
                showRelocalizingStatus(message)
                return
            }
        }

        guard !Task.isCancelled else { return }
        let configuration = ARWorldTrackingConfiguration()
        let coordinateSystem = bridge?.scene.coordinateSystem.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        configuration.worldAlignment = coordinateSystem == "wgs84" || coordinateSystem == "geo-wgs84" || coordinateSystem == "geographic-wgs84"
            ? .gravityAndHeading
            : .gravity
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.initialWorldMap = initialWorldMap
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        if requiresWorldMapRelocalization {
            showRelocalizingStatus("Raum langsam scannen, bis ARKit die gespeicherte Position erkennt.")
            bridge?.emitRelocalizationState(
                action: "arOverlayRelocalizing",
                state: "relocalizing",
                message: "Raum langsam scannen, bis das gespeicherte AR-Overlay erscheint."
            )
        } else {
            showOverlayStatus()
        }
        bridge?.emitReadyFromController()
    }

    private func loadInitialWorldMap() async throws -> ARWorldMap {
        if let base64 = bridge?.requestedWorldMapBase64(), !base64.isEmpty {
            let encoded = base64.contains(",") ? String(base64.split(separator: ",", maxSplits: 1).last ?? "") : base64
            guard let data = Data(base64Encoded: encoded) else {
                throw AROverlayError.worldMapDecodeFailed
            }
            return try decodeWorldMap(data)
        }
        if let url = bridge?.requestedWorldMapURL() {
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(from: url)
            } catch {
                throw AROverlayError.worldMapDownloadFailed(error.localizedDescription)
            }
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                throw AROverlayError.worldMapHTTPStatus(httpResponse.statusCode)
            }
            guard !data.isEmpty else {
                throw AROverlayError.worldMapEmpty
            }
            return try decodeWorldMap(data)
        }
        throw AROverlayError.worldMapMissing
    }

    private func decodeWorldMap(_ data: Data) throws -> ARWorldMap {
        do {
            if let worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) {
                return worldMap
            }
        } catch {
            if let worldMap = try? decodeWorldMapWithoutSecureCoding(data) {
                return worldMap
            }
            throw error
        }
        throw AROverlayError.worldMapDecodeFailed
    }

    private func decodeWorldMapWithoutSecureCoding(_ data: Data) throws -> ARWorldMap {
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        defer {
            unarchiver.finishDecoding()
        }
        guard let worldMap = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? ARWorldMap else {
            throw AROverlayError.worldMapDecodeFailed
        }
        return worldMap
    }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor in
            self.updateRelocalizationState(frame: frame)
            if self.canUseWorldAnchors {
                self.renderOverlayIfNeeded()
            }
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
        for hit in hits {
            var node: SCNNode? = hit.node
            while let current = node {
                if let name = current.name, let item = itemByNodeName[name] {
                    select(item: item)
                    return
                }
                node = current.parent
            }
        }
    }

    @objc private func closeButtonPressed() {
        bridge?.closeFromController()
    }

    private var canUseWorldAnchors: Bool {
        !requiresWorldMapRelocalization || worldMapRelocalized
    }

    private func updateRelocalizationState(frame: ARFrame) {
        guard requiresWorldMapRelocalization, !worldMapRelocalized else { return }
        switch frame.camera.trackingState {
        case .normal:
            worldMapRelocalized = true
            showOverlayStatus()
            bridge?.emitRelocalizationState(
                action: "arOverlayRelocalized",
                state: "relocalized",
                message: "ARKit hat die gespeicherte Raumkarte wiedererkannt.",
                frame: frame
            )
        case .limited, .notAvailable:
            guard frame.timestamp - lastRelocalizationStatusTime >= 0.4 else { return }
            lastRelocalizationStatusTime = frame.timestamp
            showRelocalizingStatus("Raum langsam links/rechts scannen. Das Overlay erscheint nach Wiedererkennung.")
            bridge?.emitRelocalizationState(
                action: "arOverlayRelocalizing",
                state: "relocalizing",
                message: "ARKit sucht die gespeicherte Raumkarte.",
                frame: frame
            )
        }
    }

    private func renderOverlayIfNeeded() {
        guard overlayRoot == nil, let scene = bridge?.scene else { return }
        let root = SCNNode()
        root.name = "arOverlayRoot"
        itemByNodeName = [:]

        for line in scene.lines {
            addLine(line, to: root)
        }

        for item in scene.items {
            let node = itemNode(for: item)
            root.addChildNode(node)
            if let headingYaw = item.headingYaw {
                let direction = SIMD3<Float>(cos(headingYaw), 0, sin(headingYaw))
                if let heading = lineNode(from: item.position, to: item.position + direction * 0.28, radius: max(0.01, CGFloat(item.radius * 0.18)), color: item.color.withAlphaComponent(0.88), name: "arOverlayItem:\(item.id):heading") {
                    root.addChildNode(heading)
                    itemByNodeName[heading.name ?? ""] = item
                }
            }
        }

        sceneView.scene.rootNode.addChildNode(root)
        overlayRoot = root
        showOverlayStatus()
        renderedSceneId = UUID()
    }

    private func removeOverlay() {
        overlayRoot?.removeFromParentNode()
        overlayRoot = nil
        itemByNodeName = [:]
    }

    private func addLine(_ line: AROverlayLine, to root: SCNNode) {
        guard line.points.count >= 2 else { return }
        for index in 1..<line.points.count {
            guard let node = lineNode(from: line.points[index - 1], to: line.points[index], radius: CGFloat(line.radius), color: line.color, name: "arOverlayLine:\(line.id):\(index)") else {
                continue
            }
            root.addChildNode(node)
        }
    }

    private func itemNode(for item: AROverlayItem) -> SCNNode {
        let geometry: SCNGeometry
        switch item.kind {
        case "box", "cube":
            geometry = SCNBox(width: CGFloat(item.radius * 2.0), height: CGFloat(item.radius * 2.0), length: CGFloat(item.radius * 2.0), chamferRadius: CGFloat(item.radius * 0.18))
        case "speed", "diamond":
            geometry = SCNBox(width: CGFloat(item.radius * 2.2), height: CGFloat(item.radius * 1.2), length: CGFloat(item.radius * 2.2), chamferRadius: CGFloat(item.radius * 0.12))
        default:
            geometry = SCNSphere(radius: CGFloat(item.radius))
        }
        geometry.firstMaterial?.diffuse.contents = item.color
        geometry.firstMaterial?.emission.contents = item.color.withAlphaComponent(0.24)
        geometry.firstMaterial?.isDoubleSided = true

        let node = SCNNode(geometry: geometry)
        node.name = "arOverlayItem:\(item.id)"
        node.simdPosition = item.position
        if item.isNearbyMarker, let frame = sceneView.session.currentFrame {
            let cameraTransform = frame.camera.transform
            let cameraPosition = SIMD3<Float>(
                cameraTransform.columns.3.x,
                cameraTransform.columns.3.y,
                cameraTransform.columns.3.z
            )
            let cameraForward = simd_normalize(SIMD3<Float>(
                -cameraTransform.columns.2.x,
                -cameraTransform.columns.2.y,
                -cameraTransform.columns.2.z
            ))
            node.simdPosition = cameraPosition + cameraForward * 2.0
        }
        if item.kind == "speed" || item.kind == "diamond" {
            node.eulerAngles = SCNVector3(Float.pi / 6, Float.pi / 4, 0)
        }
        if let distanceMeters = item.distanceMeters {
            node.addChildNode(itemLabelNode(for: item, distanceMeters: distanceMeters))
        }
        itemByNodeName[node.name ?? ""] = item
        return node
    }

    private func itemLabelNode(for item: AROverlayItem, distanceMeters: Double) -> SCNNode {
        let distanceText = formatDistance(distanceMeters)
        let directionSuffix = item.isNearbyMarker ? " · In der Nähe" : (item.isDirectionMarker ? " · Richtung" : "")
        let text = SCNText(string: "\(item.title)\n\(distanceText)\(directionSuffix)", extrusionDepth: 0.35)
        text.alignmentMode = CATextLayerAlignmentMode.center.rawValue
        text.containerFrame = CGRect(x: 0, y: 0, width: 220, height: 62)
        text.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        text.flatness = 0.15
        text.firstMaterial?.diffuse.contents = UIColor.white
        text.firstMaterial?.emission.contents = UIColor.white.withAlphaComponent(0.72)
        text.firstMaterial?.isDoubleSided = true

        let node = SCNNode(geometry: text)
        let displayDistance = hypot(Double(item.position.x), Double(item.position.z))
        let scale = Float(max(0.006, min(0.018, displayDistance * 0.0015)))
        node.scale = SCNVector3(scale, scale, scale)
        node.pivot = SCNMatrix4MakeTranslation(110, 31, 0)
        node.position = SCNVector3(0, item.radius * 2.0 + 0.12, 0)
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        node.constraints = [billboard]
        return node
    }

    private func formatDistance(_ distanceMeters: Double) -> String {
        if distanceMeters < 1_000 {
            return "\(Int(distanceMeters.rounded())) m"
        }
        let kilometers = distanceMeters / 1_000.0
        if kilometers < 10 {
            return String(format: "%.1f km", kilometers)
        }
        return "\(Int(kilometers.rounded())) km"
    }

    private func lineNode(from start: SIMD3<Float>, to end: SIMD3<Float>, radius: CGFloat, color: UIColor, name: String) -> SCNNode? {
        let vector = end - start
        let length = simd_length(vector)
        guard length > 0.01 else { return nil }

        let geometry = SCNCylinder(radius: radius, height: CGFloat(length))
        geometry.firstMaterial?.diffuse.contents = color
        geometry.firstMaterial?.emission.contents = color.withAlphaComponent(0.18)
        geometry.firstMaterial?.isDoubleSided = true

        let node = SCNNode(geometry: geometry)
        node.name = name
        node.simdPosition = (start + end) / 2
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(vector))
        return node
    }

    private func select(item: AROverlayItem) {
        statusLabel.text = item.title.isEmpty ? "AR Overlay" : item.title
        detailLabel.text = item.detail.isEmpty ? "\(item.kind) \(item.id)" : item.detail
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        bridge?.emitItemSelected(item)
    }

    private func showRelocalizingStatus(_ detail: String) {
        statusLabel.text = "Raum wiedererkennen"
        detailLabel.text = detail
    }

    private func showOverlayStatus() {
        guard let scene = bridge?.scene else { return }
        statusLabel.text = scene.title
        if scene.items.isEmpty && scene.lines.isEmpty {
            detailLabel.text = "Keine AR-Overlay-Elemente im Request."
        } else {
            detailLabel.text = "\(scene.items.count) Elemente, \(scene.lines.count) Linien. Element antippen, um Details zu sehen."
        }
    }
}

private enum AROverlayError: LocalizedError {
    case worldMapMissing
    case worldMapDecodeFailed
    case worldMapDownloadFailed(String)
    case worldMapHTTPStatus(Int)
    case worldMapEmpty

    var errorDescription: String? {
        switch self {
        case .worldMapMissing:
            return "Keine ARWorldMap im Request."
        case .worldMapDecodeFailed:
            return "ARWorldMap konnte nicht dekodiert werden."
        case .worldMapDownloadFailed(let message):
            return "ARWorldMap Download fehlgeschlagen: \(message)"
        case .worldMapHTTPStatus(let status):
            return "ARWorldMap Download lieferte HTTP \(status)."
        case .worldMapEmpty:
            return "ARWorldMap Download war leer."
        }
    }
}

private func arOverlayWorldMappingStatusName(_ status: ARFrame.WorldMappingStatus) -> String {
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
