//
//  UserNotificationService.swift
//
//  Copyright © 2026 Matthew Bohl. All rights reserved.

import UserNotifications

enum NotificationAuthorizationStatus {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    var permitsDelivery: Bool {
        self == .authorized || self == .provisional || self == .ephemeral
    }
}

struct UserNotificationMessage: Equatable {
    let identifier: String
    let title: String
    let body: String
}

protocol UserNotificationCenterClient: AnyObject {
    func setDelegate(_ delegate: UNUserNotificationCenterDelegate)
    func authorizationStatus() async -> NotificationAuthorizationStatus
    func requestAlertAuthorization() async throws -> Bool
    func deliver(_ message: UserNotificationMessage) async throws
}

final class SystemUserNotificationCenterClient: UserNotificationCenterClient {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func setDelegate(_ delegate: UNUserNotificationCenterDelegate) {
        center.delegate = delegate
    }

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        case .provisional:
            return .provisional
        case .ephemeral:
            return .ephemeral
        @unknown default:
            return .denied
        }
    }

    func requestAlertAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert])
    }

    func deliver(_ message: UserNotificationMessage) async throws {
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body

        let request = UNNotificationRequest(
            identifier: message.identifier,
            content: content,
            trigger: nil
        )
        try await center.add(request)
    }
}

final class UserNotificationService: NSObject {
    private let center: UserNotificationCenterClient

    init(center: UserNotificationCenterClient = SystemUserNotificationCenterClient()) {
        self.center = center
        super.init()
        center.setDelegate(self)
    }

    func notificationPreferenceIsEnabled() async -> Bool {
        let isAuthorized = await center.authorizationStatus().permitsDelivery
        if !isAuthorized {
            Settings.notificationsEnabled = false
        }
        return Settings.notificationsEnabled && isAuthorized
    }

    func enableNotifications() async throws -> Bool {
        let isAuthorized: Bool

        switch await center.authorizationStatus() {
        case .notDetermined:
            isAuthorized = try await center.requestAlertAuthorization()
        case .authorized, .provisional, .ephemeral:
            isAuthorized = true
        case .denied:
            isAuthorized = false
        }

        Settings.notificationsEnabled = isAuthorized
        return isAuthorized
    }

    func disableNotifications() {
        Settings.notificationsEnabled = false
    }

    @discardableResult
    func sendTrackNotification(station: String, track: String) async throws -> Bool {
        guard Settings.notificationsEnabled else { return false }

        return try await deliverIfAuthorized(
            UserNotificationMessage(
                identifier: "track-\(UUID().uuidString)",
                title: station,
                body: track
            )
        )
    }

    @discardableResult
    func sendNetworkErrorNotification() async throws -> Bool {
        try await deliverIfAuthorized(
            UserNotificationMessage(
                identifier: "network-error",
                title: "Network error",
                body: "Can't connect to SomaFM.com"
            )
        )
    }

    private func deliverIfAuthorized(_ message: UserNotificationMessage) async throws -> Bool {
        guard await center.authorizationStatus().permitsDelivery else { return false }

        try await center.deliver(message)
        return true
    }
}

extension UserNotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
