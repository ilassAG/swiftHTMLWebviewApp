//
//  StartupLoadCoordinatorTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class StartupLoadCoordinatorTests: XCTestCase {
    func testStartLoadsFirstConfiguredCandidateAndSchedulesTimeoutForRemote() {
        var coordinator = StartupLoadCoordinator()

        let command = coordinator.start(
            candidates: ["https://primary.invalid/app/", "https://backup.invalid/app/"],
            highAvailabilityEnabled: true
        )

        XCTAssertEqual(command, .load(urlString: "https://primary.invalid/app/", index: 0, scheduleTimeout: true))
    }

    func testLocalCandidateDoesNotScheduleTimeout() {
        var coordinator = StartupLoadCoordinator()

        let command = coordinator.start(candidates: ["local"], highAvailabilityEnabled: true)

        XCTAssertEqual(command, .load(urlString: "local", index: 0, scheduleTimeout: false))
    }

    func testMainFrameFailureAdvancesToNextHighAvailabilityCandidate() {
        var coordinator = StartupLoadCoordinator()
        _ = coordinator.start(candidates: ["https://primary.invalid/app/", "https://backup.invalid/app/"], highAvailabilityEnabled: true)

        let command = coordinator.mainFrameFailed(reason: "network failed", fallbackServerURL: "https://fallback.invalid")

        XCTAssertEqual(command, .load(urlString: "https://backup.invalid/app/", index: 1, scheduleTimeout: true))
    }

    func testTimeoutAdvancesToNextHighAvailabilityCandidate() {
        var coordinator = StartupLoadCoordinator()
        _ = coordinator.start(candidates: ["https://primary.invalid/app/", "local"], highAvailabilityEnabled: true)

        let command = coordinator.timeout(fallbackServerURL: "https://fallback.invalid")

        XCTAssertEqual(command, .load(urlString: "local", index: 1, scheduleTimeout: false))
    }

    func testLastFailureShowsRecoveryWithOriginalCandidateList() {
        var coordinator = StartupLoadCoordinator()
        _ = coordinator.start(candidates: ["https://primary.invalid/app/", "https://backup.invalid/app/"], highAvailabilityEnabled: true)
        _ = coordinator.mainFrameFailed(reason: "first failed", fallbackServerURL: "https://fallback.invalid")

        let command = coordinator.mainFrameFailed(reason: "backup failed", fallbackServerURL: "https://fallback.invalid")

        XCTAssertEqual(command, .showRecovery(
            reason: "backup failed",
            failedCandidates: ["https://primary.invalid/app/", "https://backup.invalid/app/"]
        ))
        XCTAssertEqual(coordinator.timeout(fallbackServerURL: "https://fallback.invalid"), .none)
    }

    func testHighAvailabilityDisabledShowsRecoveryAfterFirstFailure() {
        var coordinator = StartupLoadCoordinator()
        _ = coordinator.start(candidates: ["https://primary.invalid/app/", "https://backup.invalid/app/"], highAvailabilityEnabled: false)

        let command = coordinator.mainFrameFailed(reason: "primary failed", fallbackServerURL: "https://fallback.invalid")

        XCTAssertEqual(command, .showRecovery(
            reason: "primary failed",
            failedCandidates: ["https://primary.invalid/app/", "https://backup.invalid/app/"]
        ))
    }

    func testReloadResetsCandidateIndexAndRecoveryState() {
        var coordinator = StartupLoadCoordinator()
        _ = coordinator.start(candidates: ["https://primary.invalid/app/", "https://backup.invalid/app/"], highAvailabilityEnabled: true)
        _ = coordinator.mainFrameFailed(reason: "first failed", fallbackServerURL: "https://fallback.invalid")
        _ = coordinator.mainFrameFailed(reason: "backup failed", fallbackServerURL: "https://fallback.invalid")

        let command = coordinator.start(
            candidates: ["https://new-primary.invalid/app/", "https://new-backup.invalid/app/"],
            highAvailabilityEnabled: true
        )

        XCTAssertEqual(command, .load(urlString: "https://new-primary.invalid/app/", index: 0, scheduleTimeout: true))
        XCTAssertEqual(
            coordinator.mainFrameFailed(reason: "new primary failed", fallbackServerURL: "https://fallback.invalid"),
            .load(urlString: "https://new-backup.invalid/app/", index: 1, scheduleTimeout: true)
        )
    }

    func testEmptyCandidatesLoadLocalFallback() {
        var coordinator = StartupLoadCoordinator()

        let command = coordinator.start(candidates: [], highAvailabilityEnabled: true)

        XCTAssertEqual(command, .load(urlString: "local", index: 0, scheduleTimeout: false))
    }
}
