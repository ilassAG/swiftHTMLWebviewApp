//
//  Utilities/BackgroundRemoval.swift
//  swiftHTMLWebviewApp
//
//  Uses Vision instance mask APIs to separate foreground subjects from the background.
//  Intended for photo capture workflows where an ID-style portrait is needed.
//

import UIKit
import Vision
import CoreImage
import ImageIO

enum BackgroundRemoval {
    enum BackgroundStyle {
        case transparent
        case color(UIColor, String)

        init(backgroundMode: String?, backgroundColorHex: String?) {
            let normalizedMode = backgroundMode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            switch normalizedMode {
            case "transparent":
                self = .transparent
            case "white":
                self = .color(.white, "#FFFFFF")
            case "black":
                self = .color(.black, "#000000")
            case "color":
                if let parsedColor = Self.parseHexColor(backgroundColorHex) {
                    self = .color(parsedColor.color, parsedColor.normalizedHex)
                } else {
                    self = .color(.white, "#FFFFFF")
                }
            default:
                if normalizedMode == nil, let parsedColor = Self.parseHexColor(backgroundColorHex) {
                    self = .color(parsedColor.color, parsedColor.normalizedHex)
                } else {
                    self = .transparent
                }
            }
        }

        var isTransparent: Bool {
            if case .transparent = self {
                return true
            }
            return false
        }

        var responseMode: String {
            switch self {
            case .transparent:
                return "transparent"
            case .color:
                return "color"
            }
        }

        var responseColorHex: String? {
            switch self {
            case .transparent:
                return nil
            case .color(_, let normalizedHex):
                return normalizedHex
            }
        }

        var uiColor: UIColor? {
            switch self {
            case .transparent:
                return nil
            case .color(let color, _):
                return color
            }
        }

        private static func parseHexColor(_ input: String?) -> (color: UIColor, normalizedHex: String)? {
            guard var hex = input?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else {
                return nil
            }

            if hex.hasPrefix("#") {
                hex.removeFirst()
            }

            if hex.count == 3 {
                hex = hex.map { String(repeating: $0, count: 2) }.joined()
            }

            guard hex.count == 6, let value = UInt32(hex, radix: 16) else {
                return nil
            }

            let red = CGFloat((value & 0xFF0000) >> 16) / 255.0
            let green = CGFloat((value & 0x00FF00) >> 8) / 255.0
            let blue = CGFloat(value & 0x0000FF) / 255.0

            let color = UIColor(red: red, green: green, blue: blue, alpha: 1)
            let normalizedHex = "#\(hex.uppercased())"
            return (color, normalizedHex)
        }
    }

    private struct MaskResult {
        let observation: VNInstanceMaskObservation
        let requestHandler: VNImageRequestHandler
    }

    private static let ciContext = CIContext()

    static var isSupported: Bool {
        if #available(iOS 17.0, *) {
            return true
        }
        return false
    }

    static func removeBackground(from image: UIImage, style: BackgroundStyle, cropTransparent: Bool = false) throws -> UIImage {
        guard #available(iOS 17.0, *) else {
            throw AppError.featureNotAvailable("Background Removal")
        }

        guard let cgImage = image.cgImage else {
            throw AppError.internalError("Could not create CGImage for background removal.")
        }

        do {
            let personMask = try generatePersonMask(cgImage: cgImage, orientation: image.cgImagePropertyOrientation)
            return try renderImage(from: personMask, style: style, scale: image.scale, cropTransparent: cropTransparent)
        } catch {
            let foregroundMask = try generateForegroundMask(cgImage: cgImage, orientation: image.cgImagePropertyOrientation)
            return try renderImage(from: foregroundMask, style: style, scale: image.scale, cropTransparent: cropTransparent)
        }
    }

    @available(iOS 17.0, *)
    private static func generatePersonMask(cgImage: CGImage, orientation: CGImagePropertyOrientation) throws -> MaskResult {
        let request = VNGeneratePersonInstanceMaskRequest()
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

        try requestHandler.perform([request])

        guard let observation = request.results?.first else {
            throw AppError.internalError("No person mask could be generated.")
        }
        guard !observation.allInstances.isEmpty else {
            throw AppError.internalError("No person instances were detected.")
        }

        return MaskResult(observation: observation, requestHandler: requestHandler)
    }

    @available(iOS 17.0, *)
    private static func generateForegroundMask(cgImage: CGImage, orientation: CGImagePropertyOrientation) throws -> MaskResult {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

        try requestHandler.perform([request])

        guard let observation = request.results?.first else {
            throw AppError.internalError("No foreground mask could be generated.")
        }
        guard !observation.allInstances.isEmpty else {
            throw AppError.internalError("No foreground instances were detected.")
        }

        return MaskResult(observation: observation, requestHandler: requestHandler)
    }

    @available(iOS 17.0, *)
    private static func renderImage(from maskResult: MaskResult, style: BackgroundStyle, scale: CGFloat, cropTransparent: Bool) throws -> UIImage {
        let maskedPixelBuffer: CVPixelBuffer
        let shouldCropToSubject = cropTransparent && style.isTransparent
        do {
            maskedPixelBuffer = try maskResult.observation.generateMaskedImage(
                ofInstances: maskResult.observation.allInstances,
                from: maskResult.requestHandler,
                croppedToInstancesExtent: shouldCropToSubject
            )
        } catch {
            throw AppError.internalError("Failed to build masked image: \(error.localizedDescription)")
        }

        let maskedImage = CIImage(cvPixelBuffer: maskedPixelBuffer)
        let outputImage: CIImage

        switch style {
        case .transparent:
            outputImage = maskedImage
        case .color(let backgroundUIColor, _):
            let backgroundColor = CIColor(color: backgroundUIColor)
            let background = CIImage(color: backgroundColor).cropped(to: maskedImage.extent)
            outputImage = maskedImage.composited(over: background)
        }

        guard let outputCGImage = ciContext.createCGImage(outputImage, from: outputImage.extent) else {
            throw AppError.internalError("Failed to render background-removed image.")
        }

        let normalizedScale = scale > 0 ? scale : 1
        return UIImage(cgImage: outputCGImage, scale: normalizedScale, orientation: .up)
    }
}

private extension UIImage {
    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up:
            return .up
        case .down:
            return .down
        case .left:
            return .left
        case .right:
            return .right
        case .upMirrored:
            return .upMirrored
        case .downMirrored:
            return .downMirrored
        case .leftMirrored:
            return .leftMirrored
        case .rightMirrored:
            return .rightMirrored
        @unknown default:
            return .up
        }
    }
}
