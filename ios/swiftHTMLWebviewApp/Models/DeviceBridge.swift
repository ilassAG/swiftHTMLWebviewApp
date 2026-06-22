//
//  DeviceBridge.swift
//  swiftHTMLWebviewApp
//
//  Device, screenshot, Wi-Fi status, and sound helpers for the JS bridge.
//

import AVFoundation
import ARKit
@preconcurrency import CoreBluetooth
import CoreMotion
import CoreNFC
import Darwin
import Foundation
@preconcurrency import NetworkExtension
import UIKit
import WebKit

final class DeviceBridge: ObservableObject {
    private var audioPlayer: AVAudioPlayer?

    @MainActor
    func deviceInfo(request: [String: Any]) -> [String: Any] {
        UIDevice.current.isBatteryMonitoringEnabled = true
        var response = DeviceBridgePayload.baseResponse(request: request, action: "deviceInfoGet")
        response["success"] = true
        response["name"] = UIDevice.current.name
        response["configuredDeviceName"] = AppSettings.shared.deviceName
        response["configuredDeviceUUID"] = AppSettings.shared.deviceUUIDString
        response["configuredDeviceLocation"] = AppSettings.shared.deviceLocation
        response["os"] = UIDevice.current.systemName
        response["osVersion"] = UIDevice.current.systemVersion
        response["device"] = UIDevice.current.model
        response["model"] = utsMachine()
        response["modelName"] = UIDevice.current.localizedModel
        response["identifierForVendor"] = UIDevice.current.identifierForVendor?.uuidString ?? ""
        response["serialNumber"] = "unavailable"
        response["appVersion"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        response["buildNumber"] = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        response["battery"] = batteryInfo()
        response["screen"] = screenInfo()
        response["memory"] = memoryInfo()
        response["network"] = DeviceBridge.networkInfo()
        response["cameras"] = cameraInfo()
        response["sensors"] = sensorInfo()
        response["capabilities"] = capabilities()
        return response
    }

    @MainActor
    func wifiStatus(request: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        let requestId = DeviceBridgePayload.requestId(from: request)
        NEHotspotNetwork.fetchCurrent { currentNetwork in
            completion(DeviceBridgePayload.wifiStatusResponse(
                requestId: requestId,
                wifi: DeviceBridge.networkInfo(currentNetwork: currentNetwork)
            ))
        }
    }

    @MainActor
    func configureWifi(request: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        let wifiRequest = DeviceBridgePayload.wifiConfigureRequest(from: request)
        let persistedServerURL = persistServerURLIfPresent(in: request)
        guard !wifiRequest.ssid.isEmpty else {
            completion(DeviceBridgePayload.errorResponse(request: request, action: "wifiConfigure", error: "ssid is required."))
            return
        }

        let configuration: NEHotspotConfiguration
        if wifiRequest.passphrase.isEmpty {
            configuration = NEHotspotConfiguration(ssid: wifiRequest.ssid)
        } else {
            configuration = NEHotspotConfiguration(ssid: wifiRequest.ssid, passphrase: wifiRequest.passphrase, isWEP: false)
        }
        configuration.joinOnce = wifiRequest.joinOnce

        NEHotspotConfigurationManager.shared.apply(configuration) { error in
            var response = DeviceBridgePayload.wifiConfigureResponse(
                requestId: wifiRequest.requestId,
                ssid: wifiRequest.ssid,
                joinOnce: wifiRequest.joinOnce,
                persistedServerURL: persistedServerURL
            )
            response["success"] = error == nil
            if let error = error as NSError? {
                response["nativeErrorDomain"] = error.domain
                response["nativeErrorCode"] = error.code
                response["nativeErrorMessage"] = error.localizedDescription
                if error.domain == NEHotspotConfigurationErrorDomain
                    && error.code == NEHotspotConfigurationError.alreadyAssociated.rawValue {
                    response["success"] = true
                    response["alreadyAssociated"] = true
                } else {
                    DeviceBridge.applyWifiErrorDetails(error, response: &response)
                }
            }
            DispatchQueue.main.async {
                completion(response)
            }
        }
    }

    @MainActor
    func waitForWifiReady(
        ssid: String?,
        timeout: TimeInterval = 75,
        pollInterval: TimeInterval = 1,
        completion: @escaping ([String: Any]) -> Void
    ) {
        let targetSSID = ssid?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let startedAt = Date()

        func poll() {
            NEHotspotNetwork.fetchCurrent { currentNetwork in
                let wifiInfo = DeviceBridge.networkInfo(currentNetwork: currentNetwork)
                let wifiIpAddresses = (wifiInfo["wifiIpAddresses"] as? [String]) ?? []
                let currentSSID = currentNetwork?.ssid ?? ""
                let hasWifiAddress = !wifiIpAddresses.isEmpty
                let ssidMatches = targetSSID.isEmpty || currentSSID == targetSSID || currentSSID.isEmpty

                if hasWifiAddress && ssidMatches {
                    DispatchQueue.main.async {
                        completion([
                            "platform": "ios",
                            "action": "wifiReady",
                            "success": true,
                            "ssid": currentSSID,
                            "targetSSID": targetSSID,
                            "wifi": wifiInfo,
                            "elapsedSeconds": Date().timeIntervalSince(startedAt)
                        ])
                    }
                    return
                }

                if Date().timeIntervalSince(startedAt) >= timeout {
                    DispatchQueue.main.async {
                        completion([
                            "platform": "ios",
                            "action": "wifiReady",
                            "success": false,
                            "ssid": currentSSID,
                            "targetSSID": targetSSID,
                            "wifi": wifiInfo,
                            "elapsedSeconds": Date().timeIntervalSince(startedAt),
                            "error": "Timed out waiting for Wi-Fi connectivity."
                        ])
                    }
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) {
                    poll()
                }
            }
        }

        poll()
    }

    private func persistServerURLIfPresent(in request: [String: Any]) -> String? {
        let directValue = firstNonEmptyString(in: request, keys: [
            "serverURL",
            "serverUrl",
            "defaultServerURL",
            "defaultServerUrl",
            "mobileURL",
            "mobileUrl",
            "url"
        ])
        let backendValue = firstNonEmptyString(in: request, keys: [
            "backendURL",
            "backendUrl"
        ])

        let serverURL = directValue ?? mobileURL(fromBackendURL: backendValue, linkId: stringValue(request["linkId"]))
        guard let serverURL, !serverURL.isEmpty else {
            return nil
        }

        let snapshot = AppSettings.shared.applyConfiguration(["serverURL": serverURL])
        return snapshot["serverURL"] as? String ?? serverURL
    }

    private func firstNonEmptyString(in request: [String: Any], keys: [String]) -> String? {
        for key in keys {
            let value = stringValue(request[key]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func mobileURL(fromBackendURL backendURL: String?, linkId: String) -> String? {
        guard let backendURL, var components = URLComponents(string: backendURL) else {
            return nil
        }

        components.path = "/mobile/"
        components.queryItems = linkId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : [URLQueryItem(name: "link", value: linkId)]
        components.fragment = nil
        return components.url?.absoluteString
    }

    @MainActor
    func screenshot(request: [String: Any], webView: WKWebView, completion: @escaping ([String: Any]) -> Void) {
        let maxWidth = max(240, min(2160, intValue(request["maxWidth"]) ?? 1080))
        let quality = max(0.25, min(0.95, (doubleValue(request["quality"]) ?? 82.0) / 100.0))
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        webView.takeSnapshot(with: config) { image, error in
            if let error {
                completion(DeviceBridgePayload.errorResponse(request: request, action: "screenshotGet", error: error.localizedDescription))
                return
            }
            guard let image else {
                completion(DeviceBridgePayload.errorResponse(request: request, action: "screenshotGet", error: "No screenshot image was produced."))
                return
            }
            let output = self.scale(image: image, maxWidth: CGFloat(maxWidth))
            guard let data = output.jpegData(compressionQuality: quality) else {
                completion(DeviceBridgePayload.errorResponse(request: request, action: "screenshotGet", error: "JPEG encoding failed."))
                return
            }
            var response = DeviceBridgePayload.baseResponse(request: request, action: "screenshotGet")
            response["success"] = true
            response["format"] = "jpeg"
            response["width"] = output.cgImage?.width ?? Int(output.size.width * output.scale)
            response["height"] = output.cgImage?.height ?? Int(output.size.height * output.scale)
            response["imageData"] = "data:image/jpeg;base64,\(data.base64EncodedString())"
            completion(response)
        }
    }

    @MainActor
    func playSound(request: [String: Any]) -> [String: Any] {
        let sound = DeviceBridgePayload.soundRequest(from: request)

        do {
            let data = try wavToneData(frequencyHz: sound.frequencyHz, durationMs: sound.durationMs, volume: sound.volume)
            let player = try AVAudioPlayer(data: data)
            player.prepareToPlay()
            player.play()
            audioPlayer = player
            return DeviceBridgePayload.soundResponse(request: request, sound: sound)
        } catch {
            return DeviceBridgePayload.errorResponse(request: request, action: "soundPlay", error: error.localizedDescription)
        }
    }

    private func capabilities() -> [String: Any] {
        DeviceBridgePayload.capabilities(
            arPositionSupported: ARPositionBridge.isSupported(),
            arGuidedMeasurementSupported: ARGuidedMeasurementBridge.isSupported(),
            arOverlaySupported: AROverlayBridge.isSupported(),
            roomPlanSupported: RoomPlanBridge.isSupported(),
            nfcTagReadAvailable: NFCTagReaderSession.readingAvailable,
            beaconAdvertiseSupported: CBPeripheralManager.authorization != .denied
        )
    }

    private static func applyWifiErrorDetails(_ error: NSError, response: inout [String: Any]) {
        guard error.domain == NEHotspotConfigurationErrorDomain else {
            response["error"] = error.localizedDescription
            return
        }

        DeviceBridgePayload.applyWifiErrorDetails(
            kind: wifiErrorKind(for: error.code),
            message: error.localizedDescription,
            response: &response
        )
    }

    private func batteryInfo() -> [String: Any] {
        let state: String
        switch UIDevice.current.batteryState {
        case .charging: state = "charging"
        case .full: state = "full"
        case .unplugged: state = "battery"
        default: state = "unknown"
        }
        return [
            "percent": UIDevice.current.batteryLevel >= 0 ? Double(UIDevice.current.batteryLevel * 100) : NSNull(),
            "charging": UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full,
            "powerSource": state
        ]
    }

    @MainActor
    private func screenInfo() -> [String: Any] {
        let screen = UIScreen.main
        return [
            "widthPixels": Int(screen.bounds.width * screen.scale),
            "heightPixels": Int(screen.bounds.height * screen.scale),
            "scale": screen.scale,
            "nativeScale": screen.nativeScale,
            "brightness": screen.brightness
        ]
    }

    private func memoryInfo() -> [String: Any] {
        [
            "totalBytes": ProcessInfo.processInfo.physicalMemory
        ]
    }

    private static func networkInfo(currentNetwork: NEHotspotNetwork? = nil) -> [String: Any] {
        DeviceBridgePayload.wifiInfo(
            ipAddresses: ipAddresses(),
            wifiIpAddresses: ipAddresses(interfaceName: "en0"),
            currentNetwork: currentNetwork.map {
                DeviceBridgePayload.CurrentWiFi(
                    ssid: $0.ssid,
                    bssid: $0.bssid,
                    securityTypeRawValue: $0.securityType.rawValue
                )
            }
        )
    }

    private func cameraInfo() -> [[String: Any]] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera, .builtInDualCamera, .builtInTrueDepthCamera],
            mediaType: .video,
            position: .unspecified
        )
        return session.devices.map { device in
            [
                "id": device.uniqueID,
                "name": device.localizedName,
                "position": cameraPositionName(device.position),
                "type": device.deviceType.rawValue
            ]
        }
    }

    private func sensorInfo() -> [[String: Any]] {
        let motion = CMMotionManager()
        return [
            ["typeName": "accelerometer", "available": motion.isAccelerometerAvailable],
            ["typeName": "gyroscope", "available": motion.isGyroAvailable],
            ["typeName": "magnetometer", "available": motion.isMagnetometerAvailable],
            ["typeName": "deviceMotion", "available": motion.isDeviceMotionAvailable]
        ]
    }

    private static func ipAddresses(interfaceName: String? = nil) -> [String] {
        var result: [String] = []
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let first = ifaddrPointer else {
            return result
        }
        defer { freeifaddrs(ifaddrPointer) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let name = String(cString: interface.ifa_name)
            if let interfaceName, name != interfaceName { continue }
            let family = interface.ifa_addr.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(interface.ifa_addr.pointee.sa_len)
            if getnameinfo(interface.ifa_addr, length, &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                let address = String(cString: hostname)
                if !address.hasPrefix("127.") && address != "::1" {
                    result.append(address)
                }
            }
        }
        return result
    }

    private func utsMachine() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { result, child in
            guard let value = child.value as? Int8, value != 0 else { return }
            result.append(String(UnicodeScalar(UInt8(value))))
        }
    }

