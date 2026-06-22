//
//  AROverlayPayloadTests.swift
//  swiftHTMLWebviewAppTests
//

import UIKit
import XCTest
@testable import swiftHTMLWebviewApp

final class AROverlayPayloadTests: XCTestCase {
    func testGenericItemsAndLinesNormalizeRequestShape() {
        let scene = AROverlayScene(request: [
            "title": "Inspection",
            "coordinateSystem": "custom-local",
            "items": [
                [
                    "id": "marker-1",
                    "kind": "box",
                    "label": "Marker 1",
                    "caption": "Rack",
                    "position": ["x": 1.0, "y": 2.0, "z": -3.0],
                    "radius": 0.08,
                    "color": "#336699",
                    "headingYawRadians": 1.25,
                    "payload": ["domainId": "abc"]
                ],
                ["id": "missing-position"]
            ],
            "lines": [
                [
                    "id": "path-1",
                    "points": [
                        ["x": 0.0, "z": 0.0],
                        ["x": 1.0, "z": -1.0]
                    ],
                    "radius": 0.02,
                    "severity": "red"
                ]
            ]
        ])

        XCTAssertEqual(scene.title, "Inspection")
        XCTAssertEqual(scene.coordinateSystem, "custom-local")
        XCTAssertEqual(scene.items.count, 1)
        XCTAssertEqual(scene.lines.count, 1)

        let item = scene.items[0]
        XCTAssertEqual(item.id, "marker-1")
        XCTAssertEqual(item.kind, "box")
        XCTAssertEqual(item.title, "Marker 1")
        XCTAssertEqual(item.detail, "Rack")
        XCTAssertEqual(item.position.x, 1.0, accuracy: 0.001)
        XCTAssertEqual(item.position.y, 2.0, accuracy: 0.001)
        XCTAssertEqual(item.position.z, -3.0, accuracy: 0.001)
        XCTAssertEqual(item.radius, 0.08, accuracy: 0.001)
        XCTAssertEqual(item.headingYaw ?? .nan, 1.25, accuracy: 0.001)
        XCTAssertEqual(item.payload["domainId"] as? String, "abc")
        assertColor(item.color, red: 0x33, green: 0x66, blue: 0x99)

        let line = scene.lines[0]
        XCTAssertEqual(line.id, "path-1")
        XCTAssertEqual(line.points.count, 2)
        XCTAssertEqual(line.points[0].y, 0.045, accuracy: 0.001)
        XCTAssertEqual(line.radius, 0.02, accuracy: 0.001)
    }

    func testFloorPlanAndDemoOverlayCreateSceneItemsAndLines() {
        let scene = AROverlayScene(request: [
            "overlay": [
                "session": ["name": "WLAN Walk"],
                "floorPlan": [
                    "planJson": [
                        "floorY": -0.2,
                        "walls": [
                            ["x1": 0.0, "y1": 0.0, "x2": 2.0, "y2": 0.0]
                        ]
                    ]
                ],
                "tracePoints": [
                    ["arX": 0.0, "arZ": 0.0],
                    ["arX": 1.0, "arZ": -0.5],
                    ["arX": 2.0, "arZ": -1.0]
                ],
                "txPoints": [
                    [
                        "locationSampleId": "sample-1",
                        "protocol": "http",
                        "sequence": 7,
                        "status": "ok",
                        "rttMs": 42.4,
                        "severity": "violet",
                        "arX": 1.2,
                        "arZ": -0.4,
                        "meta": ["bssid": "aa:bb:cc:dd:ee:ff"]
                    ]
                ],
                "speedPoints": [
                    [
                        "id": "speed-a",
                        "downloadMbps": 12.4,
                        "uploadMbps": 4.6,
                        "latencyMs": 18.2,
                        "arX": 1.4,
                        "arZ": -0.6
                    ]
                ]
            ]
        ])

        XCTAssertEqual(scene.title, "WLAN Walk")
        XCTAssertEqual(scene.lines.count, 2)
        XCTAssertEqual(scene.items.count, 2)

        let wall = scene.lines.first { $0.id == "wall_0" }
        XCTAssertNotNil(wall)
        XCTAssertEqual(wall?.points.first?.y ?? .nan, -0.175, accuracy: 0.001)

        let trace = scene.lines.first { $0.id == "trace" }
        XCTAssertNotNil(trace)
        XCTAssertEqual(trace?.points.count, 3)
        XCTAssertEqual(trace?.points.first?.y ?? .nan, -0.145, accuracy: 0.001)

        let tx = scene.items.first { $0.id == "sample-1" }
        XCTAssertEqual(tx?.title, "HTTP #7")
        XCTAssertEqual(tx?.detail, "ok | 42 ms | aa:bb:cc:dd:ee:ff")
        XCTAssertEqual(tx?.radius ?? .nan, 0.075, accuracy: 0.001)
        XCTAssertEqual(tx?.position.y ?? .nan, -0.1, accuracy: 0.001)

        let speed = scene.items.first { $0.id == "speed-a" }
        XCTAssertEqual(speed?.kind, "speed")
        XCTAssertEqual(speed?.title, "Speedtest")
        XCTAssertEqual(speed?.detail, "Down 12 Mbit/s | Up 4.6 Mbit/s | Latenz 18 ms")
        XCTAssertEqual(speed?.position.y ?? .nan, -0.07, accuracy: 0.001)
    }

