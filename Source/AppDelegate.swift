//
//  AppDelegate.swift
//
//  Copyright © 2017 Evgeny Aleksandrov. All rights reserved.

import Cocoa
#if SOAK_TEST
import Darwin
#endif

@NSApplicationMain
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    let notificationService = UserNotificationService()
    private(set) lazy var menubarController = MenubarController(notificationService: notificationService)

#if SOAK_TEST
    private var soakTestController: SoakTestController?
#endif

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

#if SOAK_TEST
        if ProcessInfo.processInfo.environment["SOMAFM_SOAK_ENABLED"] == "1" {
            do {
                let configuration = try SoakTestConfiguration(environment: ProcessInfo.processInfo.environment)
                let controller = SoakTestController(
                    configuration: configuration,
                    menubarController: menubarController
                )
                soakTestController = controller
                controller.start()
            } catch {
                Log.error("Unable to start soak test: \(error)")
                Darwin.exit(EXIT_FAILURE)
            }
        }
#endif
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        prefsWindowController = nil
    }

}
