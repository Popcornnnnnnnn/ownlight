import XCTest
@testable import PrivateMoments

final class CloudKitConfigurationTests: XCTestCase {
    func testReadsConfiguredContainerIdentifier() {
        let configuration = CloudKitConfiguration(
            infoDictionary: [
                "PrivateMomentsCloudKitContainerIdentifier": "iCloud.com.example.ownlight.tests"
            ]
        )

        XCTAssertEqual(configuration.containerIdentifier, "iCloud.com.example.ownlight.tests")
        XCTAssertTrue(configuration.isConfigured)
    }

    func testRejectsBlankContainerIdentifier() {
        let configuration = CloudKitConfiguration(
            infoDictionary: [
                "PrivateMomentsCloudKitContainerIdentifier": "   "
            ]
        )

        XCTAssertNil(configuration.containerIdentifier)
        XCTAssertFalse(configuration.isConfigured)
    }

    func testRejectsUnexpandedBuildSetting() {
        let configuration = CloudKitConfiguration(
            infoDictionary: [
                "PrivateMomentsCloudKitContainerIdentifier": "$(PRIVATE_MOMENTS_ICLOUD_CONTAINER_ID)"
            ]
        )

        XCTAssertNil(configuration.containerIdentifier)
        XCTAssertFalse(configuration.isConfigured)
    }

    func testRequiresICloudPrefix() {
        let configuration = CloudKitConfiguration(
            infoDictionary: [
                "PrivateMomentsCloudKitContainerIdentifier": "com.example.ownlight.tests"
            ]
        )

        XCTAssertNil(configuration.containerIdentifier)
        XCTAssertFalse(configuration.isConfigured)
    }

    func testRejectsSourceBuildPlaceholderContainer() {
        let configuration = CloudKitConfiguration(
            infoDictionary: [
                "PrivateMomentsCloudKitContainerIdentifier": "iCloud.dev.privatemoments.app"
            ]
        )

        XCTAssertNil(configuration.containerIdentifier)
        XCTAssertFalse(configuration.isConfigured)
    }

    func testRejectsUATSourceBuildPlaceholderContainer() {
        let configuration = CloudKitConfiguration(
            infoDictionary: [
                "PrivateMomentsCloudKitContainerIdentifier": "iCloud.dev.privatemoments.app.uat"
            ]
        )

        XCTAssertNil(configuration.containerIdentifier)
        XCTAssertFalse(configuration.isConfigured)
    }
}
