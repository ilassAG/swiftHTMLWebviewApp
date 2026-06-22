//
//  ARPositionBridge.swift
//  swiftHTMLWebviewApp
//
//  Generic ARKit local-position bridge for WebView apps.
//

import ARKit
import AVFoundation
import Foundation
import simd

@MainActor
final class ARPositionBridge: NSObject, ObservableObject, ARSessionDelegate {
    private let session = ARSession()
    private var eventHandler: (([String: Any]) -> Void)?
    private var latestRequest: [String: Any] = [:]
    private var intervalSeconds: TimeInterval = 0.5
    private var lastEmitTime: TimeInterval = 0
    private var startedAt = Date()
    private var streamToken = UUID()
    private var running = false

    override init() {
        super.init()
        session.delegate = self
    }

    nonisolated static func isSupported() -> Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    func start(request: [String: Any], eventHandler: @escaping ([String: Any]) -> Void) -> [String: Any] {
        stopInternal()
        latestRequest = request
        self.eventHandler = eventHandler
        let intervalMs = ARPositionPayload.intervalMs(from: request)
        intervalSeconds = Double(intervalMs) / 1000.0
        let token = UUID()
        streamToken = token

        guard Self.isSupported() else {
            return ARPositionPayload.errorResponse(
                request: request,
                action: "arPositionStart",
                error: "ARKit world tracking is not supported on this device.",
                trackingSupported: Self.isSupported()
            )
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            runSession()
            return ARPositionPayload.startResponse(
                request: request,
                intervalMs: intervalMs,
                trackingSupported: true
            )
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self, self.streamToken == token else { return }
                    if granted {
                        self.runSession()
                        self.eventHandler?(ARPositionPayload.startResponse(
                            request: request,
                            intervalMs: intervalMs,
                            trackingSupported: true
                        ))
                    } else {
                        self.eventHandler?(ARPositionPayload.errorResponse(
                            request: request,
                            action: "arPositionStart",
                            error: "Camera permission was denied.",
                            trackingSupported: true
                        ))
                    }
                }
            }
            return ARPositionPayload.startResponse(
                request: request,
                intervalMs: intervalMs,
                trackingSupported: true,
                pendingPermission: true
            )
        case .denied, .restricted:
            return ARPositionPayload.errorResponse(
                request: request,
                action: "arPositionStart",
                error: "Camera permission is required for ARKit tracking.",
                trackingSupported: true
            )
        @unknown default:
            return ARPositionPayload.errorResponse(
                request: request,
                action: "arPositionStart",
                error: "Unknown camera authorization state.",
                trackingSupported: true
            )
        }
    }

    func stop(request: [String: Any]) -> [String: Any] {
        stopInternal()
        return ARPositionPayload.stopResponse(request: request)
    }

    func shutdown() {
        stopInternal()
    }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor in
            self.emit(frame: frame)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            let request = self.latestRequest
            self.eventHandler?(ARPositionPayload.errorResponse(
                request: request,
                action: "arPosition",
                error: error.localizedDescription,
                trackingSupported: Self.isSupported()
            ))
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in
            self.eventHandler?(ARPositionPayload.interruptionEvent(request: self.latestRequest))
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor in
            guard self.running else { return }
            self.runSession()
        }
    }

    private func runSession() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        if boolValue(latestRequest["planeDetection"]) ?? false {
            configuration.planeDetection = [.horizontal, .vertical]
        }
        startedAt = Date()
        lastEmitTime = 0
        running = true
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    private func emit(frame: ARFrame) {
        guard running else { return }
        if lastEmitTime > 0, frame.timestamp - lastEmitTime < intervalSeconds {
            return
        }
        lastEmitTime = frame.timestamp

        let tracking = trackingStatePayload(frame.camera.trackingState)
        let transform = frame.camera.transform
        let position = transform.columns.3
        eventHandler?(ARPositionPayload.positionEvent(
            request: latestRequest,
            timestampMs: Int(Date().timeIntervalSince1970 * 1000),
            arTimestampSeconds: frame.timestamp,
            elapsedSeconds: Date().timeIntervalSince(startedAt),
            trackingState: tracking.state,
            trackingReason: tracking.reason,
            position: .init(x: Double(position.x), y: Double(position.y), z: Double(position.z)),
            orientation: .init(
                x: Double(frame.camera.eulerAngles.x),
                y: Double(frame.camera.eulerAngles.y),
                z: Double(frame.camera.eulerAngles.z)
            ),
            transform: transformPayload(transform)
        ))
    }

    private func stopInternal() {
        running = false
        eventHandler = nil
        lastEmitTime = 0
        streamToken = UUID()
        session.pause()
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

}
