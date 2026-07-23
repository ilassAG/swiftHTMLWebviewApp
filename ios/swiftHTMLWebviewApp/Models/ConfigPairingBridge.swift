//
//  ConfigPairingBridge.swift
//  swiftHTMLWebviewApp
//
//  Ephemeral BLE pairing transport for external device configuration.
//

import Combine
@preconcurrency import CoreBluetooth
import CoreImage.CIFilterBuiltins
import Foundation
import Security
import SwiftUI
import UIKit

final class ConfigPairingBridge: NSObject, ObservableObject {
    private enum CentralMode: Equatable {
        case idle
        case qrPairing
        case persistentDevice
    }

    fileprivate static let serviceUUID = CBUUID(string: ConfigPairingPayload.serviceUUID)
    private static let persistentDeviceServiceUUID = CBUUID(string: ConfigPairingPayload.persistentDeviceServiceUUID)
    private static let commandUUID = CBUUID(string: ConfigPairingPayload.commandUUID)
    private static let responseUUID = CBUUID(string: ConfigPairingPayload.responseUUID)
    private static let sessionLifetimeSeconds: TimeInterval = 300
    private static let singleNotificationLimit = 160
    private static let chunkPayloadSize = ConfigPairingPayload.chunkPayloadSize

    @Published private(set) var targetPayload: String?
    @Published private(set) var targetQRCode: UIImage?
    @Published private(set) var targetExpiresAt: Date?
    @Published private(set) var targetAdvertising = false

    private var targetSessionID = ""
    private var targetSecret = ""
    private var targetExpiry = Date.distantPast
    private var targetCentral: CBCentral?
    private var peripheralManager: CBPeripheralManager?
    private var commandCharacteristic: CBMutableCharacteristic?
    private var responseCharacteristic: CBMutableCharacteristic?

    private var centralManager: CBCentralManager?
    private var centralMode: CentralMode = .idle
    private var pairingTarget: ConfigPairingPayload.PairingTarget?
    private var connectedPeripheral: CBPeripheral?
    private var persistentDeviceScanning = false
    private var discoveredPersistentDevices: [UUID: CBPeripheral] = [:]
    private var selectedPersistentDeviceID = ""
    private var centralCommandCharacteristic: CBCharacteristic?
    private var centralResponseCharacteristic: CBCharacteristic?
    private var centralChunkAccumulators: [String: ConfigPairingPayload.ChunkAccumulator] = [:]
    private var targetChunkAccumulators: [String: ConfigPairingPayload.ChunkAccumulator] = [:]
    private var centralWritePackets: [Data] = []
    private weak var centralWritePeripheral: CBPeripheral?
    private weak var centralWriteCharacteristic: CBCharacteristic?
    private var centralWriteInFlight = false

    private var eventHandler: (([String: Any]) -> Void)?
    private var settingsProvider: () -> [String: Any] = { AppSettings.shared.configurationSnapshot() }
    private var settingsApplier: ([String: Any]) -> [String: Any] = { AppSettings.shared.applyConfiguration($0) }
    private var wifiConfigurator: (([String: Any], @escaping ([String: Any]) -> Void) -> Void)?
    private var reloadHandler: (() -> Void)?
    private var deviceInfoProvider: () -> [String: Any] = { [:] }

    func configure(
        eventHandler: @escaping ([String: Any]) -> Void,
        settingsProvider: @escaping () -> [String: Any],
        settingsApplier: @escaping ([String: Any]) -> [String: Any],
        wifiConfigurator: @escaping ([String: Any], @escaping ([String: Any]) -> Void) -> Void,
        reloadHandler: @escaping () -> Void,
        deviceInfoProvider: @escaping () -> [String: Any]
    ) {
        self.eventHandler = eventHandler
        self.settingsProvider = settingsProvider
        self.settingsApplier = settingsApplier
        self.wifiConfigurator = wifiConfigurator
        self.reloadHandler = reloadHandler
        self.deviceInfoProvider = deviceInfoProvider
    }

