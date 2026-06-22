//
//  NativePersistenceBridge.swift
//  swiftHTMLWebviewApp
//
//  App-private persistence primitives exposed to web apps through the bridge.
//

import Foundation
import SQLite3

private enum NativePersistenceError: Error, LocalizedError {
    case invalidKey
    case invalidPath
    case invalidPayload(String)
    case filesystem(String)
    case sqlite(String)

    var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "A non-empty storage key is required."
        case .invalidPath:
            return "The path is invalid or escapes the app-private storage directory."
        case let .invalidPayload(message):
            return message
        case let .filesystem(message):
            return message
        case let .sqlite(message):
            return message
        }
    }
}

struct NativeStorageBridge {
    private let userDefaults: UserDefaults
    private let prefix = "native_storage_v1"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func get(request: [String: Any]) -> [String: Any] {
        do {
            let namespace = normalizedNamespace(request["namespace"])
            var response = BridgeResponse.base(request: request, action: "storageGet")
            response["success"] = true
            response["namespace"] = namespace
            if let key = try optionalKey(request["key"]) {
                response["key"] = key
                response["found"] = userDefaults.object(forKey: storageKey(namespace: namespace, key: key)) != nil
                response["value"] = userDefaults.object(forKey: storageKey(namespace: namespace, key: key)) ?? NSNull()
            } else {
                response["values"] = values(namespace: namespace)
            }
            return response
        } catch {
            return BridgeResponse.error(request: request, action: "storageGet", message: error.localizedDescription)
        }
    }

    func set(request: [String: Any]) -> [String: Any] {
        do {
            let namespace = normalizedNamespace(request["namespace"])
            let values = try valuesToSet(from: request)
            for (key, value) in values {
                try validateKey(key)
                if value is NSNull {
                    userDefaults.removeObject(forKey: storageKey(namespace: namespace, key: key))
                } else {
                    guard PropertyListSerialization.propertyList(value, isValidFor: .binary) else {
                        throw NativePersistenceError.invalidPayload("Storage values must be JSON/property-list compatible.")
                    }
                    userDefaults.set(value, forKey: storageKey(namespace: namespace, key: key))
                }
            }
            userDefaults.synchronize()
            var response = BridgeResponse.base(request: request, action: "storageSet")
            response["success"] = true
            response["namespace"] = namespace
            response["keys"] = Array(values.keys).sorted()
            response["values"] = self.values(namespace: namespace)
            return response
        } catch {
            return BridgeResponse.error(request: request, action: "storageSet", message: error.localizedDescription)
        }
    }

    func remove(request: [String: Any]) -> [String: Any] {
        do {
            let namespace = normalizedNamespace(request["namespace"])
            let keys = try keysToRemove(from: request)
            for key in keys {
                userDefaults.removeObject(forKey: storageKey(namespace: namespace, key: key))
            }
            userDefaults.synchronize()
            var response = BridgeResponse.base(request: request, action: "storageRemove")
            response["success"] = true
            response["namespace"] = namespace
            response["keys"] = keys
            response["values"] = values(namespace: namespace)
            return response
        } catch {
            return BridgeResponse.error(request: request, action: "storageRemove", message: error.localizedDescription)
        }
    }

    func clear(request: [String: Any]) -> [String: Any] {
        let namespace = normalizedNamespace(request["namespace"])
        for key in userDefaults.dictionaryRepresentation().keys where key.hasPrefix(storagePrefix(namespace: namespace)) {
            userDefaults.removeObject(forKey: key)
        }
        userDefaults.synchronize()
        var response = BridgeResponse.base(request: request, action: "storageClear")
        response["success"] = true
        response["namespace"] = namespace
        return response
    }

    private func valuesToSet(from request: [String: Any]) throws -> [String: Any] {
        if let values = request["values"] as? [String: Any] {
            return values
        }
        let key = try requiredKey(request["key"])
        return [key: request["value"] ?? NSNull()]
    }

    private func keysToRemove(from request: [String: Any]) throws -> [String] {
        if let keys = request["keys"] as? [String] {
            try keys.forEach(validateKey)
            return keys
        }
        return [try requiredKey(request["key"])]
    }

    private func optionalKey(_ value: Any?) throws -> String? {
        let key = stringValue(value).trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { return nil }
        try validateKey(key)
        return key
    }

    private func requiredKey(_ value: Any?) throws -> String {
        guard let key = try optionalKey(value) else {
            throw NativePersistenceError.invalidKey
        }
        return key
    }

    private func validateKey(_ key: String) throws {
        if key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || key.contains("\u{0}") {
            throw NativePersistenceError.invalidKey
        }
    }

    private func normalizedNamespace(_ value: Any?) -> String {
        let raw = stringValue(value).trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "default" : raw
    }

    private func storagePrefix(namespace: String) -> String {
        "\(prefix).\(namespace)."
    }

