import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.appLanguage) private var appLanguage
    @State private var iCloudSyncEnabled = AppSettings.iCloudSyncEnabled

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t("Data Storage", appLanguage)) {
                    SettingsHomeRow(
                        title: L10n.t("This iPhone", appLanguage),
                        systemImage: "iphone",
                        iconColor: .blue,
                        badge: SettingsStatusBadgeModel(
                            title: L10n.t("Local", appLanguage),
                            systemImage: "iphone",
                            tone: .success
                        )
                    )

                    NavigationLink {
                        DataICloudSettingsView()
                    } label: {
                        SettingsHomeRow(
                            title: L10n.t("iCloud", appLanguage),
                            systemImage: "icloud",
                            iconColor: .blue,
                            badge: iCloudSyncStatusBadge
                        )
                    }

                    NavigationLink {
                        StorageExportSettingsView()
                    } label: {
                        SettingsHomeRow(
                            title: L10n.t("Storage & Export", appLanguage),
                            systemImage: "internaldrive",
                            iconColor: .gray
                        )
                    }
                }
                .settingsHomeSectionRows()

                Section(L10n.t("AI & Analysis", appLanguage)) {
                    NavigationLink {
                        AIAnalysisSettingsView()
                    } label: {
                        SettingsHomeRow(
                            title: L10n.t("AI & Analysis", appLanguage),
                            systemImage: "sparkles",
                            iconColor: .purple,
                            badge: aiAnalysisStatusBadge
                        )
                    }
                }
                .settingsHomeSectionRows()

                Section(L10n.t("Organization", appLanguage)) {
                    NavigationLink {
                        TagManagementView()
                    } label: {
                        SettingsHomeRow(
                            title: L10n.t("Tags", appLanguage),
                            systemImage: "tag",
                            iconColor: .green
                        )
                    }
                }
                .settingsHomeSectionRows()

                Section(L10n.t("App Preferences", appLanguage)) {
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        SettingsHomeRow(
                            title: L10n.t("Appearance", appLanguage),
                            systemImage: "paintbrush",
                            iconColor: .pink,
                            value: appearanceSummary
                        )
                    }

                    NavigationLink {
                        LanguageSettingsView()
                    } label: {
                        SettingsHomeRow(
                            title: L10n.t("Language", appLanguage),
                            systemImage: "globe",
                            iconColor: .blue,
                            value: languageSummary
                        )
                    }

                    NavigationLink {
                        DisplaySettingsView()
                    } label: {
                        SettingsHomeRow(
                            title: L10n.t("Display", appLanguage),
                            systemImage: "textformat.size",
                            iconColor: .indigo
                        )
                    }
                }
                .settingsHomeSectionRows()

                Section {
                    if let privacyPolicyURL = supportLinks.privacyPolicyURL {
                        Link(destination: privacyPolicyURL) {
                            SettingsHomeRow(
                                title: L10n.t("Privacy Policy", appLanguage),
                                systemImage: "hand.raised",
                                iconColor: .teal
                            )
                        }
                    } else {
                        SettingsHomeRow(
                            title: L10n.t("Privacy Policy", appLanguage),
                            systemImage: "hand.raised",
                            iconColor: .teal,
                            value: L10n.t("Not configured", appLanguage)
                        )
                    }

                    if let supportURL = supportLinks.supportURL {
                        Link(destination: supportURL) {
                            SettingsHomeRow(
                                title: L10n.t("Support", appLanguage),
                                systemImage: "questionmark.circle",
                                iconColor: .orange
                            )
                        }
                    } else {
                        SettingsHomeRow(
                            title: L10n.t("Support", appLanguage),
                            systemImage: "questionmark.circle",
                            iconColor: .orange,
                            value: L10n.t("Not configured", appLanguage)
                        )
                    }
                } header: {
                    Text(L10n.t("Privacy & Support", appLanguage))
                } footer: {
                    Text(L10n.t("Privacy and support pages open in your browser.", appLanguage))
                }
                .settingsHomeSectionRows()
            }
            .navigationTitle(L10n.t("Settings", appLanguage))
            .listSectionSpacing(.compact)
            .onAppear {
                iCloudSyncEnabled = AppSettings.iCloudSyncEnabled
            }
            .alert(L10n.t("Error", appLanguage), isPresented: errorBinding) {
                Button(L10n.t("OK", appLanguage), role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }

    private var iCloudSyncStatusBadge: SettingsStatusBadgeModel {
        if iCloudSyncEnabled {
            return SettingsStatusBadgeModel(
                title: L10n.t("On", appLanguage),
                systemImage: "checkmark",
                tone: .success
            )
        }

        return SettingsStatusBadgeModel(
            title: L10n.t("Off", appLanguage),
            systemImage: "pause",
            tone: .neutral
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { _ in store.clearError() }
        )
    }

    private var appearanceSummary: String {
        L10n.t(store.appAppearanceMode.title, appLanguage)
    }

    private var languageSummary: String {
        store.appLanguageMode.title(language: appLanguage)
    }

    private var aiAnalysisStatusBadge: SettingsStatusBadgeModel {
        guard store.aiAnalysisEnabled else {
            return SettingsStatusBadgeModel(
                title: L10n.t("Off", appLanguage),
                systemImage: "pause",
                tone: .neutral
            )
        }

        if AIProviderRouter.selectProfile(
            profiles: store.aiProviderProfiles,
            fallbackState: store.aiProviderFallbackState
        ) != nil {
            return SettingsStatusBadgeModel(
                title: L10n.t("Ready", appLanguage),
                systemImage: "checkmark",
                tone: .success
            )
        }

        return SettingsStatusBadgeModel(
            title: L10n.t("Needs setup", appLanguage),
            systemImage: "exclamationmark.triangle",
            tone: .warning
        )
    }

    private var supportLinks: AppStoreSupportLinks {
        AppStoreSupportLinks(language: appLanguage)
    }
}

