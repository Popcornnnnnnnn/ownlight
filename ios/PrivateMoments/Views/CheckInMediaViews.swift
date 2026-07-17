import AVFoundation
import SwiftUI
import UIKit

struct CheckInImageThumbnail: View {
    let media: CheckInMedia

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(.secondarySystemBackground)

                if let image = UIImage(contentsOfFile: media.localCompressedPath) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    PlaceholderImage()
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct CheckInAudioCompactBadge: View {
    let media: CheckInMedia

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.12))

            Image(systemName: "waveform")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
}

struct CheckInAudioAttachmentView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.appLanguage) private var appLanguage

    let media: CheckInMedia

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var isLoading = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                togglePlayback()
            } label: {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t(isPlaying ? "Pause audio" : "Play audio", appLanguage))

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("Audio", appLanguage))
                    .font(.subheadline.weight(.semibold))

                Text(audioDetailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "waveform")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onDisappear {
            player?.pause()
            isPlaying = false
        }
    }

    private var audioDetailText: String {
        if let duration = media.durationSeconds, duration > 0 {
            return mediaDurationLabel(duration)
        }

        return L10n.t("Voice note", appLanguage)
    }

    private func togglePlayback() {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }

        Task {
            isLoading = true
            defer {
                isLoading = false
            }

            do {
                let url = try await store.localPlayableURL(for: media)
                if player == nil {
                    player = AVPlayer(url: url)
                    addPlaybackFinishedObserver(for: player?.currentItem)
                } else if let currentURL = (player?.currentItem?.asset as? AVURLAsset)?.url, currentURL != url {
                    let item = AVPlayerItem(url: url)
                    player?.replaceCurrentItem(with: item)
                    addPlaybackFinishedObserver(for: item)
                }
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try? AVAudioSession.sharedInstance().setActive(true)
                player?.play()
                isPlaying = true
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
    }

    private func addPlaybackFinishedObserver(for item: AVPlayerItem?) {
        guard let item else {
            return
        }

        NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { _ in
            player?.seek(to: .zero)
            isPlaying = false
        }
    }
}

struct CheckInSummaryCard: View {
    @Environment(\.appLanguage) private var appLanguage

    let summary: CheckInAISummary
    var transcriptText: String?
    var compact = false
    @State private var isTranscriptExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(L10n.t("Audio Summary", appLanguage))
                    .font(compact ? .caption.weight(.semibold) : .footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let sourceLabel {
                Text(sourceLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            if let title = displayTitle {
                Text(title)
                    .font(compact ? .footnote.weight(.semibold) : .headline)
                    .foregroundStyle(.primary)
                    .lineLimit(compact ? 2 : nil)
            }

            if let oneLiner = displayOneLiner {
                Text(oneLiner)
                    .font(compact ? .caption : .subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 3 : nil)
            }

            if !bulletLines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(bulletLines.prefix(compact ? 2 : 4).enumerated()), id: \.offset) { _, bullet in
                        Text("• \(bullet)")
                            .font(compact ? .caption : .subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(compact ? 2 : nil)
                    }
                }
            } else if let fallbackBody {
                Text(fallbackBody)
                    .font(compact ? .caption : .subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(compact ? 4 : nil)
            }

            if !compact {
                transcriptDisclosure
                    .padding(.top, 4)
            }
        }
        .padding(compact ? 10 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(compact ? 0.06 : 0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var displayTitle: String? {
        normalized(summary.documentTitle)
    }

    private var displayOneLiner: String? {
        let candidates = [summary.oneLiner, summary.overview, summary.summaryText]
        for candidate in candidates {
            guard let value = normalized(candidate) else {
                continue
            }

            if value != displayTitle {
                return value
            }
        }

        return nil
    }

    private var sourceLabel: String? {
        AIProviderSourceFormatter.label(
            provider: summary.provider,
            model: summary.model,
            language: appLanguage
        )
    }

    private var bulletLines: [String] {
        let sectionBullets = summary.sections.flatMap(\.bullets)
        let blockBullets = summary.documentBlocks.flatMap(\.items)
        return (summary.keyPoints + sectionBullets + blockBullets)
            .compactMap(normalized(_:))
    }

    private var fallbackBody: String? {
        guard let summaryText = normalized(summary.summaryText), summaryText != displayOneLiner else {
            return nil
        }

        return summaryText
    }

    private var transcriptDisclosure: some View {
        DisclosureGroup(isExpanded: $isTranscriptExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if let text = normalized(transcriptText) {
                    Text(text)
                        .font(.callout)
                        .lineSpacing(4)
                        .foregroundStyle(.primary.opacity(0.86))
                        .textSelection(.enabled)
                } else {
                    Text(L10n.t("Transcript is not available yet.", appLanguage))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text(L10n.t("Saved privately on this iPhone for search and diagnostics.", appLanguage))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 8)
        } label: {
            Label(L10n.t("Transcript", appLanguage), systemImage: "doc.text.magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct CheckInDraftAudioPreview: View {
    @Environment(\.appLanguage) private var appLanguage

    let media: PreparedMomentMedia
    let onRemove: () -> Void

    @State private var player: AVPlayer?
    @State private var isPlaying = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t(isPlaying ? "Pause audio" : "Play audio", appLanguage))

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("Audio", appLanguage))
                    .font(.subheadline.weight(.semibold))
                Text(mediaDurationLabel(media.durationSeconds ?? 0))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.secondary, .quaternary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("Remove audio", appLanguage))
        }
        .padding(.vertical, 8)
    }

    private func togglePlayback() {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }

        if player == nil {
            player = AVPlayer(url: media.fileURL)
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        player?.play()
        isPlaying = true
    }
}

struct CheckInRecordingStatusView: View {
    @Environment(\.appLanguage) private var appLanguage

    @ObservedObject var audioRecorder: AudioRecorderController

    var body: some View {
        HStack {
            Label(
                L10n.t(audioRecorder.isPaused ? "Recording paused" : "Recording", appLanguage),
                systemImage: audioRecorder.isPaused ? "pause.circle.fill" : "waveform"
            )
            Spacer()
            Text(mediaDurationLabel(audioRecorder.elapsedSeconds))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button(L10n.t(audioRecorder.isPaused ? "Resume" : "Pause", appLanguage)) {
                audioRecorder.pauseOrResume()
            }
        }
        .padding(.vertical, 8)
    }
}

struct CheckInCapturedImagePreview: View {
    let image: UIImage
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
                    .padding(8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove photo")
        }
        .padding(.vertical, 4)
    }
}
