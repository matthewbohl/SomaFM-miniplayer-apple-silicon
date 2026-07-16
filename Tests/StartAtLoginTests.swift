import XCTest
@testable import SomaFM_miniplayer

final class StartAtLoginTests: XCTestCase {
    func testRegisteringDisabledLoginItem() throws {
        let service = LoginItemServiceStub(status: .notRegistered)
        let startAtLogin = StartAtLogin(service: service)

        let status = try startAtLogin.setEnabled(true)

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(status, .enabled)
        XCTAssertTrue(startAtLogin.isEnabled)
    }

    func testEnablingRegisteredLoginItemDoesNotRegisterAgain() throws {
        let service = LoginItemServiceStub(status: .enabled)
        let startAtLogin = StartAtLogin(service: service)

        try startAtLogin.setEnabled(true)

        XCTAssertEqual(service.registerCallCount, 0)
    }

    func testUnregisteringEnabledLoginItem() throws {
        let service = LoginItemServiceStub(status: .enabled)
        let startAtLogin = StartAtLogin(service: service)

        let status = try startAtLogin.setEnabled(false)

        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(status, .notRegistered)
        XCTAssertFalse(startAtLogin.isEnabled)
    }

    func testApprovalPendingLoginItemIsEnabled() {
        let service = LoginItemServiceStub(status: .requiresApproval)

        XCTAssertTrue(StartAtLogin(service: service).isEnabled)
    }

    func testRegistrationErrorPreservesDisabledState() {
        let service = LoginItemServiceStub(status: .notRegistered)
        service.registerError = TestError.registrationFailed
        let startAtLogin = StartAtLogin(service: service)

        XCTAssertThrowsError(try startAtLogin.setEnabled(true))
        XCTAssertFalse(startAtLogin.isEnabled)
    }
}

private final class LoginItemServiceStub: LoginItemService {
    var status: StartAtLoginStatus
    var registerError: Error?
    var registerCallCount = 0
    var unregisterCallCount = 0

    init(status: StartAtLoginStatus) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        status = .notRegistered
    }
}

private enum TestError: Error {
    case registrationFailed
}
