//
//  NativePersistenceBridgeTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class NativePersistenceBridgeTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "NativePersistenceBridgeTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testStorageBridgePersistsNamespacedJSONValues() {
        let bridge = NativeStorageBridge(userDefaults: defaults)

        let set = bridge.set(request: [
            "action": "storageSet",
            "namespace": "demo",
            "key": "station",
            "value": [
                "name": "Terminal 1",
                "counter": 2
            ]
        ])
        let get = bridge.get(request: [
            "action": "storageGet",
            "namespace": "demo",
            "key": "station"
        ])

        XCTAssertEqual(set["success"] as? Bool, true)
        XCTAssertEqual(get["found"] as? Bool, true)
        let value = get["value"] as? [String: Any]
        XCTAssertEqual(value?["name"] as? String, "Terminal 1")
        XCTAssertEqual(value?["counter"] as? Int, 2)
    }

    func testFilesystemBridgeWritesReadsAndDeletesPrivateFiles() {
        let bridge = NativeFilesystemBridge()
        let path = "tests/\(UUID().uuidString)/state.json"

        let write = bridge.write(request: [
            "action": "filesystemWrite",
            "directory": "temporary",
            "path": path,
            "data": "{\"ok\":true}",
            "encoding": "utf8"
        ])
        let read = bridge.read(request: [
            "action": "filesystemRead",
            "directory": "temporary",
            "path": path,
            "encoding": "utf8"
        ])
        let delete = bridge.delete(request: [
            "action": "filesystemDelete",
            "directory": "temporary",
            "path": path
        ])

        XCTAssertEqual(write["success"] as? Bool, true)
        XCTAssertEqual(read["data"] as? String, "{\"ok\":true}")
        XCTAssertEqual(delete["success"] as? Bool, true)
    }

    func testSQLiteBridgeExecutesParameterizedStatements() {
        let bridge = NativeSQLiteBridge()
        let database = "test-\(UUID().uuidString).sqlite"

        let create = bridge.execute(request: [
            "action": "sqliteExecute",
            "database": database,
            "sql": "CREATE TABLE IF NOT EXISTS demo_store (key TEXT PRIMARY KEY, value TEXT NOT NULL)"
        ])
        let insert = bridge.execute(request: [
            "action": "sqliteExecute",
            "database": database,
            "sql": "INSERT INTO demo_store (key, value) VALUES (?, ?)",
            "args": ["station", "Terminal 1"]
        ])
        let select = bridge.execute(request: [
            "action": "sqliteExecute",
            "database": database,
            "sql": "SELECT key, value FROM demo_store WHERE key = ?",
            "args": ["station"]
        ])
        let delete = bridge.deleteDatabase(request: [
            "action": "sqliteDeleteDatabase",
            "database": database
        ])

        XCTAssertEqual(create["success"] as? Bool, true)
        XCTAssertEqual(insert["success"] as? Bool, true)
        XCTAssertEqual(delete["success"] as? Bool, true)
        let rows = select["rows"] as? [[String: Any]]
        XCTAssertEqual(rows?.first?["value"] as? String, "Terminal 1")
    }
}
