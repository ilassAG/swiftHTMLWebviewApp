//
//  StartupURLResolverTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class StartupURLResolverTests: XCTestCase {
    func testCandidatesDeduplicateRemoteAndLocalURLs() {
        let resolver = StartupURLResolver()

        let candidates = resolver.candidates(
            primary: "https://example.invalid/mobile/",
            fallback: "local",
            highAvailabilityEnabled: true,
            failoverURLs: [
                "https://example.invalid/mobile",
                " local ",
                "about:local"
            ]
        )

        XCTAssertEqual(candidates, [
            "https://example.invalid/mobile/",
            "local"
        ])
    }

    func testCandidatesIgnoreFailoverURLsWhenHighAvailabilityIsDisabled() {
        let resolver = StartupURLResolver()

        let candidates = resolver.candidates(
            primary: "https://primary.invalid/mobile/",
            fallback: "local",
            highAvailabilityEnabled: false,
            failoverURLs: [
                "https://secondary.invalid/mobile/"
            ]
        )

        XCTAssertEqual(candidates, ["https://primary.invalid/mobile/"])
    }

    func testCandidatesFallBackToLocalWhenNothingIsConfigured() {
        let resolver = StartupURLResolver()

        let candidates = resolver.candidates(
            primary: " ",
            fallback: "",
            highAvailabilityEnabled: true,
            failoverURLs: [nil, " ", ""]
        )

        XCTAssertEqual(candidates, ["local"])
    }
}
