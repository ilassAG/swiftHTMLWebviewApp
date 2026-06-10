//
//  RoomPlanBridge.swift
//  swiftHTMLWebviewApp
//
//  Generic iOS RoomPlan bridge for WebView apps.
//

import Foundation
import SwiftUI
import UIKit
import simd

#if canImport(RoomPlan)
import RoomPlan
#endif

@MainActor
final class RoomPlanBridge: ObservableObject {
    @Published var scannerVisible = false

    private var eventHandler: (([String: Any]) -> Void)?
    private var latestRequest: [String: Any] = [:]
    private var latestResult: [String: Any]?
    fileprivate var captureController: AnyObject?
    private var streamToken = UUID()

    nonisolated static func isSupported() -> Bool {
        #if canImport(RoomPlan)
        if #available(iOS 16.0, *) {
            return RoomCaptureSession.isSupported
        }
        #endif
        return false
    }

    func start(request: [String: Any], eventHandler: @escaping ([String: Any]) -> Void) -> [String: Any] {
        latestRequest = request
        self.eventHandler = eventHandler
        latestResult = nil
        streamToken = UUID()

        guard Self.isSupported() else {
            return errorResponse(request: request, action: "roomPlanScanStart", error: "RoomPlan/LiDAR scanning is not supported on this device.")
        }

        scannerVisible = true
        var response = baseResponse(request: request, action: "roomPlanScanStart")
        response["success"] = true
        response["supported"] = true
        response["source"] = "roomplan"
        response["coordinateSystem"] = "roomplan-local-meter"
        return response
    }

    func stop(request: [String: Any]) -> [String: Any] {
        #if canImport(RoomPlan)
        if #available(iOS 16.0, *), let controller = captureController as? RoomPlanCaptureViewController {
            controller.finishCapture()
            var response = baseResponse(request: request, action: "roomPlanScanStop")
            response["success"] = true
            response["state"] = "processing"
            response["message"] = "RoomPlan scan stopped. Processing result."
            return response
        }
        #endif
        return errorResponse(request: request, action: "roomPlanScanStop", error: "No active RoomPlan scan.")
    }

    func export(request: [String: Any]) -> [String: Any] {
        if let latestResult {
            var response = latestResult
            response["action"] = "roomPlanScanExport"
            if let requestId = request["requestId"] {
                response["requestId"] = requestId
            }
            return response
        }
        return errorResponse(request: request, action: "roomPlanScanExport", error: "No RoomPlan result available yet.")
    }

    func shutdown() {
        #if canImport(RoomPlan)
        if #available(iOS 16.0, *), let controller = captureController as? RoomPlanCaptureViewController {
            controller.cancelCapture(sendEvent: false)
        }
        #endif
        scannerVisible = false
        eventHandler = nil
        captureController = nil
        streamToken = UUID()
    }

    func emitState(_ state: String, message: String = "") {
        var response = baseResponse(request: latestRequest, action: "roomPlanScanState")
        response["success"] = true
        response["source"] = "roomplan"
        response["state"] = state
        if !message.isEmpty {
            response["message"] = message
        }
        eventHandler?(response)
    }

    func emitError(_ error: String) {
        eventHandler?(errorResponse(request: latestRequest, action: "roomPlanScanError", error: error))
    }

    func cancelFromNative(sendEvent: Bool = true) {
        if sendEvent {
            emitState("cancelled", message: "RoomPlan scan cancelled.")
        }
        scannerVisible = false
        captureController = nil
    }

    #if canImport(RoomPlan)
    @available(iOS 16.0, *)
    func bind(controller: RoomPlanCaptureViewController) {
        captureController = controller
    }

    @available(iOS 16.0, *)
    func complete(room: CapturedRoom) {
        let normalizedPlan = normalize(room: room)
        let previewSVG = previewSVG(plan: normalizedPlan)
        let rawRoomPlan = rawRoomPlanPayload(room: room)

        var response = baseResponse(request: latestRequest, action: "roomPlanScanResult")
        response["success"] = true
        response["supported"] = true
        response["source"] = "roomplan"
        response["coordinateSystem"] = "roomplan-local-meter"
        response["normalizedPlan"] = normalizedPlan
        response["previewSvg"] = previewSVG
        response["raw"] = rawRoomPlan
        response["counts"] = [
            "walls": room.walls.count,
            "doors": room.doors.count,
            "windows": room.windows.count,
            "openings": room.openings.count,
            "objects": room.objects.count
        ]
        latestResult = response
        eventHandler?(response)
        scannerVisible = false
        captureController = nil
    }
    #endif

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
        response["supported"] = Self.isSupported()
        response["source"] = "roomplan"
        response["error"] = error
        return response
    }
}

