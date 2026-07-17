import SwiftUI

struct SettingsStatusBadgeModel: Identifiable, Equatable {
    enum Tone {
        case success
        case warning
        case danger
        case neutral
        case accent
    }

    let title: String
    let systemImage: String?
    let tone: Tone

    var id: String {
        "\(title)-\(systemImage ?? "")"
    }
}

struct SettingsStatusBadge: View {
    let model: SettingsStatusBadgeModel

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage = model.systemImage, showsIcon {
                Image(systemName: systemImage)
                    .font(.footnote.weight(.medium))
            }

            Text(model.title)
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(foregroundStyle)
        .accessibilityLabel(model.title)
    }

    private var showsIcon: Bool {
        switch model.tone {
        case .warning, .danger:
            return true
        case .success, .neutral, .accent:
            return false
        }
    }

    private var foregroundStyle: Color {
        switch model.tone {
        case .success:
            return .secondary
        case .warning:
            return .orange
        case .danger:
            return .red
        case .neutral:
            return .secondary
        case .accent:
            return .accentColor
        }
    }
}

struct SettingsHomeIcon: View {
    let systemImage: String
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color.opacity(0.76).gradient)
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
        }
        .frame(width: 29, height: 29)
        .accessibilityHidden(true)
    }
}

struct SettingsHomeRow: View {
    let title: String
    let systemImage: String
    let iconColor: Color
    var badge: SettingsStatusBadgeModel?
    var value: String?

    var body: some View {
        HStack(spacing: 11) {
            SettingsHomeIcon(systemImage: systemImage, color: iconColor)

            Text(title)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.86)

            Spacer(minLength: 8)

            if let badge {
                SettingsStatusBadge(model: badge)
            } else if let value {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
                    .minimumScaleFactor(0.82)
            }
        }
        .frame(minHeight: 30)
        .contentShape(Rectangle())
        .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
    }
}
