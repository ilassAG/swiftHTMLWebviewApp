//
//  DeviceBridge.swift
//  swiftHTMLWebviewApp
//
//  Device, screenshot, Wi-Fi status, and sound helpers for the JS bridge.
//

import AVFoundation
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
        var response = baseResponse(request: request, action: "deviceInfoGet")
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
        let requestId = request["requestId"].map { stringValue($0) }.flatMap { $0.isEmpty ? nil : $0 }
        NEHotspotNetwork.fetchCurrent { currentNetwork in
            var response = DeviceBridge.baseResponse(requestId: requestId, action: "wifiStatusGet")
            response["success"] = true
            response["wifi"] = DeviceBridge.networkInfo(currentNetwork: currentNetwork)
            completion(response)
        }
    }

    @MainActor
    func configureWifi(request: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        let ssid = stringValue(request["ssid"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let passphrase = (stringValue(request["passphrase"]).isEmpty ? stringValue(request["password"]) : stringValue(request["passphrase"]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let requestId = request["requestId"].map { stringValue($0) }.flatMap { $0.isEmpty ? nil : $0 }
        guard !ssid.isEmpty else {
            completion(errorResponse(request: request, action: "wifiConfigure", error: "ssid is required."))
            return
        }

        let configuration: NEHotspotConfiguration
        if passphrase.isEmpty {
            configuration = NEHotspotConfiguration(ssid: ssid)
        } else {
            configuration = NEHotspotConfiguration(ssid: ssid, passphrase: passphrase, isWEP: false)
        }
        let joinOnce = boolValue(request["joinOnce"]) ?? false
        configuration.joinOnce = joinOnce

        NEHotspotConfigurationManager.shared.apply(configuration) { error in
            var response = DeviceBridge.baseResponse(requestId: requestId, action: "wifiConfigure")
            response["success"] = error == nil
            response["method"] = "NEHotspotConfiguration"
            response["ssid"] = ssid
            response["joinOnce"] = joinOnce
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
    func screenshot(request: [String: Any], webView: WKWebView, completion: @escaping ([String: Any]) -> Void) {
        let maxWidth = max(240, min(2160, intValue(request["maxWidth"]) ?? 1080))
        let quality = max(0.25, min(0.95, (doubleValue(request["quality"]) ?? 82.0) / 100.0))
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        webView.takeSnapshot(with: config) { image, error in
            if let error {
                completion(self.errorResponse(request: request, action: "screenshotGet", error: error.localizedDescription))
                return
            }
            guard let image else {
                completion(self.errorResponse(request: request, action: "screenshotGet", error: "No screenshot image was produced."))
                return
            }
            let output = self.scale(image: image, maxWidth: CGFloat(maxWidth))
            guard let data = output.jpegData(compressionQuality: quality) else {
                completion(self.errorResponse(request: request, action: "screenshotGet", error: "JPEG encoding failed."))
                return
            }
            var response = self.baseResponse(request: request, action: "screenshotGet")
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
        let frequencyHz = max(80, min(4000, intValue(request["frequencyHz"]) ?? 880))
        let durationMs = max(40, min(5000, intValue(request["durationMs"]) ?? 240))
        let volume = max(0.0, min(1.0, doubleValue(request["volume"]) ?? 0.85))

        do {
            let data = try wavToneData(frequencyHz: frequencyHz, durationMs: durationMs, volume: volume)
            let player = try AVAudioPlayer(data: data)
            player.prepareToPlay()
            player.play()
            audioPlayer = player
            var response = baseResponse(request: request, action: "soundPlay")
            response["success"] = true
            response["frequencyHz"] = frequencyHz
            response["durationMs"] = durationMs
            response["volume"] = volume
            return response
        } catch {
            return errorResponse(request: request, action: "soundPlay", error: error.localizedDescription)
        }
    }

    private func capabilities() -> [String: Any] {
        [
            "deviceInfoGet": true,
            "settingsGet": true,
            "settingsSet": true,
            "screenOrientationSet": true,
            "wifiConfigure": true,
            "screenshotGet": true,
            "geoLocationGet": true,
            "screenStreamStart": true,
            "screenStreamFormats": ["jpeg"],
            "soundPlay": true,
            "idleTimerStart": true,
            "sensorStreamStart": true,
            "nfcTagRead": NFCTagReaderSession.readingAvailable,
            "beaconAdvertiseStart": BeaconAdvertiserBridge.isSupported(),
            "beaconAdvertiseStop": true,
            "beaconAdvertiseSupported": CBPeripheralManager.authorization != .denied
        ]
    }

    private static func applyWifiErrorDetails(_ error: NSError, response: inout [String: Any]) {
        guard error.domain == NEHotspotConfigurationErrorDomain else {
            response["error"] = error.localizedDescription
            return
        }

        response["capabilityRequired"] = "Hotspot Configuration"

        switch error.code {
        case NEHotspotConfigurationError.userDenied.rawValue:
            response["error"] = "The user cancelled the Wi-Fi join request."
        case NEHotspotConfigurationError.invalidSSID.rawValue:
            response["error"] = "The SSID is invalid."
        case NEHotspotConfigurationError.invalidWPAPassphrase.rawValue,
            NEHotspotConfigurationError.invalidWEPPassphrase.rawValue:
            response["error"] = "The Wi-Fi password is invalid for the selected security mode."
        case NEHotspotConfigurationError.pending.rawValue:
            response["error"] = "A Wi-Fi configuration request is already pending."
        case NEHotspotConfigurationError.applicationIsNotInForeground.rawValue:
            response["error"] = "The app must be in the foreground to configure Wi-Fi."
        default:
            let nativeMessage = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            if nativeMessage.lowercased().contains("internal") {
                response["error"] = "NEHotspotConfiguration returned an internal error. The app is probably not signed with the Hotspot Configuration capability/entitlement."
            } else {
                response["error"] = nativeMessage.isEmpty ? "Wi-Fi configuration failed." : nativeMessage
            }
        }
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
        var info: [String: Any] = [
            "ipAddresses": ipAddresses(),
            "wifiIpAddresses": ipAddresses(interfaceName: "en0")
        ]

        guard let currentNetwork else {
            info["ssid"] = "unavailable"
            info["ssidAvailable"] = false
            info["unavailableReason"] = "No current Wi-Fi details returned by iOS. The app needs the Access WiFi Information entitlement and either precise location authorization, a current network configured through NEHotspotConfiguration, an active VPN configuration, or an active DNS settings configuration."
            return info
        }

        info["ssidAvailable"] = true
        info["ssid"] = currentNetwork.ssid
        info["bssid"] = currentNetwork.bssid
        info["securityType"] = hotspotSecurityTypeName(rawValue: currentNetwork.securityType.rawValue)
        info["securityTypeRawValue"] = currentNetwork.securityType.rawValue
        return info
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

    private static func hotspotSecurityTypeName(rawValue: Int) -> String {
        switch rawValue {
        case 0: return "open"
        case 1: return "wep"
        case 2: return "personal"
        case 3: return "enterprise"
        default: return "unknown"
        }
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

    private static func baseResponse(requestId: String?, action: String) -> [String: Any] {
        var response: [String: Any] = [
            "platform": "ios",
            "action": action
        ]
        if let requestId {
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
}

private extension FixedWidthInteger {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}