#if canImport(RoomPlan)
@available(iOS 16.0, *)
struct RoomPlanScannerSheet: View {
    @ObservedObject var bridge: RoomPlanBridge
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            RoomPlanCaptureRepresentable(bridge: bridge)
                .ignoresSafeArea()

            HStack {
                Button("Abbrechen") {
                    if let controller = bridge.captureController as? RoomPlanCaptureViewController {
                        controller.cancelCapture(sendEvent: true)
                    } else {
                        bridge.cancelFromNative(sendEvent: true)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                Spacer()

                Button("Fertig") {
                    if let controller = bridge.captureController as? RoomPlanCaptureViewController {
                        controller.finishCapture()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
        }
        .onChange(of: bridge.scannerVisible) { _, visible in
            if !visible {
                dismiss()
            }
        }
    }
}

@available(iOS 16.0, *)
private struct RoomPlanCaptureRepresentable: UIViewControllerRepresentable {
    let bridge: RoomPlanBridge

    func makeUIViewController(context: Context) -> RoomPlanCaptureViewController {
        let controller = RoomPlanCaptureViewController(bridge: bridge)
        bridge.bind(controller: controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: RoomPlanCaptureViewController, context: Context) {
    }
}

@available(iOS 16.0, *)
final class RoomPlanCaptureViewController: UIViewController, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    private let captureView = RoomCaptureView(frame: .zero)
    private weak var bridge: RoomPlanBridge?
    private var running = false
    private var cancelled = false

    init(bridge: RoomPlanBridge) {
        self.bridge = bridge
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        captureView.delegate = self
        captureView.captureSession.delegate = self
        captureView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(captureView)
        NSLayoutConstraint.activate([
            captureView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            captureView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            captureView.topAnchor.constraint(equalTo: view.topAnchor),
            captureView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startCapture()
    }

    func startCapture() {
        guard !running else { return }
        cancelled = false
        running = true
        var configuration = RoomCaptureSession.Configuration()
        configuration.isCoachingEnabled = true
        captureView.captureSession.run(configuration: configuration)
        bridge?.emitState("running", message: "RoomPlan scan running.")
    }

    func finishCapture() {
        guard running else { return }
        running = false
        bridge?.emitState("processing", message: "RoomPlan scan processing.")
        captureView.captureSession.stop()
    }

    func cancelCapture(sendEvent: Bool) {
        cancelled = true
        if running {
            running = false
            captureView.captureSession.stop()
        }
        bridge?.cancelFromNative(sendEvent: sendEvent)
    }

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: (any Error)?) -> Bool {
        if let error {
            bridge?.emitError(error.localizedDescription)
            return false
        }
        return !cancelled
    }

    func captureView(didPresent processedResult: CapturedRoom, error: (any Error)?) {
        guard !cancelled else { return }
        if let error {
            bridge?.emitError(error.localizedDescription)
            return
        }
        bridge?.complete(room: processedResult)
    }

    func captureSession(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction) {
        bridge?.emitState("instruction", message: String(describing: instruction))
    }

    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: (any Error)?) {
        if let error, !cancelled {
            bridge?.emitError(error.localizedDescription)
        }
    }
}

@available(iOS 16.0, *)
private func normalize(room: CapturedRoom) -> [String: Any] {
    var walls: [[String: Any]] = room.walls.map { normalizedWall($0) }
    if walls.isEmpty {
        walls = room.openings.map { normalizedWall($0) }
    }

    let openings = room.doors.map { normalizedOpening($0, type: "door") }
        + room.windows.map { normalizedOpening($0, type: "window") }
        + room.openings.map { normalizedOpening($0, type: "opening") }
    let objects = room.objects.map { normalizedObject($0) }
    let bounds = normalizedBounds(walls: walls, openings: openings, objects: objects)

    return [
        "coordinateSystem": "roomplan-local-meter",
        "roomIdentifier": room.identifier.uuidString,
        "bounds": bounds,
        "walls": walls,
        "openings": openings,
        "objects": objects
    ]
}

@available(iOS 16.0, *)
private func normalizedWall(_ surface: CapturedRoom.Surface) -> [String: Any] {
    let width = max(0.05, Double(surface.dimensions.x))
    let center = surface.transform.columns.3
    let right = surface.transform.columns.0
    let x1 = Double(center.x) - Double(right.x) * width / 2.0
    let y1 = Double(center.z) - Double(right.z) * width / 2.0
    let x2 = Double(center.x) + Double(right.x) * width / 2.0
    let y2 = Double(center.z) + Double(right.z) * width / 2.0
    return [
        "id": surface.identifier.uuidString,
        "type": categoryName(surface.category),
        "x1": rounded(x1),
        "y1": rounded(y1),
        "x2": rounded(x2),
        "y2": rounded(y2),
        "height": rounded(Double(surface.dimensions.y)),
        "confidence": confidenceName(surface.confidence),
        "transform": matrixPayload(surface.transform)
    ]
}

@available(iOS 16.0, *)
private func normalizedOpening(_ surface: CapturedRoom.Surface, type: String) -> [String: Any] {
    let center = surface.transform.columns.3
    let right = surface.transform.columns.0
    let rotation = atan2(Double(right.z), Double(right.x))
    return [
        "id": surface.identifier.uuidString,
        "type": type,
        "x": rounded(Double(center.x)),
        "y": rounded(Double(center.z)),
        "width": rounded(Double(surface.dimensions.x)),
        "height": rounded(Double(surface.dimensions.y)),
        "rotation": rounded(rotation),
        "confidence": confidenceName(surface.confidence),
        "transform": matrixPayload(surface.transform)
    ]
}

@available(iOS 16.0, *)
private func normalizedObject(_ object: CapturedRoom.Object) -> [String: Any] {
    let center = object.transform.columns.3
    let right = object.transform.columns.0
    let rotation = atan2(Double(right.z), Double(right.x))
    return [
        "id": object.identifier.uuidString,
        "type": categoryName(object.category),
        "x": rounded(Double(center.x)),
        "y": rounded(Double(center.z)),
        "width": rounded(max(0.1, Double(object.dimensions.x))),
        "height": rounded(max(0.1, Double(object.dimensions.z))),
        "rotation": rounded(rotation),
        "confidence": confidenceName(object.confidence),
        "transform": matrixPayload(object.transform)
    ]
}

private func normalizedBounds(walls: [[String: Any]], openings: [[String: Any]], objects: [[String: Any]]) -> [String: Double] {
    var xs: [Double] = []
    var ys: [Double] = []

    for wall in walls {
        appendNumber(wall["x1"], to: &xs)
        appendNumber(wall["x2"], to: &xs)
        appendNumber(wall["y1"], to: &ys)
        appendNumber(wall["y2"], to: &ys)
    }
    for opening in openings {
        appendNumber(opening["x"], to: &xs)
        appendNumber(opening["y"], to: &ys)
    }
    for object in objects {
        let x = object["x"] as? Double ?? 0
        let y = object["y"] as? Double ?? 0
        let width = object["width"] as? Double ?? 0.4
        let height = object["height"] as? Double ?? 0.4
        xs.append(contentsOf: [x - width / 2.0, x + width / 2.0])
        ys.append(contentsOf: [y - height / 2.0, y + height / 2.0])
    }

    guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
        return ["minX": -2, "minY": -2, "maxX": 2, "maxY": 2]
    }
    return [
        "minX": rounded(minX),
        "minY": rounded(minY),
        "maxX": rounded(maxX),
        "maxY": rounded(maxY)
    ]
}

private func appendNumber(_ value: Any?, to target: inout [Double]) {
    if let number = value as? Double {
        target.append(number)
    } else if let number = value as? NSNumber {
        target.append(number.doubleValue)
    }
}

@available(iOS 16.0, *)
private func rawRoomPlanPayload(room: CapturedRoom) -> [String: Any] {
    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(room)
        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any] ?? ["encoded": true]
    } catch {
        return [
            "encoded": false,
            "error": error.localizedDescription,
            "identifier": room.identifier.uuidString
        ]
    }
}

