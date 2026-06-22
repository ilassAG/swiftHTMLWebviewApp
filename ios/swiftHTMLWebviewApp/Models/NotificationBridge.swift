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
            completion(NotificationPayload.permissionResponse(
                request: request,
                action: "notificationPermissionGet",
                settings: self.permissionSettings(settings)
            ))
        }
    }

    func requestPermission(request: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        let options = authorizationOptions(request)
        UNUserNotificationCenter.current().requestAuthorization(options: options) { granted, error in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                var response = NotificationPayload.permissionResponse(
                    request: request,
                    action: "notificationPermissionRequest",
                    settings: self.permissionSettings(settings)
                )
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
        let ids = NotificationPayload.ids(from: request)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)

        return NotificationPayload.cancelResponse(request: request, ids: ids)
    }

    func cancelAll(request: [String: Any]) -> [String: Any] {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()

        return NotificationPayload.cancelAllResponse(request: request)
    }

    func list(request: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { pendingRequests in
            UNUserNotificationCenter.current().getDeliveredNotifications { deliveredNotifications in
                let response = NotificationPayload.listResponse(
                    request: request,
                    pending: pendingRequests.map { self.notificationPayload(id: $0.identifier, content: $0.content, state: "pending") },
                    delivered: deliveredNotifications.map { self.notificationPayload(id: $0.request.identifier, content: $0.request.content, state: "delivered") }
                )
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
                completion(NotificationPayload.permissionError(
                    request: request,
                    action: action,
                    authorizationStatus: self.authorizationStatusName(settings.authorizationStatus)
                ))
                return
            }

            let notificationRequestPayload = NotificationPayload.notificationRequest(from: request)
            let content = UNMutableNotificationContent()
            content.title = notificationRequestPayload.title
            content.subtitle = notificationRequestPayload.subtitle
            content.body = notificationRequestPayload.body
            content.sound = notificationRequestPayload.sound ? .default : nil
            if let badge = notificationRequestPayload.badge {
                content.badge = NSNumber(value: badge)
            }
            content.categoryIdentifier = notificationRequestPayload.categoryId
            content.threadIdentifier = notificationRequestPayload.threadId
            content.userInfo = notificationRequestPayload.userInfo

            let notificationRequest = UNNotificationRequest(identifier: notificationRequestPayload.id, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(notificationRequest) { error in
                if let intervalTrigger = trigger as? UNTimeIntervalNotificationTrigger {
                    completion(NotificationPayload.scheduleResponse(
                        request: request,
                        action: action,
                        id: notificationRequestPayload.id,
                        authorizationStatus: self.authorizationStatusName(settings.authorizationStatus),
                        seconds: intervalTrigger.timeInterval,
                        repeats: intervalTrigger.repeats,
                        error: error
                    ))
                } else {
                    completion(NotificationPayload.showResponse(
                        request: request,
                        action: action,
                        id: notificationRequestPayload.id,
                        authorizationStatus: self.authorizationStatusName(settings.authorizationStatus),
                        error: error
                    ))
                }
            }
        }
    }

    private func authorizationOptions(_ request: [String: Any]) -> UNAuthorizationOptions {
        var options: UNAuthorizationOptions = []
        if boolValue(request["alert"]) ?? true { options.insert(.alert) }
        if boolValue(request["sound"]) ?? true { options.insert(.sound) }
        if boolValue(request["badge"]) ?? true { options.insert(.badge) }
        if boolValue(request["provisional"]) ?? false { options.insert(.provisional) }
        return options
    }

    private func notificationPayload(id: String, content: UNNotificationContent, state: String) -> [String: Any] {
        NotificationPayload.notificationPayload(
            id: id,
            state: state,
            title: content.title,
            subtitle: content.subtitle,
            body: content.body,
            badge: content.badge,
            threadId: content.threadIdentifier,
            categoryId: content.categoryIdentifier,
            userInfo: content.userInfo
        )
    }

    private func eventPayload(action: String, notification: UNNotification, source: String) -> [String: Any] {
        NotificationPayload.eventPayload(
            action: action,
            id: notification.request.identifier,
            source: source,
            notification: notificationPayload(id: notification.request.identifier, content: notification.request.content, state: "delivered"),
            data: NotificationPayload.jsonUserInfo(notification.request.content.userInfo)
        )
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

    private func permissionSettings(_ settings: UNNotificationSettings) -> NotificationPayload.PermissionSettings {
        let status = settings.authorizationStatus
        return NotificationPayload.PermissionSettings(
            authorizationStatus: authorizationStatusName(status),
            authorized: status == .authorized || status == .provisional || status == .ephemeral,
            alertSetting: notificationSettingName(settings.alertSetting),
            badgeSetting: notificationSettingName(settings.badgeSetting),
            soundSetting: notificationSettingName(settings.soundSetting),
            lockScreenSetting: notificationSettingName(settings.lockScreenSetting),
            notificationCenterSetting: notificationSettingName(settings.notificationCenterSetting)
        )
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
