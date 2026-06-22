//
//  SensorPayloadTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class SensorPayloadTests: XCTestCase {
    func testCapabilitiesResponseUsesInjectedAvailabilityAndOverlaySupport() {
        let response = SensorPayload.capabilitiesResponse(
            request: ["requestId": "req-sensors"],
            sensors: [
                .init(typeName: "accelerometer", available: true),
                .init(typeName: "gyroscope", available: false)
            ],
            arOverlaySupported: false
        )

        XCTAssertEqual(response["platform"] as? String, "ios")
        XCTAssertEqual(response["action"] as? String, "sensorCapabilitiesGet")
        XCTAssertEqual(response["requestId"] as? String, "req-sensors")
        XCTAssertEqual(response["success"] as? Bool, true)

        let sensors = response["sensors"] as? [[String: Any]]
        XCTAssertEqual(sensors?.count, 2)
        XCTAssertEqual(sensors?.first?["typeName"] as? String, "accelerometer")
        XCTAssertEqual(sensors?.first?["available"] as? Bool, true)
        XCTAssertEqual(sensors?[1]["typeName"] as? String, "gyroscope")
        XCTAssertEqual(sensors?[1]["available"] as? Bool, false)

        let capabilities = response["capabilities"] as? [String: Any]
        XCTAssertEqual(capabilities?["sensorCapabilitiesGet"] as? Bool, true)
        XCTAssertEqual(capabilities?["sensorStreamStart"] as? Bool, true)
        XCTAssertEqual(capabilities?["sensorStreamStop"] as? Bool, true)
        XCTAssertEqual(capabilities?["arOverlayOpen"] as? Bool, false)
        XCTAssertEqual(capabilities?["arOverlaySupported"] as? Bool, false)
        XCTAssertEqual(capabilities?["arReplayOpen"] as? Bool, false)
        XCTAssertEqual(capabilities?["arReplayClose"] as? Bool, true)
    }

    func testStreamRequestDefaultsAndClampsInterval() {
        XCTAssertEqual(SensorPayload.streamRequest(from: [:]).intervalMs, 500)
        XCTAssertEqual(SensorPayload.streamRequest(from: ["intervalMs": 33]).intervalMs, 100)
        XCTAssertEqual(SensorPayload.streamRequest(from: ["intervalMs": 250.6]).intervalMs, 251)
        XCTAssertEqual(SensorPayload.streamRequest(from: ["intervalMs": "750"]).intervalMs, 750)
        XCTAssertEqual(SensorPayload.streamRequest(from: ["intervalMs": Double.nan]).intervalMs, 500)
        XCTAssertEqual(SensorPayload.streamRequest(from: ["intervalMs": 250]).intervalSeconds, 0.25)
    }

    func testStartAndStopResponsesUseCommonBridgeShape() {
        let request: [String: Any] = ["requestId": "req-stream"]
        let start = SensorPayload.streamStartResponse(
            request: request,
            streamRequest: .init(intervalMs: 250)
        )

        XCTAssertEqual(start["platform"] as? String, "ios")
        XCTAssertEqual(start["action"] as? String, "sensorStreamStart")
        XCTAssertEqual(start["requestId"] as? String, "req-stream")
        XCTAssertEqual(start["success"] as? Bool, true)
        XCTAssertEqual(start["intervalMs"] as? Int, 250)

        let stop = SensorPayload.stopResponse(request: request)
        XCTAssertEqual(stop["platform"] as? String, "ios")
        XCTAssertEqual(stop["action"] as? String, "sensorStreamStop")
        XCTAssertEqual(stop["requestId"] as? String, "req-stream")
        XCTAssertEqual(stop["success"] as? Bool, true)
    }

    func testSensorDataEventUsesCatalogedPayloadShape() {
        let event = SensorPayload.sensorDataEvent(samples: [
            .init(
                typeName: "accelerometer",
                values: [1.25, -2.5, 0.0],
                timestampSeconds: 123.456
            ),
            .init(
                typeName: "deviceMotion",
                timestampSeconds: 124,
                attitude: ["roll": 0.1, "pitch": -0.2, "yaw": 0.3],
                gravity: [0.0, -1.0, 0.0],
                userAcceleration: [0.01, 0.02, 0.03]
            )
        ])

        XCTAssertEqual(event["platform"] as? String, "ios")
        XCTAssertEqual(event["action"] as? String, "sensorData")
        XCTAssertEqual(event["success"] as? Bool, true)

        let sensors = event["sensors"] as? [[String: Any]]
        XCTAssertEqual(sensors?.count, 2)
        XCTAssertEqual(sensors?.first?["typeName"] as? String, "accelerometer")
        XCTAssertEqual(sensors?.first?["values"] as? [Double], [1.25, -2.5, 0.0])
        XCTAssertEqual(sensors?.first?["timestampSeconds"] as? Double, 123.456)

        let deviceMotion = sensors?[1]
        XCTAssertEqual(deviceMotion?["typeName"] as? String, "deviceMotion")
        XCTAssertEqual(deviceMotion?["timestampSeconds"] as? Double, 124)
        let attitude = deviceMotion?["attitude"] as? [String: Double]
        XCTAssertEqual(attitude?["roll"], 0.1)
        XCTAssertEqual(attitude?["pitch"], -0.2)
        XCTAssertEqual(attitude?["yaw"], 0.3)
        XCTAssertEqual(deviceMotion?["gravity"] as? [Double], [0.0, -1.0, 0.0])
        XCTAssertEqual(deviceMotion?["userAcceleration"] as? [Double], [0.01, 0.02, 0.03])
    }

    func testErrorResponseKeepsRequestId() {
        let response = SensorPayload.errorResponse(
            request: ["requestId": "req-sensor-error"],
            action: "sensorStreamStart",
            error: "Sensor service is not available."
        )

        XCTAssertEqual(response["platform"] as? String, "ios")
        XCTAssertEqual(response["action"] as? String, "sensorStreamStart")
        XCTAssertEqual(response["requestId"] as? String, "req-sensor-error")
        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertEqual(response["error"] as? String, "Sensor service is not available.")
    }
}
