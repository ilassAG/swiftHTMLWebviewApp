//
//  StartupReachabilityPolicy.swift
//  swiftHTMLWebviewApp
//

import Foundation

enum StartupReachabilityPolicy {
    static func probeURLs(for candidate: String) -> [URL] {
        guard let candidateURL = URL(string: candidate),
              let scheme = candidateURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return []
        }

        var urls: [URL] = []
        if var healthComponents = URLComponents(url: candidateURL, resolvingAgainstBaseURL: false) {
            healthComponents.path = "/api/health"
            healthComponents.query = nil
            healthComponents.fragment = nil
            if let healthURL = healthComponents.url {
                urls.append(healthURL)
            }
        }
        urls.append(candidateURL)

        return urls.reduce(into: [URL]()) { uniqueURLs, url in
            if !uniqueURLs.contains(url) {
                uniqueURLs.append(url)
            }
        }
    }

    static func probeTimeout(seconds: Int) -> TimeInterval {
        TimeInterval(min(max(seconds, 1), 4))
    }

    static func loadTimeout(seconds: Int, highAvailabilityEnabled: Bool) -> TimeInterval {
        highAvailabilityEnabled ? TimeInterval(max(seconds, 1)) : 60
    }

    static func isSuccessfulProbeStatusCode(_ statusCode: Int) -> Bool {
        (200..<400).contains(statusCode)
    }

    static func failoverDelay(seconds: Int) -> DispatchTimeInterval {
        .seconds(max(seconds, 1))
    }
}
