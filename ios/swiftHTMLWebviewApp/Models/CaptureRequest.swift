//
//  CaptureRequest.swift
//  swiftHTMLWebviewApp
//

import UIKit

struct DocumentCaptureRequest {
    let action: String
    let requiresOCR: Bool
    let outputType: String

    init(_ request: [String: Any]?) {
        action = Self.stringValue(request?["action"], defaultValue: "scanDocument")
        requiresOCR = request?["ocr"] as? Bool ?? false
        outputType = Self.normalizedOutputType(request?["outputType"], defaultValue: "png")
    }

    var imageFormat: ImageConverter.ImageFormat {
        Self.imageFormat(for: outputType)
    }

    var responseFormat: String {
        Self.responseFormat(for: outputType)
    }

    static func imageFormat(for outputType: String) -> ImageConverter.ImageFormat {
        responseFormat(for: outputType) == "jpeg" ? .jpeg() : .png
    }

    static func responseFormat(for outputType: String) -> String {
        let normalized = normalizedOutputType(outputType, defaultValue: "png")
        return normalized == "jpeg" || normalized == "jpg" ? "jpeg" : "png"
    }

    private static func normalizedOutputType(_ value: Any?, defaultValue: String) -> String {
        stringValue(value, defaultValue: defaultValue).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func stringValue(_ value: Any?, defaultValue: String) -> String {
        guard let string = value as? String else {
            return defaultValue
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultValue : trimmed
    }
}

struct PhotoCaptureRequest {
    let action: String
    let outputType: String
    let shouldRemoveBackground: Bool
    let cropTransparent: Bool
    let backgroundStyle: BackgroundRemoval.BackgroundStyle
    let cameraDevice: UIImagePickerController.CameraDevice

    init(_ request: [String: Any]?) {
        action = Self.stringValue(request?["action"], defaultValue: "takePhoto")
        outputType = Self.normalizedOutputType(request?["outputType"], defaultValue: "jpeg")
        shouldRemoveBackground = request?["removeBackground"] as? Bool ?? false
        cropTransparent = request?["cropTransparent"] as? Bool ?? false
        backgroundStyle = BackgroundRemoval.BackgroundStyle(
            backgroundMode: request?["background"] as? String,
            backgroundColorHex: request?["backgroundColor"] as? String
        )
        cameraDevice = Self.cameraDevice(for: request?["camera"] as? String)
    }

    func imageFormat(backgroundRemoved: Bool) -> ImageConverter.ImageFormat {
        responseFormat(backgroundRemoved: backgroundRemoved) == "png" ? .png : .jpeg()
    }

    func responseFormat(backgroundRemoved: Bool) -> String {
        if backgroundRemoved && backgroundStyle.isTransparent {
            return "png"
        }
        return outputType == "png" ? "png" : "jpeg"
    }

    private static func cameraDevice(for value: String?) -> UIImagePickerController.CameraDevice {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "front" ? .front : .rear
    }

    private static func normalizedOutputType(_ value: Any?, defaultValue: String) -> String {
        let normalized = stringValue(value, defaultValue: defaultValue).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "png" ? "png" : "jpeg"
    }

    private static func stringValue(_ value: Any?, defaultValue: String) -> String {
        guard let string = value as? String else {
            return defaultValue
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultValue : trimmed
    }
}

struct PortraitCaptureRequest {
    let action: String
    let outputType: String
    let shouldRemoveBackground: Bool
    let cropTransparent: Bool
    let backgroundStyle: BackgroundRemoval.BackgroundStyle
    let cameraPosition: PortraitCaptureCameraPosition
    let requiredFaces: Int
    let countdownSeconds: TimeInterval
    let variationCount: Int
    let captureIntervalSeconds: TimeInterval
    let faceCenteredCrop: Bool
    let mirrorOutput: Bool

    init(_ request: [String: Any]?) {
        action = Self.stringValue(request?["action"], defaultValue: "portraitCapture")
        shouldRemoveBackground = Self.boolValue(request?["removeBackground"], defaultValue: false)
        cropTransparent = Self.boolValue(request?["cropTransparent"], defaultValue: false)
        backgroundStyle = BackgroundRemoval.BackgroundStyle(
            backgroundMode: request?["background"] as? String,
            backgroundColorHex: request?["backgroundColor"] as? String
        )
        outputType = Self.normalizedOutputType(request?["outputType"], defaultValue: backgroundStyle.isTransparent && shouldRemoveBackground ? "png" : "jpeg")
        cameraPosition = PortraitCaptureCameraPosition(value: request?["camera"] as? String)
        requiredFaces = Self.clampedInt(Self.firstPresentValue(request, keys: ["requiredFaces", "amountFaces"]), defaultValue: 1, min: 1, max: 8)
        countdownSeconds = Self.clampedDouble(Self.firstPresentValue(request, keys: ["countdownSeconds", "secondsDelay"]), defaultValue: 3, min: 0, max: 15)
        variationCount = Self.clampedInt(Self.firstPresentValue(request, keys: ["variationCount", "withVariation"]), defaultValue: 4, min: 1, max: 8)
        let captureIntervalMs = Self.clampedDouble(
            Self.firstPresentValue(request, keys: ["captureIntervalMs", "burstIntervalMs", "variationIntervalMs"]),
            defaultValue: 200,
            min: 50,
            max: 2000
        )
        captureIntervalSeconds = captureIntervalMs / 1000
        let cropValue = request?["crop"] as? String
        faceCenteredCrop = cropValue == nil || cropValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "squarefacecentered"
        mirrorOutput = Self.boolValue(Self.firstPresentValue(request, keys: ["mirrorOutput", "mirror"]), defaultValue: false)
    }

    func imageFormat(backgroundRemoved: Bool) -> ImageConverter.ImageFormat {
        responseFormat(backgroundRemoved: backgroundRemoved) == "png" ? .png : .jpeg()
    }

    func responseFormat(backgroundRemoved: Bool) -> String {
        if backgroundRemoved && backgroundStyle.isTransparent {
            return "png"
        }
        return outputType == "png" ? "png" : "jpeg"
    }

    private static func firstPresentValue(_ request: [String: Any]?, keys: [String]) -> Any? {
        for key in keys {
            if let value = request?[key] {
                return value
            }
        }
        return nil
    }

    private static func clampedInt(_ value: Any?, defaultValue: Int, min: Int, max: Int) -> Int {
        let parsed: Int?
        if let intValue = value as? Int {
            parsed = intValue
        } else if let doubleValue = value as? Double {
            parsed = Int(doubleValue)
        } else if let stringValue = value as? String {
            parsed = Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            parsed = nil
        }
        return Swift.max(min, Swift.min(max, parsed ?? defaultValue))
    }

    private static func clampedDouble(_ value: Any?, defaultValue: Double, min: Double, max: Double) -> Double {
        let parsed: Double?
        if let doubleValue = value as? Double {
            parsed = doubleValue
        } else if let intValue = value as? Int {
            parsed = Double(intValue)
        } else if let stringValue = value as? String {
            parsed = Double(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            parsed = nil
        }
        return Swift.max(min, Swift.min(max, parsed ?? defaultValue))
    }

    private static func boolValue(_ value: Any?, defaultValue: Bool) -> Bool {
        if let boolValue = value as? Bool {
            return boolValue
        }
        guard let stringValue = value as? String else {
            return defaultValue
        }
        switch stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y", "on":
            return true
        case "0", "false", "no", "n", "off":
            return false
        default:
            return defaultValue
        }
    }

    private static func normalizedOutputType(_ value: Any?, defaultValue: String) -> String {
        let normalized = stringValue(value, defaultValue: defaultValue).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "png" ? "png" : "jpeg"
    }

    private static func stringValue(_ value: Any?, defaultValue: String) -> String {
        guard let string = value as? String else {
            return defaultValue
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultValue : trimmed
    }
}

enum PortraitCaptureCameraPosition {
    case front
    case back

    init(value: String?) {
        self = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "back" ? .back : .front
    }
}

struct BarcodeCaptureRequest {
    let action: String
    let types: [String]?

    init(_ request: [String: Any]?) {
        action = Self.stringValue(request?["action"], defaultValue: "scanBarcode")
        types = request?["types"] as? [String]
    }

    private static func stringValue(_ value: Any?, defaultValue: String) -> String {
        guard let string = value as? String else {
            return defaultValue
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultValue : trimmed
    }
}
