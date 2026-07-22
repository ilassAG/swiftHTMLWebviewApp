//
//  AROverlayPayload.swift
//  swiftHTMLWebviewApp
//

import Foundation
import UIKit
import simd

enum AROverlayPayload {
    static let source = "arkit-overlay"

    static func requestAction(_ request: [String: Any], defaultAction: String) -> String {
        let action = stringValue(request["action"])
        return action.isEmpty ? defaultAction : action
    }

    static func readyResponse(
        request: [String: Any],
        action: String,
        scene: AROverlayScene,
        worldMapAvailable: Bool,
        supported: Bool = true
    ) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: action)
        response["success"] = true
        response["supported"] = supported
        response["source"] = source
        response["coordinateSystem"] = scene.coordinateSystem
        response["itemCount"] = scene.items.count
        response["lineCount"] = scene.lines.count
        response["title"] = scene.title
        response["worldMapAvailable"] = worldMapAvailable
        return response
    }

    static func pendingPermissionResponse(
        request: [String: Any],
        action: String,
        scene: AROverlayScene,
        worldMapAvailable: Bool
    ) -> [String: Any] {
        var response = readyResponse(
            request: request,
            action: action,
            scene: scene,
            worldMapAvailable: worldMapAvailable
        )
        response["pendingPermission"] = true
        return response
    }

    static func closeResponse(request: [String: Any], action: String) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: action)
        response["success"] = true
        response["source"] = source
        return response
    }

    static func errorResponse(
        request: [String: Any],
        action: String,
        error: String,
        supported: Bool
    ) -> [String: Any] {
        var response = BridgeResponse.error(request: request, action: action, message: error)
        response["supported"] = supported
        response["source"] = source
        return response
    }

    static func relocalizationEvent(
        request: [String: Any],
        action: String,
        state: String,
        message: String,
        worldMapAvailable: Bool,
        trackingState: String? = nil,
        trackingReason: String? = nil,
        worldMappingStatus: String? = nil
    ) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: action)
        response["success"] = true
        response["source"] = source
        response["state"] = state
        response["message"] = message
        response["worldMapAvailable"] = worldMapAvailable
        if let trackingState, !trackingState.isEmpty {
            response["trackingState"] = trackingState
        }
        if let trackingReason, !trackingReason.isEmpty {
            response["trackingReason"] = trackingReason
        }
        if let worldMappingStatus, !worldMappingStatus.isEmpty {
            response["worldMappingStatus"] = worldMappingStatus
        }
        return response
    }

    static func itemSelectedEvent(request: [String: Any], item: AROverlayItem) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "arOverlayItemSelected")
        response["success"] = true
        response["source"] = source
        response["id"] = item.id
        response["kind"] = item.kind
        response["title"] = item.title
        response["detail"] = item.detail
        response["position"] = [
            "x": Double(item.position.x),
            "y": Double(item.position.y),
            "z": Double(item.position.z),
            "unit": "meters"
        ]
        if let distanceMeters = item.distanceMeters {
            response["distanceMeters"] = distanceMeters
            response["directionMarker"] = item.isDirectionMarker
        }
        response["payload"] = item.payload
        return response
    }
}

struct AROverlayScene {
    static let empty = AROverlayScene(
        title: "AR Overlay",
        coordinateSystem: "arkit-gravity-local",
        items: [],
        lines: []
    )

    var title: String
    var coordinateSystem: String
    var items: [AROverlayItem]
    var lines: [AROverlayLine]

    init(title: String, coordinateSystem: String, items: [AROverlayItem], lines: [AROverlayLine]) {
        self.title = title
        self.coordinateSystem = coordinateSystem
        self.items = items
        self.lines = lines
    }

