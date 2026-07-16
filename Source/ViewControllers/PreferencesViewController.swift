//
//  PreferencesViewController.swift
//
//  Copyright © 2017 Evgeny Aleksandrov. All rights reserved.

import Cocoa
import ServiceManagement

class PreferencesViewController: NSViewController {

    @IBOutlet weak var startAtLoginButton: NSButton!
    @IBOutlet weak var versionLabel: NSTextField!

    private let startAtLogin = StartAtLogin()

    override func viewDidLoad() {
        super.viewDidLoad()

        updateStartAtLoginButton()

        if let shortVersionString: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            let buildVersionString: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            versionLabel.stringValue = "Version \(shortVersionString) (\(buildVersionString))"
        }
    }

    @IBAction func tapStartAtLogin(_ sender: NSButton) {
        do {
            let status = try startAtLogin.setEnabled(sender.state == .on)
            updateStartAtLoginButton()

            if status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            updateStartAtLoginButton()
            presentStartAtLoginError(error)
        }
    }

    @IBAction func updateSortOrder(_ sender: NSPopUpButton) {
        NotificationCenter.default.post(name: .somaApiChannelsUpdated, object: nil)
    }

    private func updateStartAtLoginButton() {
        startAtLoginButton.state = startAtLogin.isEnabled ? .on : .off
    }

    private func presentStartAtLoginError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Unable to Update Login Item"

        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
