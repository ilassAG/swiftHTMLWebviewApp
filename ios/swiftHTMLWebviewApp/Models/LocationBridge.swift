//
//  LocationBridge.swift
//  swiftHTMLWebviewApp
//
//  CoreLocation bridge for one-shot and continuous location events.
//

import CoreLocation
import Foundation

@MainActor
final class LocationBridge: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var pendingRequest: [String: Any]?
    private var pendingAction: String?
    private var eventHandler: (([String: Any]) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    func get(request: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        pendingRequest = request
        pendingAction = "geoLocationGet"
        eventHandler = completion
        ensureAuthorization()
        if authorizationAllowsLocation {
            manager.requestLocation()
        }
    }

    func start(request: [String: Any], eventHandler: @escaping ([String: Any]) -> Void) -> [String: Any] {
        pendingRequest = request
        pendingAction = "geoLocationStart"
        self.eventHandler = eventHandler
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = doubleValue(request["minDistanceMeters"]) ?? kCLDistanceFilterNone
        ensureAuthorization()
        if authorizationAllowsLocation {
            manager.startUpdatingLocation()
        }
        var response = baseResponse(request: request, action: "geoLocationStart")
        response["success"] = authorizationAllowsLocation
        if !authorizationAllowsLocation {
            response["pendingPermission"] = true
        }
        response["minDistanceMeters"] = manager.distanceFilter
        return response
    }

    func stop(request: [String: Any]) -> [String: Any] {
        manager.stopUpdatingLocation()
        var response = baseResponse(request: request, action: "geoLocationStop")
        response["success"] = true
        return response
    }

    func shutdown() {
        manager.stopUpdatingLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.authorizationAllowsLocation else {
                if let request = self.pendingRequest, let action = self.pendingAction {
                    self.eventHandler?(self.errorResponse(request: request, action: action, error: "Location permission was denied."))
                }
                return
            }
            if self.pendingAction == "geoLocationGet" {
                self.manager.requestLocation()
            } else if self.pendingAction == "geoLocationStart" {
                self.manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }
            let action = self.pendingAction == "geoLocationGet" ? "geoLocationGet" : "geoLocation"
            let request = self.pendingRequest ?? [:]
            var response = self.baseResponse(request: request, action: action)
            response["success"] = true
            response["location"] = self.locationPayload(location)
            self.eventHandler?(response)
            if self.pendingAction == "geoLocationGet" {
                self.pendingAction = nil
                self.pendingRequest = nil
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            let request = self.pendingRequest ?? [:]
            let action = self.pendingAction ?? "geoLocationGet"
            self.eventHandler?(self.errorResponse(request: request, action: action, error: error.localizedDescription))
        }
    }

    private var authorizationAllowsLocation: Bool {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    private func ensureAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    private func locationPayload(_ location: CLLocation) -> [String: Any] {
        [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "accuracyMeters": location.horizontalAccuracy,
            "altitudeMeters": location.verticalAccuracy >= 0 ? location.altitude : NSNull(),
            "speedMetersPerSecond": location.speed >= 0 ? location.speed : NSNull(),
            "bearingDegrees": location.course >= 0 ? location.course : NSNull(),
            "timestampMs": Int(location.timestamp.timeIntervalSince1970 * 1000)
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
        response["error"] = error
        return response
    }
}
