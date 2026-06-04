//
//  NFCTagReaderBridge.swift
//  swiftHTMLWebviewApp
//
//  One-shot CoreNFC tag reader for the JavaScript bridge.
//

import CoreNFC
import Foundation

final class NFCTagReaderBridge: NSObject, ObservableObject {
    private var session: NFCTagReaderSession?
    private var request: [String: Any] = [:]
    private var completion: (([String: Any]) -> Void)?
    private var timeoutWorkItem: DispatchWorkItem?
    private var completed = false

    @MainActor
    func read(request: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        guard NFCTagReaderSession.readingAvailable else {
            completion(errorResponse(request: request, error: "NFC tag reading is not available on this device."))
            return
        }
        guard session == nil else {
            completion(errorResponse(request: request, error: "An NFC tag read session is already active."))
            return
        }

        self.request = request
        self.completion = completion
        self.completed = false

        // FeliCa / ISO 18092 polling needs additional system-code entitlements.
        // Keep the default reader focused on common NFC/NDEF tags that are covered
        // by the NDEF + TAG reader-session formats entitlement.
        let polling: NFCTagReaderSession.PollingOption = [.iso14443, .iso15693]
        guard let session = NFCTagReaderSession(pollingOption: polling, delegate: self, queue: .main) else {
            completion(errorResponse(request: request, error: "Could not create an NFC tag reader session."))
            return
        }
        session.alertMessage = stringValue(request["message"]).isEmpty
            ? "NFC-Tag an die obere Kante des iPhones halten."
            : stringValue(request["message"])
        self.session = session
        scheduleTimeout(seconds: doubleValue(request["timeoutSeconds"]) ?? (doubleValue(request["timeoutMs"]).map { $0 / 1000.0 } ?? 0))
        session.begin()
    }