    init(request: [String: Any]) {
        let overlay = request["overlay"] as? [String: Any]
        let overlaySession = overlay?["session"] as? [String: Any]
        let overlayFloorPlan = overlay?["floorPlan"] as? [String: Any]
        let title = arOverlayFirstNonEmpty(
            stringValue(request["title"]),
            stringValue(overlaySession?["name"]),
            stringValue(overlayFloorPlan?["name"]),
            "AR Overlay"
        )
        let coordinateSystem = arOverlayFirstNonEmpty(stringValue(request["coordinateSystem"]), "arkit-gravity-local")
        let floorY = AROverlayScene.floorY(from: request, overlay: overlay)
        let geographicOrigin = AROverlayScene.geographicOrigin(from: request)
        let maxDisplayDistanceMeters = max(2.0, doubleValue(request["maxDisplayDistanceMeters"]) ?? 15.0)
        var items: [AROverlayItem] = []
        var lines: [AROverlayLine] = []

        items.append(contentsOf: AROverlayScene.genericItems(
            from: request["items"],
            defaultY: floorY + 0.08,
            coordinateSystem: coordinateSystem,
            geographicOrigin: geographicOrigin,
            maxDisplayDistanceMeters: maxDisplayDistanceMeters
        ))
        items.append(contentsOf: AROverlayScene.genericItems(
            from: request["points"],
            defaultY: floorY + 0.08,
            coordinateSystem: coordinateSystem,
            geographicOrigin: geographicOrigin,
            maxDisplayDistanceMeters: maxDisplayDistanceMeters
        ))
        lines.append(contentsOf: AROverlayScene.genericLines(from: request["lines"], defaultY: floorY + 0.045))
        lines.append(contentsOf: AROverlayScene.planLines(from: request, overlay: overlay, floorY: floorY))

        if let overlay {
            lines.append(contentsOf: AROverlayScene.traceLines(from: overlay, floorY: floorY))
            items.append(contentsOf: AROverlayScene.transactionItems(from: overlay, floorY: floorY))
            items.append(contentsOf: AROverlayScene.speedItems(from: overlay, floorY: floorY))
        }

        self.init(title: title, coordinateSystem: coordinateSystem, items: items, lines: lines)
    }

    private static func genericItems(
        from raw: Any?,
        defaultY: Float,
        coordinateSystem: String,
        geographicOrigin: AROverlayGeoCoordinate?,
        maxDisplayDistanceMeters: Double
    ) -> [AROverlayItem] {
        guard let dictionaries = raw as? [[String: Any]] else { return [] }
        return dictionaries.enumerated().compactMap { index, item in
            let usesGeographicCoordinates = isGeographicCoordinateSystem(coordinateSystem)
            let geographicProjection: AROverlayGeoProjection?
            if usesGeographicCoordinates,
               let geographicOrigin,
               let target = geographicCoordinate(from: item) {
                geographicProjection = AROverlayGeoProjection.project(
                    origin: geographicOrigin,
                    target: target,
                    defaultY: defaultY,
                    maxDisplayDistanceMeters: maxDisplayDistanceMeters
                )
            } else {
                geographicProjection = nil
            }
            let localPosition = usesGeographicCoordinates ? nil : position(from: item, defaultY: defaultY)
            guard let position = geographicProjection?.position ?? localPosition else { return nil }
            let id = arOverlayFirstNonEmpty(stringValue(item["id"]), "item_\(index)")
            let kind = arOverlayFirstNonEmpty(stringValue(item["kind"]), "point")
            return AROverlayItem(
                id: id,
                kind: kind,
                title: arOverlayFirstNonEmpty(stringValue(item["title"]), stringValue(item["label"]), id),
                detail: arOverlayFirstNonEmpty(stringValue(item["detail"]), stringValue(item["caption"])),
                position: position,
                radius: Float(doubleValue(item["radius"]) ?? 0.055),
                color: color(value: item["color"], severity: stringValue(item["severity"])),
                headingYaw: floatValue(item["headingYawRadians"]) ?? floatValue(item["yawRadians"]),
                payload: item["payload"] as? [String: Any] ?? item,
                distanceMeters: geographicProjection?.distanceMeters,
                isDirectionMarker: geographicProjection?.isDirectionMarker ?? false
            )
        }
    }