    private func storageKey(namespace: String, key: String) -> String {
        "\(storagePrefix(namespace: namespace))\(key)"
    }

    private func values(namespace: String) -> [String: Any] {
        let prefix = storagePrefix(namespace: namespace)
        var result: [String: Any] = [:]
        for (key, value) in userDefaults.dictionaryRepresentation() where key.hasPrefix(prefix) {
            result[String(key.dropFirst(prefix.count))] = value
        }
        return result
    }
}

struct NativeFilesystemBridge {
    enum Directory: String {
        case data
        case cache
        case temporary
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func write(request: [String: Any]) -> [String: Any] {
        do {
            let target = try resolvedURL(request: request)
            let data = try dataFromRequest(request)
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
            var response = success(request: request, action: "filesystemWrite", url: target)
            response["bytes"] = data.count
            return response
        } catch {
            return BridgeResponse.error(request: request, action: "filesystemWrite", message: error.localizedDescription)
        }
    }

    func read(request: [String: Any]) -> [String: Any] {
        do {
            let target = try resolvedURL(request: request)
            let data = try Data(contentsOf: target)
            var response = success(request: request, action: "filesystemRead", url: target)
            response["bytes"] = data.count
            if encoding(request) == "base64" {
                response["data"] = data.base64EncodedString()
                response["encoding"] = "base64"
            } else {
                response["data"] = String(data: data, encoding: .utf8) ?? ""
                response["encoding"] = "utf8"
            }
            return response
        } catch {
            return BridgeResponse.error(request: request, action: "filesystemRead", message: error.localizedDescription)
        }
    }

    func list(request: [String: Any]) -> [String: Any] {
        do {
            let target = try resolvedURL(request: request, allowMissingLeaf: true)
            let entries = try fileManager.contentsOfDirectory(at: target, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles])
            var response = success(request: request, action: "filesystemList", url: target)
            response["entries"] = entries.map { url in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                return [
                    "name": url.lastPathComponent,
                    "path": relativePath(for: url, directory: directory(request)),
                    "isDirectory": values?.isDirectory ?? false,
                    "size": values?.fileSize ?? 0
                ] as [String: Any]
            }
            return response
        } catch {
            return BridgeResponse.error(request: request, action: "filesystemList", message: error.localizedDescription)
        }
    }

    func delete(request: [String: Any]) -> [String: Any] {
        do {
            let target = try resolvedURL(request: request)
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            return success(request: request, action: "filesystemDelete", url: target)
        } catch {
            return BridgeResponse.error(request: request, action: "filesystemDelete", message: error.localizedDescription)
        }
    }

    private func dataFromRequest(_ request: [String: Any]) throws -> Data {
        let raw = stringValue(request["data"])
        if encoding(request) == "base64" {
            guard let data = Data(base64Encoded: raw) else {
                throw NativePersistenceError.invalidPayload("Invalid base64 payload.")
            }
            return data
        }
        return Data(raw.utf8)
    }

