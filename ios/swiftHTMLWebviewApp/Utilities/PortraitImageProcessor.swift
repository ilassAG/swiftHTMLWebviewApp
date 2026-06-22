//
//  Utilities/PortraitImageProcessor.swift
//  swiftHTMLWebviewApp
//

import UIKit
import Vision

enum PortraitImageProcessor {
    struct CropPlan: Equatable {
        let rect: CGRect
        let faceCount: Int
    }

    static func faceCenteredSquareCrop(_ image: UIImage, requiredFaces: Int) throws -> (image: UIImage, faceCount: Int) {
        let normalized = image.normalizedOrientation()
        guard let cgImage = normalized.cgImage else {
            throw AppError.internalError("Could not create CGImage for portrait crop.")
        }

        let faces = try detectFaces(cgImage: cgImage)
        guard faces.count == requiredFaces else {
            throw AppError.internalError("Expected \(requiredFaces) face(s), found \(faces.count).")
        }

        let plan = squareCropPlan(
            imageSize: CGSize(width: cgImage.width, height: cgImage.height),
            faces: faces.map(\.boundingBox)
        )

        guard let cropped = cgImage.cropping(to: plan.rect.integral) else {
            throw AppError.internalError("Could not crop portrait image.")
        }

        return (UIImage(cgImage: cropped, scale: normalized.scale, orientation: .up), plan.faceCount)
    }

    static func squareCropPlan(imageSize: CGSize, faces: [CGRect]) -> CropPlan {
        guard imageSize.width > 0, imageSize.height > 0, let primaryFace = largestFace(faces, imageSize: imageSize) else {
            let side = min(imageSize.width, imageSize.height)
            return CropPlan(
                rect: CGRect(x: (imageSize.width - side) / 2, y: (imageSize.height - side) / 2, width: side, height: side),
                faceCount: faces.count
            )
        }

        let faceRect = denormalizedVisionRect(primaryFace, imageSize: imageSize)
        let side = min(
            min(imageSize.width, imageSize.height),
            max(faceRect.width * 2.8, faceRect.height * 2.35, min(imageSize.width, imageSize.height) * 0.52)
        )
        let center = CGPoint(x: faceRect.midX, y: faceRect.midY)
        let origin = CGPoint(
            x: clamp(center.x - side / 2, lower: 0, upper: imageSize.width - side),
            y: clamp(center.y - side / 2, lower: 0, upper: imageSize.height - side)
        )
        return CropPlan(rect: CGRect(origin: origin, size: CGSize(width: side, height: side)), faceCount: faces.count)
    }

    private static func detectFaces(cgImage: CGImage) throws -> [VNFaceObservation] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        try handler.perform([request])
        return request.results ?? []
    }

    private static func largestFace(_ faces: [CGRect], imageSize: CGSize) -> CGRect? {
        faces.max { left, right in
            let leftRect = denormalizedVisionRect(left, imageSize: imageSize)
            let rightRect = denormalizedVisionRect(right, imageSize: imageSize)
            return leftRect.width * leftRect.height < rightRect.width * rightRect.height
        }
    }

    private static func denormalizedVisionRect(_ rect: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(
            x: rect.minX * imageSize.width,
            y: (1 - rect.maxY) * imageSize.height,
            width: rect.width * imageSize.width,
            height: rect.height * imageSize.height
        )
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), max(lower, upper))
    }
}

private extension UIImage {
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else {
            return self
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
