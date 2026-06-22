//
//  StartupLoadStateTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class StartupLoadStateTests: XCTestCase {
    func testResetFallsBackToLocalCandidateAndClearsRecoveryState() {
        var state = StartupLoadState()
        state.markRecovery()

        state.reset(candidates: [])

        XCTAssertEqual(state.candidates, ["local"])
        XCTAssertEqual(state.selectedIndex, 0)
        XCTAssertFalse(state.isShowingRecovery)
        XCTAssertEqual(state.firstDisplayName, "local")
    }

    func testSignatureCanonicalizesLocalAliases() {
        let state = StartupLoadState()

        XCTAssertEqual(
            state.signature(for: ["https://example.invalid/mobile/", "bundle", "about:local"]),
            "https://example.invalid/mobile/\u{1F}local\u{1F}local"
        )
    }

    func testAdvanceRequiresHighAvailabilityAndRemainingCandidate() {
        var state = StartupLoadState()
        state.reset(candidates: ["https://primary.invalid", "https://backup.invalid"])

        XCTAssertNil(state.advance(highAvailabilityEnabled: false))
        XCTAssertEqual(state.selectedIndex, 0)

        XCTAssertEqual(state.advance(highAvailabilityEnabled: true), 1)
        XCTAssertEqual(state.selectedIndex, 1)
        XCTAssertNil(state.advance(highAvailabilityEnabled: true))
    }

    func testSelectCandidateUpdatesIndexAndClearsRecoveryState() {
        var state = StartupLoadState()
        state.reset(candidates: ["https://primary.invalid", "local"])
        state.markRecovery()

        let candidate = state.select(index: 1)

        XCTAssertEqual(candidate, "local")
        XCTAssertEqual(state.selectedIndex, 1)
        XCTAssertFalse(state.isShowingRecovery)
    }

    func testRecoveryCandidatesUseFallbackBeforeResetAndConfiguredListAfterReset() {
        var state = StartupLoadState()

        XCTAssertEqual(state.recoveryCandidates(fallbackServerURL: "https://fallback.invalid"), ["https://fallback.invalid"])

        state.reset(candidates: ["https://primary.invalid", "https://backup.invalid"])

        XCTAssertEqual(state.recoveryCandidates(fallbackServerURL: "https://fallback.invalid"), [
            "https://primary.invalid",
            "https://backup.invalid"
        ])
    }

    func testCurrentLocalPageMatchesLocalAliasesAndFileURLs() {
        let state = StartupLoadState()

        XCTAssertTrue(state.isCurrentLocalPage(urlString: "about:local", isFileURL: false))
        XCTAssertTrue(state.isCurrentLocalPage(urlString: "https://example.invalid/index.html", isFileURL: true))
        XCTAssertFalse(state.isCurrentLocalPage(urlString: "https://example.invalid/index.html", isFileURL: false))
    }
}
