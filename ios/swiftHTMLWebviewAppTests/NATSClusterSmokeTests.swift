//
//  NATSClusterSmokeTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

#if canImport(Nats)
import Nats
#endif

@MainActor
final class NATSClusterSmokeTests: XCTestCase {
    func testBridgeConnectsHandlesCommandAndPublishesAgainstRealClusterWhenConfigured() async throws {
        #if canImport(Nats)
        let credential = try smokeCredential()
        try XCTSkipUnless(!credential.isEmpty, "Set NATS_SMOKE_CREDS_B64 or NATS_SMOKE_CREDS_PATH to run this smoke test.")
        let urls = smokeURLs()
        try XCTSkipUnless(!urls.isEmpty, "Set NATS_SMOKE_URLS to run this smoke test.")

        let suiteName = "NATSClusterSmokeTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults suite.")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(userDefaults: defaults, variant: .demo)
        settings.registerDefaults()
        settings.natsConfiguration.enabled = true
        settings.natsConfiguration.urls = urls
        settings.natsConfiguration.authMethod = .creds
        settings.natsConfiguration.clientNameTemplate = "swift-wrapper-ios-smoke-${appUUID}"

        let store = StaticCredentialStore(credential: credential)
        let bridge = NATSBridge(
            settings: settings,
            credentialStore: store,
            connection: NATSSwiftConnectionDriver()
        )
        bridge.configureCommandExecutor { command, completion in
            completion([
                "action": stringValue(command["action"]),
                "requestId": stringValue(command["requestId"]),
                "success": true,
                "platform": "ios"
            ])
        }

        let connected = bridge.connect(request: ["requestId": "ios-smoke-connect"])
        XCTAssertEqual(connected["success"] as? Bool, true, "\(connected)")

        let credentialFile = try writeTemporaryCredentialFile(credential)
        let control = try makeControlClient(urls: settings.natsConfiguration.urls, credentialFile: credentialFile)
        do {
            try await control.connect()
            let subject = "\(settings.natsConfiguration.devicePrefix(appUUID: settings.appUUIDString)).commands.status"
            let reply = try await control.request(
                Data("{\"requestId\":\"ios-smoke-command\"}".utf8),
                subject: subject,
                timeout: 8
            )
            let data = try XCTUnwrap(reply.payload)
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(payload["action"] as? String, "deviceInfoGet")
            XCTAssertEqual(payload["success"] as? Bool, true)
            XCTAssertEqual(payload["platform"] as? String, "ios")
            XCTAssertNotNil(payload["natsCommand"])

            let published = bridge.publish(request: [
                "requestId": "ios-smoke-publish",
                "subject": "\(settings.natsConfiguration.devicePrefix(appUUID: settings.appUUIDString)).events.demo",
                "payload": "{\"ok\":true}"
            ])
            XCTAssertEqual(published["success"] as? Bool, true, "\(published)")
        } catch {
            XCTFail("NATS smoke test failed: \(error.localizedDescription)")
        }
        do {
            try await control.close()
        } catch {
            // Closing an already closed smoke-test connection is harmless.
        }
        _ = bridge.disconnect(request: ["requestId": "ios-smoke-disconnect"])
        try? FileManager.default.removeItem(at: credentialFile)
        defaults.removePersistentDomain(forName: suiteName)
        #else
        throw XCTSkip("NATS Swift package is not linked in this build.")
        #endif
    }

    #if canImport(Nats)
    private func smokeURLs() -> [String] {
        let environment = ProcessInfo.processInfo.environment
        let raw = environment["NATS_SMOKE_URLS"]
            ?? environment["TEST_RUNNER_NATS_SMOKE_URLS"]
            ?? ""
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func smokeCredential() throws -> String {
        let environment = ProcessInfo.processInfo.environment
        if let encoded = environment["NATS_SMOKE_CREDS_B64"] ?? environment["TEST_RUNNER_NATS_SMOKE_CREDS_B64"],
           !encoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let data = Data(base64Encoded: encoded.filter { !$0.isWhitespace }),
           let credential = String(data: data, encoding: .utf8) {
            return credential
        }
        if let path = environment["NATS_SMOKE_CREDS_PATH"] ?? environment["TEST_RUNNER_NATS_SMOKE_CREDS_PATH"],
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try String(contentsOfFile: path.trimmingCharacters(in: .whitespacesAndNewlines), encoding: .utf8)
        }
        return ""
    }

    private func writeTemporaryCredentialFile(_ credential: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-wrapper-nats-smoke-\(UUID().uuidString).creds")
        try credential.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeControlClient(urls: [String], credentialFile: URL) throws -> NatsClient {
        let options = NatsClientOptions()
            .urls(urls.compactMap(URL.init(string:)))
            .pingInterval(10)
            .reconnectWait(0.5)
            .withTlsFirst()
            .requireTls()
            .credentialsFile(credentialFile)
        return options.build()
    }
    #endif

    private final class StaticCredentialStore: NATSCredentialStore {
        let credential: String

        init(credential: String) {
            self.credential = credential
        }

        func store(_ credential: String, method: NATSAuthMethod) throws {
        }

        func hasCredential() -> Bool {
            !credential.isEmpty
        }

        func loadCredential() -> String? {
            credential
        }

        func clear() {
        }
    }
}
