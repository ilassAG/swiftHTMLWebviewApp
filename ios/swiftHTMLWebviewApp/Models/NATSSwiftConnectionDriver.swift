//
//  NATSSwiftConnectionDriver.swift
//  swiftHTMLWebviewApp
//

#if canImport(Nats)
import Foundation
import Nats

final class NATSSwiftConnectionDriver: NATSConnectionDriver {
    private let lock = NSLock()
    private var client: NatsClient?
    private var subscriptionTask: Task<Void, Never>?
    private var credentialFileURL: URL?
    private var connectedState = false

    var connected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return connectedState
    }

    func connect(
        settings: NATSSettings,
        appUUID: String,
        credential: String?,
        commandHandler: @escaping NATSCommandHandler
    ) -> String? {
        disconnect()

        do {
            let client = try buildClient(settings: settings, appUUID: appUUID, credential: credential)
            let commandSubject = settings.commandSubject(appUUID: appUUID)
            let semaphore = DispatchSemaphore(value: 0)
            var errorMessage: String?
            var startedTask: Task<Void, Never>?

            startedTask = Task.detached { [weak self] in
                do {
                    try await client.connect()
                    let subscription = try await client.subscribe(subject: commandSubject)
                    let receiveTask = Task.detached {
                        do {
                            for try await message in subscription {
                                commandHandler(message.subject, message.payload ?? Data(), message.replySubject)
                            }
                        } catch {
                            // Subscription errors are reflected by the next explicit status/publish call.
                        }
                    }
                    self?.setConnected(client: client, subscriptionTask: receiveTask)
                } catch {
                    errorMessage = error.localizedDescription
                    self?.cleanupCredentialFile()
                }
                semaphore.signal()
            }

            if semaphore.wait(timeout: .now() + 8) == .timedOut {
                startedTask?.cancel()
                cleanupCredentialFile()
                return "NATS connect timed out."
            }
            return errorMessage
        } catch {
            cleanupCredentialFile()
            return error.localizedDescription
        }
    }

    func disconnect() {
        lock.lock()
        let currentClient = client
        let currentTask = subscriptionTask
        client = nil
        subscriptionTask = nil
        connectedState = false
        lock.unlock()

        currentTask?.cancel()
        if let currentClient {
            let semaphore = DispatchSemaphore(value: 0)
            Task.detached {
                do {
                    try await currentClient.close()
                } catch {
                    // Closing an already closed connection is harmless here.
                }
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 3)
        }
        cleanupCredentialFile()
    }

    func publish(subject: String, payload: Data) -> String? {
        lock.lock()
        let currentClient = client
        let isConnected = connectedState
        lock.unlock()

        guard let currentClient, isConnected else {
            return "NATS is not connected."
        }

        let semaphore = DispatchSemaphore(value: 0)
        var errorMessage: String?
        Task.detached {
            do {
                try await currentClient.publish(payload, subject: subject)
            } catch {
                errorMessage = error.localizedDescription
            }
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + 5) == .timedOut {
            return "NATS publish timed out."
        }
        return errorMessage
    }

    private func buildClient(settings: NATSSettings, appUUID: String, credential: String?) throws -> NatsClient {
        let urls = settings.urls.compactMap { URL(string: $0) }
        guard !urls.isEmpty else {
            throw AppError.invalidRequest("At least one NATS URL is required.")
        }

        let options = NatsClientOptions()
            .urls(urls)
            .pingInterval(TimeInterval(settings.pingIntervalSeconds))
            .reconnectWait(TimeInterval(settings.reconnectWaitMs) / 1000.0)

        if settings.maxReconnects >= 0 {
            _ = options.maxReconnects(settings.maxReconnects)
        }
        if settings.tlsFirst {
            _ = options.withTlsFirst()
        }
        if settings.urls.contains(where: { $0.lowercased().hasPrefix("tls://") }) {
            _ = options.requireTls()
        }

        let secret = credential ?? ""
        switch settings.authMethod {
        case .creds:
            _ = options.credentialsFile(try writeCredentialFile(secret))
        case .token:
            _ = options.token(secret)
        case .nkey:
            _ = options.nkey(secret)
        case .none:
            break
        case .userPassword, .tlsCertificate:
            throw AppError.invalidRequest("NATS auth method is not supported by the iOS transport yet: \(settings.authMethod.rawValue).")
        }

        return options.build()
    }

    private func setConnected(client: NatsClient, subscriptionTask: Task<Void, Never>) {
        lock.lock()
        self.client = client
        self.subscriptionTask = subscriptionTask
        connectedState = true
        lock.unlock()
    }

    private func writeCredentialFile(_ credential: String) throws -> URL {
        guard let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AppError.invalidRequest("Application Support directory is unavailable.")
        }
        let directory = baseDirectory.appendingPathComponent("NATS", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("credentials-\(UUID().uuidString).creds")
        try credential.data(using: .utf8)?.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableFileURL = fileURL
        try? mutableFileURL.setResourceValues(resourceValues)
        credentialFileURL = fileURL
        return fileURL
    }

    private func cleanupCredentialFile() {
        lock.lock()
        let fileURL = credentialFileURL
        credentialFileURL = nil
        lock.unlock()

        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
#endif
