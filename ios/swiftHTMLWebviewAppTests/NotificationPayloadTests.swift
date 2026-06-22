//
//  NotificationPayloadTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class NotificationPayloadTests: XCTestCase {
    func testPermissionResponsesUseCommonBridgeShape() {
        let settings = NotificationPayload.PermissionSettings(
            authorizationStatus: "provisional",
            authorized: true,
            alertSetting: "enabled",
            badgeSetting: "disabled",
            soundSetting: "enabled",
            lockScreenSetting: "enabled",
            notificationCenterSetting: "disabled"
        )

        let response = NotificationPayload.permissionResponse(
            request: ["requestId": "notif-req-1"],
            action: "notificationPermissionGet",
            settings: settings
        )

        XCTAssertEqual(response["platform"] as? String, "ios")
        XCTAssertEqual(response["action"] as? String, "notificationPermissionGet")
        XCTAssertEqual(response["requestId"] as? String, "notif-req-1")
        XCTAssertEqual(response["success"] as? Bool, true)
        XCTAssertEqual(response["authorizationStatus"] as? String, "provisional")
        XCTAssertEqual(response["authorized"] as? Bool, true)
        XCTAssertEqual(response["alertSetting"] as? String, "enabled")
        XCTAssertEqual(response["badgeSetting"] as? String, "disabled")
        XCTAssertEqual(response["soundSetting"] as? String, "enabled")
        XCTAssertEqual(response["lockScreenSetting"] as? String, "enabled")
        XCTAssertEqual(response["notificationCenterSetting"] as? String, "disabled")

        let error = NotificationPayload.permissionError(
            request: ["requestId": "notif-req-2"],
            action: "notificationShow",
            authorizationStatus: "denied"
        )

        XCTAssertEqual(error["platform"] as? String, "ios")
        XCTAssertEqual(error["action"] as? String, "notificationShow")
        XCTAssertEqual(error["requestId"] as? String, "notif-req-2")
        XCTAssertEqual(error["success"] as? Bool, false)
        XCTAssertEqual(error["authorized"] as? Bool, false)
        XCTAssertEqual(error["authorizationStatus"] as? String, "denied")
        XCTAssertEqual(error["error"] as? String, "Notification permission is not granted.")
    }

    func testNotificationPayloadNormalizesFallbacksAndData() {
        let request = NotificationPayload.notificationRequest(from: [
            "notificationId": " legacy-id ",
            "message": "Fallback body",
            "sound": false,
            "badge": "7",
            "threadIdentifier": "ops",
            "categoryIdentifier": "print",
            "data": [
                "jobId": "42",
                "invalid": Date(timeIntervalSince1970: 0)
            ]
        ], fallbackId: "generated-id")

        XCTAssertEqual(request.id, "legacy-id")
        XCTAssertEqual(request.title, "Notification")
        XCTAssertEqual(request.subtitle, "")
        XCTAssertEqual(request.body, "Fallback body")
        XCTAssertEqual(request.sound, false)
        XCTAssertEqual(request.badge, 7)
        XCTAssertEqual(request.threadId, "ops")
        XCTAssertEqual(request.categoryId, "print")

        let data = NotificationPayload.jsonUserInfo(request.userInfo)
        XCTAssertEqual(data["jobId"] as? String, "42")
        XCTAssertEqual(data["source"] as? String, "local")
        XCTAssertNil(data["invalid"])

        let payload = NotificationPayload.notificationPayload(
            id: request.id,
            state: "pending",
            title: request.title,
            subtitle: request.subtitle,
            body: request.body,
            badge: nil,
            threadId: request.threadId,
            categoryId: request.categoryId,
            userInfo: request.userInfo
        )

        XCTAssertEqual(payload["id"] as? String, "legacy-id")
        XCTAssertEqual(payload["state"] as? String, "pending")
        XCTAssertEqual(payload["title"] as? String, "Notification")
        XCTAssertEqual(payload["body"] as? String, "Fallback body")
        XCTAssertTrue(payload["badge"] is NSNull)
        XCTAssertEqual((payload["data"] as? [String: Any])?["jobId"] as? String, "42")
    }

    func testIdsFromRequestPrefersExplicitArrayAndSkipsBlanks() {
        let ids = NotificationPayload.ids(from: [
            "id": "fallback",
            "ids": [" first ", "", "second", 12]
        ], fallbackId: "generated")

        XCTAssertEqual(ids, ["first", "second", "12"])

        XCTAssertEqual(NotificationPayload.ids(from: [
            "notificationId": "legacy-id"
        ], fallbackId: "generated"), ["legacy-id"])

        XCTAssertEqual(NotificationPayload.ids(from: [:], fallbackId: "generated"), ["generated"])
    }

    func testEventsAndScheduleResponsesWrapNotificationPayloads() {
        let notification = NotificationPayload.notificationPayload(
            id: "notif-2",
            state: "delivered",
            title: "Printed",
            subtitle: "Kitchen",
            body: "Bon fertig",
            badge: 3,
            threadId: "tickets",
            categoryId: "print",
            userInfo: ["ticket": "A7"]
        )

        let event = NotificationPayload.eventPayload(
            action: "notificationOpened",
            id: "notif-2",
            source: "local",
            notification: notification,
            data: ["ticket": "A7"]
        )

        XCTAssertEqual(event["platform"] as? String, "ios")
        XCTAssertEqual(event["action"] as? String, "notificationOpened")
        XCTAssertEqual(event["success"] as? Bool, true)
        XCTAssertEqual(event["source"] as? String, "local")
        XCTAssertEqual(event["id"] as? String, "notif-2")
        XCTAssertEqual((event["notification"] as? [String: Any])?["title"] as? String, "Printed")
        XCTAssertEqual((event["data"] as? [String: Any])?["ticket"] as? String, "A7")

        let scheduled = NotificationPayload.scheduleResponse(
            request: ["requestId": "notif-req-3"],
            action: "notificationSchedule",
            id: "notif-3",
            authorizationStatus: "authorized",
            seconds: 12,
            repeats: true,
            error: nil
        )

        XCTAssertEqual(scheduled["requestId"] as? String, "notif-req-3")
        XCTAssertEqual(scheduled["success"] as? Bool, true)
        XCTAssertEqual(scheduled["id"] as? String, "notif-3")
        XCTAssertEqual(scheduled["authorizationStatus"] as? String, "authorized")
        XCTAssertEqual(scheduled["seconds"] as? Double, 12)
        XCTAssertEqual(scheduled["repeats"] as? Bool, true)
    }
}
