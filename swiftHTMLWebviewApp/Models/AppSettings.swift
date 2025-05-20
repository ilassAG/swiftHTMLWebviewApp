//
//  AppSettings.swift
//  swiftHTMLWebviewApp
//
//  This class manages application settings using UserDefaults.
//  It provides a singleton `shared` instance to access and modify
//  settings like the server URL and security token. Default values are
//  registered and can be reset.
//

import Foundation

class AppSettings {
    static let shared = AppSettings()

    private let userDefaults = UserDefaults.standard
    private let serverUrlKey = "server_url_preference"
    private let defaultServerUrl = "https://apps.ilass.com/swiftHTMLWebviewApp/"
    private let securityTokenKey = "security_token_preference"
    private let defaultSecurityToken = "CHANGEmeASAP!"

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

    var securityToken: String {
        get {
            userDefaults.string(forKey: securityTokenKey) ?? defaultSecurityToken
        }
        set {
            userDefaults.set(newValue, forKey: securityTokenKey)
        }
    }

    func registerDefaults() {
        // Registriere die Standardwerte, damit sie in den Einstellungen angezeigt werden,
        // bevor der Benutzer sie zum ersten Mal ändert.
        userDefaults.register(defaults: [
            serverUrlKey: defaultServerUrl,
            securityTokenKey: defaultSecurityToken
        ])
    }

    func resetToDefaultURL() {
        serverURL = defaultServerUrl
    }

    // Optional: Eine Funktion zum Zurücksetzen des Security Tokens auf den Standardwert
    func resetToDefaultSecurityToken() {
        securityToken = defaultSecurityToken
    }
}