private extension View {
    func settingsHomeSectionRows() -> some View {
        listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
    }
}

private struct AppearanceSettingsView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.appLanguage) private var appLanguage

    var body: some View {
        Form {
            Section(L10n.t("Appearance", appLanguage)) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Button {
                        store.setAppAppearanceMode(mode)
                    } label: {
                        AppearanceModeRow(
                            mode: mode,
                            isSelected: store.appAppearanceMode == mode
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(store.appAppearanceMode == mode ? .isSelected : [])
                }
            }

            Section(L10n.t("Markdown", appLanguage)) {
                NavigationLink {
                    MarkdownSettingsView()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t("Markdown Rendering", appLanguage))
                        Text(L10n.t("Syntax support without extra editor buttons", appLanguage))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .navigationTitle(L10n.t("Appearance", appLanguage))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MarkdownSettingsView: View {
    @Environment(\.appLanguage) private var appLanguage

    var body: some View {
        Form {
            Section {
                LabeledContent(
                    L10n.t("Default Rendering", appLanguage),
                    value: L10n.t("System Markdown", appLanguage)
                )

                NavigationLink(L10n.t("Advanced Rendering", appLanguage)) {
                    AdvancedMarkdownRenderingSettingsView()
                }
            } footer: {
                Text(L10n.t("Markdown syntax stays optional. The composer remains a plain source editor with compact heading controls only.", appLanguage))
            }
        }
        .navigationTitle(L10n.t("Markdown", appLanguage))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AdvancedMarkdownRenderingSettingsView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.appLanguage) private var appLanguage
    @State private var pendingOption: AdvancedMarkdownOption?

    var body: some View {
        Form {
            Section {
                advancedToggle(
                    option: .math,
                    isOn: Binding(
                        get: { store.markdownMathRenderingEnabled },
                        set: { set(option: .math, enabled: $0) }
                    )
                )
                advancedToggle(
                    option: .remoteImages,
                    isOn: Binding(
                        get: { store.markdownRemoteImagesEnabled },
                        set: { set(option: .remoteImages, enabled: $0) }
                    )
                )
                advancedToggle(
                    option: .rawHTML,
                    isOn: Binding(
                        get: { store.markdownRawHTMLRenderingEnabled },
                        set: { set(option: .rawHTML, enabled: $0) }
                    )
                )
            } footer: {
                Text(L10n.t("These options are for specialized notes. Leave them off for normal private timeline use.", appLanguage))
            }
        }
        .navigationTitle(L10n.t("Advanced Rendering", appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            pendingOption?.title(language: appLanguage) ?? "",
            isPresented: Binding(
                get: { pendingOption != nil },
                set: { if !$0 { pendingOption = nil } }
            )
        ) {
            Button(L10n.t("Enable", appLanguage)) {
                guard let pendingOption else {
                    return
                }

                apply(option: pendingOption, enabled: true)
                self.pendingOption = nil
            }
            Button(L10n.t("Keep Off", appLanguage), role: .cancel) {
                pendingOption = nil
            }
        } message: {
            Text(pendingOption?.warning(language: appLanguage) ?? "")
        }
    }

    private func advancedToggle(option: AdvancedMarkdownOption, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(option.title(language: appLanguage))
                Text(option.subtitle(language: appLanguage))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func set(option: AdvancedMarkdownOption, enabled: Bool) {
        if enabled {
            pendingOption = option
        } else {
            apply(option: option, enabled: false)
        }
    }

    private func apply(option: AdvancedMarkdownOption, enabled: Bool) {
        switch option {
        case .math:
            store.setMarkdownMathRenderingEnabled(enabled)
        case .remoteImages:
            store.setMarkdownRemoteImagesEnabled(enabled)
        case .rawHTML:
            store.setMarkdownRawHTMLRenderingEnabled(enabled)
        }
    }
}

private enum AdvancedMarkdownOption: String, Identifiable {
    case math
    case remoteImages
    case rawHTML

    var id: String {
        rawValue
    }

    func title(language: AppResolvedLanguage) -> String {
        switch self {
        case .math:
            return L10n.t("Math Formulas", language)
        case .remoteImages:
            return L10n.t("Remote Images", language)
        case .rawHTML:
            return L10n.t("Raw HTML", language)
        }
    }

    func subtitle(language: AppResolvedLanguage) -> String {
        switch self {
        case .math:
            return L10n.t("Allow dollar-sign formula syntax", language)
        case .remoteImages:
            return L10n.t("Allow Markdown image URLs to render inline", language)
        case .rawHTML:
            return L10n.t("Allow HTML-shaped Markdown source", language)
        }
    }

    func warning(language: AppResolvedLanguage) -> String {
        switch self {
        case .math:
            return L10n.t("Math formulas are useful for rare technical notes and can make long Markdown rendering heavier.", language)
        case .remoteImages:
            return L10n.t("Remote images can reveal when a private moment is viewed by requesting external URLs.", language)
        case .rawHTML:
            return L10n.t("Raw HTML is only for trusted source you wrote yourself. Script-like HTML remains unsafe for private notes.", language)
        }
    }
}

private struct LanguageSettingsView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.appLanguage) private var appLanguage

    var body: some View {
        Form {
            Section(L10n.t("Language", appLanguage)) {
                ForEach(AppLanguageMode.allCases) { mode in
                    Button {
                        store.setAppLanguageMode(mode)
                    } label: {
                        LanguageModeRow(
                            mode: mode,
                            isSelected: store.appLanguageMode == mode
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(store.appLanguageMode == mode ? .isSelected : [])
                }
            }

        }
        .navigationTitle(L10n.t("Language", appLanguage))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DisplaySettingsView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.appLanguage) private var appLanguage

    var body: some View {
        Form {
            Section {
                Toggle(
                    L10n.t("Show Tags in Timeline", appLanguage),
                    isOn: Binding(
                        get: { store.showTagsInTimeline },
                        set: { store.setShowTagsInTimeline($0) }
                    )
                )

                Toggle(
                    L10n.t("Show Memories in Timeline", appLanguage),
                    isOn: Binding(
                        get: { store.memoryLinksEnabled },
                        set: { store.setMemoryLinksEnabled($0) }
                    )
                )
                    .accessibilityIdentifier("settings.display.memoryLinksToggle")
            } header: {
                Text(L10n.t("Timeline", appLanguage))
            } footer: {
                Text(L10n.t("Display preferences only change what is shown. Tags, memories, and generated summaries remain stored locally.", appLanguage))
            }

            Section(L10n.t("Check-ins", appLanguage)) {
                Toggle(
                    L10n.t("Show Check-in Summaries", appLanguage),
                    isOn: Binding(
                        get: { store.showCheckInSummaries },
                        set: { store.setShowCheckInSummaries($0) }
                    )
                )
            }
        }
        .navigationTitle(L10n.t("Display", appLanguage))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AppearanceModeRow: View {
    @Environment(\.appLanguage) private var appLanguage

    let mode: AppAppearanceMode
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: mode.systemImageName)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(L10n.t(mode.title, appLanguage))
                .foregroundStyle(.primary)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

private struct LanguageModeRow: View {
    @Environment(\.appLanguage) private var appLanguage

    let mode: AppLanguageMode
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: mode.systemImageName)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(mode.title(language: appLanguage))
                .foregroundStyle(.primary)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

struct AILanguageModeRow: View {
    @Environment(\.appLanguage) private var appLanguage

    let mode: AILanguageMode
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: mode == .auto ? "wand.and.stars" : "textformat")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(mode.title(language: appLanguage))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 12)

            Text(mode.subtitle(language: appLanguage))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .truncationMode(.tail)
                .multilineTextAlignment(.trailing)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

private extension AppAppearanceMode {
    var systemImageName: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max"
        case .dark:
            return "moon"
        }
    }
}
