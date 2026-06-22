//
//  ConfigPairingPayload.swift
//  swiftHTMLWebviewApp
//

import Foundation

enum ConfigPairingPayload {
    static let serviceUUID = "6D8E0F22-9C2D-4E8E-A7D7-2B1D49F48A01"
    static let commandUUID = "6D8E0F22-9C2D-4E8E-A7D7-2B1D49F48A02"
    static let responseUUID = "6D8E0F22-9C2D-4E8E-A7D7-2B1D49F48A03"
    static let chunkPayloadSize = 32

    struct PairingTarget {
        let sessionID: String
        let secret: String
        let serviceUUID: String
        let name: String
        let deviceName: String
        let deviceUUID: String
        let deviceLocation: String

        var identity: [String: String] {
            [
                "name": name,
                "deviceName": deviceName,
                "deviceUUID": deviceUUID,
                "deviceLocation": deviceLocation
            ]
        }

        init?(payload: String) {
            guard let components = URLComponents(string: payload),
                  components.scheme == "swifthtml-config",
                  components.host == "pair" else { return nil }

            let items = (components.queryItems ?? []).reduce(into: [String: String]()) { values, item in
                values[item.name] = item.value ?? ""
            }
            guard let sessionID = items["id"], !sessionID.isEmpty,
                  let secret = items["secret"], !secret.isEmpty else { return nil }

            self.sessionID = sessionID
            self.secret = secret
            self.serviceUUID = nonEmpty(items["service"], ConfigPairingPayload.serviceUUID)
            self.deviceName = items["deviceName"] ?? items["device_name"] ?? ""
            self.deviceUUID = items["deviceUUID"] ?? items["deviceUuid"] ?? items["device_uuid"] ?? ""
            self.deviceLocation = items["deviceLocation"] ?? items["device_location"] ?? ""
            self.name = self.deviceName.isEmpty ? (items["name"] ?? "") : self.deviceName
        }
    }

    struct ChunkAccumulator {
        let count: Int
        var chunks: [Int: Data] = [:]

        var isComplete: Bool {
            chunks.count == count
        }

        var assembled: Data {
            (0..<count).reduce(into: Data()) { output, index in
                if let chunk = chunks[index] {
                    output.append(chunk)
                }
            }
        }
    }

    static func identity(settings: [String: Any], fallbackName: String) -> [String: String] {
        let deviceName = string(settings["deviceName"]) ?? ""
        let deviceUUID = string(settings["deviceUUID"]) ?? ""
        let deviceLocation = string(settings["deviceLocation"]) ?? ""
        let displayName = deviceName.isEmpty ? fallbackName : deviceName
        return [
            "name": displayName,
            "deviceName": deviceName,
            "deviceUUID": deviceUUID,
            "deviceLocation": deviceLocation
        ]
    }

