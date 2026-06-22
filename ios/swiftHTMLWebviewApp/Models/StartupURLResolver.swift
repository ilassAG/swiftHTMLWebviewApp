//
//  StartupURLResolver.swift
//  swiftHTMLWebviewApp
//

import Foundation

struct StartupURLResolver {
    private let localValue: String
    private let isLocalValue: (String?) -> Bool

    init(
        localValue: String = Configuration.localHTMLPathValue,
        isLocalValue: @escaping (String?) -> Bool = Configuration.isLocalHTMLPath
    ) {
        self.localValue = localValue
        self.isLocalValue = isLocalValue
    }

    func candidates(
        primary: String?,
        fallback: String,
        highAvailabilityEnabled: Bool,
        failoverURLs: [String?]
    ) -> [String] {
        var candidates: [String] = []
        appendUniqueCandidate(primary, fallback: fallback, to: &candidates)

        if highAvailabilityEnabled {
            for failoverURL in failoverURLs {
                appendUniqueCandidate(failoverURL, fallback: nil, to: &candidates)
            }
        }

        return candidates.isEmpty ? [localValue] : candidates
    }

    func normalizedSettingValue(_ value: String?, fallback: String) -> String {
        normalizedOptionalValue(value) ?? fallback
    }

    private func appendUniqueCandidate(_ rawValue: String?, fallback: String?, to candidates: inout [String]) {
        guard let candidate = normalizedCandidate(rawValue, fallback: fallback) else {
            return
        }

        let identity = urlIdentity(candidate)
        guard !candidates.contains(where: { urlIdentity($0) == identity }) else {
            return
        }

        candidates.append(candidate)
    }

    private func normalizedCandidate(_ value: String?, fallback: String?) -> String? {
        guard let normalized = normalizedOptionalValue(value) ?? normalizedOptionalValue(fallback) else {
            return nil
        }
        return isLocalValue(normalized) ? localValue : normalized
    }

    private func normalizedOptionalValue(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func urlIdentity(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if isLocalValue(trimmed) {
            return localValue
        }
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }
}