    func startTargetSession(request: [String: Any]) -> [String: Any] {
        targetSessionID = UUID().uuidString
        targetSecret = randomBase64URL(byteCount: 18)
        targetExpiry = Date().addingTimeInterval(Self.sessionLifetimeSeconds)
        let identity = targetIdentity()
        let payload = ConfigPairingPayload.pairingPayload(sessionID: targetSessionID, secret: targetSecret, expiresAt: targetExpiry, identity: identity)

        targetPayload = payload
        targetQRCode = qrImage(for: payload)
        targetExpiresAt = targetExpiry

        if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
        } else {
            configurePeripheralServiceIfReady()
        }

        return ConfigPairingPayload.showResponse(
            request: request,
            payload: payload,
            expiresAt: targetExpiry,
            identity: identity
        )
    }

    func stopTargetSession(request: [String: Any]) -> [String: Any] {
        stopTargetSession()
        return ConfigPairingPayload.acknowledgementResponse(request: request, action: "configPairingStop")
    }

    func connect(request: [String: Any]) -> [String: Any] {
        guard let payload = configString(request["payload"] ?? request["pairingPayload"] ?? request["code"]),
              let target = ConfigPairingPayload.PairingTarget(payload: payload) else {
            return ConfigPairingPayload.errorResponse(request: request, action: "configPairingConnect", error: "Invalid config pairing payload.")
        }

        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        centralManager?.stopScan()
        centralMode = .qrPairing
        persistentDeviceScanning = false
        pairingTarget = target
        centralCommandCharacteristic = nil
        centralResponseCharacteristic = nil
        connectedPeripheral = nil
        resetCentralWriteQueue()

        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: .main)
        } else {
            startCentralScanIfReady()
        }

        return ConfigPairingPayload.connectResponse(request: request, target: target)
    }

    func disconnect(request: [String: Any]) -> [String: Any] {
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        centralManager?.stopScan()
        centralMode = .idle
        persistentDeviceScanning = false
        pairingTarget = nil
        connectedPeripheral = nil
        centralCommandCharacteristic = nil
        centralResponseCharacteristic = nil
        centralChunkAccumulators.removeAll()
        resetCentralWriteQueue()

        return ConfigPairingPayload.acknowledgementResponse(request: request, action: "configPairingDisconnect")
    }

    func startPersistentDeviceScan(request: [String: Any]) -> [String: Any] {
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        centralMode = .persistentDevice
        pairingTarget = nil
        connectedPeripheral = nil
        selectedPersistentDeviceID = ""
        centralCommandCharacteristic = nil
        centralResponseCharacteristic = nil
        centralChunkAccumulators.removeAll()
        resetCentralWriteQueue()
        discoveredPersistentDevices.removeAll()
        persistentDeviceScanning = true

        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: .main)
        } else {
            startCentralScanIfReady()
        }

        var response = ConfigPairingPayload.baseResponse(request: request, action: "configDeviceScanStart")
        response["success"] = true
        response["state"] = "scanning"
        response["serviceUUID"] = Self.persistentDeviceServiceUUID.uuidString
        return response
    }

    func stopPersistentDeviceScan(request: [String: Any]) -> [String: Any] {
        persistentDeviceScanning = false
        centralManager?.stopScan()
        return ConfigPairingPayload.acknowledgementResponse(request: request, action: "configDeviceScanStop")
    }

    func connectPersistentDevice(request: [String: Any]) -> [String: Any] {
        guard let scanIDText = configString(request["scanId"] ?? request["peripheralId"]),
              let scanID = UUID(uuidString: scanIDText),
              let peripheral = discoveredPersistentDevices[scanID] else {
            return ConfigPairingPayload.errorResponse(
                request: request,
                action: "configDeviceConnect",
                error: "Unknown ESP device. Scan again and select a discovered device."
            )
        }

        centralMode = .persistentDevice
        persistentDeviceScanning = false
        pairingTarget = nil
        selectedPersistentDeviceID = configString(request["deviceId"]) ?? ""
        connectedPeripheral = peripheral
        centralCommandCharacteristic = nil
        centralResponseCharacteristic = nil
        centralChunkAccumulators.removeAll()
        resetCentralWriteQueue()
        peripheral.delegate = self
        centralManager?.stopScan()
        centralManager?.connect(peripheral, options: nil)

        var response = ConfigPairingPayload.baseResponse(request: request, action: "configDeviceConnect")
        response["success"] = true
        response["state"] = "connecting"
        response["scanId"] = scanID.uuidString
        response["name"] = peripheral.name ?? ""
        return response
    }

    func disconnectPersistentDevice(request: [String: Any]) -> [String: Any] {
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        persistentDeviceScanning = false
        centralManager?.stopScan()
        connectedPeripheral = nil
        selectedPersistentDeviceID = ""
        centralCommandCharacteristic = nil
        centralResponseCharacteristic = nil
        centralChunkAccumulators.removeAll()
        resetCentralWriteQueue()
        return ConfigPairingPayload.acknowledgementResponse(request: request, action: "configDeviceDisconnect")
    }

    func sendPersistentDevice(request: [String: Any]) -> [String: Any] {
        guard centralMode == .persistentDevice,
              let peripheral = connectedPeripheral,
              let characteristic = centralCommandCharacteristic else {
            return ConfigPairingPayload.errorResponse(
                request: request,
                action: "configDeviceSend",
                error: "No ESP device is ready. Scan, select, and connect first."
            )
        }

        let command = ConfigPairingPayload.persistentDeviceCommand(
            request: request,
            deviceID: selectedPersistentDeviceID,
            requestId: ConfigPairingPayload.stringOrGenerated(request["requestId"])
        )
        guard let data = try? JSONSerialization.data(withJSONObject: command, options: []) else {
            return ConfigPairingPayload.errorResponse(request: request, action: "configDeviceSend", error: "Could not serialize ESP command.")
        }

        let writeResult = writeCentralCommandData(data, peripheral: peripheral, characteristic: characteristic)
        guard writeResult.success else {
            return ConfigPairingPayload.errorResponse(
                request: request,
                action: "configDeviceSend",
                error: writeResult.error ?? "Could not write ESP command."
            )
        }

        var response = ConfigPairingPayload.sendResponse(
            request: request,
            command: configString(command["command"]) ?? "statusGet",
            bytes: data.count,
            chunks: writeResult.chunks
        )
        response["action"] = "configDeviceSend"
        response["deviceId"] = selectedPersistentDeviceID
        return response
    }

    func send(request: [String: Any]) -> [String: Any] {
        guard let target = pairingTarget else {
            return ConfigPairingPayload.errorResponse(request: request, action: "configPairingSend", error: "No config pairing target is connected.")
        }
        guard let peripheral = connectedPeripheral,
              let characteristic = centralCommandCharacteristic else {
            return ConfigPairingPayload.errorResponse(request: request, action: "configPairingSend", error: "Config pairing is not ready yet.")
        }

        let command = ConfigPairingPayload.command(
            target: target,
            request: request,
            requestId: ConfigPairingPayload.stringOrGenerated(request["requestId"])
        )

        guard let data = try? JSONSerialization.data(withJSONObject: command, options: []) else {
            return ConfigPairingPayload.errorResponse(request: request, action: "configPairingSend", error: "Could not serialize config command.")
        }

        let writeResult = writeCentralCommandData(data, peripheral: peripheral, characteristic: characteristic)
        guard writeResult.success else {
            return ConfigPairingPayload.errorResponse(request: request, action: "configPairingSend", error: writeResult.error ?? "Could not write config command.")
        }

        return ConfigPairingPayload.sendResponse(
            request: request,
            command: configString(command["command"]) ?? "statusGet",
            bytes: data.count,
            chunks: writeResult.chunks
        )
    }

    private func stopTargetSession() {
        peripheralManager?.stopAdvertising()
        targetPayload = nil
        targetQRCode = nil
        targetExpiresAt = nil
        targetAdvertising = false
        targetSessionID = ""
        targetSecret = ""
        targetExpiry = Date.distantPast
        targetCentral = nil
        targetChunkAccumulators.removeAll()
    }

    private func closePairingPromptAfterConnection() {
        peripheralManager?.stopAdvertising()
        targetPayload = nil
        targetQRCode = nil
        targetExpiresAt = nil
        targetAdvertising = false
    }

    private func configurePeripheralServiceIfReady() {
        guard let manager = peripheralManager, manager.state == .poweredOn else { return }

        manager.stopAdvertising()
        manager.removeAllServices()

        let command = CBMutableCharacteristic(
            type: Self.commandUUID,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        let response = CBMutableCharacteristic(
            type: Self.responseUUID,
            properties: [.notify, .read],
            value: nil,
            permissions: [.readable]
        )
        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = [command, response]

        commandCharacteristic = command
        responseCharacteristic = response
        manager.add(service)
    }

    private func startAdvertisingIfReady() {
        guard let manager = peripheralManager,
              manager.state == .poweredOn,
              targetPayload != nil else { return }

        manager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
            CBAdvertisementDataLocalNameKey: "swiftHTML Config"
        ])
        targetAdvertising = true
        emitEvent([
            "action": "configPairingEvent",
            "platform": "ios",
            "role": "target",
            "event": "advertising",
            "success": true,
            "serviceUUID": Self.serviceUUID.uuidString
        ])
    }

    private func startCentralScanIfReady() {
        guard let central = centralManager, central.state == .poweredOn else { return }

        let serviceUUID: CBUUID
        switch centralMode {
        case .qrPairing:
            guard let target = pairingTarget else { return }
            serviceUUID = CBUUID(string: target.serviceUUID)
        case .persistentDevice:
            guard persistentDeviceScanning else { return }
            serviceUUID = Self.persistentDeviceServiceUUID
        case .idle:
            return
        }

        central.stopScan()
        central.scanForPeripherals(withServices: [serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        emitEvent([
            "action": centralEventAction(),
            "platform": "ios",
            "role": "configurator",
            "event": "scanning",
            "success": true,
            "serviceUUID": serviceUUID.uuidString
        ])
    }

    private func handleTargetCommand(_ data: Data, central: CBCentral) {
        if let targetCentral,
           targetCentral.identifier != central.identifier {
            notifyTargetResponse(
                errorPayload(command: "unknown", error: "Another config device is already connected."),
                centrals: [central]
            )
            return
        }

        guard let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            notifyTargetResponse(errorPayload(command: "unknown", error: "Invalid JSON command."))
            return
        }

        if configString(object["action"]) == "configPairingChunk" {
            handleTargetCommandChunk(object, central: central)
            return
        }

        processTargetCommand(object, central: central)
    }

    private func processTargetCommand(_ command: [String: Any], central: CBCentral) {
        let commandName = configString(command["command"]) ?? "statusGet"
        guard commandIsPaired(command) else {
            notifyTargetResponse(errorPayload(command: commandName, requestId: command["requestId"], error: "Invalid or expired config pairing session."))
            return
        }

        switch commandName {
        case "statusGet":
            var response = responsePayload(command: commandName, requestId: command["requestId"])
            response["success"] = true
            response["settings"] = settingsProvider()
            response["deviceInfo"] = deviceInfoProvider()
            notifyTargetResponse(response)

        case "settingsGet":
            var response = responsePayload(command: commandName, requestId: command["requestId"])
            response["success"] = true
            response["settings"] = settingsProvider()
            notifyTargetResponse(response)

        case "settingsSet":
            guard commandHasValidSecurityToken(command) else {
                notifyTargetResponse(errorPayload(command: commandName, requestId: command["requestId"], error: "securityToken is required for settingsSet."))
                return
            }
            let values = (command["settings"] as? [String: Any]) ?? command
            let snapshot = settingsApplier(values)
            reloadHandler?()
            var response = responsePayload(command: commandName, requestId: command["requestId"])
            response["success"] = true
            response["settings"] = snapshot
            notifyTargetResponse(response)

        case "wifiConfigure":
            guard commandHasValidSecurityToken(command) else {
                notifyTargetResponse(errorPayload(command: commandName, requestId: command["requestId"], error: "securityToken is required for wifiConfigure."))
                return
            }
            guard let wifiConfigurator else {
                notifyTargetResponse(errorPayload(command: commandName, requestId: command["requestId"], error: "Wi-Fi configuration is not available."))
                return
            }
            var wifiRequest = command
            wifiRequest["action"] = "wifiConfigure"
            wifiConfigurator(wifiRequest) { [weak self] result in
                var response = self?.responsePayload(command: commandName, requestId: command["requestId"]) ?? [:]
                response["success"] = result["success"] as? Bool ?? false
                response["wifiResult"] = result
                self?.notifyTargetResponse(response)
            }

        case "reload":
            guard commandHasValidSecurityToken(command) else {
                notifyTargetResponse(errorPayload(command: commandName, requestId: command["requestId"], error: "securityToken is required for reload."))
                return
            }
            reloadHandler?()
            var response = responsePayload(command: commandName, requestId: command["requestId"])
            response["success"] = true
            notifyTargetResponse(response)

        default:
            notifyTargetResponse(errorPayload(command: commandName, requestId: command["requestId"], error: "Unknown config command: \(commandName)."))
        }
    }

    private func handleTargetCommandChunk(_ object: [String: Any], central: CBCentral) {
        guard let chunk = ConfigPairingPayload.chunkData(from: object) else {
            notifyTargetResponse(
                errorPayload(command: "unknown", error: "Invalid config command chunk."),
                centrals: [central]
            )
            return
        }

        var accumulator = targetChunkAccumulators[chunk.id] ?? ConfigPairingPayload.ChunkAccumulator(count: chunk.count)
        accumulator.chunks[chunk.index] = chunk.data
        targetChunkAccumulators[chunk.id] = accumulator

        guard accumulator.isComplete else { return }
        targetChunkAccumulators.removeValue(forKey: chunk.id)

        let assembled = accumulator.assembled
        guard let command = try? JSONSerialization.jsonObject(with: assembled, options: []) as? [String: Any] else {
            notifyTargetResponse(
                errorPayload(command: "unknown", error: "Could not assemble config command chunks."),
                centrals: [central]
            )
            return
        }
        processTargetCommand(command, central: central)
    }

    private func writeCentralCommandData(_ data: Data, peripheral: CBPeripheral, characteristic: CBCharacteristic) -> (success: Bool, chunks: Int, error: String?) {
        guard !centralWriteInFlight, centralWritePackets.isEmpty else {
            return (false, 0, "Another BLE command is still being written.")
        }

        let maxLength = peripheral.maximumWriteValueLength(for: .withResponse)
        let payloads: [Data]
        if data.count <= maxLength {
            payloads = [data]
        } else {
            guard let chunkPayloads = ConfigPairingPayload.chunkPayloads(for: data, maxLength: maxLength) else {
                return (false, 0, "Config command is too large for the negotiated BLE write length.")
            }
            payloads = chunkPayloads
        }

        centralWritePackets = payloads
        centralWritePeripheral = peripheral
        centralWriteCharacteristic = characteristic
        writeNextCentralCommandPacket()
        return (true, payloads.count, nil)
    }

    private func writeNextCentralCommandPacket() {
        guard !centralWriteInFlight else { return }
        guard !centralWritePackets.isEmpty else {
            centralWritePeripheral = nil
            centralWriteCharacteristic = nil
            return
        }
        guard let peripheral = centralWritePeripheral,
              let characteristic = centralWriteCharacteristic,
              peripheral.state == .connected else {
            resetCentralWriteQueue()
            return
        }

        centralWriteInFlight = true
        peripheral.writeValue(centralWritePackets.removeFirst(), for: characteristic, type: .withResponse)
    }

    private func resetCentralWriteQueue() {
        centralWritePackets.removeAll()
        centralWritePeripheral = nil
        centralWriteCharacteristic = nil
        centralWriteInFlight = false
    }

    private func commandIsPaired(_ command: [String: Any]) -> Bool {
        Date() <= targetExpiry
            && configString(command["sessionId"] ?? command["id"]) == targetSessionID
            && configString(command["secret"]) == targetSecret
    }

    private func commandHasValidSecurityToken(_ command: [String: Any]) -> Bool {
        guard let token = configString(command["token"] ?? command["securityToken"]) else { return false }
        return token == AppSettings.shared.securityToken
    }

    private func notifyTargetResponse(_ payload: [String: Any], centrals: [CBCentral]? = nil) {
        emitEvent(payload)
        guard let responseCharacteristic,
              let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return }

        if data.count <= Self.singleNotificationLimit {
            notifyTargetData(data, characteristic: responseCharacteristic, centrals: centrals)
            return
        }

        notifyTargetDataInChunks(data, characteristic: responseCharacteristic, centrals: centrals)
    }

    private func notifyTargetData(_ data: Data, characteristic: CBMutableCharacteristic, centrals: [CBCentral]? = nil) {
        characteristic.value = data
        peripheralManager?.updateValue(data, for: characteristic, onSubscribedCentrals: centrals ?? targetCentral.map { [$0] })
    }

    private func notifyTargetDataInChunks(_ data: Data, characteristic: CBMutableCharacteristic, centrals: [CBCentral]? = nil) {
        let chunkID = UUID().uuidString
        let chunkCount = Int(ceil(Double(data.count) / Double(Self.chunkPayloadSize)))

        for index in 0..<chunkCount {
            let start = index * Self.chunkPayloadSize
            let end = min(start + Self.chunkPayloadSize, data.count)
            let chunk = data.subdata(in: start..<end)
            let payload = ConfigPairingPayload.chunkEnvelope(id: chunkID, index: index, count: chunkCount, data: chunk)
            guard let payloadData = try? JSONSerialization.data(withJSONObject: payload, options: []) else { continue }
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.02) { [weak self, weak characteristic, centrals] in
                guard let self, let characteristic else { return }
                self.notifyTargetData(payloadData, characteristic: characteristic, centrals: centrals)
            }
        }
    }

    private func responsePayload(command: String, requestId: Any?) -> [String: Any] {
        ConfigPairingPayload.responsePayload(command: command, requestId: requestId, sessionID: targetSessionID)
    }

    private func errorPayload(command: String, requestId: Any? = nil, error: String) -> [String: Any] {
        ConfigPairingPayload.errorPayload(command: command, requestId: requestId, sessionID: targetSessionID, error: error)
    }

    private func emitEvent(_ event: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.eventHandler?(event)
        }
    }

    private func targetIdentity() -> [String: String] {
        ConfigPairingPayload.identity(settings: settingsProvider(), fallbackName: UIDevice.current.name)
    }

    private func qrImage(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }

        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func randomBase64URL(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        if status != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

}

