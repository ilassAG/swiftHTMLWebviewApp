//
//  Utilities/ImageConverter.swift
//  swiftHTMLWebviewApp
//
//  This utility provides functions to convert UIImage objects to data URLs (Base64 encoded strings)
//  in either PNG or JPEG format. It's used to prepare images for transmission to the WebView.
//

import Foundation
import UIKit
import CoreGraphics // Für CGFloat

enum ImageConverter {

    enum ImageFormat: Equatable { // Equatable hinzugefügt für Vergleich
        case png
        case jpeg(quality: CGFloat = Configuration.jpegCompressionQuality)

        var mimeType: String {
            switch self {
            case .png: return "image/png"
            case .jpeg: return "image/jpeg"
            }
        }
    }

    static func convertImageToDataURL(image: UIImage, format: ImageFormat) -> String? {
        var imageData: Data?

        switch format {
        case .png:
            imageData = image.pngData()
        case .jpeg(let quality):
            imageData = image.jpegData(compressionQuality: quality)
        }

        guard let data = imageData else {
            print("Error: Could not get image data for format \(format).")
            return nil
        }

        let base64String = data.base64EncodedString()
        return "data:\(format.mimeType);base64,\(base64String)"
    }

    static func convertImagesToDataURLs(images: [UIImage], format: ImageFormat) -> [String] {
        return images.compactMap { convertImageToDataURL(image: $0, format: format) }
    }
}