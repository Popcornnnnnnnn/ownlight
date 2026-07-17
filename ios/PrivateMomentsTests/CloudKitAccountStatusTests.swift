import CloudKit
import XCTest
@testable import PrivateMoments

final class CloudKitAccountStatusTests: XCTestCase {
    func testMapsAvailableStatus() {
        let snapshot = CloudKitAccountStatusSnapshot(
            configuration: .init(infoDictionary: [
                "PrivateMomentsCloudKitContainerIdentifier": "iCloud.com.example.ownlight.tests"
            ]),
            accountStatus: .available,
            checkedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(snapshot.state, .available)
        XCTAssertTrue(snapshot.canCheckCloudKit)
        XCTAssertEqual(snapshot.containerIdentifier, "iCloud.com.example.ownlight.tests")
    }

    func testMapsNoAccountStatus() {
        let snapshot = CloudKitAccountStatusSnapshot(
            configuration: .init(infoDictionary: [
                "PrivateMomentsCloudKitContainerIdentifier": "iCloud.com.example.ownlight.tests"
            ]),
            accountStatus: .noAccount,
            checkedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(snapshot.state, .noAccount)
        XCTAssertFalse(snapshot.canEnableSync)
    }

    func testUnconfiguredContainerSkipsAccountCheck() {
        let snapshot = CloudKitAccountStatusSnapshot.notConfigured

        XCTAssertEqual(snapshot.state, .notConfigured)
        XCTAssertFalse(snapshot.canCheckCloudKit)
        XCTAssertFalse(snapshot.canEnableSync)
    }

    func testServiceDoesNotAskCloudKitWhenUnconfigured() async {
        let checker = StubCloudKitAccountStatusChecker(result: .success(.available))
        let service = CloudKitAccountStatusService(
            configuration: .init(infoDictionary: [:]),
            checker: checker
        )

        let snapshot = await service.loadAccountStatus()

        XCTAssertEqual(snapshot.state, .notConfigured)
        XCTAssertEqual(checker.calls, 0)
    }

    func testServiceMapsThrownErrorToCouldNotDetermine() async {
        let checker = StubCloudKitAccountStatusChecker(result: .failure(TestError.failure))
        let service = CloudKitAccountStatusService(
            configuration: .init(infoDictionary: [
                "PrivateMomentsCloudKitContainerIdentifier": "iCloud.com.example.ownlight.tests"
            ]),
            checker: checker
        )

        let snapshot = await service.loadAccountStatus()

        XCTAssertEqual(snapshot.state, .couldNotDetermine)
        XCTAssertEqual(checker.calls, 1)
    }
}

private enum TestError: Error {
    case failure
}

private final class StubCloudKitAccountStatusChecker: CloudKitAccountStatusChecking {
    private let result: Result<CKAccountStatus, Error>
    private(set) var calls = 0

    init(result: Result<CKAccountStatus, Error>) {
        self.result = result
    }

    func accountStatus() async throws -> CKAccountStatus {
        calls += 1
        return try result.get()
    }
}
