//
//  BridgeScriptBuilder.swift
//  swiftHTMLWebviewApp
//

import Foundation

enum BridgeScriptBuilder {
    enum ResultKind: Equatable {
        case payload
        case fallback
    }

    struct ScriptResult: Equatable {
        let script: String
        let kind: ResultKind
    }

    static func nativeResultScript(payload: [String: Any]) -> ScriptResult {
        if let jsonString = jsonString(payload) {
            return ScriptResult(script: handleNativeResultScript(jsonString: jsonString), kind: .payload)
        }

        return ScriptResult(script: fallbackScript(), kind: .fallback)
    }

    private static func fallbackScript() -> String {
        let fallbackError: [String: Any] = [
            "error": AppError.internalError(
                NSLocalizedString(
                    "error.internalError.jsonResponseFailed",
                    comment: "Failed to create JSON response fallback message"
                )
            ).localizedDescription
        ]

        let fallbackString = jsonString(fallbackError) ?? "{ \"error\": \"\(NSLocalizedString("error.internalError.criticalFailure", comment: "Critical internal Swift error fallback"))\" }"
        return handleNativeResultScript(jsonString: fallbackString)
    }

    private static func handleNativeResultScript(jsonString: String) -> String {
        "window.handleNativeResult(\(jsonString));"
    }

    private static func jsonString(_ payload: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(payload),
              let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        return jsonString
    }
}
