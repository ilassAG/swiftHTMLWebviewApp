//
//  WebViewErrorPayload.swift
//  swiftHTMLWebviewApp
//

import Foundation

enum WebViewErrorPayload {
    static func response(action: String?, error: Error) -> [String: Any] {
        let appError: AppError
        if let knownError = error as? AppError {
            appError = knownError
        } else {
            appError = .internalError(error.localizedDescription)
        }

        return BridgeResponse.error(
            request: [:],
            action: action ?? "unknown",
            message: appError.localizedDescription
        )
    }
}
