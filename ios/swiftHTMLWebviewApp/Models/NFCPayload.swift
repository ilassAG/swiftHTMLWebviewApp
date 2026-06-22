//
//  NFCPayload.swift
//  swiftHTMLWebviewApp
//
//  Pure response and NDEF payload helpers for NFC tag reads.
//

import Foundation

enum NFCPayload {
    enum TypeNameFormat: Int {
        case empty = 0
        case nfcWellKnown = 1
        case media = 2
        case absoluteURI = 3
        case nfcExternal = 4
        case unknown = 5
        case unchanged = 6
    }

    struct TextRecord {
        let text: String
        let languageCode: String
        let encoding: String
    }

    struct RecordInput {
        let index: Int
        let typeNameFormatRawValue: Int
        let type: Data
        let identifier: Data
        let payload: Data
        let uri: String?
        let mimeType: String?

        init(
            index: Int,
            typeNameFormatRawValue: Int,
            type: Data,
            identifier: Data,
            payload: Data,
            uri: String? = nil,
            mimeType: String? = nil
        ) {
            self.index = index
            self.typeNameFormatRawValue = typeNameFormatRawValue
            self.type = type
            self.identifier = identifier
            self.payload = payload
            self.uri = uri
            self.mimeType = mimeType
        }

        var typeNameFormat: TypeNameFormat? {
            TypeNameFormat(rawValue: typeNameFormatRawValue)
        }
    }

    static func successResponse(request: [String: Any]) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "nfcTagRead")
        response["success"] = true
        return response
    }

    static func errorResponse(request: [String: Any], error: String?) -> [String: Any] {
        BridgeResponse.error(request: request, action: "nfcTagRead", message: error ?? "Unknown NFC error.")
    }

    static func tagPayload(type: String, identifier: Data, extra: [String: Any] = [:]) -> [String: Any] {
        var payload: [String: Any] = [
            "type": type,
            "identifierHex": hex(identifier),
            "identifierBase64": identifier.base64EncodedString()
        ]
        extra.forEach { key, value in
            payload[key] = value
        }
        return payload
    }

    static func ndefUnavailablePayload(status: String = "notSupported", capacityBytes: Int? = nil) -> [String: Any] {
        var payload: [String: Any] = [
            "available": false,
            "status": status,
            "messages": [],
            "records": []
        ]
        if let capacityBytes {
            payload["capacityBytes"] = capacityBytes
        }
        return payload
    }

    static func ndefPayload(status: String, capacityBytes: Int, messages: [[RecordInput]]) -> [String: Any] {
        let messagePayloads = messages.map { records in
            messagePayload(records: records.map(recordPayload))
        }
        let records = messages.flatMap { $0 }.map(recordPayload)
        return [
            "available": true,
            "status": status,
            "capacityBytes": capacityBytes,
            "messageCount": messagePayloads.count,
            "recordCount": records.count,
            "messages": messagePayloads,
            "records": records
        ]
    }

    static func messagePayload(records: [[String: Any]]) -> [String: Any] {
        [
            "recordCount": records.count,
            "records": records
        ]
    }

    static func recordPayload(_ record: RecordInput) -> [String: Any] {
        var payload: [String: Any] = [
            "index": record.index,
            "typeNameFormat": typeNameFormatName(rawValue: record.typeNameFormatRawValue),
            "typeNameFormatRawValue": record.typeNameFormatRawValue,
            "type": stringOrHex(record.type),
            "typeHex": hex(record.type),
            "identifier": stringOrHex(record.identifier),
            "identifierHex": hex(record.identifier),
            "payloadBase64": record.payload.base64EncodedString(),
            "payloadHex": hex(record.payload)
        ]

        if let text = decodeTextRecord(
            tnfRawValue: record.typeNameFormatRawValue,
            type: record.type,
            payload: record.payload
        ) {
            payload["text"] = text.text
            payload["languageCode"] = text.languageCode
            payload["encoding"] = text.encoding
        } else if let utf8 = String(data: record.payload, encoding: .utf8), !utf8.isEmpty {
            payload["text"] = utf8
        }

        if let uri = record.uri ?? decodeURIRecord(
            tnfRawValue: record.typeNameFormatRawValue,
            type: record.type,
            payload: record.payload
        ) {
            payload["uri"] = uri
        }

        if let mimeType = record.mimeType, !mimeType.isEmpty {
            payload["mimeType"] = mimeType
        } else if record.typeNameFormat == .media,
                  let mimeType = String(data: record.type, encoding: .utf8),
                  !mimeType.isEmpty {
            payload["mimeType"] = mimeType
        }
        return payload
    }

    static func decodeTextRecord(tnfRawValue: Int, type: Data, payload: Data) -> TextRecord? {
        guard TypeNameFormat(rawValue: tnfRawValue) == .nfcWellKnown,
              String(data: type, encoding: .utf8) == "T",
              payload.count >= 1 else { return nil }
        let bytes = [UInt8](payload)
        let status = bytes[0]
        let isUTF16 = (status & 0x80) != 0
        let languageLength = Int(status & 0x3f)
        guard bytes.count >= 1 + languageLength else { return nil }
        let languageData = Data(bytes[1..<(1 + languageLength)])
        let textData = Data(bytes[(1 + languageLength)..<bytes.count])
        let encoding: String.Encoding = isUTF16 ? .utf16 : .utf8
        guard let text = String(data: textData, encoding: encoding) else { return nil }
        return TextRecord(
            text: text,
            languageCode: String(data: languageData, encoding: .ascii) ?? "",
            encoding: isUTF16 ? "utf16" : "utf8"
        )
    }

    static func decodeURIRecord(tnfRawValue: Int, type: Data, payload: Data) -> String? {
        guard TypeNameFormat(rawValue: tnfRawValue) == .nfcWellKnown,
              String(data: type, encoding: .utf8) == "U",
              payload.count >= 1 else { return nil }
        let bytes = [UInt8](payload)
        let prefix = uriPrefix(Int(bytes[0]))
        let rest = String(data: Data(bytes.dropFirst()), encoding: .utf8) ?? ""
        return prefix + rest
    }

    static func typeNameFormatName(rawValue: Int) -> String {
        switch TypeNameFormat(rawValue: rawValue) {
        case .empty: return "empty"
        case .nfcWellKnown: return "nfcWellKnown"
        case .media: return "media"
        case .absoluteURI: return "absoluteURI"
        case .nfcExternal: return "nfcExternal"
        case .unknown: return "unknown"
        case .unchanged: return "unchanged"
        case nil: return "unknown"
        }
    }

    static func stringOrHex(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }
        return hex(data)
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }

    static func uriPrefix(_ code: Int) -> String {
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
