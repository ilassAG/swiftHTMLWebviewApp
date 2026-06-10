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
        intervalSeconds = max(0.1, min(2.0, (doubleValue(request["intervalMs"]) ?? 500) / 1000.0))
        let token = UUID()
        streamToken = token

        guard Self.isSupported() else {
            return errorResponse(request: request, action: "arPositionStart", error: "ARKit world tracking is not supported on this device.")
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            runSession()
            return startedResponse(request: request)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self, self.streamToken == token else { return }
                    if granted {
                        self.runSession()
                        self.eventHandler?(self.startedResponse(request: request))
                    } else {
                        self.eventHandler?(self.errorResponse(request: request, action: "arPositionStart", error: "Camera permission was denied."))
                    }
                }
            }
            var response = baseResponse(request: request, action: "arPositionStart")
            response["success"] = false
            response["pendingPermission"] = true
            response["trackingSupported"] = true
            response["source"] = "arkit"
            response["intervalMs"] = Int(intervalSeconds * 1000)
            response["coordinateSystem"] = "arkit-gravity-local"
            return response
        case .denied, .restricted:
            return errorResponse(request: request, action: "arPositionStart", error: "Camera permission is required for ARKit tracking.")
        @unknown default:
            return errorResponse(request: request, action: "arPositionStart", error: "Unknown camera authorization state.")
        }
    }

    func stop(request: [String: Any]) -> [String: Any] {
        stopInternal()
        var response = baseResponse(request: request, action: "arPositionStop")
        response["success"] = true
        return response
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
            self.eventHandler?(self.errorResponse(request: request, action: "arPosition", error: error.localizedDescription))
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in
            var response = self.baseResponse(request: self.latestRequest, action: "arPosition")
            response["success"] = false
            response["source"] = "arkit"
            response["interrupted"] = true
            response["error"] = "AR session was interrupted."
            self.eventHandler?(response)
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

        var response = baseResponse(request: latestRequest, action: "arPosition")
        response["success"] = true
        response["source"] = "arkit"
        response["coordinateSystem"] = "arkit-gravity-local"
        response["timestampMs"] = Int(Date().timeIntervalSince1970 * 1000)
        response["arTimestampSeconds"] = frame.timestamp
        response["elapsedSeconds"] = Date().timeIntervalSince(startedAt)
        response["trackingSupported"] = true

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
        eventHandler?(response)
    }

    private func stopInternal() {
        running = false
        eventHandler = nil
        lastEmitTime = 0
        streamToken = UUID()
        session.pause()
    }

    private func startedResponse(request: [String: Any]) -> [String: Any] {
        var response = baseResponse(request: request, action: "arPositionStart")
        response["success"] = true
        response["source"] = "arkit"
        response["intervalMs"] = Int(intervalSeconds * 1000)
        response["coordinateSystem"] = "arkit-gravity-local"
        response["trackingSupported"] = true
        return response
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
        response["source"] = "arkit"
        response["error"] = error
        response["trackingSupported"] = Self.isSupported()
        return response
    }
}
