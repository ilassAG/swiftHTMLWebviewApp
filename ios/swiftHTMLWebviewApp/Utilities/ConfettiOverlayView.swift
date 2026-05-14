//
//  Utilities/ConfettiOverlayView.swift
//  swiftHTMLWebviewApp
//
//  Reliable UIWindow overlay confetti using CAEmitterLayer + CoreMotion tilt.
//

import UIKit
import CoreMotion

@MainActor
final class ConfettiOverlayPresenter {
    static let shared = ConfettiOverlayPresenter()

    private weak var hostWindow: UIWindow?
    private weak var overlayView: UIView?

    private let motionManager = CMMotionManager()
    private var smoothedGravity = CGVector(dx: 0, dy: 1)
    private var totalBursts = 0

    private var activeEmitters: [CAEmitterLayer] = []
    private let cellNames = ["pink", "orange", "yellow", "green", "blue", "violet", "rose"]

    private init() {}

    @discardableResult
    func launchBurst() -> Int? {
        guard let window = activeWindow() else { return nil }
        guard let overlay = attachOverlayIfNeeded(to: window) else { return nil }

        emitBurst(in: overlay)
        startMotionUpdatesIfNeeded()

        totalBursts += 1
        return totalBursts
    }

    private func attachOverlayIfNeeded(to window: UIWindow) -> UIView? {
        if overlayView?.superview !== window || hostWindow !== window {
            overlayView?.removeFromSuperview()

            let view = UIView(frame: window.bounds)
            view.backgroundColor = .clear
            view.isOpaque = false
            view.isUserInteractionEnabled = false
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]

            window.addSubview(view)
            window.bringSubviewToFront(view)

            overlayView = view
            hostWindow = window
        }

