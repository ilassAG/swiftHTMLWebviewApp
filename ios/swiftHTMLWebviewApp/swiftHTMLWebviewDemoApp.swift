//
//  swiftHTMLWebviewAppApp.swift // Adjusted filename to reflect app name change
//  swiftHTMLWebviewApp
//
//  This is the main entry point of the application.
//  It initializes `AppSettings` to register default user preferences
//  and sets up the main `WindowGroup` with `ContentView` as the root view.
//

import SwiftUI

@main
struct swiftHTMLWebviewAppApp: App { // Adjusted struct name
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        AppSettings.shared.registerDefaults()
        _ = NotificationBridge.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
