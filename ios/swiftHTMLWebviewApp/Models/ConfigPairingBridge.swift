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
    fileprivate static let serviceUUID = CBUUID(string: "6D8E0F22-9C2D-4E8E-A7D7-2B1D49F48A01")
    private static let commandUUID = CBUUID(string: "6D8E0F22-9C2D-4E8E-A7D7-2B1D49F48A02")
    private static let responseUUID = CBUUID(string: "6D8E0F22-9C2D-4E8E-A7D7-2B1D49F48A03")
    private static let sessionLifetimeSeconds: TimeInterval = 300

    @Published private(set) var targetPayload: String?
    @Published private(set) var targetQRCode: UIImage?
    @Published private(set) var targetExpiresAt: Date?
    @Published private(set) var targetAdvertising = false

    private var targetSessionID = ""
    private var targetSecret = ""
    private var targetExpiry = Date.distantPast
    private var peripheralManager: CBPeripheralManager?
    private var commandCharacteristic: CBMutableCharacteristic?
    private var responseCharacteristic: CBMutableCharacteristic?

    private var centralManager: CBCentralManager?
    private var pairingTarget: PairingTarget?
    private var connectedPeripheral: CBPeripheral?
    private var centralCommandCharacteristic: CBCharacteristic?
    private var centralResponseCharacteristic: CBCharacteristic?

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
        let payload = pairingPayload(sessionID: targetSessionID, secret: targetSecret, expiresAt: targetExpiry)

        targetPayload = payload
        targetQRCode = qrImage(for: payload)
        targetExpiresAt = targetExpiry

        if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
        } else {
            configurePeripheralServiceIfReady()
        }

        var response = baseResponse(request: request, action: "configPairingShow")
        response["success"] = true
        response["payload"] = payload
        response["expiresAt"] = Int(targetExpiry.timeIntervalSince1970)
        response["transport"] = "ble-gatt"
        response["serviceUUID"] = Self.serviceUUID.uuidString
        return response
    }

    func stopTargetSession(request: [String: Any]) -> [String: Any] {
        stopTargetSession()
        var response = baseResponse(request: request, action: "configPairingStop")
        response["success"] = true
        return response
    }

    func connect(request: [String: Any]) -> [String: Any] {
        guard let payload = configString(request["payload"] ?? request["pairingPayload"] ?? request["code"]),
              let target = PairingTarget(payload: payload) else {
            return errorResponse(request: request, action: "configPairingConnect", error: "Invalid config pairing payload.")
        }

        pairingTarget = target
        centralCommandCharacteristic = nil
        centralResponseCharacteristic = nil
        connectedPeripheral = nil

        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: .main)
        } else {
            startCentralScanIfReady()
        }

        var response = baseResponse(request: request, action: "configPairingConnect")
        response["success"] = true
        response["state"] = "scanning"
        response["targetName"] = target.name
        response["serviceUUID"] = target.serviceUUID.uuidString
        return response
    }

    func disconnect(request: [String: Any]) -> [String: Any] {
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        centralManager?.stopScan()
        pairingTarget = nil
        connectedPeripheral = nil
        centralCommandCharacteristic = nil
        centralResponseCharacteristic = nil

        var response = baseResponse(request: request, action: "configPairingDisconnect")
        response["success"] = true
        return response
    }

    func send(request: [String: Any]) -> [String: Any] {
        guard let target = pairingTarget else {
            return errorResponse(request: request, action: "configPairingSend", error: "No config pairing target is connected.")
        }
        guard let peripheral = connectedPeripheral,
              let characteristic = centralCommandCharacteristic else {
            return errorResponse(request: request, action: "configPairingSend", error: "Config pairing is not ready yet.")
        }

        var command: [String: Any] = [
            "sessionId": target.sessionID,
            "secret": target.secret,
            "requestId": stringOrGenerated(request["requestId"]),
            "command": configString(request["command"]) ?? configString(request["configCommand"]) ?? "statusGet"
        ]

        if let token = configString(request["token"] ?? request["securityToken"]), !token.isEmpty {
            command["token"] = token
        }
        if let settings = request["settings"] as? [String: Any] {
            command["settings"] = settings
        }
        if let ssid = configString(request["ssid"]), !ssid.isEmpty {
            command["ssid"] = ssid
        }
        if let passphrase = configString(request["passphrase"] ?? request["password"]), !passphrase.isEmpty {
            command["passphrase"] = passphrase
        }
        if let joinOnce = request["joinOnce"] as? Bool {
            command["joinOnce"] = joinOnce
        }

        guard let data = try? JSONSerialization.data(withJSONObject: command, options: []) else {
            return errorResponse(request: request, action: "configPairingSend", error: "Could not serialize config command.")
        }

        let maxLength = peripheral.maximumWriteValueLength(for: .withResponse)
        guard data.count <= maxLength else {
            return errorResponse(request: request, action: "configPairingSend", error: "Config command is too large for the negotiated BLE write length.")
        }

        peripheral.writeValue(data, for: characteristic, type: .withResponse)

        var response = baseResponse(request: request, action: "configPairingSend")
        response["success"] = true
        response["state"] = "sent"
        response["command"] = command["command"]
        response["bytes"] = data.count
        return response
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
        guard let central = centralManager,
              central.state == .poweredOn,
              let target = pairingTarget else { return }

        central.stopScan()
        central.scanForPeripherals(withServices: [target.serviceUUID], options: nil)
        emitEvent([
            "action": "configPairingEvent",
            "platform": "ios",
            "role": "configurator",
            "event": "scanning",
            "success": true,
            "serviceUUID": target.serviceUUID.uuidString
        ])
    }

    private func handleTargetCommand(_ data: Data) {
        guard let command = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            notifyTargetResponse(errorPayload(command: "unknown", error: "Invalid JSON command."))
            return
        }

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

    private func commandIsPaired(_ command: [String: Any]) -> Bool {
        Date() <= targetExpiry
            && configString(command["sessionId"] ?? command["id"]) == targetSessionID
            && configString(command["secret"]) == targetSecret
    }

    private func commandHasValidSecurityToken(_ command: [String: Any]) -> Bool {
        guard let token = configString(command["token"] ?? command["securityToken"]) else { return false }
        return token == AppSettings.shared.securityToken
    }

    private func notifyTargetResponse(_ payload: [String: Any]) {
        emitEvent(payload)
        guard let responseCharacteristic,
              let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return }

        responseCharacteristic.value = data
        peripheralManager?.updateValue(data, for: responseCharacteristic, onSubscribedCentrals: nil)
    }

    private func responsePayload(command: String, requestId: Any?) -> [String: Any] {
        [
            "action": "configPairingResponse",
            "platform": "ios",
            "role": "target",
            "command": command,
            "requestId": stringOrGenerated(requestId),
            "sessionId": targetSessionID
        ]
    }

    private func errorPayload(command: String, requestId: Any? = nil, error: String) -> [String: Any] {
        var response = responsePayload(command: command, requestId: requestId)
        response["success"] = false
        response["error"] = error
        return response
    }

    private func emitEvent(_ event: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.eventHandler?(event)
        }
    }

    private func pairingPayload(sessionID: String, secret: String, expiresAt: Date) -> String {
        var components = URLComponents()
        components.scheme = "swifthtml-config"
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "id", value: sessionID),
            URLQueryItem(name: "secret", value: secret),
            URLQueryItem(name: "service", value: Self.serviceUUID.uuidString),
            URLQueryItem(name: "expires", value: String(Int(expiresAt.timeIntervalSince1970))),
            URLQueryItem(name: "name", value: UIDevice.current.name)
        ]
        return components.string ?? "swifthtml-config://pair"
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

    private func baseResponse(request: [String: Any], action: String) -> [String: Any] {
        var response: [String: Any] = [
            "action": action,
            "platform": "ios"
        ]
        if let requestId = request["requestId"] {
            response["requestId"] = requestId
        }
        return response
    }

    private func errorResponse(request: [String: Any], action: String, error: String) -> [String: Any] {
        var response = baseResponse(request: request, action: action)
        response["success"] = false
        response["error"] = error
        return response
    }

    private func stringOrGenerated(_ value: Any?) -> String {
        let stringValue = configString(value) ?? ""
        return stringValue.isEmpty ? UUID().uuidString : stringValue
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
                handleTargetCommand(value)
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
}

