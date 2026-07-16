//
//  PreferencesViewController.swift
//
//  Copyright © 2017 Evgeny Aleksandrov. All rights reserved.

import Cocoa
import ServiceManagement

class PreferencesViewController: NSViewController {

    @IBOutlet weak var startAtLoginButton: NSButton!
    @IBOutlet weak var notificationsButton: NSButton!
    @IBOutlet weak var repositoryLink: HyperTextField!
    @IBOutlet weak var versionLabel: NSTextField!

    private let startAtLogin = StartAtLogin()

    override func viewDidLoad() {
        super.viewDidLoad()

        updateStartAtLoginButton()
        updateNotificationsButton()

        if let shortVersionString: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            let buildVersionString: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            versionLabel.stringValue = "Version \(shortVersionString) (\(buildVersionString))"
        }

        if let repositoryURL = Bundle.main.infoDictionary?["SomaFMRepositoryURL"] as? String {
            repositoryLink.href = repositoryURL
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

    @IBAction func tapNotifications(_ sender: NSButton) {
        guard let notificationService = notificationService else { return }

        sender.isEnabled = false
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            defer { sender.isEnabled = true }

            if sender.state == .off {
                notificationService.disableNotifications()
                sender.state = .off
                return
            }

            do {
                let isEnabled = try await notificationService.enableNotifications()
                sender.state = isEnabled ? .on : .off
                if !isEnabled {
                    presentNotificationsDeniedAlert()
                }
            } catch {
                notificationService.disableNotifications()
                sender.state = .off
                presentNotificationsError(error)
            }
        }
    }

    @IBAction func updateSortOrder(_ sender: NSPopUpButton) {
        NotificationCenter.default.post(name: .somaApiChannelsUpdated, object: nil)
    }

    private func updateStartAtLoginButton() {
        startAtLoginButton.state = startAtLogin.isEnabled ? .on : .off
    }

    private var notificationService: UserNotificationService? {
        (NSApp.delegate as? AppDelegate)?.notificationService
    }

    private func updateNotificationsButton() {
        guard let notificationService = notificationService else {
            notificationsButton.state = .off
            return
        }

        notificationsButton.isEnabled = false
        Task { @MainActor [weak self] in
            let isEnabled = await notificationService.notificationPreferenceIsEnabled()
            self?.notificationsButton.state = isEnabled ? .on : .off
            self?.notificationsButton.isEnabled = true
        }
    }

    private func presentNotificationsDeniedAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Notifications Are Disabled"
        alert.informativeText = "Allow notifications for SomaFM miniplayer in System Settings, then enable them here again."
        present(alert)
    }

    private func presentNotificationsError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Unable to Enable Notifications"
        present(alert)
    }

    private func present(_ alert: NSAlert) {
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func presentStartAtLoginError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Unable to Update Login Item"
        present(alert)
    }
}
