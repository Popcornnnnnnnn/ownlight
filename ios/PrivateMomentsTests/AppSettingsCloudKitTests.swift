import XCTest
@testable import PrivateMoments

final class AppSettingsCloudKitTests: XCTestCase {
    private var savedICloudSyncPreference: Any?

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedICloudSyncPreference = UserDefaults.standard.object(
            forKey: AppSettings.KeysForTesting.iCloudSyncEnabled
        )
        UserDefaults.standard.removeObject(forKey: AppSettings.KeysForTesting.iCloudSyncEnabled)
    }

    override func tearDownWithError() throws {
        if let savedICloudSyncPreference {
            UserDefaults.standard.set(
                savedICloudSyncPreference,
                forKey: AppSettings.KeysForTesting.iCloudSyncEnabled
            )
        } else {
            UserDefaults.standard.removeObject(forKey: AppSettings.KeysForTesting.iCloudSyncEnabled)
        }
        savedICloudSyncPreference = nil
        try super.tearDownWithError()
    }

    func testRestoreICloudSyncOptInOnlyWhenMissingAndCloudKitHistoryExists() {
        XCTAssertFalse(AppSettings.hasExplicitICloudSyncPreference)
        XCTAssertFalse(AppSettings.restoreICloudSyncOptInIfMissing(hasCloudKitHistory: false))
        XCTAssertFalse(AppSettings.iCloudSyncEnabled)

        XCTAssertTrue(AppSettings.restoreICloudSyncOptInIfMissing(hasCloudKitHistory: true))
        XCTAssertTrue(AppSettings.hasExplicitICloudSyncPreference)
        XCTAssertTrue(AppSettings.iCloudSyncEnabled)
    }

    func testRestoreICloudSyncOptInDoesNotOverrideExplicitOffChoice() {
        AppSettings.iCloudSyncEnabled = false

        XCTAssertFalse(AppSettings.restoreICloudSyncOptInIfMissing(hasCloudKitHistory: true))
        XCTAssertTrue(AppSettings.hasExplicitICloudSyncPreference)
        XCTAssertFalse(AppSettings.iCloudSyncEnabled)
    }
}
