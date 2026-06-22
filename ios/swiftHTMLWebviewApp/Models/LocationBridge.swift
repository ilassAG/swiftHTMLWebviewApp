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
        manager.distanceFilter = LocationPayload.minDistanceMeters(from: request, fallback: kCLDistanceFilterNone)
        ensureAuthorization()
        if authorizationAllowsLocation {
            manager.startUpdatingLocation()
        }
        return LocationPayload.startResponse(
            request: request,
            authorized: authorizationAllowsLocation,
            minDistanceMeters: manager.distanceFilter
        )
    }

    func stop(request: [String: Any]) -> [String: Any] {
        manager.stopUpdatingLocation()
        return LocationPayload.stopResponse(request: request)
    }

    func shutdown() {
        manager.stopUpdatingLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.authorizationAllowsLocation else {
                if let request = self.pendingRequest, let action = self.pendingAction {
                    self.eventHandler?(LocationPayload.errorResponse(request: request, action: action, error: "Location permission was denied."))
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
            self.eventHandler?(LocationPayload.response(
                request: request,
                action: action,
                location: self.locationObject(location)
            ))
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
            self.eventHandler?(LocationPayload.errorResponse(request: request, action: action, error: error.localizedDescription))
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

    private func locationObject(_ location: CLLocation) -> LocationPayload.LocationObject {
        LocationPayload.LocationObject(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracyMeters: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
            altitudeMeters: location.verticalAccuracy >= 0 ? location.altitude : nil,
            speedMetersPerSecond: location.speed >= 0 ? location.speed : nil,
            bearingDegrees: location.course >= 0 ? location.course : nil,
            provider: "corelocation",
            timestampMs: Int(location.timestamp.timeIntervalSince1970 * 1000)
        )
    }
}
