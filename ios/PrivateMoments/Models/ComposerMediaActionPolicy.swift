enum ComposerMediaActionPolicy {
    static func startAudioRecordingIfPossible(
        canStart: Bool,
        dismissKeyboard: () -> Void,
        startRecording: () -> Void
    ) {
        guard canStart else {
            return
        }

        dismissKeyboard()
        startRecording()
    }
}
