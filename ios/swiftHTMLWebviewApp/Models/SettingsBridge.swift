//
//  SettingsBridge.swift
//  swiftHTMLWebviewApp
//
//  Handles the JS settings bridge without tying settings behavior to ContentView.
//

import Foundation

struct SettingsBridge {
    private let settings: AppSettings

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    func getResponse(request: [String: Any]) -> [String: Any] {
        var response = BridgeResponse.base(request: request, action: "settingsGet")
        response["success"] = true
        response["settings"] = settings.configurationSnapshot()
        return response
    }

    func setResponse(request: [String: Any]) -> [String: Any] {
        let token = stringValue(request["token"] ?? request["securityToken"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let storedToken = settings.securityToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokenAccepted = storedToken.isEmpty ? token.isEmpty : token == storedToken
        guard tokenAccepted else {
            return BridgeResponse.error(
                request: request,
                action: "settingsSet",
                message: "securityToken is required for settingsSet."
            )
        }

        let values = (request["settings"] as? [String: Any]) ?? request
        let snapshot = settings.applyConfiguration(values)
        var response = BridgeResponse.base(request: request, action: "settingsSet")
        response["success"] = true
        response["settings"] = snapshot
        return response
    }
}
