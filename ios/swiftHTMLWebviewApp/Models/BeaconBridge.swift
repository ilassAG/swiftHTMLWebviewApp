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

        let uuid = BeaconPayload.rangingUUID(from: request, defaultUUID: AppSettings.shared.beaconUUID)
        let constraint = CLBeaconIdentityConstraint(uuid: uuid)
        beaconConstraint = constraint

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            return BeaconPayload.rangingStartResponse(
                request: request,
                uuid: uuid,
                success: false,
                error: "Location permission is required for iBeacon ranging."
            )
        default:
            break
        }

        locationManager.startRangingBeacons(satisfying: constraint)
        isRunning = true
        return BeaconPayload.rangingStartResponse(request: request, uuid: uuid, success: true)
    }

    func stop(request: [String: Any]) -> [String: Any] {
        stopRanging()
        return BeaconPayload.rangingStopResponse(request: request)
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
                onEvent?(BeaconPayload.errorEvent(error: "Location permission is required for iBeacon ranging."))
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
            BeaconPayload.beaconObject(
                proximityUUID: beacon.uuid,
                major: beacon.major.intValue,
                minor: beacon.minor.intValue,
                proximity: Self.proximityName(beacon.proximity),
                accuracy: beacon.accuracy,
                rssi: beacon.rssi
            )
        }

        Task { @MainActor in
            onEvent?(BeaconPayload.rangingEvent(uuid: beaconConstraint.uuid, beacons: eventBeacons))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            onEvent?(BeaconPayload.errorEvent(error: error.localizedDescription))
        }
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
