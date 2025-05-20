//
//  Utilities/TextRecognizer.swift
//  swiftHTMLWebviewDemo
//
//  Created by KI-Generiert am 05.10.2023.
//

import Foundation
import Vision
import VisionKit
import UIKit

class TextRecognizer {
    private let cameraScan: VNDocumentCameraScan

    init(cameraScan: VNDocumentCameraScan) {
        self.cameraScan = cameraScan
    }

    func recognizeText(completionHandler: @escaping (Result<String, AppError>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var recognizedTexts: [Int: String] = [:]
            let dispatchGroup = DispatchGroup()
            var ocrError: Error? = nil

            for i in 0..<self.cameraScan.pageCount {
                dispatchGroup.enter()
                guard let cgImage = self.cameraScan.imageOfPage(at: i).cgImage else {
                    print("Error: Could not get CGImage for page \(i).")
                    ocrError = ocrError ?? AppError.internalError("CGImage für Seite \(i) konnte nicht erstellt werden.")
                    dispatchGroup.leave()
                    continue
                }

                let request = VNRecognizeTextRequest { (request, error) in
                    if let error = error {
                         print("OCR Error on page \(i): \(error.localizedDescription)")
                         ocrError = ocrError ?? error
                    } else if let observations = request.results as? [VNRecognizedTextObservation] {
                        let pageText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                        print("OCR-Ergebnis für Seite \(i): \(pageText)")
                        recognizedTexts[i] = pageText
                    } else {
                        recognizedTexts[i] = ""
                    }
                    dispatchGroup.leave()
                }

                request.recognitionLevel = .accurate
                // request.recognitionLanguages = ["de-DE", "en-US"]

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    print("Error performing VNRecognizeTextRequest for page \(i): \(error)")
                    ocrError = ocrError ?? error
                    dispatchGroup.leave()
                }
            }

            dispatchGroup.notify(queue: .main) {
                 if let firstError = ocrError {
                     completionHandler(.failure(.ocrFailed(firstError)))
                 } else {
                     let sortedTexts = recognizedTexts.sorted { $0.key < $1.key }.map { $0.value }
                     // Füge Seitentrenner hinzu, wenn mehr als eine Seite erkannt wurde
                     let fullText = sortedTexts.enumerated().map { index, text in
                         return (sortedTexts.count > 1 ? "--- Seite \(index + 1) ---\n" : "") + text
                     }.joined(separator: "\n\n")

                     completionHandler(.success(fullText))
                 }
            }
        }
    }
}
