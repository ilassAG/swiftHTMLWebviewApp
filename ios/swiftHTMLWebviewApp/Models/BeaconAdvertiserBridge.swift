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
    private var activeConfig: BeaconPayload.AdvertiseConfig?
    private var pendingRequest: [String: Any]?
    private var eventHandler: (([String: Any]) -> Void)?
    private var advertising = false

    func start(request: [String: Any], onEvent: @escaping ([String: Any]) -> Void) -> [String: Any] {
        guard let config = BeaconPayload.advertiseConfig(from: request, defaultUUID: AppSettings.shared.beaconUUID) else {
            return BeaconPayload.errorResponse(
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

        let state = peripheralManager?.state == .poweredOn ? "starting" : "waitingForBluetooth"
        return BeaconPayload.advertiseStartResponse(request: request, config: config, state: state)
    }

    func stop(request: [String: Any]) -> [String: Any] {
        stopAdvertising()
        return BeaconPayload.advertiseStopResponse(request: request)
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
                major: CLBeaconMajorValue(config.major),
                minor: CLBeaconMinorValue(config.minor),
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
        eventHandler?(BeaconPayload.advertiseStateEvent(
            request: pendingRequest ?? [:],
            config: config,
            success: success,
            state: state,
            advertising: advertising,
            error: error
        ))
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
