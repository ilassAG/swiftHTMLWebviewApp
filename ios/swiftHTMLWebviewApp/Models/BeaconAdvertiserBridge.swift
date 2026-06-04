//
//  BeaconAdvertiserBridge.swift
//  swiftHTMLWebviewApp
//
//  CoreBluetooth iBeacon advertiser bridge for JavaScript-controlled beacons.
//

@preconcurrency import CoreBluetooth
import CoreLocation
import Foundation

final class BeaconAdvertiserBridge: NSObject, ObservableObject {
    private var peripheralManager: CBPeripheralManager?
    private var activeConfig: BeaconAdvertiseConfig?
    private var pendingRequest: [String: Any]?
    private var eventHandler: (([String: Any]) -> Void)?
    private var advertising = false

    func start(request: [String: Any], onEvent: @escaping ([String: Any]) -> Void) -> [String: Any] {
        guard let config = BeaconAdvertiseConfig(request: request) else {
            return errorResponse(
                request: request,
                action: "beaconAdvertiseStart",
                error: "Invalid iBeacon parameters. uuid must be a UUID and major/minor must be between 0 and 65535."
            )
        }

        eventHandler = onEvent
        pendingRequest = request
        activeConfig = config

        if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(
                delegate: self,
                queue: .main,
                options: [CBPeripheralManagerOptionShowPowerAlertKey: true]
            )
        } else {
            startAdvertisingIfReady()
        }

        var response = config.response(base: baseResponse(request: request, action: "beaconAdvertiseStart"))
        response["success"] = true
        response["provider"] = "ios_corebluetooth"
        response["state"] = peripheralManager?.state == .poweredOn ? "starting" : "waitingForBluetooth"
        return response
    }

    func stop(request: [String: Any]) -> [String: Any] {
        stopAdvertising()
        var response = baseResponse(request: request, action: "beaconAdvertiseStop")
        response["success"] = true
        response["provider"] = "ios_corebluetooth"
        response["state"] = "stopped"
        return response
    }

    func shutdown() {
        stopAdvertising()
        eventHandler = nil
        pendingRequest = nil
        peripheralManager = nil
    }

    static func isSupported() -> Bool {
        CBPeripheralManager.authorization != .denied
    }

    private func startAdvertisingIfReady() {
        guard let peripheralManager, let config = activeConfig else { return }

        switch peripheralManager.state {
        case .poweredOn:
            let region = CLBeaconRegion(
                uuid: config.uuid,
                major: config.major,
                minor: config.minor,
                identifier: "SwiftHTMLWebviewAppAdvertiser"
            )
            let advertisement = region.peripheralData(withMeasuredPower: config.measuredPower.map(NSNumber.init(value:)))
            peripheralManager.stopAdvertising()
            peripheralManager.startAdvertising(advertisement as? [String: Any] ?? [:])

        case .unsupported, .unauthorized, .poweredOff:
            advertising = false
            emitState(
                success: false,
                state: bluetoothStateName(peripheralManager.state),
                error: "Bluetooth is required for iBeacon advertising."
            )

        case .unknown, .resetting:
            break

        @unknown default:
            advertising = false
            emitState(success: false, state: "unknown", error: "Bluetooth entered an unknown state.")
        }
    }

    private func stopAdvertising() {
        peripheralManager?.stopAdvertising()
        advertising = false
        activeConfig = nil
        pendingRequest = nil
    }

    private func emitState(success: Bool, state: String, error: String? = nil) {
        guard let config = activeConfig else { return }
        var response = config.response(base: baseResponse(request: pendingRequest ?? [:], action: "beaconAdvertiseStart"))
        response["success"] = success
        response["provider"] = "ios_corebluetooth"
        response["state"] = state
        response["advertising"] = advertising
        if let error {
            response["error"] = error
        }
        eventHandler?(response)
    }

    private func baseResponse(request: [String: Any], action: String) -> [String: Any] {
        var response: [String: Any] = [
            "platform": "ios",
            "action": action
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
}

extension BeaconAdvertiserBridge: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        startAdvertisingIfReady()
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            advertising = false
            emitState(success: false, state: "advertisingFailed", error: error.localizedDescription)
            return
        }

        advertising = true
        emitState(success: true, state: "advertising")
    }
}

private struct BeaconAdvertiseConfig {
    let uuid: UUID
    let major: CLBeaconMajorValue
    let minor: CLBeaconMinorValue
    let measuredPower: Int?

    init?(request: [String: Any]) {
        let uuidString = stringValue(request["uuid"] ?? request["beaconUUID"] ?? request["beaconUuid"] ?? request["proximityUUID"])
        if uuidString.isEmpty {
            uuid = AppSettings.shared.beaconUUID
        } else if let parsedUUID = UUID(uuidString: uuidString) {
            uuid = parsedUUID
        } else {
            return nil
        }

        let majorValue = intValue(request["major"]) ?? 1
        let minorValue = intValue(request["minor"]) ?? 1
        guard (0...65535).contains(majorValue),
              (0...65535).contains(minorValue) else {
            return nil
        }
        major = CLBeaconMajorValue(majorValue)
        minor = CLBeaconMinorValue(minorValue)

        if let power = intValue(request["measuredPower"] ?? request["measuredPowerDbm"] ?? request["txPower"]) {
            guard (-127...20).contains(power) else {
                return nil
            }
            measuredPower = power
        } else {
            measuredPower = nil
        }
    }

    func response(base: [String: Any]) -> [String: Any] {
        var response = base
        response["uuid"] = uuid.uuidString
        response["major"] = Int(major)
        response["minor"] = Int(minor)
        if let measuredPower {
            response["measuredPower"] = measuredPower
        }
        return response
    }
}