extension ConfigPairingBridge: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            configurePeripheralServiceIfReady()
        } else {
            targetAdvertising = false
            emitEvent([
                "action": "configPairingEvent",
                "platform": "ios",
                "role": "target",
                "event": "bluetoothState",
                "success": false,
                "state": bluetoothStateName(peripheral.state)
            ])
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            targetAdvertising = false
            emitEvent([
                "action": "configPairingEvent",
                "platform": "ios",
                "role": "target",
                "event": "serviceAddFailed",
                "success": false,
                "error": error.localizedDescription
            ])
            return
        }
        startAdvertisingIfReady()
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            targetAdvertising = false
            emitEvent([
                "action": "configPairingEvent",
                "platform": "ios",
                "role": "target",
                "event": "advertisingFailed",
                "success": false,
                "error": error.localizedDescription
            ])
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests where request.characteristic.uuid == Self.commandUUID {
            if let value = request.value {
                handleTargetCommand(value, central: request.central)
            }
            peripheral.respond(to: request, withResult: .success)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        if request.characteristic.uuid == Self.responseUUID {
            request.value = responseCharacteristic?.value
            peripheral.respond(to: request, withResult: .success)
        } else {
            peripheral.respond(to: request, withResult: .attributeNotFound)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        guard characteristic.uuid == Self.responseUUID else { return }
        if targetCentral == nil {
            targetCentral = central
            closePairingPromptAfterConnection()
            emitEvent([
                "action": "configPairingEvent",
                "platform": "ios",
                "role": "target",
                "event": "subscribed",
                "success": true
            ])
            return
        }

        if targetCentral?.identifier != central.identifier {
            emitEvent([
                "action": "configPairingEvent",
                "platform": "ios",
                "role": "target",
                "event": "subscriptionRejected",
                "success": false,
                "error": "Another config device is already connected."
            ])
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        guard characteristic.uuid == Self.responseUUID,
              targetCentral?.identifier == central.identifier else { return }
        targetCentral = nil
    }
}

extension ConfigPairingBridge: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startCentralScanIfReady()
        } else {
            emitEvent([
                "action": centralEventAction(),
                "platform": "ios",
                "role": "configurator",
                "event": "bluetoothState",
                "success": false,
                "state": bluetoothStateName(central.state)
            ])
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if centralMode == .persistentDevice {
            guard persistentDeviceScanning else { return }
            discoveredPersistentDevices[peripheral.identifier] = peripheral
            let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            emitEvent([
                "action": "configDeviceEvent",
                "platform": "ios",
                "role": "configurator",
                "event": "discovered",
                "success": true,
                "scanId": peripheral.identifier.uuidString,
                "name": advertisedName ?? peripheral.name ?? "ESP32",
                "rssi": RSSI,
                "connectable": advertisementData[CBAdvertisementDataIsConnectable] as? Bool ?? true
            ])
            return
        }

        guard connectedPeripheral == nil else { return }
        connectedPeripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        central.connect(peripheral, options: nil)
        emitEvent([
            "action": "configPairingEvent",
            "platform": "ios",
            "role": "configurator",
            "event": "discovered",
            "success": true,
            "name": peripheral.name ?? "",
            "rssi": RSSI
        ])
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([activeCentralServiceUUID()])
        emitEvent([
            "action": centralEventAction(),
            "platform": "ios",
            "role": "configurator",
            "event": "connected",
            "success": true,
            "name": peripheral.name ?? "",
            "scanId": peripheral.identifier.uuidString
        ])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectedPeripheral = nil
        resetCentralWriteQueue()
        emitEvent([
            "action": centralEventAction(),
            "platform": "ios",
            "role": "configurator",
            "event": "connectFailed",
            "success": false,
            "error": error?.localizedDescription ?? "Could not connect."
        ])
        startCentralScanIfReady()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedPeripheral = nil
        centralCommandCharacteristic = nil
        centralResponseCharacteristic = nil
        centralChunkAccumulators.removeAll()
        resetCentralWriteQueue()
        emitEvent([
            "action": centralEventAction(),
            "platform": "ios",
            "role": "configurator",
            "event": "disconnected",
            "success": error == nil,
            "error": error?.localizedDescription ?? ""
        ])
    }
}

