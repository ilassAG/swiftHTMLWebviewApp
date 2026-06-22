//
//  OrientationController.swift
//  swiftHTMLWebviewApp
//
//  Runtime orientation lock used by the JavaScript bridge.
//

import UIKit

final class OrientationController {
    static let shared = OrientationController()

    private(set) var mask: UIInterfaceOrientationMask = .allButUpsideDown
    private(set) var mode: String = "unlocked"

    private init() {}

    @MainActor
    func setMode(_ requestedMode: String) -> [String: Any] {
        setMode(OrientationPayload.mode(from: requestedMode), request: [:])
    }

    @MainActor
    func setPayload(request: [String: Any]) -> [String: Any] {
        setMode(OrientationPayload.mode(from: request), request: request)
    }

    @MainActor
    private func setMode(_ normalized: String, request: [String: Any]) -> [String: Any] {
        let nextMask: UIInterfaceOrientationMask
        let orientation: UIInterfaceOrientation?
        let nextMode: String

        switch normalized {
        case "portrait":
            nextMask = .portrait
            orientation = .portrait
            nextMode = "portrait"
        case "landscape":
            nextMask = .landscape
            orientation = .landscapeRight
            nextMode = "landscape"
        case "locked", "current":
            let current = activeInterfaceOrientation()
            nextMask = mask(for: current)
            orientation = current
            nextMode = "locked"
        case "unlocked", "auto":
            fallthrough
        default:
            nextMask = .allButUpsideDown
            orientation = nil
            nextMode = "unlocked"
        }

        mask = nextMask
        mode = nextMode

        if let orientation {
            UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        }

        if #available(iOS 16.0, *), let scene = activeWindowScene() {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: nextMask)) { error in
                print("Orientation geometry update failed: \(error.localizedDescription)")
            }
            scene.windows.forEach { window in
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }

        return OrientationPayload.setResponse(
            request: request,
            mode: nextMode,
            mask: maskName(nextMask)
        )
    }

    @MainActor
    func statusPayload(request: [String: Any]) -> [String: Any] {
        OrientationPayload.statusResponse(
            request: request,
            mode: mode,
            mask: maskName(mask),
            currentOrientation: orientationName(activeInterfaceOrientation())
        )
    }

    @MainActor
    private func activeInterfaceOrientation() -> UIInterfaceOrientation {
        activeWindowScene()?.interfaceOrientation ?? .portrait
    }

    @MainActor
    private func activeWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    private func mask(for orientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask {
        switch orientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        default:
            return .allButUpsideDown
        }
    }

    private func maskName(_ mask: UIInterfaceOrientationMask) -> String {
        if mask == .portrait { return "portrait" }
        if mask == .portraitUpsideDown { return "portraitUpsideDown" }
        if mask == .landscape { return "landscape" }
        if mask == .landscapeLeft { return "landscapeLeft" }
        if mask == .landscapeRight { return "landscapeRight" }
        if mask == .all { return "all" }
        return "allButUpsideDown"
    }

    private func orientationName(_ orientation: UIInterfaceOrientation) -> String {
        switch orientation {
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "portraitUpsideDown"
        case .landscapeLeft: return "landscapeLeft"
        case .landscapeRight: return "landscapeRight"
        default: return "unknown"
        }
    }

}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationController.shared.mask
    }
}