    func testOpenCloseResponsesPreserveDefaultAndAliasActions() {
        let scene = AROverlayScene(request: ["items": [["id": "a", "x": 1, "z": 2]]])

        let defaultAction = AROverlayPayload.requestAction([:], defaultAction: "arOverlayOpen")
        XCTAssertEqual(defaultAction, "arOverlayOpen")

        let aliasAction = AROverlayPayload.requestAction(["action": "arReplayOpen"], defaultAction: "arOverlayOpen")
        XCTAssertEqual(aliasAction, "arReplayOpen")

        let ready = AROverlayPayload.readyResponse(
            request: ["requestId": "req-overlay"],
            action: aliasAction,
            scene: scene,
            worldMapAvailable: true
        )
        XCTAssertEqual(ready["platform"] as? String, "ios")
        XCTAssertEqual(ready["action"] as? String, "arReplayOpen")
        XCTAssertEqual(ready["requestId"] as? String, "req-overlay")
        XCTAssertEqual(ready["success"] as? Bool, true)
        XCTAssertEqual(ready["source"] as? String, "arkit-overlay")
        XCTAssertEqual(ready["coordinateSystem"] as? String, "arkit-gravity-local")
        XCTAssertEqual(ready["itemCount"] as? Int, 1)
        XCTAssertEqual(ready["lineCount"] as? Int, 0)
        XCTAssertEqual(ready["title"] as? String, "AR Overlay")
        XCTAssertEqual(ready["worldMapAvailable"] as? Bool, true)

        let pending = AROverlayPayload.pendingPermissionResponse(
            request: [:],
            action: "arOverlayOpen",
            scene: scene,
            worldMapAvailable: false
        )
        XCTAssertEqual(pending["pendingPermission"] as? Bool, true)
        XCTAssertEqual(pending["success"] as? Bool, true)

        let close = AROverlayPayload.closeResponse(
            request: ["requestId": "close-req"],
            action: "arReplayClose"
        )
        XCTAssertEqual(close["action"] as? String, "arReplayClose")
        XCTAssertEqual(close["requestId"] as? String, "close-req")
        XCTAssertEqual(close["success"] as? Bool, true)
        XCTAssertEqual(close["source"] as? String, "arkit-overlay")
    }

    func testEventsAndErrorsUseCommonBridgeShape() {
        let request: [String: Any] = ["requestId": "req-event"]
        let item = AROverlayItem(
            id: "item-1",
            kind: "point",
            title: "Point",
            detail: "Detail",
            position: .init(1, 2, 3),
            radius: 0.05,
            color: .systemGreen,
            headingYaw: nil,
            payload: ["domain": "wifi"]
        )

        let selected = AROverlayPayload.itemSelectedEvent(request: request, item: item)
        XCTAssertEqual(selected["platform"] as? String, "ios")
        XCTAssertEqual(selected["action"] as? String, "arOverlayItemSelected")
        XCTAssertEqual(selected["requestId"] as? String, "req-event")
        XCTAssertEqual(selected["success"] as? Bool, true)
        XCTAssertEqual(selected["source"] as? String, "arkit-overlay")
        XCTAssertEqual(selected["id"] as? String, "item-1")
        XCTAssertEqual(selected["kind"] as? String, "point")
        XCTAssertEqual((selected["position"] as? [String: Any])?["unit"] as? String, "meters")
        XCTAssertEqual((selected["payload"] as? [String: Any])?["domain"] as? String, "wifi")

        let relocalizing = AROverlayPayload.relocalizationEvent(
            request: request,
            action: "arOverlayRelocalizing",
            state: "relocalizing",
            message: "Searching",
            worldMapAvailable: true,
            trackingState: "limited",
            trackingReason: "relocalizing",
            worldMappingStatus: "limited"
        )
        XCTAssertEqual(relocalizing["action"] as? String, "arOverlayRelocalizing")
        XCTAssertEqual(relocalizing["state"] as? String, "relocalizing")
        XCTAssertEqual(relocalizing["trackingState"] as? String, "limited")
        XCTAssertEqual(relocalizing["trackingReason"] as? String, "relocalizing")
        XCTAssertEqual(relocalizing["worldMappingStatus"] as? String, "limited")

        let error = AROverlayPayload.errorResponse(
            request: request,
            action: "arOverlayError",
            error: "Camera permission was denied.",
            supported: true
        )
        XCTAssertEqual(error["action"] as? String, "arOverlayError")
        XCTAssertEqual(error["success"] as? Bool, false)
        XCTAssertEqual(error["supported"] as? Bool, true)
        XCTAssertEqual(error["source"] as? String, "arkit-overlay")
        XCTAssertEqual(error["error"] as? String, "Camera permission was denied.")
    }

    private func assertColor(
        _ color: UIColor,
        red: Int,
        green: Int,
        blue: Int,
        alpha: Int = 255,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var actualRed: CGFloat = 0
        var actualGreen: CGFloat = 0
        var actualBlue: CGFloat = 0
        var actualAlpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&actualRed, green: &actualGreen, blue: &actualBlue, alpha: &actualAlpha), file: file, line: line)
        XCTAssertEqual(Int((actualRed * 255).rounded()), red, file: file, line: line)
        XCTAssertEqual(Int((actualGreen * 255).rounded()), green, file: file, line: line)
        XCTAssertEqual(Int((actualBlue * 255).rounded()), blue, file: file, line: line)
        XCTAssertEqual(Int((actualAlpha * 255).rounded()), alpha, file: file, line: line)
    }
}