    @MainActor
    func shutdown() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        session?.invalidate()
        session = nil
        request = [:]
        completion = nil
        completed = false
    }

    private func scheduleTimeout(seconds: Double) {
        timeoutWorkItem?.cancel()
        guard seconds > 0 else { return }
        let timeout = min(max(seconds, 1), 60)
        let workItem = DispatchWorkItem { [weak self] in
            self?.session?.invalidate(errorMessage: "NFC scan timed out.")
        }
        timeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    private func handle(tag: NFCTag, session: NFCTagReaderSession) {
        let tagInfo = tagPayload(tag)
        guard let ndefTag = ndefTag(for: tag) else {
            var response = successResponse()
            response["tag"] = tagInfo
            response["ndef"] = [
                "available": false,
                "status": "notSupported",
                "messages": [],
                "records": []
            ]
            complete(response: response, alertMessage: "NFC-Tag gelesen.")
            return
        }

        ndefTag.queryNDEFStatus { [weak self] status, capacity, error in
            guard let self else { return }
            if let error {
                self.complete(response: self.errorResponse(error: error.localizedDescription), alertMessage: "NFC-Tag konnte nicht gelesen werden.")
                return
            }

            if status == .notSupported {
                var response = self.successResponse()
                var enrichedTag = tagInfo
                enrichedTag["ndefAvailable"] = false
                response["tag"] = enrichedTag
                response["ndef"] = [
                    "available": false,
                    "status": self.ndefStatusName(status),
                    "capacityBytes": capacity,
                    "messages": [],
                    "records": []
                ]
                self.complete(response: response, alertMessage: "NFC-Tag gelesen.")
                return
            }

            ndefTag.readNDEF { message, error in
                if let error {
                    self.complete(response: self.errorResponse(error: error.localizedDescription), alertMessage: "NDEF-Daten konnten nicht gelesen werden.")
                    return
                }

                var response = self.successResponse()
                var enrichedTag = tagInfo
                enrichedTag["ndefAvailable"] = true
                enrichedTag["ndefWritable"] = status == .readWrite
                enrichedTag["ndefStatus"] = self.ndefStatusName(status)
                enrichedTag["ndefCapacityBytes"] = capacity
                response["tag"] = enrichedTag
                response["ndef"] = self.ndefPayload(message: message, status: status, capacity: capacity)
                self.complete(response: response, alertMessage: "NFC-Tag gelesen.")
            }
        }
    }

    private func complete(response: [String: Any], alertMessage: String) {
        DispatchQueue.main.async {
            guard !self.completed else { return }
            self.completed = true
            self.timeoutWorkItem?.cancel()
            self.timeoutWorkItem = nil
            self.session?.alertMessage = alertMessage
            self.session?.invalidate()
            self.session = nil
            let completion = self.completion
            self.completion = nil
            self.request = [:]
            completion?(response)
        }
    }

    private func ndefTag(for tag: NFCTag) -> NFCNDEFTag? {
        switch tag {
        case .miFare(let tag): return tag
        case .iso7816(let tag): return tag
        case .iso15693(let tag): return tag
        case .feliCa(let tag): return tag
        @unknown default: return nil
        }
    }

    private func tagPayload(_ tag: NFCTag) -> [String: Any] {
        var payload: [String: Any] = [:]
        switch tag {
        case .miFare(let tag):
            payload["type"] = "miFare"
            payload["identifierHex"] = hex(tag.identifier)
            payload["identifierBase64"] = tag.identifier.base64EncodedString()
            payload["mifareFamily"] = mifareFamilyName(tag.mifareFamily)
            if let historicalBytes = tag.historicalBytes {
                payload["historicalBytesHex"] = hex(historicalBytes)
                payload["historicalBytesBase64"] = historicalBytes.base64EncodedString()
            }
        case .iso7816(let tag):
            payload["type"] = "iso7816"
            payload["identifierHex"] = hex(tag.identifier)
            payload["identifierBase64"] = tag.identifier.base64EncodedString()
            payload["initialSelectedAID"] = tag.initialSelectedAID
            if let applicationData = tag.applicationData {
                payload["applicationDataHex"] = hex(applicationData)
                payload["applicationDataBase64"] = applicationData.base64EncodedString()
            }
            if let historicalBytes = tag.historicalBytes {
                payload["historicalBytesHex"] = hex(historicalBytes)
                payload["historicalBytesBase64"] = historicalBytes.base64EncodedString()
            }
        case .iso15693(let tag):
            payload["type"] = "iso15693"
            payload["identifierHex"] = hex(tag.identifier)
            payload["identifierBase64"] = tag.identifier.base64EncodedString()
            payload["icManufacturerCode"] = tag.icManufacturerCode
            payload["icSerialNumberHex"] = hex(tag.icSerialNumber)
            payload["icSerialNumberBase64"] = tag.icSerialNumber.base64EncodedString()
        case .feliCa(let tag):
            payload["type"] = "feliCa"
            payload["identifierHex"] = hex(tag.currentIDm)
            payload["identifierBase64"] = tag.currentIDm.base64EncodedString()
            payload["systemCodeHex"] = hex(tag.currentSystemCode)
            payload["systemCodeBase64"] = tag.currentSystemCode.base64EncodedString()
        @unknown default:
            payload["type"] = "unknown"
        }
        return payload
    }

    private func ndefPayload(message: NFCNDEFMessage?, status: NFCNDEFStatus, capacity: Int) -> [String: Any] {
        let messages = message.map { [messagePayload($0)] } ?? []
        let records = message?.records.enumerated().map { index, record in
            recordPayload(record, index: index)
        } ?? []
        return [
            "available": true,
            "status": ndefStatusName(status),
            "capacityBytes": capacity,
            "messageCount": messages.count,
            "recordCount": records.count,
            "messages": messages,
            "records": records
        ]
    }

    private func messagePayload(_ message: NFCNDEFMessage) -> [String: Any] {
        [
            "recordCount": message.records.count,
            "records": message.records.enumerated().map { index, record in
                recordPayload(record, index: index)
            }
        ]
    }

    private func recordPayload(_ record: NFCNDEFPayload, index: Int) -> [String: Any] {
        var payload: [String: Any] = [
            "index": index,
            "typeNameFormat": typeNameFormatName(record.typeNameFormat),
            "typeNameFormatRawValue": Int(record.typeNameFormat.rawValue),
            "type": stringOrHex(record.type),
            "typeHex": hex(record.type),
            "identifier": stringOrHex(record.identifier),
            "identifierHex": hex(record.identifier),
            "payloadBase64": record.payload.base64EncodedString(),
            "payloadHex": hex(record.payload)
        ]

        if let text = decodeTextRecord(record) {
            payload["text"] = text.text
            payload["languageCode"] = text.languageCode
            payload["encoding"] = text.encoding
        } else if let utf8 = String(data: record.payload, encoding: .utf8), !utf8.isEmpty {
            payload["text"] = utf8
        }
        if let uri = decodeURIRecord(record) {
            payload["uri"] = uri
        }
        if record.typeNameFormat == .media,
           let mimeType = String(data: record.type, encoding: .utf8),
           !mimeType.isEmpty {
            payload["mimeType"] = mimeType
        }
        return payload
    }

    private func decodeTextRecord(_ record: NFCNDEFPayload) -> (text: String, languageCode: String, encoding: String)? {
        guard record.typeNameFormat == .nfcWellKnown,
              String(data: record.type, encoding: .utf8) == "T",
              record.payload.count >= 1 else { return nil }
        let bytes = [UInt8](record.payload)
        let status = bytes[0]
        let isUTF16 = (status & 0x80) != 0
        let languageLength = Int(status & 0x3f)
        guard bytes.count >= 1 + languageLength else { return nil }
        let languageData = Data(bytes[1..<(1 + languageLength)])
        let textData = Data(bytes[(1 + languageLength)..<bytes.count])
        let encoding: String.Encoding = isUTF16 ? .utf16 : .utf8
        guard let text = String(data: textData, encoding: encoding) else { return nil }
        return (
            text: text,
            languageCode: String(data: languageData, encoding: .ascii) ?? "",
            encoding: isUTF16 ? "utf16" : "utf8"
        )
    }

    private func decodeURIRecord(_ record: NFCNDEFPayload) -> String? {
        guard record.typeNameFormat == .nfcWellKnown,
              String(data: record.type, encoding: .utf8) == "U",
              record.payload.count >= 1 else { return nil }
        let bytes = [UInt8](record.payload)
        let prefix = uriPrefix(Int(bytes[0]))
        let rest = String(data: Data(bytes.dropFirst()), encoding: .utf8) ?? ""
        return prefix + rest
    }

    private func successResponse() -> [String: Any] {
        var response = baseResponse()
        response["success"] = true
        return response
    }

    private func errorResponse(error: String) -> [String: Any] {
        errorResponse(request: request, error: error)
    }

    private func errorResponse(request: [String: Any], error: String) -> [String: Any] {
        var response: [String: Any] = [
            "platform": "ios",
            "action": "nfcTagRead",
            "success": false,
            "error": error
        ]
        if let requestId = request["requestId"] {
            response["requestId"] = requestId
        }
        return response
    }

    private func baseResponse() -> [String: Any] {
        var response: [String: Any] = [
            "platform": "ios",
            "action": "nfcTagRead"
        ]
        if let requestId = request["requestId"] {
            response["requestId"] = requestId
        }
        return response
    }

    private func ndefStatusName(_ status: NFCNDEFStatus) -> String {
        switch status {
        case .notSupported: return "notSupported"
        case .readOnly: return "readOnly"
        case .readWrite: return "readWrite"
        @unknown default: return "unknown"
        }
    }

    private func typeNameFormatName(_ value: NFCTypeNameFormat) -> String {
        switch value {
        case .empty: return "empty"
        case .nfcWellKnown: return "nfcWellKnown"
        case .media: return "media"
        case .absoluteURI: return "absoluteURI"
        case .nfcExternal: return "nfcExternal"
        case .unknown: return "unknown"
        case .unchanged: return "unchanged"
        @unknown default: return "unknown"
        }
    }

    private func mifareFamilyName(_ family: NFCMiFareFamily) -> String {
        switch family {
        case .unknown: return "unknown"
        case .ultralight: return "ultralight"
        case .plus: return "plus"
        case .desfire: return "desfire"
        @unknown default: return "unknown"
        }
    }

    private func stringOrHex(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }
        return hex(data)
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }

    private func uriPrefix(_ code: Int) -> String {
        let prefixes = [
            "", "http://www.", "https://www.", "http://", "https://", "tel:",
            "mailto:", "ftp://anonymous:anonymous@", "ftp://ftp.", "ftps://",
            "sftp://", "smb://", "nfs://", "ftp://", "dav://", "news:",
            "telnet://", "imap:", "rtsp://", "urn:", "pop:", "sip:", "sips:",
            "tftp:", "btspp://", "btl2cap://", "btgoep://", "tcpobex://",
            "irdaobex://", "file://", "urn:epc:id:", "urn:epc:tag:",
            "urn:epc:pat:", "urn:epc:raw:", "urn:epc:", "urn:nfc:"
        ]
        return prefixes.indices.contains(code) ? prefixes[code] : ""
    }
}

