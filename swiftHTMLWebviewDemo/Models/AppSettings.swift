//
//  AppSettings.swift
//  swiftHTMLWebviewDemo
//
//  Created by Roo on 20.05.2025.
//

import Foundation

class AppSettings {
    static let shared = AppSettings()

    private let userDefaults = UserDefaults.standard
    private let serverUrlKey = "server_url_preference"
    private let defaultServerUrl = "https://apps.ilass.com/swiftHTMLWebviewDemo/"

    var serverURL: String {
        get {
            // Gebe den Wert aus UserDefaults zurück, oder den Standardwert, falls nichts gesetzt ist.
            userDefaults.string(forKey: serverUrlKey) ?? defaultServerUrl
        }
        set {
            // Setze den neuen Wert in UserDefaults.
            userDefaults.set(newValue, forKey: serverUrlKey)
        }
    }

    func registerDefaults() {
        // Registriere den Standardwert, damit er in den Einstellungen angezeigt wird,
        // bevor der Benutzer ihn zum ersten Mal ändert.
        userDefaults.register(defaults: [serverUrlKey: defaultServerUrl])
    }

    func resetToDefaultURL() {
        serverURL = defaultServerUrl
    }
}