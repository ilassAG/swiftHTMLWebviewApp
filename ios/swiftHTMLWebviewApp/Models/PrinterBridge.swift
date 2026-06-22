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
        let kind = PrinterPayload.selectedPrinterKind(request)
        guard kind == "epson_epos_xml" else {
            completion(PrinterPayload.unsupportedKindResponse(request: request, kind: kind))
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
        let job = PrinterPayload.epsonRequest(from: request)

        DispatchQueue.global(qos: .userInitiated).async {
            let coreJson = PMPrintercorePrintEpsonHelloWorld(
                job.host,
                job.devid,
                job.timeoutMs,
                job.title,
                job.subtitle,
                job.body
            )
            let coreResponse = PrinterPayload.coreResponse(from: coreJson)
            let response = PrinterPayload.epsonJobResponse(
                request: request,
                action: responseAction,
                job: job,
                core: coreResponse,
                goCoreVersion: PMPrintercoreCoreVersion(),
                printerLabel: PrinterPayload.selectedPrinterLabel(request, fallback: "Epson ePOS-Print")
            )

            DispatchQueue.main.async {
                completion(response)
            }
        }
        #else
        completion(PrinterPayload.printercoreUnavailable(request: request, action: responseAction))
        #endif
    }

    func discoverPrinters(
        request: [String: Any],
        completion: @escaping ([String: Any]) -> Void
    ) {
        #if canImport(Printercore)
        let optionsJSON = PrinterPayload.discoveryOptionsJSON(from: request)

        DispatchQueue.global(qos: .userInitiated).async {
            var response = BridgeResponse.base(request: request, action: "printerDiscover")
            response["goCoreVersion"] = PMPrintercoreCoreVersion()

            let coreJson = PMPrintercoreDiscoverPrinters(optionsJSON)
            let coreResponse = PrinterPayload.coreResponse(from: coreJson)
            coreResponse.forEach { key, value in
                response[key] = value
            }

            DispatchQueue.main.async {
                completion(response)
            }
        }
        #else
        completion(PrinterPayload.discoveryUnavailable(request: request))
        #endif
    }
}
