//
//  NATSBridgeTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

@MainActor
final class NATSBridgeTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var settings: AppSettings!
    private var credentialStore: MockNATSCredentialStore!
    private var connection: MockNATSConnectionDriver!
    private var bridge: NATSBridge!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "NATSBridgeTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        settings = AppSettings(userDefaults: defaults, variant: .demo)
        settings.registerDefaults()
        settings.securityToken = "current-token"
        credentialStore = MockNATSCredentialStore()
        connection = MockNATSConnectionDriver()
        bridge = NATSBridge(settings: settings, credentialStore: credentialStore, connection: connection)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        bridge = nil
        connection = nil
        credentialStore = nil
        settings = nil
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    func testProvisionRequiresCurrentSecurityToken() {
        let response = bridge.provision(request: [
            "requestId": "req-1",
            "nats": [
                "enabled": true,
                "auth": ["method": "creds", "creds": "SECRET"]
            ]
        ])

        XCTAssertEqual(response["action"] as? String, "natsProvision")
        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertEqual(response["error"] as? String, "securityToken is required for natsProvision.")
        XCTAssertFalse(credentialStore.hasCredential())
    }

    func testProvisionStoresSecretAndReturnsOnlyRedactedStatus() {
        let response = bridge.provision(request: [
            "requestId": "req-2",
            "token": "current-token",
            "nats": [
                "enabled": true,
                "urls": ["tls://nats.example.invalid:4222"],
                "auth": [
                    "method": "creds",
                    "creds": "SECRET-CREDS"
                ]
            ]
        ])
        let nats = response["nats"] as? [String: Any]
        let auth = nats?["auth"] as? [String: Any]

        XCTAssertEqual(response["success"] as? Bool, true)
        XCTAssertEqual(credentialStore.credential, "SECRET-CREDS")
        XCTAssertEqual(settings.natsConfiguration.urls, ["tls://nats.example.invalid:4222"])
        XCTAssertEqual(auth?["credentialSet"] as? Bool, true)
        XCTAssertNil(auth?["creds"])
        XCTAssertFalse("\(response)".contains("SECRET-CREDS"))
    }

    func testProvisionRejectsAuthMethodsNotSupportedByNativeTransport() {
        let response = bridge.provision(request: [
            "requestId": "req-unsupported-auth",
            "token": "current-token",
            "nats": [
                "enabled": true,
                "urls": ["tls://nats.example.invalid:4222"],
                "auth": [
                    "method": "userPassword",
                    "password": "SECRET"
                ]
            ]
        ])

        XCTAssertEqual(response["action"] as? String, "natsProvision")
        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertEqual(response["error"] as? String, "NATS auth method is not supported by the native transport yet: userPassword.")
        XCTAssertFalse(credentialStore.hasCredential())
    }

    func testConnectUsesProvisionedCredentialThroughDriver() {
        _ = bridge.provision(request: [
            "token": "current-token",
            "nats": [
                "enabled": true,
                "urls": ["tls://nats.example.invalid:4222"],
                "auth": ["method": "creds", "creds": "SECRET-CREDS"]
            ]
        ])
        connection.connectError = nil

        let response = bridge.connect(request: ["requestId": "req-3"])

        XCTAssertEqual(response["action"] as? String, "natsConnect")
        XCTAssertEqual(response["success"] as? Bool, true)
        XCTAssertEqual(connection.lastCredential, "SECRET-CREDS")
        XCTAssertEqual(connection.lastClientName, "swift-wrapper-\(settings.appUUIDString)")
        XCTAssertEqual(connection.lastPublishedSubject, "swift.wrapper.\(settings.appUUIDString).status")
        XCTAssertTrue(connection.lastPublishedPayloadString?.contains("\"action\":\"natsStatus\"") ?? false)
    }

    func testConnectRejectsEnabledConfigurationWithoutURL() {
        settings.natsConfiguration.enabled = true
        settings.natsConfiguration.authMethod = .none

        let response = bridge.connect(request: ["requestId": "req-empty-url"])

        XCTAssertEqual(response["action"] as? String, "natsConnect")
        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertEqual(response["error"] as? String, "At least one NATS URL is required.")
        XCTAssertFalse(connection.connected)
    }

    func testCommandHandlerExecutesAllowedCommandAndPublishesReply() async {
        _ = bridge.provision(request: [
            "token": "current-token",
            "nats": [
                "enabled": true,
                "urls": ["tls://nats.example.invalid:4222"],
                "auth": ["method": "creds", "creds": "SECRET-CREDS"]
            ]
        ])
        connection.connectError = nil
        bridge.configureCommandExecutor { command, completion in
            completion([
                "platform": "ios",
                "action": command["action"] as? String ?? "",
                "success": true
            ])
        }
        _ = bridge.connect(request: ["requestId": "req-4"])
        connection.lastPublishedSubject = nil
        let published = expectation(description: "NATS command response published")
        connection.publishExpectation = published

        connection.commandHandler?(
            "swift.wrapper.\(settings.appUUIDString).commands.status",
            Data("{}".utf8),
            "swift.wrapper.\(settings.appUUIDString).reply.req-1"
        )
        await fulfillment(of: [published], timeout: 1)

        XCTAssertEqual(connection.lastPublishedSubject, "swift.wrapper.\(settings.appUUIDString).reply.req-1")
        XCTAssertTrue(connection.lastPublishedPayloadString?.contains("\"action\":\"deviceInfoGet\"") ?? false)
        XCTAssertTrue(connection.lastPublishedPayloadString?.contains("\"natsCommand\"") ?? false)
    }

    func testCommandAliasesAllowQRAndScreenStreamCommands() async {
        _ = bridge.provision(request: [
            "token": "current-token",
            "nats": [
                "enabled": true,
                "urls": ["tls://nats.example.invalid:4222"],
                "auth": ["method": "creds", "creds": "SECRET-CREDS"]
            ]
        ])
        connection.connectError = nil
        var actions: [String] = []
        bridge.configureCommandExecutor { command, completion in
            let action = command["action"] as? String ?? ""
            actions.append(action)
            completion(["platform": "ios", "action": action, "success": true])
        }
        _ = bridge.connect(request: [:])

        for subjectAction in ["qrScan", "qrScanJob", "videoStreamStart", "videoStreamStop"] {
            let published = expectation(description: "published \(subjectAction)")
            connection.publishExpectation = published
            connection.commandHandler?(
                "swift.wrapper.\(settings.appUUIDString).commands.\(subjectAction)",
                Data("{}".utf8),
                "swift.wrapper.\(settings.appUUIDString).reply.\(subjectAction)"
            )
            await fulfillment(of: [published], timeout: 1)
        }

        XCTAssertEqual(actions, ["qrScanImage", "qrScanImage", "screenStreamStart", "screenStreamStop"])
    }

    func testInternalBinaryPublishIsScopedToDeviceNamespace() {
        settings.natsConfiguration.enabled = true
        settings.natsConfiguration.urls = ["tls://nats.example.invalid:4222"]
        settings.natsConfiguration.authMethod = .none
        connection.connectError = nil
        _ = bridge.connect(request: [:])

        XCTAssertNil(bridge.publishData(
            subject: "swift.wrapper.\(settings.appUUIDString).screen.frames",
            payload: Data([1, 2, 3])
        ))
        XCTAssertEqual(connection.lastPublishedSubject, "swift.wrapper.\(settings.appUUIDString).screen.frames")
        XCTAssertEqual(connection.lastPublishedPayloadData, Data([1, 2, 3]))

        let error = bridge.publishData(subject: "swift.wrapper.other.screen.frames", payload: Data())
        XCTAssertEqual(error, "NATS publish subject is outside the device namespace.")
    }

    private final class MockNATSCredentialStore: NATSCredentialStore {
        var credential: String?

        func store(_ credential: String, method: NATSAuthMethod) {
            self.credential = credential
        }

        func hasCredential() -> Bool {
            credential != nil
        }

        func loadCredential() -> String? {
            credential
        }

        func clear() {
            credential = nil
        }
    }

    private final class MockNATSConnectionDriver: NATSConnectionDriver {
        var connected = false
        var connectError: String? = "offline"
        var lastCredential: String?
        var lastClientName: String?
        var commandHandler: NATSCommandHandler?
        var lastPublishedSubject: String?
        var lastPublishedPayloadString: String?
        var lastPublishedPayloadData: Data?
        var publishExpectation: XCTestExpectation?

        func connect(
            settings: NATSSettings,
            appUUID: String,
            credential: String?,
            commandHandler: @escaping NATSCommandHandler
        ) -> String? {
            lastCredential = credential
            lastClientName = settings.clientName(appUUID: appUUID)
            self.commandHandler = commandHandler
            connected = connectError == nil
            return connectError
        }

        func disconnect() {
            connected = false
        }

        func publish(subject: String, payload: Data) -> String? {
            guard connected else {
                return "offline"
            }
            lastPublishedSubject = subject
            lastPublishedPayloadData = payload
            lastPublishedPayloadString = String(data: payload, encoding: .utf8)
            publishExpectation?.fulfill()
            return nil
        }
    }
}
