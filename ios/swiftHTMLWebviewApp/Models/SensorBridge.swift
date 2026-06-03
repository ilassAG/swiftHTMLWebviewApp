//
//  SensorBridge.swift
//  swiftHTMLWebviewApp
//
//  CoreMotion live sensor bridge.
//

import CoreMotion
import Foundation

@MainActor
final class SensorBridge: ObservableObject {
    private let motion = CMMotionManager()
    private let queue = OperationQueue()
    private var timer: Timer?
    private var intervalSeconds: TimeInterval = 0.5
    private var eventHandler: (([String: Any]) -> Void)?

    func capabilities(request: [String: Any]) -> [String: Any] {
        var response = baseResponse(request: request, action: "sensorCapabilitiesGet")
        response["success"] = true
        response["sensors"] = [
            ["typeName": "accelerometer", "available": motion.isAccelerometerAvailable],
            ["typeName": "gyroscope", "available": motion.isGyroAvailable],
            ["typeName": "magnetometer", "available": motion.isMagnetometerAvailable],
            ["typeName": "deviceMotion", "available": motion.isDeviceMotionAvailable]
        ]
        return response
    }

    func start(request: [String: Any], eventHandler: @escaping ([String: Any]) -> Void) -> [String: Any] {
        stopInternal()
        self.eventHandler = eventHandler
        intervalSeconds = max(0.1, (doubleValue(request["intervalMs"]) ?? 500) / 1000.0)
        let updateInterval = intervalSeconds

        if motion.isAccelerometerAvailable {
            motion.accelerometerUpdateInterval = updateInterval
            motion.startAccelerometerUpdates()
        }
        if motion.isGyroAvailable {
            motion.gyroUpdateInterval = updateInterval
            motion.startGyroUpdates()
        }
        if motion.isMagnetometerAvailable {
            motion.magnetometerUpdateInterval = updateInterval
            motion.startMagnetometerUpdates()
        }
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = updateInterval
            motion.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: queue) { _, _ in }
        }

        timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.emitSnapshot()
            }
        }

        var response = baseResponse(request: request, action: "sensorStreamStart")
        response["success"] = true
        response["intervalMs"] = Int(intervalSeconds * 1000)
        return response
    }

    func stop(request: [String: Any]) -> [String: Any] {
        stopInternal()
        var response = baseResponse(request: request, action: "sensorStreamStop")
        response["success"] = true
        return response
    }

    func shutdown() {
        stopInternal()
    }

    private func emitSnapshot() {
        var sensors: [[String: Any]] = []
        if let data = motion.accelerometerData {
            sensors.append([
                "typeName": "accelerometer",
                "values": [data.acceleration.x, data.acceleration.y, data.acceleration.z],
                "timestampSeconds": data.timestamp
            ])
        }
        if let data = motion.gyroData {
            sensors.append([
                "typeName": "gyroscope",
                "values": [data.rotationRate.x, data.rotationRate.y, data.rotationRate.z],
                "timestampSeconds": data.timestamp
            ])
        }
        if let data = motion.magnetometerData {
            sensors.append([
                "typeName": "magnetometer",
                "values": [data.magneticField.x, data.magneticField.y, data.magneticField.z],
                "timestampSeconds": data.timestamp
            ])
        }
        if let data = motion.deviceMotion {
            sensors.append([
                "typeName": "deviceMotion",
                "attitude": [
                    "roll": data.attitude.roll,
                    "pitch": data.attitude.pitch,
                    "yaw": data.attitude.yaw
                ],
                "gravity": [data.gravity.x, data.gravity.y, data.gravity.z],
                "userAcceleration": [data.userAcceleration.x, data.userAcceleration.y, data.userAcceleration.z],
                "timestampSeconds": data.timestamp
            ])
        }

        eventHandler?([
            "platform": "ios",
            "action": "sensorData",
            "success": true,
            "sensors": sensors
        ])
    }

    private func stopInternal() {
        timer?.invalidate()
        timer = nil
        motion.stopAccelerometerUpdates()
        motion.stopGyroUpdates()
        motion.stopMagnetometerUpdates()
        motion.stopDeviceMotionUpdates()
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
}
