//
//  StartupLoadState.swift
//  swiftHTMLWebviewApp
//

import Foundation

struct StartupLoadState {
    private let localValue: String
    private let isLocalValue: (String?) -> Bool

    private(set) var candidates: [String] = []
    private(set) var selectedIndex = 0
    private(set) var isShowingRecovery = false

    init(
        localValue: String = Configuration.localHTMLPathValue,
        isLocalValue: @escaping (String?) -> Bool = Configuration.isLocalHTMLPath
    ) {
        self.localValue = localValue
        self.isLocalValue = isLocalValue
    }

    mutating func reset(candidates configuredCandidates: [String]) {
        candidates = configuredCandidates.isEmpty ? [localValue] : configuredCandidates
        selectedIndex = 0
        isShowingRecovery = false
    }

    var firstDisplayName: String {
        displayName(for: candidates.first ?? localValue)
    }

    var currentSignature: String {
        signature(for: candidates)
    }

    func contains(index: Int) -> Bool {
        candidates.indices.contains(index)
    }

    mutating func select(index: Int) -> String? {
        guard contains(index: index) else {
            return nil
        }
        selectedIndex = index
        isShowingRecovery = false
        return candidates[index]
    }

    func candidate(at index: Int) -> String? {
        guard contains(index: index) else {
            return nil
        }
        return candidates[index]
    }

    func hasRemainingCandidates(highAvailabilityEnabled: Bool) -> Bool {
        highAvailabilityEnabled && selectedIndex + 1 < candidates.count
    }

    mutating func advance(highAvailabilityEnabled: Bool) -> Int? {
        guard hasRemainingCandidates(highAvailabilityEnabled: highAvailabilityEnabled) else {
            return nil
        }
        selectedIndex += 1
        isShowingRecovery = false
        return selectedIndex
    }

    mutating func markRecovery() {
        isShowingRecovery = true
    }

    mutating func clearRecovery() {
        isShowingRecovery = false
    }

    func recoveryCandidates(fallbackServerURL: String) -> [String] {
        candidates.isEmpty ? [fallbackServerURL] : candidates
    }

    func signature(for candidates: [String]) -> String {
        candidates.map { displayName(for: $0) }.joined(separator: "\u{1F}")
    }

    func displayName(for urlString: String) -> String {
        isLocalValue(urlString) ? localValue : urlString
    }

    func isLocalCandidate(_ urlString: String) -> Bool {
        isLocalValue(urlString)
    }

    func isCurrentLocalPage(urlString: String?, isFileURL: Bool) -> Bool {
        isLocalValue(urlString) || isFileURL
    }
}
