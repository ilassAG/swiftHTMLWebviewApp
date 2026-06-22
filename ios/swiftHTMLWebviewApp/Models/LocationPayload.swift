//
//  LocationPayload.swift
//  swiftHTMLWebviewApp
//
//  Pure response and location payload helpers for CoreLocation bridge actions.
//

import Foundation

enum LocationPayload {
    struct LocationObject {
        let latitude: Double
        let longitude: Double
        let accuracyMeters: Double?
        let altitudeMeters: Double?
        let speedMetersPerSecond: Double?
        let bearingDegrees: Double?
        let provider: String
        let timestampMs: Int
    }

    static func response(request: [String: Any], action: String, location: LocationObject) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: action)
        response["success"] = true
        response["location"] = locationPayload(location)
        return response
    }

    static func startResponse(
        request: [String: Any],
        authorized: Bool,
        minDistanceMeters: Double
    ) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "geoLocationStart")
        response["success"] = authorized
        if !authorized {
            response["pendingPermission"] = true
        }
        response["minDistanceMeters"] = minDistanceMeters
        return response
    }

    static func stopResponse(request: [String: Any]) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "geoLocationStop")
        response["success"] = true
        return response
    }

    static func errorResponse(request: [String: Any], action: String, error: String) -> [String: Any] {
        BridgeResponse.error(request: request, action: action, message: error)
    }

    static func minDistanceMeters(from request: [String: Any], fallback: Double) -> Double {
        doubleValue(request["minDistanceMeters"]) ?? fallback
    }

    static func locationPayload(_ location: LocationObject) -> [String: Any] {
        [
            "latitude": location.latitude,
            "longitude": location.longitude,
            "accuracyMeters": location.accuracyMeters ?? NSNull(),
            "altitudeMeters": location.altitudeMeters ?? NSNull(),
            "speedMetersPerSecond": location.speedMetersPerSecond ?? NSNull(),
            "bearingDegrees": location.bearingDegrees ?? NSNull(),
            "provider": location.provider,
            "timestampMs": location.timestampMs
        ]
    }
}