extension ConfigPairingBridge: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            emitEvent([
                "action": centralEventAction(),
                "platform": "ios",
                "role": "configurator",
                "event": "serviceDiscoveryFailed",
                "success": false,
                "error": error.localizedDescription
            ])
            return
        }

        for service in peripheral.services ?? [] where service.uuid == activeCentralServiceUUID() {
            peripheral.discoverCharacteristics([Self.commandUUID, Self.responseUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            emitEvent([
                "action": centralEventAction(),
                "platform": "ios",
                "role": "configurator",
                "event": "characteristicDiscoveryFailed",
                "success": false,
                "error": error.localizedDescription
            ])
            return
        }

        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == Self.commandUUID {
                centralCommandCharacteristic = characteristic
            }
            if characteristic.uuid == Self.responseUUID {
                centralResponseCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }

    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.responseUUID else { return }
        if let error {
            emitEvent([
                "action": centralEventAction(),
                "platform": "ios",
                "role": "configurator",
                "event": "notificationSetupFailed",
                "success": false,
                "error": error.localizedDescription
            ])
            return
        }

        guard characteristic.isNotifying, centralCommandCharacteristic != nil else { return }
        emitEvent([
            "action": centralEventAction(),
            "platform": "ios",
            "role": "configurator",
            "event": "ready",
            "success": true,
            "scanId": peripheral.identifier.uuidString
        ])
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            emitEvent([
                "action": centralEventAction(),
                "platform": "ios",
                "role": "configurator",
                "event": "responseError",
                "success": false,
                "error": error.localizedDescription
            ])
            return
        }

        guard let data = characteristic.value,
              let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            emitEvent([
                "action": centralEventAction(),
                "platform": "ios",
                "role": "configurator",
                "event": "responseParseFailed",
                "success": false
            ])
            return
        }
        handleCentralResponseObject(object)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            resetCentralWriteQueue()
            emitEvent([
                "action": centralEventAction(),
                "platform": "ios",
                "role": "configurator",
                "event": "writeFailed",
                "success": false,
                "error": error.localizedDescription
            ])
            return
        }
        guard characteristic.uuid == Self.commandUUID else { return }
        centralWriteInFlight = false
        writeNextCentralCommandPacket()
    }
}

