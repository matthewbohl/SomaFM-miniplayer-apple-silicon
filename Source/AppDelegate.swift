//
//  AppDelegate.swift
//
//  Copyright © 2017 Evgeny Aleksandrov. All rights reserved.

import Cocoa

@NSApplicationMain
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    let notificationService = UserNotificationService()
    private(set) lazy var menubarController = MenubarController(notificationService: notificationService)

    private var prefsWindowController: NSWindowController?
    var preferencesWindowController: NSWindowController? {
        if prefsWindowController == nil {
            let storyboard = NSStoryboard(name: "Main", bundle: nil)
            prefsWindowController = storyboard.instantiateController(withIdentifier:
                "PreferencesWindow") as? NSWindowController
        }
        return prefsWindowController
    }

    static let bundleId: String = Bundle.main.bundleIdentifier ?? "unknown"
    static let bundleShortVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    static let bundleVersion: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        Log.info("Starting \(AppDelegate.bundleId) v\(AppDelegate.bundleShortVersion) (\(AppDelegate.bundleVersion))")

        UserDefaults.standard.register(defaults: [UserDefaultsKey.notificationsEnabled: false])
        _ = menubarController
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        prefsWindowController = nil
    }

}