    private func cameraPositionName(_ position: AVCaptureDevice.Position) -> String {
        switch position {
        case .front: return "front"
        case .back: return "back"
        case .unspecified: return "unspecified"
        @unknown default: return "unknown"
        }
    }

    private func scale(image: UIImage, maxWidth: CGFloat) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        guard pixelWidth > maxWidth else { return image }

        let scale = maxWidth / pixelWidth
        let pixelHeight = image.size.height * image.scale
        let target = CGSize(width: maxWidth, height: pixelHeight * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    private func wavToneData(frequencyHz: Int, durationMs: Int, volume: Double) throws -> Data {
        let sampleRate = 44100
        let sampleCount = max(1, durationMs * sampleRate / 1000)
        var pcm = Data(capacity: sampleCount * 2)
        for index in 0..<sampleCount {
            let angle = 2.0 * Double.pi * Double(index) * Double(frequencyHz) / Double(sampleRate)
            var sample = Int16((sin(angle) * volume * Double(Int16.max)).rounded())
            withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
        }

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(UInt32(36 + pcm.count).littleEndianData)
        data.append("WAVEfmt ".data(using: .ascii)!)
        data.append(UInt32(16).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(UInt32(sampleRate).littleEndianData)
        data.append(UInt32(sampleRate * 2).littleEndianData)
        data.append(UInt16(2).littleEndianData)
        data.append(UInt16(16).littleEndianData)
        data.append("data".data(using: .ascii)!)
        data.append(UInt32(pcm.count).littleEndianData)
        data.append(pcm)
        return data
    }

    private static func wifiErrorKind(for code: Int) -> DeviceBridgePayload.WifiErrorKind {
        switch code {
        case NEHotspotConfigurationError.userDenied.rawValue:
            return .userDenied
        case NEHotspotConfigurationError.invalidSSID.rawValue:
            return .invalidSSID
        case NEHotspotConfigurationError.invalidWPAPassphrase.rawValue:
            return .invalidWPAPassphrase
        case NEHotspotConfigurationError.invalidWEPPassphrase.rawValue:
            return .invalidWEPPassphrase
        case NEHotspotConfigurationError.pending.rawValue:
            return .pending
        case NEHotspotConfigurationError.applicationIsNotInForeground.rawValue:
            return .applicationIsNotInForeground
        default:
            return .other
        }
    }
}

private extension FixedWidthInteger {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}