private extension ConfigPairingBridge {
    func handleCentralResponseObject(_ object: [String: Any]) {
        guard configString(object["action"]) == "configPairingChunk" else {
            updateSelectedPersistentDeviceID(from: object)
            emitEvent(object)
            return
        }

        guard let chunk = ConfigPairingPayload.chunkData(from: object) else {
            emitEvent([
                "action": centralEventAction(),
                "platform": "ios",
                "role": "configurator",
                "event": "chunkParseFailed",
                "success": false
            ])
            return
        }

        var accumulator = centralChunkAccumulators[chunk.id] ?? ConfigPairingPayload.ChunkAccumulator(count: chunk.count)
        accumulator.chunks[chunk.index] = chunk.data
        centralChunkAccumulators[chunk.id] = accumulator

        guard accumulator.isComplete else { return }
        centralChunkAccumulators.removeValue(forKey: chunk.id)

        let assembled = accumulator.assembled
        guard let object = try? JSONSerialization.jsonObject(with: assembled, options: []) as? [String: Any] else {
            emitEvent([
                "action": centralEventAction(),
                "platform": "ios",
                "role": "configurator",
                "event": "chunkAssemblyFailed",
                "success": false
            ])
            return
        }
        updateSelectedPersistentDeviceID(from: object)
        emitEvent(object)
    }

