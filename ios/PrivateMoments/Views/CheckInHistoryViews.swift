import SwiftUI
import UIKit

struct CheckInHistorySummary: View {
    @Environment(\.appLanguage) private var appLanguage

    let entries: [CheckInFeedEntry]

    var body: some View {
        HStack(spacing: 10) {
            CheckInSummaryPill(title: L10n.t("Week", appLanguage), value: "\(recentCount(days: 7))")
            CheckInSummaryPill(title: L10n.t("Month", appLanguage), value: "\(recentCount(days: 30))")
            CheckInSummaryPill(title: L10n.t("Items", appLanguage), value: "\(Set(entries.map(\.item.id)).count)")
        }
    }

    private func recentCount(days: Int) -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return entries.filter { $0.occurredAt >= cutoff }.count
    }
}

private struct CheckInSummaryPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.headline.weight(.semibold).monospacedDigit())
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .frame(height: 56)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct CheckInHistoryFilterBar: View {
    @Environment(\.appLanguage) private var appLanguage

    let items: [CheckInItem]
    @Binding var selectedItemId: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CheckInHistoryFilterChip(
                    title: L10n.t("All", appLanguage),
                    symbolName: "tray.full",
                    color: .accentColor,
                    isSelected: selectedItemId == nil
                ) {
                    selectedItemId = nil
                }

                ForEach(items) { item in
                    CheckInHistoryFilterChip(
                        title: item.name,
                        symbolName: item.symbolName,
                        color: Color(hex: item.colorHex) ?? .accentColor,
                        isSelected: selectedItemId == item.id
                    ) {
                        selectedItemId = item.id
                    }
                }
            }
            .padding(.vertical, 2)
            .padding(.trailing, 18)
        }
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [
                    Color(.systemBackground).opacity(0),
                    Color(.systemBackground)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 26)
            .allowsHitTesting(false)
        }
    }
}

private struct CheckInHistoryFilterChip: View {
    let title: String
    let symbolName: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            } icon: {
                Image(systemName: symbolName)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isSelected ? color : Color.secondary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(isSelected ? color.opacity(0.16) : Color.secondary.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct CheckInHistoryRow: View {
    let entry: CheckInFeedEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.item.symbolName)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(hex: entry.item.colorHex) ?? .accentColor)
                .frame(width: 30, height: 30)
                .background((Color(hex: entry.item.colorHex) ?? .accentColor).opacity(0.13), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.item.name)
                    .font(.body.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let media = entry.media.first(where: \.isImage) {
                CheckInImageThumbnail(media: media)
                    .frame(width: 44, height: 44)
            } else if let media = entry.media.first(where: \.isAudio) {
                CheckInAudioCompactBadge(media: media)
                    .frame(width: 44, height: 44)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private var subtitle: String {
        let date = DateFormatter.checkInHistory.string(from: entry.occurredAt)
        if entry.entry.hasNote {
            return "\(date) · \(entry.entry.note)"
        }

        return date
    }
}

extension DateFormatter {
    static let checkInTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let checkInHistory: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yMMMd HHmm")
        return formatter
    }()
}
