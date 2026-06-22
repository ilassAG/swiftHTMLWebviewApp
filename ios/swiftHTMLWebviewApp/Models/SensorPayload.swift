//
//  SensorPayload.swift
//  swiftHTMLWebviewApp
//
//  Pure response and event payload helpers for sensor bridge actions.
//

import Foundation

enum SensorPayload {
    struct SensorAvailability {
        let typeName: String
        let available: Bool
    }

    struct StreamRequest {
        let intervalMs: Int

        var intervalSeconds: TimeInterval {
            TimeInterval(intervalMs) / 1000.0
        }
    }

    struct MotionSample {
        let typeName: String
        let values: [Double]?
        let timestampSeconds: Double
        let attitude: [String: Double]?
        let gravity: [Double]?
        let userAcceleration: [Double]?

        init(
            typeName: String,
            values: [Double]? = nil,
            timestampSeconds: Double,
            attitude: [String: Double]? = nil,
            gravity: [Double]? = nil,
            userAcceleration: [Double]? = nil
        ) {
            self.typeName = typeName
            self.values = values
            self.timestampSeconds = timestampSeconds
            self.attitude = attitude
            self.gravity = gravity
            self.userAcceleration = userAcceleration
        }
    }

    static func capabilitiesResponse(
        request: [String: Any],
        sensors: [SensorAvailability],
        arOverlaySupported: Bool
    ) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "sensorCapabilitiesGet")
        response["success"] = true
        response["sensors"] = sensors.map { sensor in
            [
                "typeName": sensor.typeName,
                "available": sensor.available
            ]
        }
        response["capabilities"] = [
            "sensorCapabilitiesGet": true,
            "sensorStreamStart": true,
            "sensorStreamStop": true,
            "arOverlayOpen": arOverlaySupported,
            "arOverlayClose": true,
            "arOverlaySupported": arOverlaySupported,
            "arReplayOpen": arOverlaySupported,
            "arReplayClose": true
        ]
        return response
    }

    static func streamStartResponse(request: [String: Any], streamRequest: StreamRequest) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "sensorStreamStart")
        response["success"] = true
        response["intervalMs"] = streamRequest.intervalMs
        return response
    }

    static func stopResponse(request: [String: Any]) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "sensorStreamStop")
        response["success"] = true
        return response
    }

    static func errorResponse(request: [String: Any], action: String, error: String) -> [String: Any] {
        BridgeResponse.error(request: request, action: action, message: error)
    }

    static func sensorDataEvent(samples: [MotionSample]) -> [String: Any] {
        [
            "platform": "ios",
            "action": "sensorData",
            "success": true,
            "sensors": samples.map(samplePayload)
        ]
    }

    static func streamRequest(from request: [String: Any]) -> StreamRequest {
        let raw = doubleValue(request["intervalMs"]) ?? 500
        guard raw.isFinite else { return StreamRequest(intervalMs: 500) }
        return StreamRequest(intervalMs: max(100, Int(raw.rounded())))
    }

    private static func samplePayload(_ sample: MotionSample) -> [String: Any] {
        var payload: [String: Any] = [
            "typeName": sample.typeName,
            "timestampSeconds": sample.timestampSeconds
        ]
        if let values = sample.values {
            payload["values"] = values
        }
        if let attitude = sample.attitude {
            payload["attitude"] = attitude
        }
        if let gravity = sample.gravity {
            payload["gravity"] = gravity
        }
        if let userAcceleration = sample.userAcceleration {
            payload["userAcceleration"] = userAcceleration
        }
        return payload
    }
}
