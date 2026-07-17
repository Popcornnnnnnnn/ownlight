import XCTest
@testable import PrivateMoments

@MainActor
final class CloudKitCheckInMutationTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "CloudKitCheckInMutationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        UserDefaults.standard.removeObject(forKey: AppSettings.KeysForTesting.iCloudSyncEnabled)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: AppSettings.KeysForTesting.iCloudSyncEnabled)
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        temporaryRoot = nil
        try super.tearDownWithError()
    }

    func testCreateCheckInItemEnqueuesCloudKitItemUpsertWhenICloudSyncIsEnabled() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let store = try await makeStore(database: database)

        let didCreate = await store.createCheckInItem(
            name: "Workout",
            symbolName: "figure.run",
            colorHex: "#22AA66",
            recordMode: .multiplePerDay,
            timeVisualization: .timeHeatmap,
            activeWeekdays: [2, 4, 6],
            defaultShowInTimeline: true,
            tagId: nil
        )

        XCTAssertTrue(didCreate)
        let change = try XCTUnwrap(try database.fetchPendingCloudKitChanges(limit: 10).onlyElement)
        XCTAssertEqual(change.entityType, .checkInItem)
        XCTAssertEqual(change.changeKind, .upsert)
        XCTAssertEqual(change.reason, "checkin_item_upsert")
    }

    func testRecordCheckInWithAudioEnqueuesEntryMediaAndAssetUploadWhenICloudSyncIsEnabled() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let item = Self.checkInItem(id: "checkin-item-audio", now: Date(timeIntervalSince1970: 1_800_010_000))
        try database.upsertCheckInItemOnly(item)
        let audioURL = temporaryRoot.appending(path: "checkin-voice.m4a")
        try Data("voice-bytes".utf8).write(to: audioURL)
        let store = try await makeStore(database: database)

        let maybeEntry = await store.recordCheckIn(
            item: item,
            note: "Quick voice note",
            audioDraft: PreparedMomentMedia(
                id: "checkin-media-audio",
                kind: "audio",
                fileURL: audioURL,
                mimeType: "audio/mp4",
                durationSeconds: 4.2
            )
        )
        let entry = try XCTUnwrap(maybeEntry)

        let changes = try database.fetchPendingCloudKitChanges(limit: 10)
        XCTAssertTrue(changes.contains { change in
            change.entityType == .checkInEntry
                && change.entityId == entry.id
                && change.changeKind == .upsert
                && change.reason == "checkin_entry_upsert"
        })
        XCTAssertTrue(changes.contains { change in
            change.entityType == .checkInMedia
                && change.entityId == "checkin-media-audio"
                && change.changeKind == .upsert
                && change.reason == "checkin_media_upsert"
        })
        XCTAssertTrue(changes.contains { change in
            change.entityType == .checkInMedia
                && change.entityId == "checkin-media-audio"
                && change.changeKind == .assetUpload
                && change.reason == "checkin_media_asset_upload"
        })
    }

    func testDeleteCheckInEntryEnqueuesCloudKitEntryDeleteWhenICloudSyncIsEnabled() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let now = Date(timeIntervalSince1970: 1_800_010_500)
        let item = Self.checkInItem(id: "checkin-item-delete-entry", now: now)
        let entry = CheckInEntry(
            id: "checkin-entry-delete",
            itemId: item.id,
            occurredAt: now,
            note: "Delete this",
            showInTimeline: true,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            syncStatus: "synced"
        )
        try database.upsertCheckInItemOnly(item)
        try database.upsertCheckInEntryOnly(entry)
        let store = try await makeStore(database: database)

        await store.deleteCheckInEntry(entry)

        let change = try XCTUnwrap(try database.fetchPendingCloudKitChanges(limit: 10).onlyElement)
        XCTAssertEqual(change.entityType, .checkInEntry)
        XCTAssertEqual(change.entityId, entry.id)
        XCTAssertEqual(change.changeKind, .delete)
        XCTAssertEqual(change.reason, "checkin_entry_delete")
    }

    private func makeDatabase() throws -> LocalDatabase {
        try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "test.sqlite"))
    }

    private func makeStore(database: LocalDatabase) async throws -> TimelineStore {
        let store = TimelineStore()
        store.database = database
        try await store.reload()
        return store
    }

    private static func checkInItem(id: String, now: Date) -> CheckInItem {
        CheckInItem(
            id: id,
            name: "Workout",
            symbolName: "figure.run",
            colorHex: "#22AA66",
            recordMode: .multiplePerDay,
            timeVisualization: .timeHeatmap,
            dayStartHour: 0,
            activeWeekdays: [1, 2, 3, 4, 5, 6, 7],
            sortOrder: 0,
            defaultShowInTimeline: true,
            tagId: nil,
            createdAt: now,
            updatedAt: now,
            archivedAt: nil,
            deletedAt: nil,
            syncStatus: "synced"
        )
    }
}

private extension Array {
    var onlyElement: Element? {
        count == 1 ? first : nil
    }
}
