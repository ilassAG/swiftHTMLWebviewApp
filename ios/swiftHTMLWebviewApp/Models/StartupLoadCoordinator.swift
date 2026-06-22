//
//  StartupLoadCoordinator.swift
//  swiftHTMLWebviewApp
//

import Foundation

struct StartupLoadCoordinator {
    static let noConfiguredURLReason = "No load candidate is available."
    static let timeoutReason = "High availability timeout reached."

    enum Command: Equatable {
        case load(urlString: String, index: Int, scheduleTimeout: Bool)
        case showRecovery(reason: String, failedCandidates: [String])
        case none
    }

    private var state: StartupLoadState
    private var highAvailabilityEnabled = false

    init(state: StartupLoadState = StartupLoadState()) {
        self.state = state
    }

    var candidates: [String] {
        state.candidates
    }

    var firstDisplayName: String {
        state.firstDisplayName
    }

    var currentSignature: String {
        state.currentSignature
    }

    var isShowingRecovery: Bool {
        state.isShowingRecovery
    }

    var hasRemainingCandidates: Bool {
        state.hasRemainingCandidates(highAvailabilityEnabled: highAvailabilityEnabled)
    }

    mutating func start(candidates configuredCandidates: [String], highAvailabilityEnabled: Bool) -> Command {
        self.highAvailabilityEnabled = highAvailabilityEnabled
        state.reset(candidates: configuredCandidates)
        return loadCurrentOrRecover(reason: Self.noConfiguredURLReason, fallbackServerURL: "")
    }

    mutating func selectCandidate(
        at index: Int,
        fallbackServerURL: String,
        recoveryReason: String = Self.noConfiguredURLReason
    ) -> Command {
        guard let candidate = state.select(index: index) else {
            return recover(reason: recoveryReason, fallbackServerURL: fallbackServerURL)
        }
        return loadCommand(for: candidate, index: index)
    }

    mutating func mainFrameFailed(reason: String, fallbackServerURL: String) -> Command {
        failoverOrRecover(reason: reason, fallbackServerURL: fallbackServerURL)
    }

    mutating func timeout(fallbackServerURL: String) -> Command {
        failoverOrRecover(reason: Self.timeoutReason, fallbackServerURL: fallbackServerURL)
    }

    mutating func recover(
        reason: String,
        fallbackServerURL: String,
        failedCandidates: [String]? = nil
    ) -> Command {
        guard !state.isShowingRecovery else {
            return .none
        }

        state.markRecovery()
        let candidates = failedCandidates ?? state.recoveryCandidates(fallbackServerURL: fallbackServerURL)
        return .showRecovery(reason: normalizedReason(reason), failedCandidates: candidates)
    }

    mutating func clearRecovery() {
        state.clearRecovery()
    }

    func candidate(at index: Int) -> String? {
        state.candidate(at: index)
    }

    func signature(for candidates: [String]) -> String {
        state.signature(for: candidates)
    }

    func displayName(for urlString: String) -> String {
        state.displayName(for: urlString)
    }

    func isCurrentLocalPage(urlString: String?, isFileURL: Bool) -> Bool {
        state.isCurrentLocalPage(urlString: urlString, isFileURL: isFileURL)
    }

    private mutating func failoverOrRecover(reason: String, fallbackServerURL: String) -> Command {
        guard !state.isShowingRecovery else {
            return .none
        }

        guard let nextIndex = state.advance(highAvailabilityEnabled: highAvailabilityEnabled),
              let candidate = state.candidate(at: nextIndex) else {
            return recover(reason: reason, fallbackServerURL: fallbackServerURL)
        }

        return loadCommand(for: candidate, index: nextIndex)
    }

    private mutating func loadCurrentOrRecover(reason: String, fallbackServerURL: String) -> Command {
        guard let candidate = state.candidate(at: state.selectedIndex) else {
            return recover(reason: reason, fallbackServerURL: fallbackServerURL)
        }
        return loadCommand(for: candidate, index: state.selectedIndex)
    }

    private func loadCommand(for candidate: String, index: Int) -> Command {
        .load(urlString: candidate, index: index, scheduleTimeout: !state.isLocalCandidate(candidate))
    }

    private func normalizedReason(_ reason: String) -> String {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedReason.isEmpty ? Self.noConfiguredURLReason : trimmedReason
    }
}