    private static func isGeographicCoordinateSystem(_ coordinateSystem: String) -> Bool {
        let normalized = coordinateSystem.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "wgs84" || normalized == "geo-wgs84" || normalized == "geographic-wgs84"
    }

    private static func geographicOrigin(from request: [String: Any]) -> AROverlayGeoCoordinate? {
        if let origin = request["origin"] as? [String: Any] {
            return geographicCoordinate(from: origin)
        }
        if let origin = request["geoOrigin"] as? [String: Any] {
            return geographicCoordinate(from: origin)
        }
        return nil
    }

    private static func geographicCoordinate(from dictionary: [String: Any]) -> AROverlayGeoCoordinate? {
        let source = dictionary["geoPosition"] as? [String: Any]
            ?? dictionary["coordinate"] as? [String: Any]
            ?? dictionary
        guard let latitude = firstDouble(source["latitude"], source["lat"]),
              let longitude = firstDouble(source["longitude"], source["lng"], source["lon"]),
              (-90.0...90.0).contains(latitude),
              (-180.0...180.0).contains(longitude) else {
            return nil
        }
        return AROverlayGeoCoordinate(
            latitude: latitude,
            longitude: longitude,
            altitudeMeters: firstDouble(source["altitudeMeters"], source["altitude"])
        )
    }

    private static func genericLines(from raw: Any?, defaultY: Float) -> [AROverlayLine] {
        guard let dictionaries = raw as? [[String: Any]] else { return [] }
        return dictionaries.enumerated().compactMap { index, line in
            guard let rawPoints = line["points"] as? [[String: Any]] else { return nil }
            let points = rawPoints.compactMap { position(from: $0, defaultY: defaultY) }
            guard points.count >= 2 else { return nil }
            return AROverlayLine(
                id: arOverlayFirstNonEmpty(stringValue(line["id"]), "line_\(index)"),
                points: points,
                radius: Float(doubleValue(line["radius"]) ?? 0.012),
                color: color(value: line["color"], severity: stringValue(line["severity"]), fallback: UIColor.systemBlue.withAlphaComponent(0.78))
            )
        }
    }

    private static func planLines(from request: [String: Any], overlay: [String: Any]?, floorY: Float) -> [AROverlayLine] {
        let plan = planPayload(from: request, overlay: overlay)
        let walls = plan?["walls"] as? [[String: Any]] ?? []
        let points = walls.enumerated().compactMap { index, wall -> AROverlayLine? in
            guard let x1 = doubleValue(wall["x1"]),
                  let y1 = doubleValue(wall["y1"]),
                  let x2 = doubleValue(wall["x2"]),
                  let y2 = doubleValue(wall["y2"]) else { return nil }
            return AROverlayLine(
                id: "wall_\(index)",
                points: [
                    SIMD3<Float>(Float(x1), floorY + 0.025, Float(y1)),
                    SIMD3<Float>(Float(x2), floorY + 0.025, Float(y2))
                ],
                radius: 0.012,
                color: UIColor.systemCyan.withAlphaComponent(0.82)
            )
        }
        return points
    }

    private static func traceLines(from overlay: [String: Any], floorY: Float) -> [AROverlayLine] {
        let trace = overlay["tracePoints"] as? [[String: Any]] ?? []
        let points = trace.compactMap { point -> SIMD3<Float>? in
            position(from: point, defaultY: floorY + 0.055)
        }
        guard points.count >= 2 else { return [] }
        return [
            AROverlayLine(
                id: "trace",
                points: points,
                radius: 0.01,
                color: UIColor.systemBlue.withAlphaComponent(0.74)
            )
        ]
    }

