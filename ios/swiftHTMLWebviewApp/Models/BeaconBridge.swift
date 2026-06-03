//
//  BeaconBridge.swift
//  swiftHTMLWebviewApp
//
//  CoreLocation iBeacon bridge for continuous web events.
//

import CoreLocation
import Foundation

@MainActor
final class BeaconBridge: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var beaconConstraint: CLBeaconIdentityConstraint?
    private var onEvent: (([String: Any]) -> Void)?
    private var isRunning = false

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func start(request: [String: Any], onEvent: @escaping ([String: Any]) -> Void) -> [String: Any] {
        self.onEvent = onEvent

        let requestedUUID = (request["uuid"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let uuid = requestedUUID.flatMap(UUID.init(uuidString:)) ?? AppSettings.shared.beaconUUID
        let constraint = CLBeaconIdentityConstraint(uuid: uuid)
        beaconConstraint = constraint

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            return response(
                request: request,
                action: "beaconsStart",
                success: false,
                uuid: uuid,
                error: "Location permission is required for iBeacon ranging."
            )
        default:
            break
        }

        locationManager.startRangingBeacons(satisfying: constraint)
        isRunning = true
        return response(request: request, action: "beaconsStart", success: true, uuid: uuid, error: nil)
    }

    func stop(request: [String: Any]) -> [String: Any] {
        stopRanging()
        var result = baseResponse(request: request, action: "beaconsStop")
        result["success"] = true
        return result
    }

    private func stopRanging() {
        if let beaconConstraint {
            locationManager.stopRangingBeacons(satisfying: beaconConstraint)
        }
        beaconConstraint = nil
        isRunning = false
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard isRunning, let beaconConstraint else { return }

            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.startRangingBeacons(satisfying: beaconConstraint)
            case .restricted, .denied:
                onEvent?([
                    "action": "beacons",
                    "success": false,
                    "error": "Location permission is required for iBeacon ranging."
                ])
                stopRanging()
            default:
                break
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didRange beacons: [CLBeacon],
        satisfying beaconConstraint: CLBeaconIdentityConstraint
    ) {
        let eventBeacons = beacons.map { beacon -> [String: Any] in
            [
                "proximityUUID": beacon.uuid.uuidString,
                "major": beacon.major.intValue,
                "minor": beacon.minor.intValue,
                "proximity": Self.proximityName(beacon.proximity),
                "accuracy": beacon.accuracy,
                "rssi": beacon.rssi
            ]
        }

        Task { @MainActor in
            onEvent?([
                "action": "beacons",
                "success": true,
                "uuid": beaconConstraint.uuid.uuidString,
                "count": eventBeacons.count,
                "beacons": eventBeacons,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ])
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            onEvent?([
                "action": "beacons",
                "success": false,
                "error": error.localizedDescription
            ])
        }
    }

    private func response(
        request: [String: Any],
        action: String,
        success: Bool,
        uuid: UUID,
        error: String?
    ) -> [String: Any] {
        var result = baseResponse(request: request, action: action)
        result["success"] = success
        result["uuid"] = uuid.uuidString
        result["provider"] = "ios_corelocation"
        if let error {
            result["error"] = error
        }
        return result
    }

    private func baseResponse(request: [String: Any], action: String) -> [String: Any] {
        var result: [String: Any] = [
            "platform": "ios",
            "action": action
        ]
        if let requestId = request["requestId"] {
            result["requestId"] = requestId
        }
        return result
    }

    private nonisolated static func proximityName(_ proximity: CLProximity) -> String {
        switch proximity {
        case .immediate: return "immediate"
        case .near: return "near"
        case .far: return "far"
        case .unknown: return "unknown"
        @unknown default: return "unknown"
        }
    }
}
