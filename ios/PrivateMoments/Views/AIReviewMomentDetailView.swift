import SwiftUI

struct AIReviewMomentDetailView: View {
    @Environment(\.appLanguage) private var appLanguage

    let document: AIReviewMomentDocument
    let sourceLabel: String?

    @State private var collapsedSections = Set<Int>()

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(document.title)
                .font(.largeTitle.weight(.semibold))
                .fontDesign(.rounded)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            metadataSection

            if document.sections.isEmpty {
                Text(document.timelinePreview)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(document.sections.enumerated()), id: \.offset) { index, section in
                        reviewSection(section, index: index)

                        if index < document.sections.count - 1 {
                            Divider()
                                .padding(.vertical, 14)
                        }
                    }
                }
            }

            if !document.keywords.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("Keywords", appLanguage))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(document.keywords.prefix(5).joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private var metadataSection: some View {
        let items = metadataItems
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.t("Details", appLanguage))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(items, id: \.label) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(item.label)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.tertiary)
                                .frame(width: 78, alignment: .leading)

                            Text(item.value)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private var metadataItems: [(label: String, value: String)] {
        var items: [(String, String)] = []

        if let metadataSummary = document.metadataSummary, !metadataSummary.isEmpty {
            items.append((L10n.t("Summary", appLanguage), metadataSummary))
        }

        if let rangeText = document.rangeText, !rangeText.isEmpty {
            items.append((L10n.t("Range", appLanguage), rangeText))
        }

        if let sourceLabel, !sourceLabel.isEmpty {
            items.append((L10n.t("Source", appLanguage), sourceLabel))
        }

        return items
    }

    private func reviewSection(_ section: AIReviewMomentDocument.Section, index: Int) -> some View {
        let isCollapsed = collapsedSections.contains(index)

        return VStack(alignment: .leading, spacing: 11) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    if isCollapsed {
                        collapsedSections.remove(index)
                    } else {
                        collapsedSections.insert(index)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(L10n.t(section.title, appLanguage))
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)

                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(section.title)

            if !isCollapsed {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.body)
                            .foregroundStyle(.primary.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}
