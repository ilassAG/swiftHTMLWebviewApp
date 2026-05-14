//
//  Utilities/BarcodeUtils.swift
//  swiftHTMLWebviewApp
//
//  This utility provides helper functions for barcode scanning.
//  It includes a function to map an array of barcode type strings (e.g., "qr", "ean13")
//  to a Set of `DataScannerViewController.RecognizedDataType` for configuring the scanner.
//  It also maps `VNBarcodeSymbology` to a localized display name.
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
        case .qr: return NSLocalizedString("barcode.type.qr", comment: "QR Code type name")
        case .ean13: return NSLocalizedString("barcode.type.ean13", comment: "EAN-13 type name")
        case .ean8: return NSLocalizedString("barcode.type.ean8", comment: "EAN-8 type name")
        case .code128: return NSLocalizedString("barcode.type.code128", comment: "Code 128 type name")
        case .code39: return NSLocalizedString("barcode.type.code39", comment: "Code 39 type name")
        case .code93: return NSLocalizedString("barcode.type.code93", comment: "Code 93 type name")
        case .upce: return NSLocalizedString("barcode.type.upce", comment: "UPC-E type name")
        case .pdf417: return NSLocalizedString("barcode.type.pdf417", comment: "PDF417 type name")
        case .aztec: return NSLocalizedString("barcode.type.aztec", comment: "Aztec type name")
        case .itf14: return NSLocalizedString("barcode.type.itf14", comment: "ITF-14 type name")
        case .dataMatrix: return NSLocalizedString("barcode.type.datamatrix", comment: "Data Matrix type name")
        default:
            // Fallback für unbekannte oder neue Symbologien
            let rawValueKey = "barcode.type.\(symbology.rawValue.lowercased())"
            let localizedRawValue = NSLocalizedString(rawValueKey, comment: "Raw barcode type name as fallback")
            // Wenn der rawValueKey nicht in den Strings-Dateien ist, gibt NSLocalizedString den Key selbst zurück.
            // Wir prüfen, ob das der Fall ist, und geben dann den rawValue direkt zurück, um "barcode.type.xyz" zu vermeiden.
            if localizedRawValue == rawValueKey {
                return symbology.rawValue // Reiner rawValue als letzter Ausweg
            }
            return localizedRawValue // Gibt den lokalisierten rawValue zurück, falls vorhanden
        }
    }
}