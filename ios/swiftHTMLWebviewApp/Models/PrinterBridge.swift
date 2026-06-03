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
    func printEpsonHelloWorld(
        request: [String: Any],
        completion: @escaping ([String: Any]) -> Void
    ) {
        printEpsonHelloWorld(request: request, responseAction: "printerEpsonHelloWorld", completion: completion)
    }

    func printHelloWorld(
        request: [String: Any],
        completion: @escaping ([String: Any]) -> Void
    ) {
        let kind = selectedPrinterKind(request)
        guard kind == "epson_epos_xml" else {
            var response = baseResponse(request: request, action: "printerHelloWorld")
            response["success"] = false
            response["available"] = false
            response["printerKind"] = kind
            response["printerLabel"] = selectedPrinterLabel(request, fallback: "Drucker")
            response["error"] = "Printer kind '\(kind)' is not available on iOS in this demo build."
            completion(response)
            return
        }

        printEpsonHelloWorld(request: request, responseAction: "printerHelloWorld", completion: completion)
    }

    private func printEpsonHelloWorld(
        request: [String: Any],
        responseAction: String,
        completion: @escaping ([String: Any]) -> Void
    ) {
        #if canImport(Printercore)
        let host = stringValue(request["host"], fallback: "")
        let devid = stringValue(request["devid"], fallback: "local_printer")
        let timeoutMs = intValue(request["timeoutMs"], fallback: 20_000)
        let title = stringValue(request["title"], fallback: "Hallo Welt")
        let subtitle = stringValue(request["subtitle"], fallback: "swiftHTMLWebviewApp")
        let body = stringValue(request["body"], fallback: "iOS bridge test")

        DispatchQueue.global(qos: .userInitiated).async {
            var response = self.baseResponse(request: request, action: responseAction)
            response["host"] = host
            response["devid"] = devid
            response["printerKind"] = "epson_epos_xml"
            response["printerLabel"] = self.selectedPrinterLabel(request, fallback: "Epson ePOS-Print")
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
        var response = baseResponse(request: request, action: responseAction)
        response["success"] = false
        response["available"] = false
        response["error"] = "Printercore.xcframework is not linked in this build."
        completion(response)
        #endif
    }

    func discoverPrinters(
        request: [String: Any],
        completion: @escaping ([String: Any]) -> Void
    ) {
        #if canImport(Printercore)
        let optionsJSON = jsonString(from: request)

        DispatchQueue.global(qos: .userInitiated).async {
            var response = self.baseResponse(request: request, action: "printerDiscover")
            response["goCoreVersion"] = PMPrintercoreCoreVersion()

            let coreJson = PMPrintercoreDiscoverPrinters(optionsJSON)
            let coreResponse = self.parseCoreResponse(coreJson)
            coreResponse.forEach { key, value in
                response[key] = value
            }

            DispatchQueue.main.async {
                completion(response)
            }
        }
        #else
        var response = baseResponse(request: request, action: "printerDiscover")
        response["success"] = false
        response["available"] = false
        response["printers"] = [Any]()
        response["error"] = "Printercore.xcframework is not linked in this build."
        completion(response)
        #endif
    }

    private func baseResponse(request: [String: Any], action: String) -> [String: Any] {
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

    private func jsonString(from request: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(request),
              let data = try? JSONSerialization.data(withJSONObject: request),
              let raw = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return raw
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

    private func selectedPrinterKind(_ request: [String: Any]) -> String {
        let directKind = stringValue(request["kind"], fallback: "")
        if !directKind.isEmpty {
            return directKind
        }
        if let printer = request["printer"] as? [String: Any] {
            let nestedKind = stringValue(printer["kind"], fallback: "")
            if !nestedKind.isEmpty {
                return nestedKind
            }
        }
        return "epson_epos_xml"
    }

    private func selectedPrinterLabel(_ request: [String: Any], fallback: String) -> String {
        if let printer = request["printer"] as? [String: Any] {
            let label = stringValue(printer["label"], fallback: "")
            if !label.isEmpty {
                return label
            }
        }
        return fallback
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