    private func encoding(_ request: [String: Any]) -> String {
        let value = stringValue(request["encoding"]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "base64" ? "base64" : "utf8"
    }

    private func directory(_ request: [String: Any]) -> Directory {
        Directory(rawValue: stringValue(request["directory"]).lowercased()) ?? .data
    }

    private func resolvedURL(request: [String: Any], allowMissingLeaf: Bool = false) throws -> URL {
        let base = try baseURL(for: directory(request))
        let path = stringValue(request["path"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let relative = path.isEmpty && allowMissingLeaf ? "." : path
        guard !relative.isEmpty, !relative.contains("\u{0}") else {
            throw NativePersistenceError.invalidPath
        }
        let target = base.appendingPathComponent(relative).standardizedFileURL
        guard target.path == base.path || target.path.hasPrefix(base.path + "/") else {
            throw NativePersistenceError.invalidPath
        }
        return target
    }

    private func baseURL(for directory: Directory) throws -> URL {
        switch directory {
        case .data:
            let url = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("NativeBridgeFiles", isDirectory: true)
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return url.standardizedFileURL
        case .cache:
            let url = try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("NativeBridgeFiles", isDirectory: true)
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return url.standardizedFileURL
        case .temporary:
            let url = fileManager.temporaryDirectory.appendingPathComponent("NativeBridgeFiles", isDirectory: true)
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return url.standardizedFileURL
        }
    }

    private func relativePath(for url: URL, directory: Directory) -> String {
        guard let base = try? baseURL(for: directory) else {
            return url.lastPathComponent
        }
        return String(url.path.dropFirst(base.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func success(request: [String: Any], action: String, url: URL) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: action)
        response["success"] = true
        response["directory"] = directory(request).rawValue
        response["path"] = relativePath(for: url, directory: directory(request))
        return response
    }
}

final class NativeSQLiteBridge {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func execute(request: [String: Any]) -> [String: Any] {
        do {
            let dbURL = try databaseURL(request: request)
            try fileManager.createDirectory(at: dbURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let database = try openDatabase(at: dbURL)
            defer { sqlite3_close(database) }

            let sql = stringValue(request["sql"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sql.isEmpty else {
                throw NativePersistenceError.sqlite("SQL must not be empty.")
            }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw NativePersistenceError.sqlite(errorMessage(database))
            }
            defer { sqlite3_finalize(statement) }

            try bind(arguments: request["args"] as? [Any] ?? [], to: statement)

            var rows: [[String: Any]] = []
            while true {
                let step = sqlite3_step(statement)
                if step == SQLITE_ROW {
                    rows.append(row(statement: statement))
                } else if step == SQLITE_DONE {
                    break
                } else {
                    throw NativePersistenceError.sqlite(errorMessage(database))
                }
            }

            var response = BridgeResponse.base(request: request, action: "sqliteExecute")
            response["success"] = true
            response["database"] = dbURL.lastPathComponent
            response["rows"] = rows
            response["changes"] = Int(sqlite3_changes(database))
            response["lastInsertRowId"] = Int(sqlite3_last_insert_rowid(database))
            return response
        } catch {
            return BridgeResponse.error(request: request, action: "sqliteExecute", message: error.localizedDescription)
        }
    }

    func deleteDatabase(request: [String: Any]) -> [String: Any] {
        do {
            let dbURL = try databaseURL(request: request)
            if fileManager.fileExists(atPath: dbURL.path) {
                try fileManager.removeItem(at: dbURL)
            }
            var response = BridgeResponse.base(request: request, action: "sqliteDeleteDatabase")
            response["success"] = true
            response["database"] = dbURL.lastPathComponent
            return response
        } catch {
            return BridgeResponse.error(request: request, action: "sqliteDeleteDatabase", message: error.localizedDescription)
        }
    }

    private func databaseURL(request: [String: Any]) throws -> URL {
        let rawName = stringValue(request["database"] ?? request["name"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let name = rawName.isEmpty ? "default.sqlite" : rawName
        guard !name.contains("/") && !name.contains("\\") && !name.contains("\u{0}") else {
            throw NativePersistenceError.invalidPath
        }
        let filename = name.hasSuffix(".sqlite") || name.hasSuffix(".db") ? name : "\(name).sqlite"
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("NativeBridgeSQLite", isDirectory: true)
        return base.appendingPathComponent(filename)
    }

    private func openDatabase(at url: URL) throws -> OpaquePointer? {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            defer { sqlite3_close(database) }
            throw NativePersistenceError.sqlite(errorMessage(database))
        }
        return database
    }

    private func bind(arguments: [Any], to statement: OpaquePointer?) throws {
        for (index, argument) in arguments.enumerated() {
            let position = Int32(index + 1)
            switch argument {
            case is NSNull:
                sqlite3_bind_null(statement, position)
            case let value as Int:
                sqlite3_bind_int64(statement, position, sqlite3_int64(value))
            case let value as Int64:
                sqlite3_bind_int64(statement, position, sqlite3_int64(value))
            case let value as Double:
                sqlite3_bind_double(statement, position, value)
            case let value as Bool:
                sqlite3_bind_int(statement, position, value ? 1 : 0)
            case let value as Data:
                _ = value.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, position, bytes.baseAddress, Int32(value.count), SQLITE_TRANSIENT)
                }
            default:
                sqlite3_bind_text(statement, position, stringValue(argument), -1, SQLITE_TRANSIENT)
            }
        }
    }

    private func row(statement: OpaquePointer?) -> [String: Any] {
        var result: [String: Any] = [:]
        for index in 0..<sqlite3_column_count(statement) {
            let name = String(cString: sqlite3_column_name(statement, index))
            switch sqlite3_column_type(statement, index) {
            case SQLITE_INTEGER:
                result[name] = Int(sqlite3_column_int64(statement, index))
            case SQLITE_FLOAT:
                result[name] = sqlite3_column_double(statement, index)
            case SQLITE_TEXT:
                if let text = sqlite3_column_text(statement, index) {
                    result[name] = String(cString: UnsafeRawPointer(text).assumingMemoryBound(to: CChar.self))
                } else {
                    result[name] = ""
                }
            case SQLITE_BLOB:
                let bytes = sqlite3_column_blob(statement, index)
                let count = Int(sqlite3_column_bytes(statement, index))
                if let bytes, count > 0 {
                    result[name] = Data(bytes: bytes, count: count).base64EncodedString()
                } else {
                    result[name] = ""
                }
            default:
                result[name] = NSNull()
            }
        }
        return result
    }

    private func errorMessage(_ database: OpaquePointer?) -> String {
        if let message = sqlite3_errmsg(database) {
            return String(cString: message)
        }
        return "SQLite operation failed."
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