extension ConfigPairingBridge: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startCentralScanIfReady()
        } else {
            emitEvent([
                "action": "configPairingEvent",
                "platform": "ios",
                "role": "configurator",
                "event": "bluetoothState",
                "success": false,
                "state": bluetoothStateName(central.state)
            ])
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
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
        peripheral.discoverServices([pairingTarget?.serviceUUID ?? Self.serviceUUID])
        emitEvent([
            "action": "configPairingEvent",
            "platform": "ios",
            "role": "configurator",
            "event": "connected",
            "success": true,
            "name": peripheral.name ?? ""
        ])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectedPeripheral = nil
        emitEvent([
            "action": "configPairingEvent",
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
        emitEvent([
            "action": "configPairingEvent",
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
                "action": "configPairingEvent",
                "platform": "ios",
                "role": "configurator",
                "event": "serviceDiscoveryFailed",
                "success": false,
                "error": error.localizedDescription
            ])
            return
        }

        for service in peripheral.services ?? [] where service.uuid == (pairingTarget?.serviceUUID ?? Self.serviceUUID) {
            peripheral.discoverCharacteristics([Self.commandUUID, Self.responseUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            emitEvent([
                "action": "configPairingEvent",
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

        if centralCommandCharacteristic != nil {
            emitEvent([
                "action": "configPairingEvent",
                "platform": "ios",
                "role": "configurator",
                "event": "ready",
                "success": true
            ])
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            emitEvent([
                "action": "configPairingEvent",
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
                "action": "configPairingEvent",
                "platform": "ios",
                "role": "configurator",
                "event": "responseParseFailed",
                "success": false
            ])
            return
        }
        emitEvent(object)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            emitEvent([
                "action": "configPairingEvent",
                "platform": "ios",
                "role": "configurator",
                "event": "writeFailed",
                "success": false,
                "error": error.localizedDescription
            ])
        }
    }
}

private struct PairingTarget {
    let sessionID: String
    let secret: String
    let serviceUUID: CBUUID
    let name: String

    init?(payload: String) {
        guard let components = URLComponents(string: payload),
              components.scheme == "swifthtml-config",
              components.host == "pair" else { return nil }

        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        guard let sessionID = items["id"], !sessionID.isEmpty,
              let secret = items["secret"], !secret.isEmpty else { return nil }

        self.sessionID = sessionID
        self.secret = secret
        self.serviceUUID = CBUUID(string: items["service"] ?? ConfigPairingBridge.serviceUUID.uuidString)
        self.name = items["name"] ?? ""
    }
}

private func configString(_ value: Any?) -> String? {
    guard let value else { return nil }
    if value is NSNull { return "" }
    if let stringValue = value as? String {
        return stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let numberValue = value as? NSNumber {
        return numberValue.stringValue
    }
    return nil
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