private func previewSVG(plan: [String: Any]) -> String {
    let bounds = plan["bounds"] as? [String: Double] ?? ["minX": -2, "minY": -2, "maxX": 2, "maxY": 2]
    let padding = 0.75
    let minX = (bounds["minX"] ?? -2) - padding
    let maxX = (bounds["maxX"] ?? 2) + padding
    let minY = -((bounds["maxY"] ?? 2) + padding)
    let maxY = -((bounds["minY"] ?? -2) - padding)
    let width = max(1, maxX - minX)
    let height = max(1, maxY - minY)

    let walls = (plan["walls"] as? [[String: Any]] ?? []).map { wall in
        line(x1: number(wall["x1"]), y1: -number(wall["y1"]), x2: number(wall["x2"]), y2: -number(wall["y2"]), className: "wall")
    }.joined()
    let objects = (plan["objects"] as? [[String: Any]] ?? []).map { object in
        let x = number(object["x"])
        let y = number(object["y"])
        let width = max(0.1, number(object["width"]))
        let height = max(0.1, number(object["height"]))
        return #"<rect x="\#(format(x - width / 2))" y="\#(format(-y - height / 2))" width="\#(format(width))" height="\#(format(height))" class="object"/>"#
    }.joined()

    return #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="\#(format(minX)) \#(format(minY)) \#(format(width)) \#(format(height))"><style>.bg{fill:#0d100d}.wall{stroke:#d7e6cf;stroke-width:.08;stroke-linecap:round;vector-effect:non-scaling-stroke}.object{fill:rgba(159,232,112,.14);stroke:rgba(159,232,112,.42);stroke-width:.035;vector-effect:non-scaling-stroke}</style><rect class="bg" x="\#(format(minX))" y="\#(format(minY))" width="\#(format(width))" height="\#(format(height))"/>\#(objects)\#(walls)</svg>"#
}

