//
//  StartAtLogin.swift
//
//  Copyright © 2017 Evgeny Aleksandrov. All rights reserved.

import ServiceManagement

enum StartAtLoginStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

protocol LoginItemService {
    var status: StartAtLoginStatus { get }

    func register() throws
    func unregister() throws
}

final class SystemLoginItemService: LoginItemService {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var status: StartAtLoginStatus {
        switch service.status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notRegistered
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }
}

struct StartAtLogin {
    private let service: LoginItemService

    init(service: LoginItemService = SystemLoginItemService()) {
        self.service = service
    }

    var status: StartAtLoginStatus {
        service.status
    }

    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    @discardableResult
    func setEnabled(_ isEnabled: Bool) throws -> StartAtLoginStatus {
        if isEnabled {
            if status == .notRegistered || status == .notFound {
                try service.register()
            }
        } else if status == .enabled || status == .requiresApproval {
            try service.unregister()
        }

        return status
    }
}
