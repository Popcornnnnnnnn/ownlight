import SwiftUI

struct AIExternalProcessingConsentView: View {
    @Environment(\.appLanguage) private var appLanguage
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "hand.raised")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)

                        Text(L10n.t("Before AI runs, Ownlight needs your permission to send private content to the provider or endpoint you configure.", appLanguage))
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    AIExternalProcessingConsentRow(
                        title: L10n.t("What may be sent", appLanguage),
                        detail: L10n.t("Moment text, local transcripts, review context, topic names, and audio when you use an external transcription endpoint.", appLanguage),
                        systemImage: "doc.text"
                    )
                    AIExternalProcessingConsentRow(
                        title: L10n.t("Where it goes", appLanguage),
                        detail: L10n.t("Only to the AI or transcription provider you configure. Provider privacy and retention follow that provider.", appLanguage),
                        systemImage: "network"
                    )
                    AIExternalProcessingConsentRow(
                        title: L10n.t("What stays here", appLanguage),
                        detail: L10n.t("API keys stay in this iPhone Keychain. Core recording works without AI. You can reset this permission later in Settings.", appLanguage),
                        systemImage: "key"
                    )
                }

                Section {
                    Button {
                        onAccept()
                    } label: {
                        Label(L10n.t("Allow AI Processing", appLanguage), systemImage: "checkmark.shield")
                            .fontWeight(.semibold)
                    }

                    Button(role: .cancel) {
                        onDecline()
                    } label: {
                        Text(L10n.t("Not Now", appLanguage))
                    }
                }
            }
            .navigationTitle(L10n.t("AI Privacy Permission", appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("Not Now", appLanguage), role: .cancel) {
                        onDecline()
                    }
                }
            }
        }
    }
}

private struct AIExternalProcessingConsentRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
    }
}
