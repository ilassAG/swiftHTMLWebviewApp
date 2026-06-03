//
//  BridgeValueUtils.swift
//  swiftHTMLWebviewApp
//
//  Small coercion helpers for JavaScript bridge payloads.
//

import Foundation

func stringValue(_ value: Any?) -> String {
    switch value {
    case let string as String:
        return string
    case let number as NSNumber:
        return number.stringValue
    case .some(let value):
        return String(describing: value)
    default:
        return ""
    }
}

func intValue(_ value: Any?) -> Int? {
    switch value {
    case let int as Int:
        return int
    case let double as Double:
        return Int(double)
    case let number as NSNumber:
        return number.intValue
    case let string as String:
        return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
    default:
        return nil
    }
}

func doubleValue(_ value: Any?) -> Double? {
    switch value {
    case let double as Double:
        return double
    case let int as Int:
        return Double(int)
    case let number as NSNumber:
        return number.doubleValue
    case let string as String:
        return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
    default:
        return nil
    }
}

func boolValue(_ value: Any?) -> Bool? {
    switch value {
    case let bool as Bool:
        return bool
    case let number as NSNumber:
        return number.boolValue
    case let string as String:
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["true", "yes", "1", "on"].contains(normalized) { return true }
        if ["false", "no", "0", "off"].contains(normalized) { return false }
        return nil
    default:
        return nil
    }
}