    func updateSelectedPersistentDeviceID(from object: [String: Any]) {
        guard centralMode == .persistentDevice else { return }
        if let deviceID = configString(object["deviceId"]), !deviceID.isEmpty {
            selectedPersistentDeviceID = deviceID
            return
        }
        if let deviceInfo = object["deviceInfo"] as? [String: Any],
           let deviceID = configString(deviceInfo["id"]),
           !deviceID.isEmpty {
            selectedPersistentDeviceID = deviceID
        }
    }

    func centralEventAction() -> String {
        centralMode == .persistentDevice ? "configDeviceEvent" : "configPairingEvent"
    }

    func activeCentralServiceUUID() -> CBUUID {
        if centralMode == .persistentDevice {
            return Self.persistentDeviceServiceUUID
        }
        return CBUUID(string: pairingTarget?.serviceUUID ?? ConfigPairingPayload.serviceUUID)
    }
}

private func configString(_ value: Any?) -> String? {
    ConfigPairingPayload.string(value)
}

private func intConfigValue(_ value: Any?) -> Int? {
    ConfigPairingPayload.int(value)
}

private func bluetoothStateName(_ state: CBManagerState) -> String {
    switch state {
    case .unknown: return "unknown"
    case .resetting: return "resetting"
    case .unsupported: return "unsupported"
    case .unauthorized: return "unauthorized"
    case .poweredOff: return "poweredOff"
    case .poweredOn: return "poweredOn"
    @unknown default: return "unknown"
    }
}
