//
//  Utilities/PDFGenerator.swift
//  swiftHTMLWebviewDemo
//
//  Created by KI-Generiert am 05.10.2023.
//

import Foundation
import PDFKit
import UIKit

enum PDFGenerator {

    static func generatePDFData(from images: [UIImage]) -> Data? {
        guard !images.isEmpty else { return nil }

        let pdfMetaData = [
            kCGPDFContextCreator: NSLocalizedString("pdf.creator", comment: "PDF Creator metadata"),
            kCGPDFContextAuthor: NSLocalizedString("pdf.author", comment: "PDF Author metadata")
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]

        // Verwende die Größe des ersten Bildes als Standardseitenformat
        let firstPageBounds = CGRect(origin: .zero, size: images[0].size)
        let renderer = UIGraphicsPDFRenderer(bounds: firstPageBounds, format: format)

        let data = renderer.pdfData { (context) in
            for image in images {
                // Verwende die Größe des *aktuellen* Bildes für die Zeichenfläche
                let imageBounds = CGRect(origin: .zero, size: image.size)
                // Beginne eine neue Seite mit den Dimensionen des aktuellen Bildes
                context.beginPage(withBounds: imageBounds, pageInfo: [:])
                image.draw(in: imageBounds)
            }
        }
        print("PDF generated successfully with \(images.count) pages.")
        return data
    }

     static func generatePDFDataURL(from images: [UIImage]) -> String? {
         guard let pdfData = generatePDFData(from: images) else { return nil }
         let base64String = pdfData.base64EncodedString()
         return "data:application/pdf;base64,\(base64String)"
     }
}