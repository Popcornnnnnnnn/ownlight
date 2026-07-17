import XCTest
@testable import PrivateMoments

final class ComposerMediaActionPolicyTests: XCTestCase {
    func testAudioRecordingActionDismissesKeyboardBeforeStartingRecorder() {
        var events: [String] = []

        ComposerMediaActionPolicy.startAudioRecordingIfPossible(
            canStart: true,
            dismissKeyboard: { events.append("dismiss-keyboard") },
            startRecording: { events.append("start-recording") }
        )

        XCTAssertEqual(events, ["dismiss-keyboard", "start-recording"])
    }

    func testAudioRecordingActionDoesNothingWhenRecordingCannotStart() {
        var events: [String] = []

        ComposerMediaActionPolicy.startAudioRecordingIfPossible(
            canStart: false,
            dismissKeyboard: { events.append("dismiss-keyboard") },
            startRecording: { events.append("start-recording") }
        )

        XCTAssertEqual(events, [])
    }
}