        return overlayView
    }

    private func emitBurst(in overlay: UIView) {
        let emitter = makeCenterFountainEmitter(in: overlay)
        overlay.layer.addSublayer(emitter)
        activeEmitters.append(emitter)
        applyGravity(to: emitter)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self, weak emitter] in
            guard let self, let emitter else { return }
            emitter.birthRate = 0
            self.cleanupEmitter(emitter, after: 3.4)
        }
    }

    private func cleanupEmitter(_ emitter: CAEmitterLayer, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak emitter] in
            guard let self, let emitter else { return }
            emitter.removeFromSuperlayer()
            self.activeEmitters.removeAll { $0 === emitter }
            if self.activeEmitters.isEmpty && self.motionManager.isDeviceMotionActive {
                self.motionManager.stopDeviceMotionUpdates()
            }
        }
    }

    private func makeCenterFountainEmitter(in overlay: UIView) -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.frame = overlay.bounds
        emitter.emitterShape = .point
        emitter.emitterMode = .points
        emitter.renderMode = .unordered
        emitter.emitterPosition = CGPoint(
            x: overlay.bounds.width * 0.5,
            y: overlay.bounds.height - 8
        )
        emitter.emitterSize = CGSize(width: 8, height: 8)
        emitter.birthRate = 1
        emitter.emitterCells = makeEmitterCells()
        return emitter
    }

    private func makeEmitterCells() -> [CAEmitterCell] {
        let colors: [(String, UIColor, Int)] = [
            ("pink", UIColor(red: 1.00, green: 0.35, blue: 0.37, alpha: 1.0), 0),
            ("orange", UIColor(red: 1.00, green: 0.62, blue: 0.22, alpha: 1.0), 1),
            ("yellow", UIColor(red: 1.00, green: 0.86, blue: 0.20, alpha: 1.0), 2),
            ("green", UIColor(red: 0.25, green: 0.78, blue: 0.35, alpha: 1.0), 0),
            ("blue", UIColor(red: 0.22, green: 0.62, blue: 1.00, alpha: 1.0), 1),
            ("violet", UIColor(red: 0.74, green: 0.42, blue: 1.00, alpha: 1.0), 2),
            ("rose", UIColor(red: 1.00, green: 0.45, blue: 0.78, alpha: 1.0), 0)
        ]

        return colors.map { name, color, shape in
            let cell = CAEmitterCell()
            cell.name = name
            cell.contents = confettiImage(color: color, shape: shape).cgImage
            cell.birthRate = 26
            cell.lifetime = 3.2
            cell.lifetimeRange = 0.5
            cell.velocity = 940
            cell.velocityRange = 130
            // Near-vertical shot from center, then gravity pulls the particles back down.
            cell.emissionLongitude = -(.pi / 2)
            cell.emissionRange = .pi / 12
            cell.spin = 4.2
            cell.spinRange = 7.2
            cell.scale = 0.68
            cell.scaleRange = 0.28
            cell.alphaSpeed = -0.12
            cell.yAcceleration = 420
            cell.xAcceleration = 0
            return cell
        }
    }

    private func confettiImage(color: UIColor, shape: Int) -> UIImage {
        let size = CGSize(width: 16, height: 16)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(color.cgColor)

            switch shape {
            case 0:
                cg.fill(CGRect(x: 3, y: 3, width: 10, height: 10))
            case 1:
                cg.fillEllipse(in: CGRect(x: 2.5, y: 2.5, width: 11, height: 11))
            default:
                cg.move(to: CGPoint(x: size.width / 2, y: 2))
                cg.addLine(to: CGPoint(x: 13.5, y: 13.5))
                cg.addLine(to: CGPoint(x: 2.5, y: 13.5))
                cg.closePath()
                cg.fillPath()
            }
        }
    }

    private func startMotionUpdatesIfNeeded() {
        guard motionManager.isDeviceMotionAvailable else { return }
        guard !motionManager.isDeviceMotionActive else { return }

        motionManager.deviceMotionUpdateInterval = 1.0 / 45.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.updateGravity(with: motion.gravity)
        }
    }

    private func updateGravity(with gravity: CMAcceleration) {
        let mapped = mappedGravityVector(from: gravity)

        smoothedGravity.dx = (smoothedGravity.dx * 0.82) + (mapped.dx * 0.18)
        smoothedGravity.dy = (smoothedGravity.dy * 0.82) + (mapped.dy * 0.18)

        for emitter in activeEmitters {
            applyGravity(to: emitter)
        }
    }

    private func applyGravity(to emitter: CAEmitterLayer) {
        let xAccel = smoothedGravity.dx * 160
        let yAccel = 450 + (smoothedGravity.dy * 210)

        for cellName in cellNames {
            emitter.setValue(xAccel, forKeyPath: "emitterCells.\(cellName).xAcceleration")
            emitter.setValue(yAccel, forKeyPath: "emitterCells.\(cellName).yAcceleration")
        }
    }

    private func mappedGravityVector(from gravity: CMAcceleration) -> CGVector {
        let orientation = activeInterfaceOrientation()
        let gx = gravity.x
        let gy = gravity.y

        switch orientation {
        case .portrait:
            return CGVector(dx: gx, dy: -gy)
        case .portraitUpsideDown:
            return CGVector(dx: -gx, dy: gy)
        case .landscapeLeft:
            return CGVector(dx: -gy, dy: -gx)
        case .landscapeRight:
            return CGVector(dx: gy, dy: gx)
        default:
            return CGVector(dx: gx, dy: -gy)
        }
    }

    private func activeInterfaceOrientation() -> UIInterfaceOrientation {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first { $0.activationState == .foregroundActive }
        return active?.interfaceOrientation ?? .portrait
    }

    private func activeWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }

        for scene in scenes where scene.activationState == .foregroundActive {
            if let keyWindow = scene.windows.first(where: { window in
                window.isKeyWindow &&
                !window.isHidden &&
                window.alpha > 0 &&
                window.windowLevel == .normal &&
                window.rootViewController != nil
            }) {
                return keyWindow
            }

            if let firstWindow = scene.windows.first(where: { window in
                !window.isHidden &&
                window.alpha > 0 &&
                window.windowLevel == .normal &&
                window.rootViewController != nil
            }) {
                return firstWindow
            }
        }

        return scenes
            .flatMap(\.windows)
            .first(where: { window in
                !window.isHidden &&
                window.alpha > 0 &&
                window.windowLevel == .normal &&
                window.rootViewController != nil
            })
    }
}
