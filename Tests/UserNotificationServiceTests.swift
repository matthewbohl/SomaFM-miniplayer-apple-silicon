import UserNotifications
import XCTest
@testable import SomaFM_miniplayer

final class UserNotificationServiceTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.notificationsEnabled)
        super.tearDown()
    }

    func testEnablingRequestsAuthorizationWhenNotDetermined() async throws {
        let center = UserNotificationCenterClientStub(status: .notDetermined)
        center.authorizationRequestResult = true
        let service = UserNotificationService(center: center)

        let isEnabled = try await service.enableNotifications()

        XCTAssertTrue(isEnabled)
        XCTAssertTrue(Settings.notificationsEnabled)
        XCTAssertEqual(center.authorizationRequestCount, 1)
    }

    func testDeniedAuthorizationKeepsNotificationsDisabled() async throws {
        let center = UserNotificationCenterClientStub(status: .denied)
        let service = UserNotificationService(center: center)

        let isEnabled = try await service.enableNotifications()

        XCTAssertFalse(isEnabled)
        XCTAssertFalse(Settings.notificationsEnabled)
        XCTAssertEqual(center.authorizationRequestCount, 0)
    }

    func testDisabledTrackNotificationsAreNotDelivered() async throws {
        let center = UserNotificationCenterClientStub(status: .authorized)
        let service = UserNotificationService(center: center)
        Settings.notificationsEnabled = false

        let wasDelivered = try await service.sendTrackNotification(station: "Groove Salad", track: "Test Track")

        XCTAssertFalse(wasDelivered)
        XCTAssertTrue(center.deliveredMessages.isEmpty)
    }

    func testTrackNotificationContainsStationAndTrack() async throws {
        let center = UserNotificationCenterClientStub(status: .authorized)
        let service = UserNotificationService(center: center)
        Settings.notificationsEnabled = true

        let wasDelivered = try await service.sendTrackNotification(station: "Groove Salad", track: "Test Track")

        XCTAssertTrue(wasDelivered)
        XCTAssertEqual(center.deliveredMessages.first?.title, "Groove Salad")
        XCTAssertEqual(center.deliveredMessages.first?.body, "Test Track")
        XCTAssertTrue(center.deliveredMessages.first?.identifier.hasPrefix("track-") == true)
    }

    func testNetworkErrorDoesNotPromptForAuthorization() async throws {
        let center = UserNotificationCenterClientStub(status: .notDetermined)
        let service = UserNotificationService(center: center)

        let wasDelivered = try await service.sendNetworkErrorNotification()

        XCTAssertFalse(wasDelivered)
        XCTAssertEqual(center.authorizationRequestCount, 0)
        XCTAssertTrue(center.deliveredMessages.isEmpty)
    }

    func testAuthorizedNetworkErrorIsDeliveredWhenTrackNotificationsAreDisabled() async throws {
        let center = UserNotificationCenterClientStub(status: .authorized)
        let service = UserNotificationService(center: center)
        Settings.notificationsEnabled = false

        let wasDelivered = try await service.sendNetworkErrorNotification()

        XCTAssertTrue(wasDelivered)
        XCTAssertEqual(
            center.deliveredMessages,
            [
                UserNotificationMessage(
                    identifier: "network-error",
                    title: "Network error",
                    body: "Can't connect to SomaFM.com"
                )
            ]
        )
    }

    func testDeliveryErrorIsPropagated() async {
        let center = UserNotificationCenterClientStub(status: .authorized)
        center.deliveryError = TestError.deliveryFailed
        let service = UserNotificationService(center: center)
        Settings.notificationsEnabled = true

        do {
            _ = try await service.sendTrackNotification(station: "Groove Salad", track: "Test Track")
            XCTFail("Expected delivery to throw")
        } catch {
            XCTAssertEqual(error as? TestError, .deliveryFailed)
        }
    }
}

private final class UserNotificationCenterClientStub: UserNotificationCenterClient {
    var status: NotificationAuthorizationStatus
    var authorizationRequestResult = false
    var authorizationRequestCount = 0
    var deliveredMessages: [UserNotificationMessage] = []
    var deliveryError: Error?

    init(status: NotificationAuthorizationStatus) {
        self.status = status
    }

    func setDelegate(_ delegate: UNUserNotificationCenterDelegate) {}

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        status
    }

    func requestAlertAuthorization() async throws -> Bool {
        authorizationRequestCount += 1
        status = authorizationRequestResult ? .authorized : .denied
        return authorizationRequestResult
    }

    func deliver(_ message: UserNotificationMessage) async throws {
        if let deliveryError {
            throw deliveryError
        }
        deliveredMessages.append(message)
    }
}

private enum TestError: Error {
    case deliveryFailed
}