extension NFCTagReaderBridge: NFCTagReaderSessionDelegate {
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        session.alertMessage = stringValue(request["message"]).isEmpty
            ? "NFC-Tag an die obere Kante des iPhones halten."
            : stringValue(request["message"])
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        DispatchQueue.main.async {
            guard !self.completed else { return }
            self.timeoutWorkItem?.cancel()
            self.timeoutWorkItem = nil
            self.session = nil
            let completion = self.completion
            self.completion = nil
            let nsError = error as NSError
            var response = self.errorResponse(error: error.localizedDescription)
            if nsError.domain == NFCReaderError.errorDomain
                && nsError.code == NFCReaderError.readerSessionInvalidationErrorUserCanceled.rawValue {
                response["cancelled"] = true
                response["error"] = "NFC tag reading was cancelled."
            }
            self.request = [:]
            completion?(response)
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard tags.count == 1, let tag = tags.first else {
            session.alertMessage = "Bitte nur einen NFC-Tag gleichzeitig halten."
            session.restartPolling()
            return
        }

        session.connect(to: tag) { [weak self] error in
            guard let self else { return }
            if let error {
                self.complete(response: self.errorResponse(error: error.localizedDescription), alertMessage: "NFC-Tag konnte nicht verbunden werden.")
                return
            }
            self.handle(tag: tag, session: session)
        }
    }
}
