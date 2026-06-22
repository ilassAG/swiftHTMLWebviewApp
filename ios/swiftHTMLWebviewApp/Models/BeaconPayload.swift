//
//  BeaconPayload.swift
//  swiftHTMLWebviewApp
//

import Foundation

enum BeaconPayload {
    static let rangingProvider = "ios_corelocation"
    static let advertiserProvider = "ios_corebluetooth"

    struct AdvertiseConfig {
        let uuid: UUID
        let major: UInt16
        let minor: UInt16
        let measuredPower: Int?
    }

    static func rangingUUID(from request: [String: Any], defaultUUID: UUID) -> UUID {
        let requested = stringValue(request["uuid"]).trimmingCharacters(in: .whitespacesAndNewlines)
        return UUID(uuidString: requested) ?? defaultUUID
    }

    static func rangingStartResponse(
        request: [String: Any],
        uuid: UUID,
        success: Bool,
        error: String? = nil
    ) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "beaconsStart")
        response["success"] = success
        response["uuid"] = uuid.uuidString
        response["provider"] = rangingProvider
        if let error {
            response["error"] = error
        }
        return response
    }

    static func rangingStopResponse(request: [String: Any]) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "beaconsStop")
        response["success"] = true
        return response
    }

    static func beaconObject(
        proximityUUID: UUID,
        major: Int,
        minor: Int,
        proximity: String,
        accuracy: Double,
        rssi: Int
    ) -> [String: Any] {
        [
            "proximityUUID": proximityUUID.uuidString,
            "major": major,
            "minor": minor,
            "proximity": proximity,
            "accuracy": accuracy,
            "rssi": rssi
        ]
    }

    static func rangingEvent(uuid: UUID, beacons: [[String: Any]], timestamp: Date = Date()) -> [String: Any] {
        [
            "platform": "ios",
            "action": "beacons",
            "success": true,
            "uuid": uuid.uuidString,
            "count": beacons.count,
            "beacons": beacons,
            "timestamp": ISO8601DateFormatter().string(from: timestamp)
        ]
    }

    static func errorEvent(error: String) -> [String: Any] {
        [
            "platform": "ios",
            "action": "beacons",
            "success": false,
            "error": error
        ]
    }

    static func advertiseConfig(from request: [String: Any], defaultUUID: UUID) -> AdvertiseConfig? {
        let uuidString = stringValue(request["uuid"] ?? request["beaconUUID"] ?? request["beaconUuid"] ?? request["proximityUUID"])
        let uuid: UUID
        if uuidString.isEmpty {
            uuid = defaultUUID
        } else if let parsedUUID = UUID(uuidString: uuidString) {
            uuid = parsedUUID
        } else {
            return nil
        }

        let majorValue = intValue(request["major"]) ?? 1
        let minorValue = intValue(request["minor"]) ?? 1
        guard (0...65535).contains(majorValue),
              (0...65535).contains(minorValue) else {
            return nil
        }

        let measuredPower: Int?
        if let power = intValue(request["measuredPower"] ?? request["measuredPowerDbm"] ?? request["txPower"]) {
            guard (-127...20).contains(power) else {
                return nil
            }
            measuredPower = power
        } else {
            measuredPower = nil
        }

        return AdvertiseConfig(
            uuid: uuid,
            major: UInt16(majorValue),
            minor: UInt16(minorValue),
            measuredPower: measuredPower
        )
    }

    static func advertiseStartResponse(
        request: [String: Any],
        config: AdvertiseConfig,
        state: String
    ) -> [String: Any] {
        var response = advertiseBase(request: request, action: "beaconAdvertiseStart", config: config)
        response["success"] = true
        response["provider"] = advertiserProvider
        response["state"] = state
        return response
    }

    static func advertiseStopResponse(request: [String: Any]) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "beaconAdvertiseStop")
        response["success"] = true
        response["provider"] = advertiserProvider
        response["state"] = "stopped"
        return response
    }

    static func advertiseStateEvent(
        request: [String: Any],
        config: AdvertiseConfig,
        success: Bool,
        state: String,
        advertising: Bool,
        error: String? = nil
    ) -> [String: Any] {
        var event = advertiseBase(request: request, action: "beaconAdvertiseStart", config: config)
        event["success"] = success
        event["provider"] = advertiserProvider
        event["state"] = state
        event["advertising"] = advertising
        if let error {
            event["error"] = error
        }
        return event
    }

    static func errorResponse(request: [String: Any], action: String, error: String) -> [String: Any] {
        BridgeResponse.error(request: request, action: action, message: error)
    }

    private static func advertiseBase(request: [String: Any], action: String, config: AdvertiseConfig) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: action)
        response["uuid"] = config.uuid.uuidString
        response["major"] = Int(config.major)
        response["minor"] = Int(config.minor)
        if let measuredPower = config.measuredPower {
            response["measuredPower"] = measuredPower
        }
        return response
    }
}
