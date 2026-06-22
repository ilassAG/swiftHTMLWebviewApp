//
//  TapToPayPayload.swift
//  swiftHTMLWebviewApp
//

import Foundation

enum TapToPayPayload {
    static func availability(
        request: [String: Any],
        available: Bool,
        readerType: String,
        reason: String? = nil
    ) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "tapToPayAvailability")
        response["success"] = true
        response["available"] = available
        response["readerType"] = readerType
        if let reason, !reason.isEmpty {
            response["reason"] = reason
        }
        return response
    }

    static func collectSuccess(
        request: [String: Any],
        paymentIntentId: String,
        status: String,
        nativeStatus: String
    ) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "tapToPayCollect")
        response["success"] = true
        response["paymentIntentId"] = paymentIntentId
        response["status"] = status
        response["nativeStatus"] = nativeStatus
        return response
    }

    static func cancelled(request: [String: Any], reason: String) -> [String: Any] {
        var response = BridgeResponse.error(request: request, action: "tapToPayCollect", message: reason)
        response["cancelled"] = true
        response["reason"] = reason
        return response
    }

    static func error(request: [String: Any], message: String) -> [String: Any] {
        BridgeResponse.error(request: request, action: "tapToPayCollect", message: message)
    }
}
