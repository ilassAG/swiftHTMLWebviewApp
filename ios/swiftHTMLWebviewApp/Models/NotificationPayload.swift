//
//  NotificationPayload.swift
//  swiftHTMLWebviewApp
//
//  Pure request and response helpers for the local notification bridge.
//

import Foundation

enum NotificationPayload {
    struct PermissionSettings {
        let authorizationStatus: String
        let authorized: Bool
        let alertSetting: String
        let badgeSetting: String
        let soundSetting: String
        let lockScreenSetting: String
        let notificationCenterSetting: String
    }

    struct NotificationRequest {
        let id: String
        let title: String
        let subtitle: String
        let body: String
        let sound: Bool
        let badge: Int?
        let categoryId: String
        let threadId: String
        let userInfo: [AnyHashable: Any]
    }

    static func permissionResponse(
        request: [String: Any],
        action: String,
        settings: PermissionSettings
    ) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: action)
        response["success"] = true
        response["authorizationStatus"] = settings.authorizationStatus
        response["authorized"] = settings.authorized
        response["alertSetting"] = settings.alertSetting
        response["badgeSetting"] = settings.badgeSetting
        response["soundSetting"] = settings.soundSetting
        response["lockScreenSetting"] = settings.lockScreenSetting
        response["notificationCenterSetting"] = settings.notificationCenterSetting
        return response
    }

    static func permissionError(
        request: [String: Any],
        action: String,
        authorizationStatus: String
    ) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: action)
        response["success"] = false
        response["authorized"] = false
        response["authorizationStatus"] = authorizationStatus
        response["error"] = "Notification permission is not granted."
        return response
    }

    static func notificationRequest(from request: [String: Any], fallbackId: String = UUID().uuidString) -> NotificationRequest {
        NotificationRequest(
            id: notificationID(request, fallback: fallbackId),
            title: nonEmpty(stringValue(request["title"]), fallback: "Notification"),
            subtitle: stringValue(request["subtitle"]),
            body: nonEmpty(stringValue(request["body"] ?? request["message"]), fallback: ""),
            sound: boolValue(request["sound"]) ?? true,
            badge: intValue(request["badge"]),
            categoryId: stringValue(request["categoryId"] ?? request["categoryIdentifier"]),
            threadId: stringValue(request["threadId"] ?? request["threadIdentifier"]),
            userInfo: userInfo(request)
        )
    }

    static func showResponse(
        request: [String: Any],
        action: String,
        id: String,
        authorizationStatus: String,
        error: Error?
    ) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: action)
        response["success"] = error == nil
        response["id"] = id
        response["authorizationStatus"] = authorizationStatus
        response["immediate"] = true
        if let error {
            response["error"] = error.localizedDescription
        }
        return response
    }

    static func scheduleResponse(
        request: [String: Any],
        action: String,
        id: String,
        authorizationStatus: String,
        seconds: TimeInterval,
        repeats: Bool,
        error: Error?
    ) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: action)
        response["success"] = error == nil
        response["id"] = id
        response["authorizationStatus"] = authorizationStatus
        response["seconds"] = seconds
        response["repeats"] = repeats
        if let error {
            response["error"] = error.localizedDescription
        }
        return response
    }

    static func cancelResponse(request: [String: Any], ids: [String]) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "notificationCancel")
        response["success"] = true
        response["ids"] = ids
        response["count"] = ids.count
        return response
    }

    static func cancelAllResponse(request: [String: Any]) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "notificationCancelAll")
        response["success"] = true
        return response
    }

    static func listResponse(
        request: [String: Any],
        pending: [[String: Any]],
        delivered: [[String: Any]]
    ) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "notificationList")
        response["success"] = true
        response["pending"] = pending
        response["delivered"] = delivered
        return response
    }

    static func notificationPayload(
        id: String,
        state: String,
        title: String,
        subtitle: String,
        body: String,
        badge: Any?,
        threadId: String,
        categoryId: String,
        userInfo: [AnyHashable: Any]
    ) -> [String: Any] {
        [
            "id": id,
            "state": state,
            "title": title,
            "subtitle": subtitle,
            "body": body,
            "badge": badge ?? NSNull(),
            "threadId": threadId,
            "categoryId": categoryId,
            "data": jsonUserInfo(userInfo)
        ]
    }

    static func eventPayload(
        action: String,
        id: String,
        source: String,
        notification: [String: Any],
        data: [String: Any]
    ) -> [String: Any] {
        var payload = BridgeResponse.base(request: [:], action: action)
        payload["success"] = true
        payload["id"] = id
        payload["source"] = source
        payload["notification"] = notification
        payload["data"] = data
        return payload
    }

    static func jsonUserInfo(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
        var output: [String: Any] = [:]
        userInfo.forEach { key, value in
            let stringKey = String(describing: key)
            if JSONSerialization.isValidJSONObject(["value": value]) {
                output[stringKey] = value
            }
        }
        return output
    }

    static func notificationID(_ request: [String: Any], fallback: String = UUID().uuidString) -> String {
        nonEmpty(stringValue(request["id"] ?? request["notificationId"]), fallback: fallback)
    }

    static func ids(from request: [String: Any], fallbackId: String = UUID().uuidString) -> [String] {
        if let ids = request["ids"] as? [Any] {
            return ids
                .map { stringValue($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        let id = notificationID(request, fallback: fallbackId)
        return id.isEmpty ? [] : [id]
    }

    private static func userInfo(_ request: [String: Any]) -> [AnyHashable: Any] {
        var userInfo: [AnyHashable: Any] = [:]
        if let data = request["data"] as? [String: Any] {
            data.forEach { key, value in
                if JSONSerialization.isValidJSONObject(["value": value]) {
                    userInfo[key] = value
                }
            }
        }
        userInfo["source"] = "local"
        return userInfo
    }

    private static func nonEmpty(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
