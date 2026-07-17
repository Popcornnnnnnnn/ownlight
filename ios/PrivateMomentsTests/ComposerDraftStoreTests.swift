import XCTest
@testable import PrivateMoments

final class ComposerDraftStoreTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        ComposerDraftStore.clear()
    }

    override func tearDownWithError() throws {
        ComposerDraftStore.clear()
        try super.tearDownWithError()
    }

    func testSavingEmptyImagesDoesNotDeletePreparedVideoDraftFiles() throws {
        let directory = try AppDirectories.draftMediaDirectory()
        let videoURL = directory.appending(path: "prepared-video.mp4")
        let posterURL = directory.appending(path: "prepared-video-poster.jpg")

        try Data([0x01, 0x02, 0x03]).write(to: videoURL, options: [.atomic])
        try Data([0x04, 0x05, 0x06]).write(to: posterURL, options: [.atomic])

        try ComposerDraftStore.saveImages([])

        XCTAssertTrue(FileManager.default.fileExists(atPath: videoURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: posterURL.path))
        XCTAssertEqual(ComposerDraftStore.loadImages(), [])
    }

    func testLoadImagesIgnoresNonImageDraftFiles() throws {
        let directory = try AppDirectories.draftMediaDirectory()
        let imageURL = directory.appending(path: "000.image")
        let videoURL = directory.appending(path: "prepared-video.mp4")

        let imageData = Data([0x10, 0x11, 0x12])
        try imageData.write(to: imageURL, options: [.atomic])
        try Data([0x20, 0x21, 0x22]).write(to: videoURL, options: [.atomic])

        XCTAssertEqual(ComposerDraftStore.loadImages(), [imageData])
    }

    func testLoadAudioDraftURLsReturnsOldestFirstAndCapsAtNine() throws {
        let directory = try AppDirectories.draftMediaDirectory()
        var expectedNames: [String] = []

        for index in 0..<10 {
            let fileName = String(format: "composer-audio-%02d.m4a", index)
            let url = directory.appending(path: fileName)
            try Data([UInt8(index)]).write(to: url, options: [.atomic])
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: TimeInterval(index))],
                ofItemAtPath: url.path
            )
            if index < 9 {
                expectedNames.append(fileName)
            }
        }

        try Data([0xFF]).write(to: directory.appending(path: "other-audio.m4a"), options: [.atomic])

        XCTAssertEqual(
            ComposerDraftStore.loadAudioDraftURLs().map(\.lastPathComponent),
            expectedNames
        )
    }

    func testPersistPreparedAudioMediaAssignsContinuousSortOrder() throws {
        let directory = try AppDirectories.draftMediaDirectory()
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let drafts = try (0..<3).map { index in
            let id = "test-audio-\(UUID().uuidString)-\(index)"
            let url = directory.appending(path: "\(id).m4a")
            try Data([UInt8(index), 0x0A]).write(to: url, options: [.atomic])
            return PreparedMomentMedia(
                id: id,
                kind: "audio",
                fileURL: url,
                mimeType: "audio/mp4",
                durationSeconds: Double(index + 1)
            )
        }

        let media = try TimelineStore.persistPreparedAudioMedia(
            postId: "post-audio-group",
            audio: drafts,
            createdAt: createdAt
        )

        XCTAssertEqual(media.map(\.id), drafts.map(\.id))
        XCTAssertEqual(media.map(\.kind), ["audio", "audio", "audio"])
        XCTAssertEqual(media.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(media.map(\.durationSeconds), [1, 2, 3])
        for item in media {
            XCTAssertTrue(FileManager.default.fileExists(atPath: item.localCompressedPath))
        }
    }

    func testRecoveringTransientEmptyTextRestoresPersistedDraft() {
        let savedText = "Foreground restore should keep this draft"
        ComposerDraftStore.save(text: savedText, occurredAt: Date())

        XCTAssertEqual(
            ComposerDraftStore.textAfterRecoveringTransientEmpty(currentText: ""),
            savedText
        )
    }

    func testRecoveringTransientEmptyTextKeepsCurrentTextWhenPresent() {
        ComposerDraftStore.save(text: "Persisted draft", occurredAt: Date())

        XCTAssertEqual(
            ComposerDraftStore.textAfterRecoveringTransientEmpty(currentText: "Current edit"),
            "Current edit"
        )
    }

    func testRecoveringTransientEmptyTextStaysEmptyWhenNoPersistedDraftExists() {
        XCTAssertEqual(
            ComposerDraftStore.textAfterRecoveringTransientEmpty(currentText: ""),
            ""
        )
    }

    func testClearingTextAndDateResetsDraftTimeWithoutRemovingMediaDrafts() throws {
        let oldDate = Date(timeIntervalSince1970: 1_000)
        ComposerDraftStore.save(text: "Draft I no longer want", occurredAt: oldDate)

        let directory = try AppDirectories.draftMediaDirectory()
        let imageURL = directory.appending(path: "000.image")
        try Data([0x01, 0x02, 0x03]).write(to: imageURL, options: [.atomic])

        ComposerDraftStore.clearTextAndDate()

        XCTAssertEqual(ComposerDraftStore.loadText(), "")
        XCTAssertGreaterThan(
            ComposerDraftStore.loadOccurredAt().timeIntervalSince1970,
            oldDate.addingTimeInterval(60).timeIntervalSince1970
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))
    }

    func testHasMediaDraftsDetectsRecoverableAudioFiles() throws {
        XCTAssertFalse(ComposerDraftStore.hasMediaDrafts())

        let directory = try AppDirectories.draftMediaDirectory()
        let audioURL = directory.appending(path: "composer-audio-\(UUID().uuidString).m4a")
        try Data([0x01, 0x02, 0x03]).write(to: audioURL, options: [.atomic])

        XCTAssertTrue(ComposerDraftStore.hasMediaDrafts())
    }
}