    static func pairingPayload(sessionID: String, secret: String, expiresAt: Date, identity: [String: String]) -> String {
        var components = URLComponents()
        components.scheme = "swifthtml-config"
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "id", value: sessionID),
            URLQueryItem(name: "secret", value: secret),
            URLQueryItem(name: "service", value: serviceUUID),
            URLQueryItem(name: "expires", value: String(Int(expiresAt.timeIntervalSince1970))),
            URLQueryItem(name: "name", value: identity["name"] ?? ""),
            URLQueryItem(name: "deviceName", value: identity["deviceName"] ?? ""),
            URLQueryItem(name: "deviceUUID", value: identity["deviceUUID"] ?? ""),
            URLQueryItem(name: "deviceLocation", value: identity["deviceLocation"] ?? "")
        ]
        return components.string ?? "swifthtml-config://pair"
    }

    static func baseResponse(request: [String: Any], action: String) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: action)
        response["platform"] = "ios"
        return response
    }

    static func showResponse(
        request: [String: Any],
        payload: String,
        expiresAt: Date,
        identity: [String: String]
    ) -> [String: Any] {
        var response = baseResponse(request: request, action: "configPairingShow")
        response["success"] = true
        response["payload"] = payload
        response["expiresAt"] = Int(expiresAt.timeIntervalSince1970)
        response["transport"] = "ble-gatt"
        response["serviceUUID"] = serviceUUID
        response["targetIdentity"] = identity
        response["deviceName"] = identity["deviceName"] ?? ""
        response["deviceUUID"] = identity["deviceUUID"] ?? ""
        response["deviceLocation"] = identity["deviceLocation"] ?? ""
        return response
    }

    static func acknowledgementResponse(request: [String: Any], action: String) -> [String: Any] {
        var response = baseResponse(request: request, action: action)
        response["success"] = true
        return response
    }

    static func errorResponse(request: [String: Any], action: String, error: String) -> [String: Any] {
        BridgeResponse.error(request: request, action: action, message: error)
    }

    static func connectResponse(request: [String: Any], target: PairingTarget) -> [String: Any] {
        var response = baseResponse(request: request, action: "configPairingConnect")
        response["success"] = true
        response["state"] = "scanning"
        response["targetName"] = target.name
        response["targetIdentity"] = target.identity
        response["deviceName"] = target.deviceName
        response["deviceUUID"] = target.deviceUUID
        response["deviceLocation"] = target.deviceLocation
        response["serviceUUID"] = target.serviceUUID
        return response
    }

    static func command(target: PairingTarget, request: [String: Any], requestId: String) -> [String: Any] {
        var command: [String: Any] = [
            "sessionId": target.sessionID,
            "secret": target.secret,
            "requestId": requestId,
            "command": string(request["command"]) ?? string(request["configCommand"]) ?? "statusGet"
        ]

        if let token = string(request["token"] ?? request["securityToken"]), !token.isEmpty {
            command["token"] = token
        }
        if let settings = request["settings"] as? [String: Any] {
            command["settings"] = settings
        }
        if let ssid = string(request["ssid"]), !ssid.isEmpty {
            command["ssid"] = ssid
        }
        if let passphrase = string(request["passphrase"] ?? request["password"]), !passphrase.isEmpty {
            command["passphrase"] = passphrase
        }
        if let joinOnce = request["joinOnce"] as? Bool {
            command["joinOnce"] = joinOnce
        }
        return command
    }

    static func sendResponse(request: [String: Any], command: String, bytes: Int, chunks: Int) -> [String: Any] {
        var response = baseResponse(request: request, action: "configPairingSend")
        response["success"] = true
        response["state"] = chunks > 1 ? "sentInChunks" : "sent"
        response["command"] = command
        response["bytes"] = bytes
        response["chunks"] = chunks
        return response
    }

    static func responsePayload(command: String, requestId: Any?, sessionID: String, requestIdProvider: () -> String = { UUID().uuidString }) -> [String: Any] {
        [
            "action": "configPairingResponse",
            "platform": "ios",
            "role": "target",
            "command": command,
            "requestId": stringOrGenerated(requestId, provider: requestIdProvider),
            "sessionId": sessionID
        ]
    }

    static func errorPayload(
        command: String,
        requestId: Any? = nil,
        sessionID: String,
        error: String,
        requestIdProvider: () -> String = { UUID().uuidString }
    ) -> [String: Any] {
        var response = responsePayload(command: command, requestId: requestId, sessionID: sessionID, requestIdProvider: requestIdProvider)
        response["success"] = false
        response["error"] = error
        return response
    }

    static func commandErrorPayload(command: String, requestId: Any? = nil, error: String) -> [String: Any] {
        errorPayload(command: command, requestId: requestId, sessionID: "", error: error)
    }

    static func eventPayload(role: String, event: String, success: Bool, error: String = "", extra: [String: Any] = [:]) -> [String: Any] {
        var payload: [String: Any] = [
            "action": "configPairingEvent",
            "platform": "ios",
            "role": role,
            "event": event,
            "success": success
        ]
        if !error.isEmpty {
            payload["error"] = error
        }
        for (key, value) in extra {
            payload[key] = value
        }
        return payload
    }

    static func chunkPayloads(for data: Data, maxLength: Int, chunkID: String = UUID().uuidString, chunkPayloadSize: Int = chunkPayloadSize) -> [Data]? {
        guard maxLength > 0 else { return nil }
        var chunkSize = chunkPayloadSize

        while chunkSize >= 8 {
            let chunkCount = Int(ceil(Double(data.count) / Double(chunkSize)))
            var payloads: [Data] = []
            var fits = true

            for index in 0..<chunkCount {
                let start = index * chunkSize
                let end = min(start + chunkSize, data.count)
                let chunk = data.subdata(in: start..<end)
                let payload = chunkEnvelope(id: chunkID, index: index, count: chunkCount, data: chunk)
                guard let payloadData = try? JSONSerialization.data(withJSONObject: payload, options: []),
                      payloadData.count <= maxLength else {
                    fits = false
                    break
                }
                payloads.append(payloadData)
            }

            if fits {
                return payloads
            }
            chunkSize /= 2
        }

        return nil
    }

    static func chunkEnvelope(id: String, index: Int, count: Int, data: Data) -> [String: Any] {
        [
            "action": "configPairingChunk",
            "id": id,
            "i": index,
            "n": count,
            "d": data.base64EncodedString()
        ]
    }

    static func chunkData(from object: [String: Any]) -> (id: String, index: Int, count: Int, data: Data)? {
        guard let id = string(object["id"]),
              let index = int(object["i"]),
              let count = int(object["n"]),
              let encoded = string(object["d"]),
              let data = Data(base64Encoded: encoded),
              !id.isEmpty,
              !encoded.isEmpty,
              index >= 0,
              count > 0,
              index < count else { return nil }
        return (id, index, count, data)
    }

    static func isValidChunkEnvelope(_ object: [String: Any]) -> Bool {
        chunkData(from: object) != nil
    }

    static func string(_ value: Any?) -> String? {
        guard let value else { return nil }
        if value is NSNull { return "" }
        if let stringValue = value as? String {
            return stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let numberValue = value as? NSNumber {
            return numberValue.stringValue
        }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let intValue = value as? Int {
            return intValue
        }
        if let numberValue = value as? NSNumber {
            return numberValue.intValue
        }
        if let stringValue = value as? String {
            return Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    static func stringOrGenerated(_ value: Any?, provider: () -> String = { UUID().uuidString }) -> String {
        let stringValue = string(value) ?? ""
        return stringValue.isEmpty ? provider() : stringValue
    }

    static func nonEmpty(_ value: String?, _ fallback: String) -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