    private static func transactionItems(from overlay: [String: Any], floorY: Float) -> [AROverlayItem] {
        let transactions = overlay["txPoints"] as? [[String: Any]] ?? []
        return transactions.enumerated().compactMap { index, tx in
            guard let position = position(from: tx, defaultY: floorY + 0.1) else { return nil }
            let sequence = stringValue(tx["sequence"])
            let protocolName = stringValue(tx["protocol"]).uppercased()
            let id = arOverlayFirstNonEmpty(stringValue(tx["id"]), stringValue(tx["locationSampleId"]), "\(protocolName)_\(sequence)_\(index)")
            let severity = stringValue(tx["severity"])
            return AROverlayItem(
                id: id,
                kind: "point",
                title: arOverlayFirstNonEmpty("\(protocolName) #\(sequence)", "Messpunkt"),
                detail: transactionDetail(tx),
                position: position,
                radius: severity == "violet" ? 0.075 : 0.06,
                color: color(value: tx["color"], severity: severity),
                headingYaw: floatValue(tx["arYawRadians"]) ?? floatValue(tx["headingYawRadians"]) ?? floatValue(tx["planYawRadians"]),
                payload: tx
            )
        }
    }

    private static func speedItems(from overlay: [String: Any], floorY: Float) -> [AROverlayItem] {
        let speedPoints = overlay["speedPoints"] as? [[String: Any]] ?? []
        return speedPoints.enumerated().compactMap { index, speed in
            guard let position = position(from: speed, defaultY: floorY + 0.13) else { return nil }
            let id = arOverlayFirstNonEmpty(stringValue(speed["id"]), "speed_\(index)")
            return AROverlayItem(
                id: id,
                kind: "speed",
                title: "Speedtest",
                detail: speedDetail(speed),
                position: position,
                radius: 0.075,
                color: color(value: speed["color"], severity: arOverlayFirstNonEmpty(stringValue(speed["severity"]), "cyan")),
                headingYaw: floatValue(speed["arYawRadians"]) ?? floatValue(speed["headingYawRadians"]) ?? floatValue(speed["planYawRadians"]),
                payload: speed
            )
        }
    }

    private static func transactionDetail(_ tx: [String: Any]) -> String {
        var parts: [String] = []
        let status = stringValue(tx["status"])
        if !status.isEmpty { parts.append(status) }
        if let rtt = doubleValue(tx["rttMs"]) {
            parts.append("\(Int(rtt.rounded())) ms")
        }
        if let meta = tx["meta"] as? [String: Any] {
            let ap = arOverlayFirstNonEmpty(stringValue(meta["accessPoint"]), stringValue(meta["bssid"]), stringValue(meta["wifiChange"]))
            if !ap.isEmpty { parts.append(ap) }
        }
        let time = stringValue(tx["time"])
        if !time.isEmpty { parts.append(time) }
        return parts.joined(separator: " | ")
    }

    private static func speedDetail(_ speed: [String: Any]) -> String {
        var parts: [String] = []
        if let download = doubleValue(speed["downloadMbps"]) {
            parts.append("Down \(format(download)) Mbit/s")
        }
        if let upload = doubleValue(speed["uploadMbps"]) {
            parts.append("Up \(format(upload)) Mbit/s")
        }
        if let latency = doubleValue(speed["latencyMs"]) {
            parts.append("Latenz \(Int(latency.rounded())) ms")
        }
        let status = stringValue(speed["status"])
        if !status.isEmpty { parts.append(status) }
        return parts.joined(separator: " | ")
    }