private func line(x1: Double, y1: Double, x2: Double, y2: Double, className: String) -> String {
    #"<line x1="\#(format(x1))" y1="\#(format(y1))" x2="\#(format(x2))" y2="\#(format(y2))" class="\#(className)"/>"#
}

private func matrixPayload(_ transform: simd_float4x4) -> [Double] {
    [
        Double(transform.columns.0.x), Double(transform.columns.0.y), Double(transform.columns.0.z), Double(transform.columns.0.w),
        Double(transform.columns.1.x), Double(transform.columns.1.y), Double(transform.columns.1.z), Double(transform.columns.1.w),
        Double(transform.columns.2.x), Double(transform.columns.2.y), Double(transform.columns.2.z), Double(transform.columns.2.w),
        Double(transform.columns.3.x), Double(transform.columns.3.y), Double(transform.columns.3.z), Double(transform.columns.3.w)
    ]
}

private func categoryName(_ value: Any) -> String {
    let text = String(describing: value)
    if text.hasPrefix("door") { return "door" }
    if text.hasPrefix("window") { return "window" }
    if text.hasPrefix("opening") { return "opening" }
    if text.hasPrefix("wall") { return "wall" }
    if text.hasPrefix("floor") { return "floor" }
    return text
}

private func confidenceName(_ value: Any) -> String {
    String(describing: value)
}

private func number(_ value: Any?) -> Double {
    if let value = value as? Double { return value }
    if let value = value as? NSNumber { return value.doubleValue }
    return 0
}

private func rounded(_ value: Double) -> Double {
    (value * 1000).rounded() / 1000
}

private func format(_ value: Double) -> String {
    String(format: "%.3f", value)
}
#endif
