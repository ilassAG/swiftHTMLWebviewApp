//
//  PrinterPayload.swift
//  swiftHTMLWebviewApp
//
//  Pure payload helpers for optional printer bridge actions.
//

import Foundation

enum PrinterPayload {
    struct EpsonHelloWorldRequest {
        let host: String
        let devid: String
        let timeoutMs: Int
        let title: String
        let subtitle: String
        let body: String
    }

    static func epsonRequest(from request: [String: Any]) -> EpsonHelloWorldRequest {
        EpsonHelloWorldRequest(
            host: string(request["host"], fallback: ""),
            devid: string(request["devid"], fallback: "local_printer"),
            timeoutMs: int(request["timeoutMs"], fallback: 20_000),
            title: string(request["title"], fallback: "Hallo Welt"),
            subtitle: string(request["subtitle"], fallback: "swiftHTMLWebviewApp"),
            body: string(request["body"], fallback: "iOS bridge test")
        )
    }

    static func selectedPrinterKind(_ request: [String: Any]) -> String {
        let directKind = string(request["kind"], fallback: "")
        if !directKind.isEmpty {
            return directKind
        }
        if let printer = request["printer"] as? [String: Any] {
            let nestedKind = string(printer["kind"], fallback: "")
            if !nestedKind.isEmpty {
                return nestedKind
            }
        }
        return "epson_epos_xml"
    }

    static func selectedPrinterLabel(_ request: [String: Any], fallback: String) -> String {
        if let printer = request["printer"] as? [String: Any] {
            let label = string(printer["label"], fallback: "")
            if !label.isEmpty {
                return label
            }
        }
        return fallback
    }

    static func discoveryOptionsJSON(from request: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(request),
              let data = try? JSONSerialization.data(withJSONObject: request),
              let raw = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return raw
    }

    static func coreResponse(from rawJson: String) -> [String: Any] {
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

    static func epsonJobResponse(
        request: [String: Any],
        action: String,
        job: EpsonHelloWorldRequest,
        core: [String: Any],
        goCoreVersion: String,
        printerLabel: String
    ) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: action)
        response["host"] = job.host
        response["devid"] = job.devid
        response["printerKind"] = "epson_epos_xml"
        response["printerLabel"] = printerLabel
        response["goCoreVersion"] = goCoreVersion

        core.forEach { key, value in
            response[key] = value
        }

        if (response["success"] as? Bool) != true && response["error"] == nil {
            response["error"] = (response["message"] as? String) ?? "Printer returned an unsuccessful response."
        }

        return response
    }

    static func printercoreUnavailable(
        request: [String: Any],
        action: String,
        printerKind: String = "epson_epos_xml"
    ) -> [String: Any] {
        var response = BridgeResponse.unavailable(
            request: request,
            action: action,
            message: "Printercore.xcframework is not linked in this build."
        )
        response["printerKind"] = printerKind
        return response
    }

    static func discoveryUnavailable(request: [String: Any]) -> [String: Any] {
        var response = BridgeResponse.unavailable(
            request: request,
            action: "printerDiscover",
            message: "Printercore.xcframework is not linked in this build."
        )
        response["printers"] = [Any]()
        return response
    }

    static func unsupportedKindResponse(request: [String: Any], kind: String) -> [String: Any] {
        var response = BridgeResponse.unavailable(
            request: request,
            action: "printerHelloWorld",
            message: "Printer kind '\(kind)' is not available on iOS in this demo build."
        )
        response["printerKind"] = kind
        response["printerLabel"] = selectedPrinterLabel(request, fallback: "Drucker")
        return response
    }

    static func string(_ value: Any?, fallback: String) -> String {
        if let raw = value as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? fallback : trimmed
        }
        return fallback
    }

    static func int(_ value: Any?, fallback: Int) -> Int {
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
