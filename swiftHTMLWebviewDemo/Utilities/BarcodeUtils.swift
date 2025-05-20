//
//  Utilities/BarcodeUtils.swift
//  swiftHTMLWebviewDemo
//
//  Created by KI-Generiert am 05.10.2023.
//  Korrektur: 02.04.2025 (Verwendung von Array statt Set für Symbologies)
//

import Foundation
import VisionKit // Für DataScannerViewController.RecognizedDataType
import Vision    // Für VNBarcodeSymbology

enum BarcodeUtils {

    static func mapStringToDataTypes(_ typeStrings: [String]?) -> Set<DataScannerViewController.RecognizedDataType> {
        guard let typeStrings = typeStrings, !typeStrings.isEmpty else {
             print("No specific barcode types requested, scanning for all.")
             let allBarcodeType = DataScannerViewController.RecognizedDataType.barcode() // Nimmt keine Argumente für "alle"
             return Set([allBarcodeType])
        }

        // Korrektur: Verwende ein Array statt Set, da .barcode(symbologies:) ein Array erwartet
        var requestedSymbologies: [VNBarcodeSymbology] = []

        for typeString in typeStrings {
            // Korrektur: Füge zum Array hinzu
            // Füge nur hinzu, wenn es nicht bereits enthalten ist (optional, um Duplikate zu vermeiden)
            let symbologyToAdd: VNBarcodeSymbology?
            switch typeString.lowercased() {
            case "qr": symbologyToAdd = .qr
            case "ean13": symbologyToAdd = .ean13
            case "ean8": symbologyToAdd = .ean8
            case "code128": symbologyToAdd = .code128
            case "code39": symbologyToAdd = .code39
            case "code93": symbologyToAdd = .code93
            case "upce": symbologyToAdd = .upce
            case "pdf417": symbologyToAdd = .pdf417
            case "aztec": symbologyToAdd = .aztec
            case "itf14": symbologyToAdd = .itf14
            case "datamatrix": symbologyToAdd = .dataMatrix
            default:
                symbologyToAdd = nil
                print("Warning: Unsupported or unknown barcode type requested: \(typeString)")
            }

            if let symbology = symbologyToAdd, !requestedSymbologies.contains(symbology) {
                requestedSymbologies.append(symbology)
            }
        }

        if requestedSymbologies.isEmpty {
             print("Warning: None of the requested barcode types are supported, scanning for all.")
             let allBarcodeType = DataScannerViewController.RecognizedDataType.barcode()
             return Set([allBarcodeType])
        } else {
            // Korrektur: Übergib das Array an den Initializer
            let specificBarcodeType = DataScannerViewController.RecognizedDataType.barcode(symbologies: requestedSymbologies)
            return Set([specificBarcodeType])
        }
    }

    static func mapSymbologyToDisplayName(_ symbology: VNBarcodeSymbology) -> String {
        switch symbology {
        case .qr: return "QR Code"
        case .ean13: return "EAN-13"
        case .ean8: return "EAN-8"
        case .code128: return "Code 128"
        case .code39: return "Code 39"
        case .code93: return "Code 93"
        case .upce: return "UPC-E"
        case .pdf417: return "PDF417"
        case .aztec: return "Aztec"
        case .itf14: return "ITF-14"
        case .dataMatrix: return "Data Matrix"
        default:
            return symbology.rawValue
        }
    }
}