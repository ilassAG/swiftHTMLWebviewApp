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
        SensorPayload.capabilitiesResponse(
            request: request,
            sensors: [
                .init(typeName: "accelerometer", available: motion.isAccelerometerAvailable),
                .init(typeName: "gyroscope", available: motion.isGyroAvailable),
                .init(typeName: "magnetometer", available: motion.isMagnetometerAvailable),
                .init(typeName: "deviceMotion", available: motion.isDeviceMotionAvailable)
            ],
            arOverlaySupported: AROverlayBridge.isSupported()
        )
    }

    func start(request: [String: Any], eventHandler: @escaping ([String: Any]) -> Void) -> [String: Any] {
        stopInternal()
        self.eventHandler = eventHandler
        let streamRequest = SensorPayload.streamRequest(from: request)
        intervalSeconds = streamRequest.intervalSeconds
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

        return SensorPayload.streamStartResponse(request: request, streamRequest: streamRequest)
    }

    func stop(request: [String: Any]) -> [String: Any] {
        stopInternal()
        return SensorPayload.stopResponse(request: request)
    }

    func shutdown() {
        stopInternal()
    }

    private func emitSnapshot() {
        var sensors: [SensorPayload.MotionSample] = []
        if let data = motion.accelerometerData {
            sensors.append(.init(
                typeName: "accelerometer",
                values: [data.acceleration.x, data.acceleration.y, data.acceleration.z],
                timestampSeconds: data.timestamp
            ))
        }
        if let data = motion.gyroData {
            sensors.append(.init(
                typeName: "gyroscope",
                values: [data.rotationRate.x, data.rotationRate.y, data.rotationRate.z],
                timestampSeconds: data.timestamp
            ))
        }
        if let data = motion.magnetometerData {
            sensors.append(.init(
                typeName: "magnetometer",
                values: [data.magneticField.x, data.magneticField.y, data.magneticField.z],
                timestampSeconds: data.timestamp
            ))
        }
        if let data = motion.deviceMotion {
            sensors.append(.init(
                typeName: "deviceMotion",
                timestampSeconds: data.timestamp,
                attitude: [
                    "roll": data.attitude.roll,
                    "pitch": data.attitude.pitch,
                    "yaw": data.attitude.yaw
                ],
                gravity: [data.gravity.x, data.gravity.y, data.gravity.z],
                userAcceleration: [data.userAcceleration.x, data.userAcceleration.y, data.userAcceleration.z]
            ))
        }

        eventHandler?(SensorPayload.sensorDataEvent(samples: sensors))
    }

    private func stopInternal() {
        timer?.invalidate()
        timer = nil
        motion.stopAccelerometerUpdates()
        motion.stopGyroUpdates()
        motion.stopMagnetometerUpdates()
        motion.stopDeviceMotionUpdates()
    }
}
