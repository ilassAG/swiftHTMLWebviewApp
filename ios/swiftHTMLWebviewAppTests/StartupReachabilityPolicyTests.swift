//
//  StartupReachabilityPolicyTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class StartupReachabilityPolicyTests: XCTestCase {
    func testProbeURLsUseHealthEndpointThenOriginalURL() {
        let urls = StartupReachabilityPolicy.probeURLs(for: "https://example.invalid/mobile/?tenant=wifi#start")

        XCTAssertEqual(urls.map(\.absoluteString), [
            "https://example.invalid/api/health",
            "https://example.invalid/mobile/?tenant=wifi#start"
        ])
    }

    func testProbeURLsSkipNonHttpAndInvalidCandidates() {
        XCTAssertTrue(StartupReachabilityPolicy.probeURLs(for: "local").isEmpty)
        XCTAssertTrue(StartupReachabilityPolicy.probeURLs(for: "file:///index.html").isEmpty)
        XCTAssertTrue(StartupReachabilityPolicy.probeURLs(for: "not a url").isEmpty)
    }

    func testProbeURLsDeduplicateWhenCandidateIsHealthEndpoint() {
        let urls = StartupReachabilityPolicy.probeURLs(for: "https://example.invalid/api/health")

        XCTAssertEqual(urls.map(\.absoluteString), [
            "https://example.invalid/api/health"
        ])
    }

    func testProbeTimeoutClampsToShortAvailabilityWindow() {
        XCTAssertEqual(StartupReachabilityPolicy.probeTimeout(seconds: -4), 1)
        XCTAssertEqual(StartupReachabilityPolicy.probeTimeout(seconds: 0), 1)
        XCTAssertEqual(StartupReachabilityPolicy.probeTimeout(seconds: 2), 2)
        XCTAssertEqual(StartupReachabilityPolicy.probeTimeout(seconds: 12), 4)
    }

    func testLoadTimeoutUsesLongDefaultWhenHighAvailabilityIsDisabled() {
        XCTAssertEqual(StartupReachabilityPolicy.loadTimeout(seconds: 0, highAvailabilityEnabled: true), 1)
        XCTAssertEqual(StartupReachabilityPolicy.loadTimeout(seconds: 7, highAvailabilityEnabled: true), 7)
        XCTAssertEqual(StartupReachabilityPolicy.loadTimeout(seconds: 7, highAvailabilityEnabled: false), 60)
    }
}
