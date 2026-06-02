//
//  PrinterBridge.swift
//  swiftHTMLWebviewApp
//
//  Native bridge for small printer smoke tests backed by the shared Go core.
//

import Foundation

#if canImport(Printercore)
import Printercore
#endif

final class PrinterBridge: ObservableObject {
    private let action = "printerEpsonHelloWorld"

    func printEpsonHelloWorld(
        request: [String: Any],
        completion: @escaping ([String: Any]) -> Void
    ) {
        #if canImport(Printercore)
        let host = stringValue(request["host"], fallback: "10.10.10.131")
        let devid = stringValue(request["devid"], fallback: "local_printer")
        let timeoutMs = intValue(request["timeoutMs"], fallback: 20_000)
        let title = stringValue(request["title"], fallback: "Hallo Welt")
        let subtitle = stringValue(request["subtitle"], fallback: "swiftHTMLWebviewApp")
        let body = stringValue(request["body"], fallback: "iOS bridge test")

        DispatchQueue.global(qos: .userInitiated).async {
            var response = self.baseResponse(request: request)
            response["host"] = host
            response["devid"] = devid
            response["goCoreVersion"] = PMPrintercoreCoreVersion()

            let coreJson = PMPrintercorePrintEpsonHelloWorld(
                host,
                devid,
                timeoutMs,
                title,
                subtitle,
                body
            )
            let coreResponse = self.parseCoreResponse(coreJson)
            coreResponse.forEach { key, value in
                response[key] = value
            }

            if (response["success"] as? Bool) != true && response["error"] == nil {
                response["error"] = (response["message"] as? String) ?? "Printer returned an unsuccessful response."
            }

            DispatchQueue.main.async {
                completion(response)
            }
        }
        #else
        var response = baseResponse(request: request)
        response["success"] = false
        response["available"] = false
        response["error"] = "Printercore.xcframework is not linked in this build."
        completion(response)
        #endif
    }

    private func baseResponse(request: [String: Any]) -> [String: Any] {
        var response: [String: Any] = [
            "platform": "ios",
            "action": action
        ]

        if let requestId = request["requestId"] as? String {
            response["requestId"] = requestId
        }
        if let paymentId = request["paymentId"] as? String {
            response["paymentId"] = paymentId
        }
        return response
    }

    private func parseCoreResponse(_ rawJson: String) -> [String: Any] {
        guard let data = rawJson.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [
                "success": false,
                "error": "Printercore returned invalid JSON.",
                "responseText": rawJson
            ]
        }
        return decoded
    }

    private func stringValue(_ value: Any?, fallback: String) -> String {
        if let raw = value as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? fallback : trimmed
        }
        return fallback
    }

    private func intValue(_ value: Any?, fallback: Int) -> Int {
        if let raw = value as? Int {
            return raw
        }
        if let raw = value as? Double {
            return Int(raw)
        }
        if let raw = value as? String, let parsed = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return parsed
        }
        return fallback
    }
}
