import SwiftUI
import UIKit

struct AISummarySheet: View {
    let media: TimelineMedia
    let summary: TimelineAISummary?
    let onRegenerate: () async -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage
    @State private var isDeleteAlertPresented = false
    @State private var didCopy = false
    @State private var isRegenerateRequestInFlight = false
    @State private var expandedDetailGroupIndexes = Set<Int>()
    @State private var presentedAuxiliarySheet: AISummaryAuxiliarySheet?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let displaySummary {
                        if isGenerationActive {
                            generationStatusBanner()
                        }
                        if isFailed {
                            failureStatusBanner()
                        }
                        readySummaryContent(displaySummary)
                    } else if isGenerationActive {
                        generationProgressContent()
                    } else if isFailed {
                        failureContent()
                    } else {
                        ContentUnavailableView(L10n.t("Summary unavailable", appLanguage), systemImage: "sparkles")
                    }

                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 24)
            }
            .navigationTitle(L10n.t("Summary", appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                bottomActionToolbar
                    .padding(.horizontal, 22)
                    .padding(.bottom, 10)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.t("Close", appLanguage))
                }
            }
            .alert(L10n.t("Delete summary?", appLanguage), isPresented: $isDeleteAlertPresented) {
                Button(L10n.t("Cancel", appLanguage), role: .cancel) {}
                Button(L10n.t("Delete", appLanguage), role: .destructive) {
                    onDelete()
                }
            } message: {
                Text(L10n.t("This removes only the generated AI summary.", appLanguage))
            }
            .sheet(item: $presentedAuxiliarySheet) { destination in
                switch destination {
                case .transcript:
                    AISummaryTranscriptSheet(
                        transcriptText: transcriptText,
                        unavailableMessage: transcriptUnavailableMessage
                    )
                }
            }
            .onChange(of: copyText) { _, _ in
                didCopy = false
            }
            .onChange(of: summary?.id) { _, _ in
                isRegenerateRequestInFlight = false
                expandedDetailGroupIndexes.removeAll()
                presentedAuxiliarySheet = nil
            }
            .onChange(of: summary?.status) { _, newStatus in
                if newStatus != "transcribing" && newStatus != "summarizing" {
                    isRegenerateRequestInFlight = false
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var bottomActionToolbar: some View {
        HStack {
            Spacer()

            HStack(spacing: 20) {
                if canViewOriginalText {
                    Button {
                        presentedAuxiliarySheet = .transcript
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.title3)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .accessibilityLabel(L10n.t("View original text", appLanguage))
                }

                Button {
                    copyContent()
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.title3)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .opacity(copyText == nil ? 0.45 : 1)
                .disabled(copyText == nil)
                .accessibilityLabel(L10n.t(didCopy ? "Copied" : "Copy", appLanguage))

                if canRegenerate {
                    Button {
                        startRegeneration()
                    } label: {
                        if isGenerationActive {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 26, height: 26)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.title3)
                                .frame(width: 26, height: 26)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .opacity(isGenerationActive ? 0.45 : 1)
                    .disabled(isGenerationActive)
                    .accessibilityLabel(L10n.t(isGenerationActive ? "Regenerating" : "Regenerate", appLanguage))

                    Button(role: .destructive) {
                        isDeleteAlertPresented = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.title3)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .opacity(isGenerationActive ? 0.45 : 1)
                    .disabled(isGenerationActive)
                    .accessibilityLabel(L10n.t("Delete", appLanguage))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8)
        }
    }

    private func generationStatusBanner() -> some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(generationStatusTitle)
                    .font(.subheadline.weight(.semibold))
                Text(generationStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func generationProgressContent() -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(generationStatusTitle)
                .font(.headline)
            Text(generationStatusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private func failureStatusBanner() -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("Summary update failed", appLanguage))
                    .font(.subheadline.weight(.semibold))
                Text(failureMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func failureContent() -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.orange)
            Text(L10n.t("Summary failed", appLanguage))
                .font(.headline)
            Text(failureMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private func startRegeneration() {
        guard !isGenerationActive else {
            return
        }

        isRegenerateRequestInFlight = true
        didCopy = false

        Task {
            await onRegenerate()
            await MainActor.run {
                isRegenerateRequestInFlight = false
            }
        }
    }

    @ViewBuilder
    private func readySummaryContent(_ summary: TimelineAISummary) -> some View {
        if hasDocumentContent(summary) {
            documentSummaryContent(summary)
        } else {
            legacySummaryContent(summary)
        }

        tokenUsageFooter(summary)
    }

    @ViewBuilder
    private func documentSummaryContent(_ summary: TimelineAISummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = cleaned(summary.documentTitle) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }

            Text(summaryMetadataText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }

        if let oneLiner = cleaned(summary.oneLiner ?? summary.overview) {
            summaryCallout(oneLiner)
        }

        let highlights = highlightItems(for: summary)
        if !highlights.isEmpty {
            summarySectionHeader("Highlights")
            bulletList(highlights)
                .font(.callout)
        }

        let groups = documentGroups(from: summary.documentBlocks)
        if !groups.isEmpty {
            detailsSectionHeader(groups)
            detailsGroupList(groups)
        }
    }

    @ViewBuilder
    private func legacySummaryContent(_ summary: TimelineAISummary) -> some View {
        if let overview = cleaned(summary.overview) {
            Text(overview)
                .font(.body)
                .textSelection(.enabled)
        }

        if !summary.keyPoints.isEmpty {
            summaryBlock(title: L10n.t("Key Points", appLanguage)) {
                bulletList(summary.keyPoints)
            }
        }

        ForEach(summary.sections, id: \.heading) { section in
            summaryBlock(title: section.heading) {
                bulletList(section.bullets)
            }
        }

        if cleaned(summary.overview) == nil,
           summary.keyPoints.isEmpty,
           summary.sections.isEmpty {
            if let summaryText = cleaned(summary.summaryText) {
                Text(summaryText)
                    .font(.body)
                    .textSelection(.enabled)
            } else {
                ContentUnavailableView(L10n.t("Summary unavailable", appLanguage), systemImage: "sparkles")
            }
        }
    }

    private func detailsGroupList(_ groups: [SummaryDocumentGroup]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                detailGroupRow(group, index: index, isLast: index == groups.count - 1)
            }
        }
    }

    private func detailsSectionHeader(_ groups: [SummaryDocumentGroup]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .opacity(0.18)

            HStack(alignment: .center, spacing: 12) {
                Text(L10n.t("Details", appLanguage))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                if groups.count > 1 {
                    let isExpanded = areAllDetailGroupsExpanded(groups)
                    Button {
                        toggleAllDetailGroups(groups)
                    } label: {
                        doubleChevronIcon(isExpanded: isExpanded)
                            .frame(width: 44, height: 30, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t(isExpanded ? "Collapse all details" : "Expand all details", appLanguage))
                }
            }
        }
        .padding(.top, 2)
    }

    private func doubleChevronIcon(isExpanded: Bool) -> some View {
        VStack(spacing: -4) {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary.opacity(0.45))
        .accessibilityHidden(true)
    }

    private func areAllDetailGroupsExpanded(_ groups: [SummaryDocumentGroup]) -> Bool {
        groups.indices.allSatisfy { expandedDetailGroupIndexes.contains($0) }
    }

    private func toggleAllDetailGroups(_ groups: [SummaryDocumentGroup]) {
        withAnimation(.snappy(duration: 0.18)) {
            if areAllDetailGroupsExpanded(groups) {
                expandedDetailGroupIndexes.removeAll()
            } else {
                expandedDetailGroupIndexes = Set(groups.indices)
            }
        }
    }

    private func detailGroupRow(_ group: SummaryDocumentGroup, index: Int, isLast: Bool) -> some View {
        let isExpanded = expandedDetailGroupIndexes.contains(index)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    if isExpanded {
                        expandedDetailGroupIndexes.remove(index)
                    } else {
                        expandedDetailGroupIndexes.insert(index)
                    }
                }
            } label: {
                HStack(alignment: .top, spacing: 11) {
                    detailGroupIcon(for: group)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(detailGroupTitle(group, index: index))
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary.opacity(0.92))
                            .lineSpacing(2)
                            .lineLimit(2)

                        if let preview = detailGroupPreview(group), !isExpanded {
                            Text(preview)
                                .font(.callout)
                                .lineSpacing(4)
                                .foregroundStyle(.primary.opacity(0.66))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary.opacity(0.48))
                        .padding(.top, 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(detailGroupTitle(group, index: index))

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(group.blocks.enumerated()), id: \.offset) { _, block in
                        documentBlock(block)
                    }
                }
                .padding(.top, 12)
                .padding(.leading, 32)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !isLast {
                Divider()
                    .opacity(0.14)
                    .padding(.leading, 32)
                    .padding(.vertical, 16)
            }
        }
    }

    private func detailGroupIcon(for group: SummaryDocumentGroup) -> some View {
        Image(systemName: detailGroupIconName(for: group))
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(.secondary.opacity(0.68))
            .frame(width: 18, height: 22)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func documentBlock(_ block: TimelineAISummaryBlock) -> some View {
        switch block.kind {
        case "paragraph":
            if let text = cleaned(block.text) {
                Text(text)
                    .font(.callout)
                    .lineSpacing(3)
                    .foregroundStyle(.primary.opacity(0.86))
                    .textSelection(.enabled)
            }
        case "bullets", "list":
            if let title = cleaned(block.text) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.9))
                    .textSelection(.enabled)
            }
            bulletList(block.items)
        case "numbered_list":
            if let title = cleaned(block.text) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.9))
                    .textSelection(.enabled)
            }
            numberedList(block.items)
        case "ai_suggested", "callout":
            aiSuggestedBlock(block)
        default:
            if let text = cleaned(block.text) {
                Text(text)
                    .font(.callout)
                    .lineSpacing(3)
                    .foregroundStyle(.primary.opacity(0.86))
                    .textSelection(.enabled)
            }
        }
    }

    private func summarySectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .opacity(0.18)

            Text(L10n.t(title, appLanguage))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }

    private func summaryCallout(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(.secondary.opacity(0.28))
                .frame(width: 3)
                .padding(.vertical, 3)

            Text(text)
                .font(.body)
                .lineSpacing(5)
                .foregroundStyle(.primary.opacity(0.9))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func summaryBlock<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
                .font(.callout)
        }
    }

    @ViewBuilder
    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(.secondary.opacity(0.42))
                        .frame(width: 4, height: 4)
                        .padding(.top, 8)
                    Text(item)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func numberedList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(item)
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private func aiSuggestedBlock(_ block: TimelineAISummaryBlock) -> some View {
        if cleaned(block.text) != nil || !block.items.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 18)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 9) {
                    if let text = cleaned(block.text) {
                        Text(text)
                            .font(.body)
                            .textSelection(.enabled)
                    }

                    if !block.items.isEmpty {
                        bulletList(block.items)
                            .font(.callout)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func copyContent() {
        guard let copyText else {
            return
        }

        UIPasteboard.general.string = copyText
        didCopy = true
    }

    private var displaySummary: TimelineAISummary? {
        guard let summary, summary.hasDisplayContent else {
            return nil
        }

        return summary
    }

    private var isSummarizing: Bool {
        summary?.isSummarizing == true
    }

    private var isGenerationActive: Bool {
        isRegenerateRequestInFlight || isSummarizing
    }

    private var isFailed: Bool {
        summary?.isFailed == true
    }

    private var canRegenerate: Bool {
        summary?.deletedAt == nil
    }

    private var canViewOriginalText: Bool {
        media.isAudio || media.isVideo || transcriptText != nil
    }

    private var transcriptText: String? {
        cleaned(media.transcriptionText)
    }

    private var transcriptUnavailableMessage: String {
        if let error = cleaned(media.transcriptionError) {
            return "\(L10n.t("Transcription failed", appLanguage)): \(error)"
        }

        switch media.transcriptionStatus {
        case "transcribing":
            return L10n.t("Transcription is still running.", appLanguage)
        case "failed":
            return L10n.t("Transcription failed.", appLanguage)
        case "pending", "not_requested":
            return L10n.t("Transcript is not available yet.", appLanguage)
        default:
            return L10n.t("Transcript is not available yet.", appLanguage)
        }
    }

    private var summaryMetadataText: String {
        var parts = [mediaKindLabel]
        if let duration = media.durationSeconds {
            parts.append(mediaDurationLabel(duration))
        }
        if let sourceLabel = AIProviderSourceFormatter.label(
            provider: summary?.provider,
            model: summary?.model,
            language: appLanguage
        ) {
            parts.append(sourceLabel)
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func tokenUsageFooter(_ summary: TimelineAISummary) -> some View {
        if let tokenUsageText = tokenUsageMetadataText(for: summary) {
            Text(tokenUsageText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        }
    }

    private func tokenUsageMetadataText(for summary: TimelineAISummary) -> String? {
        let input = summary.inputTokenCount
        let output = summary.outputTokenCount
        let total = summary.totalTokenCount ?? {
            let computed = (input ?? 0) + (output ?? 0)
            return computed > 0 ? computed : nil
        }()

        guard input != nil || output != nil || total != nil else {
            return nil
        }

        var parts = [String]()
        if let total {
            parts.append("\(L10n.t("Tokens", appLanguage)): \(formattedTokenCount(total))")
        }
        if let input {
            parts.append("\(L10n.t("Input", appLanguage)) \(formattedTokenCount(input))")
        }
        if let output {
            parts.append("\(L10n.t("Output", appLanguage)) \(formattedTokenCount(output))")
        }
        return parts.joined(separator: " · ")
    }

    private func formattedTokenCount(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    private var mediaKindLabel: String {
        if media.isAudio {
            return L10n.t("Audio", appLanguage)
        }

        if media.isVideo {
            return L10n.t("Video", appLanguage)
        }

        return L10n.t("Media summaries", appLanguage)
    }

    private var generationStatusTitle: String {
        if isRegenerateRequestInFlight {
            return L10n.t("Regenerating summary...", appLanguage)
        }

        if summary?.status == "transcribing" {
            return L10n.t("Transcribing media...", appLanguage)
        }

        return L10n.t("Summarizing...", appLanguage)
    }

    private var generationStatusMessage: String {
        if displaySummary != nil {
            return L10n.t("The current summary will update when the new result is ready.", appLanguage)
        }

        return L10n.t("This can take a moment.", appLanguage)
    }

    private var failureMessage: String {
        if let message = cleaned(summary?.errorMessage) {
            return message
        }

        if displaySummary != nil {
            return L10n.t("The previous summary is still available. Check the provider or transcript, then regenerate.", appLanguage)
        }

        return L10n.t("Check the provider or transcript, then regenerate.", appLanguage)
    }

    private var copyText: String? {
        if let displaySummary {
            return summaryText(for: displaySummary)
        }

        return nil
    }

    private func summaryText(for summary: TimelineAISummary) -> String? {
        if hasDocumentContent(summary) {
            return documentSummaryText(for: summary)
        }

        if let text = cleaned(summary.summaryText) {
            return text
        }

        var lines = [String]()
        if let overview = cleaned(summary.overview) {
            lines.append(overview)
        }

        if !summary.keyPoints.isEmpty {
            lines.append(contentsOf: summary.keyPoints.map { "- \($0)" })
        }

        for section in summary.sections {
            lines.append(section.heading)
            lines.append(contentsOf: section.bullets.map { "- \($0)" })
        }

        let text = lines.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    private func documentSummaryText(for summary: TimelineAISummary) -> String? {
        var lines = [String]()
        if let title = cleaned(summary.documentTitle) {
            lines.append("# \(title)")
            lines.append("")
        }

        if let oneLiner = cleaned(summary.oneLiner ?? summary.overview) {
            lines.append(oneLiner)
        }

        for block in summary.documentBlocks {
            switch block.kind {
            case "heading":
                if let text = cleaned(block.text) {
                    lines.append("")
                    lines.append("\(block.level == 2 ? "###" : "##") \(text)")
                }
            case "paragraph":
                if let text = cleaned(block.text) {
                    lines.append("")
                    lines.append(text)
                }
            case "bullets":
                appendListBlock(block, prefix: "-", lines: &lines)
            case "numbered_list":
                appendNumberedBlock(block, lines: &lines)
            case "ai_suggested":
                lines.append("")
                if let text = cleaned(block.text) {
                    lines.append("> \(text)")
                }
                lines.append(contentsOf: block.items.map { "> - \($0)" })
            default:
                if let text = cleaned(block.text) {
                    lines.append("")
                    lines.append(text)
                }
            }
        }

        let text = lines.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    private func appendListBlock(_ block: TimelineAISummaryBlock, prefix: String, lines: inout [String]) {
        lines.append("")
        if let text = cleaned(block.text) {
            lines.append(text)
        }
        lines.append(contentsOf: block.items.map { "\(prefix) \($0)" })
    }

    private func appendNumberedBlock(_ block: TimelineAISummaryBlock, lines: inout [String]) {
        lines.append("")
        if let text = cleaned(block.text) {
            lines.append(text)
        }
        lines.append(contentsOf: block.items.enumerated().map { "\($0.offset + 1). \($0.element)" })
    }

    private func hasDocumentContent(_ summary: TimelineAISummary) -> Bool {
        cleaned(summary.documentTitle) != nil ||
            cleaned(summary.oneLiner) != nil ||
            !summary.documentBlocks.isEmpty
    }

    private func highlightItems(for summary: TimelineAISummary) -> [String] {
        let candidates = summary.keyPoints.isEmpty
            ? summary.documentBlocks.flatMap(\.items)
            : summary.keyPoints
        var result = [String]()
        var seen = Set<String>()

        for candidate in candidates {
            guard let item = cleaned(candidate), !seen.contains(item) else {
                continue
            }

            result.append(item)
            seen.insert(item)

            if result.count == 3 {
                break
            }
        }

        return result
    }

    private func detailGroupTitle(_ group: SummaryDocumentGroup, index: Int) -> String {
        cleaned(group.heading) ?? "\(L10n.t("Details", appLanguage)) \(index + 1)"
    }

    private func detailGroupPreview(_ group: SummaryDocumentGroup) -> String? {
        for block in group.blocks {
            if let text = cleaned(block.text), block.kind == "paragraph" || block.kind == "ai_suggested" {
                return text
            }

            let items = block.items.compactMap(cleaned)
            if !items.isEmpty {
                return items.prefix(2).joined(separator: "；")
            }
        }

        return nil
    }

    private func detailGroupIconName(for group: SummaryDocumentGroup) -> String {
        let title = detailGroupTitle(group, index: 0).lowercased()

        if title.contains("录音") || title.contains("声音") || title.contains("audio") || title.contains("身体") || title.contains("状态") || title.contains("健康") {
            return "waveform"
        }

        if title.contains("经验") || title.contains("收获") || title.contains("复盘") || title.contains("lesson") || title.contains("takeaway") {
            return "star"
        }

        if title.contains("下一次") || title.contains("怎么做") || title.contains("建议") || title.contains("计划") || title.contains("next") {
            return "lightbulb"
        }

        if title.contains("老师") || title.contains("朋友") || title.contains("同学") || title.contains("人") || title.contains("person") {
            return "person"
        }

        if title.contains("吃") || title.contains("娱乐") || title.contains("活动") || title.contains("游戏") {
            return "circle.grid.2x2"
        }

        if title.contains("地点") || title.contains("学校") || title.contains("网吧") || title.contains("外出") || title.contains("place") {
            return "mappin.and.ellipse"
        }

        return "text.alignleft"
    }

    private func documentGroups(from blocks: [TimelineAISummaryBlock]) -> [SummaryDocumentGroup] {
        var groups = [SummaryDocumentGroup]()
        var currentHeading: String?
        var currentLevel = 1
        var currentBlocks = [TimelineAISummaryBlock]()

        func flush() {
            if currentHeading != nil || !currentBlocks.isEmpty {
                groups.append(
                    SummaryDocumentGroup(
                        heading: currentHeading,
                        level: currentLevel,
                        blocks: currentBlocks
                    )
                )
            }
            currentBlocks = []
        }

        for block in blocks {
            if block.kind == "heading" {
                flush()
                currentHeading = block.text
                currentLevel = block.level == 2 ? 2 : 1
            } else {
                currentBlocks.append(block)
            }
        }

        flush()
        return groups
    }

    private func cleaned(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

private struct SummaryDocumentGroup {
    let heading: String?
    let level: Int
    let blocks: [TimelineAISummaryBlock]
}

private enum AISummaryAuxiliarySheet: Identifiable {
    case transcript

    var id: String {
        switch self {
        case .transcript:
            return "transcript"
        }
    }
}

private struct AISummaryTranscriptSheet: View {
    let transcriptText: String?
    let unavailableMessage: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let transcriptText {
                        Text(transcriptText)
                            .font(.body)
                            .lineSpacing(5)
                            .textSelection(.enabled)
                    } else {
                        Text(unavailableMessage)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(L10n.t("Saved privately on this iPhone for search and diagnostics.", appLanguage))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .navigationTitle(L10n.t("Original Text", appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("Done", appLanguage)) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