    private static func position(from dictionary: [String: Any], defaultY: Float) -> SIMD3<Float>? {
        if let positionPayload = dictionary["position"] as? [String: Any] {
            return position(from: positionPayload, defaultY: defaultY)
        }
        if let point = dictionary["point"] as? [String: Any] {
            return position(from: point, defaultY: defaultY)
        }
        if let arX = firstDouble(dictionary["arX"]),
           let arZ = firstDouble(dictionary["arZ"]) {
            let arY = firstDouble(dictionary["arY"], dictionary["height"]) ?? Double(defaultY)
            return SIMD3<Float>(Float(arX), Float(arY), Float(arZ))
        }
        if let x = firstDouble(dictionary["x"], dictionary["lng"], dictionary["longitude"]),
           let z = firstDouble(dictionary["z"]) {
            let y = firstDouble(dictionary["y"], dictionary["height"]) ?? Double(defaultY)
            return SIMD3<Float>(Float(x), Float(y), Float(z))
        }
        if let x = firstDouble(dictionary["x"], dictionary["lng"], dictionary["longitude"]),
           let planY = firstDouble(dictionary["planY"], dictionary["y"], dictionary["lat"], dictionary["latitude"]) {
            let y = firstDouble(dictionary["height"]) ?? Double(defaultY)
            return SIMD3<Float>(Float(x), Float(y), Float(planY))
        }
        return nil
    }

    private static func planPayload(from request: [String: Any], overlay: [String: Any]?) -> [String: Any]? {
        if let plan = request["floorPlanPlanJson"] as? [String: Any] {
            return plan
        }
        if let plan = request["normalizedPlan"] as? [String: Any] {
            return plan
        }
        if let floorPlan = request["floorPlan"] as? [String: Any],
           let plan = floorPlan["planJson"] as? [String: Any] {
            return plan
        }
        if let floorPlan = overlay?["floorPlan"] as? [String: Any],
           let plan = floorPlan["planJson"] as? [String: Any] {
            return plan
        }
        return nil
    }

    private static func floorY(from request: [String: Any], overlay: [String: Any]?) -> Float {
        guard let plan = planPayload(from: request, overlay: overlay) else { return 0 }
        if let vertical = plan["vertical"] as? [String: Any],
           let floorY = doubleValue(vertical["floorY"]) {
            return Float(floorY)
        }
        if let floorY = doubleValue(plan["floorY"]) {
            return Float(floorY)
        }
        return 0
    }

    private static func color(value: Any?, severity: String, fallback: UIColor = .systemGreen) -> UIColor {
        let raw = arOverlayFirstNonEmpty(stringValue(value), severity).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if raw.hasPrefix("#"), let color = UIColor(arOverlayHexString: raw) {
            return color
        }
        switch raw {
        case "green", "ok", "success", "good":
            return .systemGreen
        case "yellow", "warning", "warn", "medium":
            return .systemYellow
        case "orange":
            return .systemOrange
        case "red", "error", "bad", "critical":
            return .systemRed
        case "violet", "purple", "wifi", "ap-change":
            return .systemPurple
        case "cyan", "speed":
            return .systemCyan
        case "blue", "trace":
            return .systemBlue
        case "gray", "grey":
            return .systemGray
        default:
            return fallback
        }
    }

    private static func firstDouble(_ values: Any?...) -> Double? {
        for value in values {
            if let number = doubleValue(value) {
                return number
            }
        }
        return nil
    }

    private static func floatValue(_ value: Any?) -> Float? {
        guard let number = doubleValue(value) else { return nil }
        return Float(number)
    }

    private static func format(_ value: Double) -> String {
        if abs(value) >= 10 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}

struct AROverlayItem {
    var id: String
    var kind: String
    var title: String
    var detail: String
    var position: SIMD3<Float>
    var radius: Float
    var color: UIColor
    var headingYaw: Float?
    var payload: [String: Any]
    var distanceMeters: Double?
    var isDirectionMarker: Bool

