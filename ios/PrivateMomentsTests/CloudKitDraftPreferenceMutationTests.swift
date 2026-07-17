import XCTest
@testable import PrivateMoments

@MainActor
final class CloudKitDraftPreferenceMutationTests: XCTestCase {
    private var temporaryRoot: URL!
    private var savedAIProviderProfiles: [AIProviderProfile] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedAIProviderProfiles = AppSettings.aiProviderProfiles
        temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "CloudKitDraftPreferenceMutationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        UserDefaults.standard.removeObject(forKey: AppSettings.KeysForTesting.iCloudSyncEnabled)
        ComposerDraftStore.clear()
        EditDraftStore.clear(postId: "post-1")
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: AppSettings.KeysForTesting.iCloudSyncEnabled)
        AppSettings.aiProviderProfiles = savedAIProviderProfiles
        ComposerDraftStore.clear()
        EditDraftStore.clear(postId: "post-1")
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        temporaryRoot = nil
        try super.tearDownWithError()
    }

    func testComposerDraftSaveDoesNotEnqueueCloudKitChangeWhenICloudSyncIsDisabled() throws {
        AppSettings.iCloudSyncEnabled = false
        let database = try makeDatabase()
        let store = makeStore(database: database)
        let occurredAt = Date(timeIntervalSince1970: 1_800_020_000)

        try store.saveComposerDraft(
            text: "Local-only draft",
            occurredAt: occurredAt,
            updatedAt: occurredAt.addingTimeInterval(1),
            reason: "draft_composer_save"
        )

        XCTAssertEqual(ComposerDraftStore.loadText(), "Local-only draft")
        XCTAssertEqual(try database.fetchPendingCloudKitChanges(limit: 10), [])
    }

    func testComposerDraftSaveEnqueuesCloudKitDraftUpsertWhenICloudSyncIsEnabled() throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let store = makeStore(database: database)
        let occurredAt = Date(timeIntervalSince1970: 1_800_020_100)

        try store.saveComposerDraft(
            text: "Composer draft",
            occurredAt: occurredAt,
            updatedAt: occurredAt.addingTimeInterval(1),
            reason: "draft_composer_save"
        )

        let change = try XCTUnwrap(try database.fetchPendingCloudKitChanges(limit: 10).onlyElement)
        XCTAssertEqual(change.entityType, .draft)
        XCTAssertEqual(change.entityId, CloudKitDraftSnapshot.composerRecordId)
        XCTAssertEqual(change.changeKind, .upsert)
        XCTAssertEqual(change.reason, "draft_composer_save")
    }

    func testComposerDraftSaveReusesPendingUpsertInsteadOfEnqueuingEveryKeystroke() throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let store = makeStore(database: database)
        let occurredAt = Date(timeIntervalSince1970: 1_800_020_150)

        try store.saveComposerDraft(
            text: "Draft a",
            occurredAt: occurredAt,
            updatedAt: occurredAt.addingTimeInterval(1),
            reason: "draft_composer_text"
        )
        try store.saveComposerDraft(
            text: "Draft after another keystroke",
            occurredAt: occurredAt,
            updatedAt: occurredAt.addingTimeInterval(2),
            reason: "draft_composer_text"
        )

        XCTAssertEqual(ComposerDraftStore.loadText(), "Draft after another keystroke")
        let changes = try database.fetchPendingCloudKitChanges(limit: 10)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.entityType, .draft)
        XCTAssertEqual(changes.first?.changeKind, .upsert)
    }

    func testComposerDraftClearEnqueuesCloudKitDraftDeleteWhenICloudSyncIsEnabled() throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let store = makeStore(database: database)
        ComposerDraftStore.save(
            text: "Discard me",
            occurredAt: Date(timeIntervalSince1970: 1_800_020_200)
        )

        try store.clearComposerDraft(reason: "draft_composer_clear")

        XCTAssertEqual(ComposerDraftStore.loadText(), "")
        let change = try XCTUnwrap(try database.fetchPendingCloudKitChanges(limit: 10).onlyElement)
        XCTAssertEqual(change.entityType, .draft)
        XCTAssertEqual(change.entityId, CloudKitDraftSnapshot.composerRecordId)
        XCTAssertEqual(change.changeKind, .delete)
        XCTAssertEqual(change.reason, "draft_composer_clear")
    }

    func testComposerDraftSaveAfterQueuedDeleteEnqueuesFollowUpUpsert() throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let store = makeStore(database: database)
        let occurredAt = Date(timeIntervalSince1970: 1_800_020_250)

        try store.saveComposerDraft(
            text: "Draft before discard",
            occurredAt: occurredAt,
            updatedAt: occurredAt.addingTimeInterval(1),
            reason: "draft_composer_text"
        )
        try store.clearComposerDraft(reason: "draft_composer_clear", now: occurredAt.addingTimeInterval(2))
        try store.saveComposerDraft(
            text: "Draft resumed after discard",
            occurredAt: occurredAt,
            updatedAt: occurredAt.addingTimeInterval(3),
            reason: "draft_composer_text"
        )

        let changes = try database.fetchPendingCloudKitChanges(limit: 10)
        XCTAssertEqual(changes.map(\.changeKind), [.upsert, .delete, .upsert])
        XCTAssertEqual(changes.map(\.entityType), [.draft, .draft, .draft])
        XCTAssertEqual(ComposerDraftStore.loadText(), "Draft resumed after discard")
    }

    func testEditDraftSaveEnqueuesCloudKitDraftUpsertWhenICloudSyncIsEnabled() throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let store = makeStore(database: database)
        let occurredAt = Date(timeIntervalSince1970: 1_800_020_300)

        try store.saveEditDraft(
            postId: "post-1",
            text: "Unsaved edit",
            occurredAt: occurredAt,
            updatedAt: occurredAt.addingTimeInterval(1),
            mediaItems: [],
            reason: "draft_edit_save"
        )

        let metadata = try XCTUnwrap(EditDraftStore.loadMetadata(postId: "post-1"))
        XCTAssertEqual(metadata.text, "Unsaved edit")
        let change = try XCTUnwrap(try database.fetchPendingCloudKitChanges(limit: 10).onlyElement)
        XCTAssertEqual(change.entityType, .draft)
        XCTAssertEqual(change.entityId, CloudKitDraftSnapshot.editRecordId(postId: "post-1"))
        XCTAssertEqual(change.changeKind, .upsert)
        XCTAssertEqual(change.reason, "draft_edit_save")
    }

    func testEditDraftClearEnqueuesCloudKitDraftDeleteWhenICloudSyncIsEnabled() throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let store = makeStore(database: database)
        let occurredAt = Date(timeIntervalSince1970: 1_800_020_400)
        try EditDraftStore.save(
            postId: "post-1",
            text: "Discard edit",
            occurredAt: occurredAt,
            updatedAt: occurredAt.addingTimeInterval(1),
            mediaItems: []
        )

        try store.clearEditDraft(postId: "post-1", reason: "draft_edit_clear")

        XCTAssertNil(EditDraftStore.loadMetadata(postId: "post-1"))
        let change = try XCTUnwrap(try database.fetchPendingCloudKitChanges(limit: 10).onlyElement)
        XCTAssertEqual(change.entityType, .draft)
        XCTAssertEqual(change.entityId, CloudKitDraftSnapshot.editRecordId(postId: "post-1"))
        XCTAssertEqual(change.changeKind, .delete)
        XCTAssertEqual(change.reason, "draft_edit_clear")
    }

    func testVisiblePreferenceChangeEnqueuesCloudKitPreferenceUpsert() throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let store = makeStore(database: database)

        store.setShowTagsInTimeline(false)

        let change = try XCTUnwrap(try database.fetchPendingCloudKitChanges(limit: 10).onlyElement)
        XCTAssertEqual(change.entityType, .preference)
        XCTAssertEqual(change.entityId, CloudKitPreferenceSnapshot.recordId)
        XCTAssertEqual(change.changeKind, .upsert)
        XCTAssertEqual(change.reason, "preference_show_tags")
    }

    func testAIProviderProfileChangeDoesNotEnqueueCloudKitPreference() throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let store = makeStore(database: database)

        store.saveAIProviderProfile(AIProviderProfile(
            id: "provider-profile-1",
            kind: .customOpenAICompatible,
            displayName: "Private Endpoint",
            baseURLString: "https://ai.example/v1",
            model: "model",
            isEnabled: true,
            sortOrder: 0
        ))

        XCTAssertEqual(try database.fetchPendingCloudKitChanges(limit: 10), [])
    }

    private func makeDatabase() throws -> LocalDatabase {
        try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "\(UUID().uuidString).sqlite"))
    }

    private func makeStore(database: LocalDatabase) -> TimelineStore {
        let store = TimelineStore()
        store.database = database
        return store
    }
}

private extension Array {
    var onlyElement: Element? {
        count == 1 ? first : nil
    }
}
