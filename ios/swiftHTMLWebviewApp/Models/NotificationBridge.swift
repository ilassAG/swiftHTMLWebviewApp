//
//  NotificationBridge.swift
//  swiftHTMLWebviewApp
//
//  Local notification bridge for web content.
//

import Foundation
import UIKit
import UserNotifications

final class NotificationBridge: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationBridge()

    private var eventHandler: (([String: Any]) -> Void)?
    private var pendingEvents: [[String: Any]] = []

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    @MainActor
    func configure(eventHandler: @escaping ([String: Any]) -> Void) {
        self.eventHandler = eventHandler
        pendingEvents.forEach { eventHandler($0) }
        pendingEvents.removeAll()
    }

    func permissionStatus(request: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            completion(self.permissionResponse(request: request, action: "notificationPermissionGet", settings: settings))
        }
    }

    func requestPermission(request: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        let options = authorizationOptions(request)
        UNUserNotificationCenter.current().requestAuthorization(options: options) { granted, error in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                var response = self.permissionResponse(request: request, action: "notificationPermissionRequest", settings: settings)
                response["success"] = error == nil
                response["granted"] = granted
                if let error {
                    response["error"] = error.localizedDescription
                }
                completion(response)
            }
        }
    }

    func show(request: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        schedule(request: request, action: "notificationShow", trigger: nil, completion: completion)
    }

    func schedule(request: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        let seconds = max(1.0, doubleValue(request["seconds"] ?? request["delaySeconds"] ?? request["timeIntervalSeconds"]) ?? 10.0)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: boolValue(request["repeats"]) ?? false)
        schedule(request: request, action: "notificationSchedule", trigger: trigger, completion: completion)
    }

    func cancel(request: [String: Any]) -> [String: Any] {
        let ids = notificationIDs(request)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)

        var response = baseResponse(request: request, action: "notificationCancel")
        response["success"] = true
        response["ids"] = ids
        response["count"] = ids.count
        return response
    }

    func cancelAll(request: [String: Any]) -> [String: Any] {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()

        var response = baseResponse(request: request, action: "notificationCancelAll")
        response["success"] = true
        return response
    }

    func list(request: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { pendingRequests in
            UNUserNotificationCenter.current().getDeliveredNotifications { deliveredNotifications in
                var response = self.baseResponse(request: request, action: "notificationList")
                response["success"] = true
                response["pending"] = pendingRequests.map { self.notificationPayload(id: $0.identifier, content: $0.content, state: "pending") }
                response["delivered"] = deliveredNotifications.map { self.notificationPayload(id: $0.request.identifier, content: $0.request.content, state: "delivered") }
                completion(response)
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        emit(eventPayload(action: "notificationReceived", notification: notification, source: "local"))
        completionHandler([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        var event = eventPayload(action: "notificationOpened", notification: response.notification, source: "local")
        event["notificationActionIdentifier"] = response.actionIdentifier
        emit(event)
        completionHandler()
    }

    private func schedule(
        request: [String: Any],
        action: String,
        trigger: UNNotificationTrigger?,
        completion: @escaping ([String: Any]) -> Void
    ) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral else {
                var response = self.baseResponse(request: request, action: action)
                response["success"] = false
                response["authorizationStatus"] = self.authorizationStatusName(settings.authorizationStatus)
                response["error"] = "Notification permission is not granted."
                completion(response)
                return
            }

            let id = self.notificationID(request)
            let content = UNMutableNotificationContent()
            content.title = self.nonEmpty(stringValue(request["title"]), fallback: "Notification")
            content.subtitle = stringValue(request["subtitle"])
            content.body = self.nonEmpty(stringValue(request["body"] ?? request["message"]), fallback: "")
            content.sound = (boolValue(request["sound"]) ?? true) ? .default : nil
            if let badge = intValue(request["badge"]) {
                content.badge = NSNumber(value: badge)
            }
            content.categoryIdentifier = stringValue(request["categoryId"] ?? request["categoryIdentifier"])
            content.threadIdentifier = stringValue(request["threadId"] ?? request["threadIdentifier"])
            content.userInfo = self.userInfo(request)

            let notificationRequest = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(notificationRequest) { error in
                var response = self.baseResponse(request: request, action: action)
                response["success"] = error == nil
                response["id"] = id
                response["authorizationStatus"] = self.authorizationStatusName(settings.authorizationStatus)
                if let intervalTrigger = trigger as? UNTimeIntervalNotificationTrigger {
                    response["seconds"] = intervalTrigger.timeInterval
                    response["repeats"] = intervalTrigger.repeats
                } else {
                    response["immediate"] = true
                }
                if let error {
                    response["error"] = error.localizedDescription
                }
                completion(response)
            }
        }
    }

    private func permissionResponse(request: [String: Any], action: String, settings: UNNotificationSettings) -> [String: Any] {
        var response = baseResponse(request: request, action: action)
        response["success"] = true
        response["authorizationStatus"] = authorizationStatusName(settings.authorizationStatus)
        response["authorized"] = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral
        response["alertSetting"] = notificationSettingName(settings.alertSetting)
        response["badgeSetting"] = notificationSettingName(settings.badgeSetting)
        response["soundSetting"] = notificationSettingName(settings.soundSetting)
        response["lockScreenSetting"] = notificationSettingName(settings.lockScreenSetting)
        response["notificationCenterSetting"] = notificationSettingName(settings.notificationCenterSetting)
        return response
    }

    private func authorizationOptions(_ request: [String: Any]) -> UNAuthorizationOptions {
        var options: UNAuthorizationOptions = []
        if boolValue(request["alert"]) ?? true { options.insert(.alert) }
        if boolValue(request["sound"]) ?? true { options.insert(.sound) }
        if boolValue(request["badge"]) ?? true { options.insert(.badge) }
        if boolValue(request["provisional"]) ?? false { options.insert(.provisional) }
        return options
    }

    private func userInfo(_ request: [String: Any]) -> [AnyHashable: Any] {
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

    private func notificationPayload(id: String, content: UNNotificationContent, state: String) -> [String: Any] {
        [
            "id": id,
            "state": state,
            "title": content.title,
            "subtitle": content.subtitle,
            "body": content.body,
            "badge": content.badge ?? NSNull(),
            "threadId": content.threadIdentifier,
            "categoryId": content.categoryIdentifier,
            "data": jsonUserInfo(content.userInfo)
        ]
    }

    private func eventPayload(action: String, notification: UNNotification, source: String) -> [String: Any] {
        var payload = baseResponse(request: [:], action: action)
        payload["success"] = true
        payload["id"] = notification.request.identifier
        payload["source"] = source
        payload["notification"] = notificationPayload(id: notification.request.identifier, content: notification.request.content, state: "delivered")
        payload["data"] = jsonUserInfo(notification.request.content.userInfo)
        return payload
    }

    private func jsonUserInfo(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
        var output: [String: Any] = [:]
        userInfo.forEach { key, value in
            let stringKey = String(describing: key)
            if JSONSerialization.isValidJSONObject(["value": value]) {
                output[stringKey] = value
            }
        }
        return output
    }

    private func notificationID(_ request: [String: Any]) -> String {
        nonEmpty(stringValue(request["id"] ?? request["notificationId"]), fallback: UUID().uuidString)
    }

    private func notificationIDs(_ request: [String: Any]) -> [String] {
        if let ids = request["ids"] as? [Any] {
            return ids.map { stringValue($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        let id = notificationID(request)
        return id.isEmpty ? [] : [id]
    }

    private func authorizationStatusName(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown"
        }
    }

    private func notificationSettingName(_ setting: UNNotificationSetting) -> String {
        switch setting {
        case .notSupported: return "notSupported"
        case .disabled: return "disabled"
        case .enabled: return "enabled"
        @unknown default: return "unknown"
        }
    }

    private func baseResponse(request: [String: Any], action: String) -> [String: Any] {
        var response: [String: Any] = [
            "action": action,
            "platform": "ios"
        ]
        if let requestId = request["requestId"] {
            response["requestId"] = requestId
        }
        return response
    }

    private func nonEmpty(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func emit(_ event: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            if let eventHandler = self?.eventHandler {
                eventHandler(event)
            } else {
                self?.pendingEvents.append(event)
            }
        }
    }
}