    init(
        id: String,
        kind: String,
        title: String,
        detail: String,
        position: SIMD3<Float>,
        radius: Float,
        color: UIColor,
        headingYaw: Float?,
        payload: [String: Any],
        distanceMeters: Double? = nil,
        isDirectionMarker: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.position = position
        self.radius = radius
        self.color = color
        self.headingYaw = headingYaw
        self.payload = payload
        self.distanceMeters = distanceMeters
        self.isDirectionMarker = isDirectionMarker
    }
}

struct AROverlayLine {
    var id: String
    var points: [SIMD3<Float>]
    var radius: Float
    var color: UIColor
}

struct AROverlayGeoCoordinate {
    var latitude: Double
    var longitude: Double
    var altitudeMeters: Double?
}

struct AROverlayGeoProjection {
    static let earthRadiusMeters = 6_371_000.0

    var position: SIMD3<Float>
    var distanceMeters: Double
    var isDirectionMarker: Bool

    static func project(
        origin: AROverlayGeoCoordinate,
        target: AROverlayGeoCoordinate,
        defaultY: Float,
        maxDisplayDistanceMeters: Double
    ) -> AROverlayGeoProjection {
        let latitude1 = origin.latitude * .pi / 180.0
        let latitude2 = target.latitude * .pi / 180.0
        let deltaLatitude = latitude2 - latitude1
        let deltaLongitude = normalizedLongitudeDelta(target.longitude - origin.longitude) * .pi / 180.0

        let haversine = pow(sin(deltaLatitude / 2.0), 2.0)
            + cos(latitude1) * cos(latitude2) * pow(sin(deltaLongitude / 2.0), 2.0)
        let angularDistance = 2.0 * atan2(sqrt(haversine), sqrt(max(0.0, 1.0 - haversine)))
        let distanceMeters = earthRadiusMeters * angularDistance

        let bearingY = sin(deltaLongitude) * cos(latitude2)
        let bearingX = cos(latitude1) * sin(latitude2)
            - sin(latitude1) * cos(latitude2) * cos(deltaLongitude)
        let bearingRadians = atan2(bearingY, bearingX)
        let isDirectionMarker = distanceMeters > maxDisplayDistanceMeters
        let displayDistance = max(1.25, min(distanceMeters, maxDisplayDistanceMeters))
        let eastMeters = sin(bearingRadians) * displayDistance
        let northMeters = cos(bearingRadians) * displayDistance

        var verticalMeters = 0.0
        if !isDirectionMarker,
           let originAltitude = origin.altitudeMeters,
           let targetAltitude = target.altitudeMeters {
            verticalMeters = max(-3.0, min(3.0, targetAltitude - originAltitude))
        }

        return AROverlayGeoProjection(
            position: SIMD3<Float>(
                Float(eastMeters),
                defaultY + Float(verticalMeters),
                Float(-northMeters)
            ),
            distanceMeters: distanceMeters,
            isDirectionMarker: isDirectionMarker
        )
    }

    private static func normalizedLongitudeDelta(_ delta: Double) -> Double {
        var normalized = delta.truncatingRemainder(dividingBy: 360.0)
        if normalized > 180.0 { normalized -= 360.0 }
        if normalized < -180.0 { normalized += 360.0 }
        return normalized
    }
}

private func arOverlayFirstNonEmpty(_ values: String...) -> String {
    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
    }
    return ""
}

private extension UIColor {
    convenience init?(arOverlayHexString hexString: String) {
        var raw = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") {
            raw.removeFirst()
        }
        guard raw.count == 6 || raw.count == 8,
              let value = UInt64(raw, radix: 16) else { return nil }

        let red: UInt64
        let green: UInt64
        let blue: UInt64
        let alpha: UInt64
        if raw.count == 8 {
            red = (value & 0xff00_0000) >> 24
            green = (value & 0x00ff_0000) >> 16
            blue = (value & 0x0000_ff00) >> 8
            alpha = value & 0x0000_00ff
        } else {
            red = (value & 0xff0000) >> 16
            green = (value & 0x00ff00) >> 8
            blue = value & 0x0000ff
            alpha = 255
        }

        self.init(
            red: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: CGFloat(alpha) / 255
        )
    }
}
