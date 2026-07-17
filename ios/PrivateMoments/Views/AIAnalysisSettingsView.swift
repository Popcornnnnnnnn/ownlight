import SwiftUI

struct AIAnalysisSettingsView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.editMode) private var editMode
    @State private var infoTopic: AIAnalysisInfoTopic?

    private var sortedProfiles: [AIProviderProfile] {
        store.aiProviderProfiles.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.displayName < rhs.displayName
            }

            return lhs.sortOrder < rhs.sortOrder
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle(
                    L10n.t("Enable AI Analysis", appLanguage),
                    isOn: Binding(
                        get: { store.aiAnalysisEnabled },
                        set: { store.setAIAnalysisEnabled($0) }
                    )
                )

                HStack(spacing: 12) {
                    LabeledContent(L10n.t("Status", appLanguage)) {
                        SettingsStatusBadge(model: aiStatusBadge)
                    }

                    infoButton(.overview)
                }
            } header: {
                Text(L10n.t("AI & Analysis", appLanguage))
            }

            Section {
                LabeledContent(L10n.t("External AI Permission", appLanguage)) {
                    SettingsStatusBadge(model: aiPermissionBadge)
                }

                if store.aiExternalProcessingConsentAccepted {
                    Button(role: .destructive) {
                        store.resetAIExternalProcessingConsent()
                    } label: {
                        Text(L10n.t("Reset AI Permission", appLanguage))
                    }
                } else {
                    Button {
                        store.presentAIExternalProcessingConsent()
                    } label: {
                        Label(L10n.t("Review AI Permission", appLanguage), systemImage: "hand.raised")
                    }
                }
            } header: {
                Text(L10n.t("Privacy Permission", appLanguage))
            } footer: {
                Text(L10n.t("Ownlight asks before sending private content to the provider you configure.", appLanguage))
            }

            Section {
                ForEach(AILanguageMode.allCases) { mode in
                    Button {
                        store.setAILanguageMode(mode)
                    } label: {
                        AILanguageModeRow(
                            mode: mode,
                            isSelected: store.aiLanguageMode == mode
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(store.aiLanguageMode == mode ? .isSelected : [])
                }
            } header: {
                Text(L10n.t("AI Language", appLanguage))
            } footer: {
                Text(L10n.t("AI Language affects new summaries and reviews. App language stays separate.", appLanguage))
            }

            Section {
                if sortedProfiles.isEmpty {
                    LabeledContent(L10n.t("Status", appLanguage), value: L10n.t("Not configured", appLanguage))
                } else {
                    ForEach(sortedProfiles) { profile in
                        NavigationLink {
                            AIProviderProfileEditorView(existingProfile: profile)
                        } label: {
                            AIProviderProfileRow(profile: profile)
                        }
                    }
                    .onMove { source, destination in
                        store.moveAIProviderProfiles(from: source, to: destination)
                    }
                    .onDelete { offsets in
                        for offset in offsets {
                            guard sortedProfiles.indices.contains(offset) else {
                                continue
                            }
                            store.deleteAIProviderProfile(id: sortedProfiles[offset].id)
                        }
                    }
                }

                Menu {
                    ForEach(AIProviderPreset.defaultTextAnalysisPresets) { preset in
                        NavigationLink(preset.displayName) {
                            AIProviderProfileEditorView(preset: preset)
                        }
                    }
                } label: {
                    Label(L10n.t("Add Provider", appLanguage), systemImage: "plus")
                }
            } header: {
                Text(L10n.t("Text Analysis Provider", appLanguage))
            }

            Section {
                Toggle(
                    L10n.t("AI Title Auto-Insert", appLanguage),
                    isOn: Binding(
                        get: { store.aiTitleAutoInsertEnabled },
                        set: { store.setAITitleAutoInsertEnabled($0) }
                    )
                )

                Toggle(
                    L10n.t("Auto-generate Weekly Review", appLanguage),
                    isOn: Binding(
                        get: { store.autoWeeklyReviewEnabled },
                        set: { store.setAutoWeeklyReviewEnabled($0) }
                    )
                )

                Toggle(
                    L10n.t("Publish Weekly Review", appLanguage),
                    isOn: Binding(
                        get: { store.publishWeeklyReviewToMoments },
                        set: { store.setPublishWeeklyReviewToMoments($0) }
                    )
                )
                .disabled(!store.autoWeeklyReviewEnabled)
            } header: {
                Text(L10n.t("Generated Artifacts", appLanguage))
            } footer: {
                Text(L10n.t("Weekly Review uses AI to summarize recent moments into a private recap. Publish Weekly Review inserts each automatically generated review into your Timeline as a Moment.", appLanguage))

                if !store.aiAnalysisEnabled {
                    Text(L10n.t("Generated artifact settings take effect when AI Analysis is enabled.", appLanguage))
                }
            }
            .disabled(!store.aiAnalysisEnabled)

            Section {
                Menu {
                    ForEach(TranscriptionProviderMode.allCases) { mode in
                        Button {
                            store.setTranscriptionProviderMode(mode)
                        } label: {
                            HStack {
                                Text(L10n.t(mode.titleKey, appLanguage))
                                if store.transcriptionProviderMode.normalizedForSettingsUI == mode.normalizedForSettingsUI {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(L10n.t("Transcription Provider", appLanguage))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)

                        Spacer(minLength: 8)

                        Text(L10n.t(store.transcriptionProviderMode.normalizedForSettingsUI.compactTitleKey, appLanguage))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.86)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.trailing)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)

                if store.transcriptionProviderMode.isExternalProvider {
                    NavigationLink {
                        TranscriptionProviderSettingsView(mode: store.transcriptionProviderMode.normalizedForSettingsUI)
                    } label: {
                        Label(
                            L10n.t(store.transcriptionProviderMode.normalizedForSettingsUI.titleKey, appLanguage),
                            systemImage: store.transcriptionProviderMode.normalizedForSettingsUI.systemImage
                        )
                    }
                }
            } header: {
                Text(L10n.t("Advanced Transcription", appLanguage))
            }
        }
        .navigationTitle(L10n.t("AI & Analysis", appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $infoTopic) { topic in
            Alert(
                title: Text(topic.title(language: appLanguage)),
                message: Text(topic.message(language: appLanguage)),
                dismissButton: .default(Text(L10n.t("OK", appLanguage)))
            )
        }
        .sheet(item: $store.aiExternalProcessingConsentRequest) { _ in
            AIExternalProcessingConsentView(
                onAccept: { store.acceptAIExternalProcessingConsent() },
                onDecline: { store.declineAIExternalProcessingConsent() }
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                TopActionButton(
                    title: L10n.t(isEditingProviders ? "Done" : "Edit", appLanguage),
                    systemImage: isEditingProviders ? "checkmark" : "pencil",
                    accessibilityIdentifier: "aiAnalysis.editProvidersButton",
                    action: toggleProviderEditing
                )
                .disabled(sortedProfiles.isEmpty)
            }
        }
    }

    private var aiPermissionBadge: SettingsStatusBadgeModel {
        if store.aiExternalProcessingConsentAccepted {
            return SettingsStatusBadgeModel(
                title: L10n.t("Accepted", appLanguage),
                systemImage: "checkmark",
                tone: .success
            )
        }

        return SettingsStatusBadgeModel(
            title: L10n.t("Not accepted", appLanguage),
            systemImage: "exclamationmark.triangle",
            tone: .warning
        )
    }

    private var isEditingProviders: Bool {
        editMode?.wrappedValue.isEditing == true
    }

    private func toggleProviderEditing() {
        withAnimation(.snappy(duration: 0.2)) {
            editMode?.wrappedValue = isEditingProviders ? .inactive : .active
        }
    }

    private var aiStatusBadge: SettingsStatusBadgeModel {
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

    private func infoButton(_ topic: AIAnalysisInfoTopic) -> some View {
        Button {
            infoTopic = topic
        } label: {
            Image(systemName: "info.circle")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(topic.title(language: appLanguage)) \(L10n.t("Details", appLanguage))")
    }

}

private enum AIAnalysisInfoTopic: Identifiable {
    case overview

    var id: String {
        switch self {
        case .overview:
            return "overview"
        }
    }

    func title(language: AppResolvedLanguage) -> String {
        switch self {
        case .overview:
            return L10n.t("AI & Analysis", language)
        }
    }

    func message(language: AppResolvedLanguage) -> String {
        switch self {
        case .overview:
            return L10n.t("AI runs on this iPhone using the providers you configure. Credentials stay in this device Keychain. Audio failures can come from transcription before the text provider is called.", language)
        }
    }
}

private struct TranscriptionProviderSettingsView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.appLanguage) private var appLanguage

    let mode: TranscriptionProviderMode

    @State private var settings = AppSettings.localTranscriptionGatewaySettings
    @State private var apiKey = ""
    @State private var isTestingConnection = false
    @State private var testResult: TranscriptionProviderConnectionTestResult?
    @State private var infoTopic: TranscriptionSettingsInfoTopic?

    var body: some View {
        Form {
            Section(L10n.t("Profile", appLanguage)) {
                LabeledContent(
                    L10n.t("Provider", appLanguage),
                    value: L10n.t(mode.titleKey, appLanguage)
                )
                LabeledContent(
                    L10n.t("Format", appLanguage),
                    value: L10n.t("OpenAI-compatible transcription", appLanguage)
                )
            }

            Section {
                TextField(L10n.t("Base URL", appLanguage), text: $settings.urlString)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                SecureField(L10n.t("API Key", appLanguage), text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .textContentType(.password)
                TextField(L10n.t("Model", appLanguage), text: $settings.model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                HStack(spacing: 12) {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            if isTestingConnection {
                                ProgressView()
                            } else {
                                Image(systemName: "checkmark.circle")
                            }
                            Text(L10n.t(isTestingConnection ? "Testing Connection" : "Test Connection", appLanguage))
                        }
                    }
                    .disabled(isTestingConnection || settings.normalizedURLString.isEmpty || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer(minLength: 12)

                    infoButton(.testConnection)
                }

                if let testResult {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(testResult.title(language: appLanguage))
                                .font(.footnote.weight(.semibold))
                            Text(testResult.detail(language: appLanguage))
                                .font(.footnote)
                        }
                    } icon: {
                        Image(systemName: testResult.systemImage)
                    }
                    .foregroundStyle(testResult.tint)
                }
            } header: {
                Text(L10n.t("Connection", appLanguage))
            }

            Section {
                HStack(spacing: 12) {
                    Button(L10n.t("Save", appLanguage)) {
                        save()
                    }
                    .disabled(settings.normalizedURLString.isEmpty)

                    Spacer(minLength: 12)

                    infoButton(.credentials)
                }
            }
        }
        .navigationTitle(L10n.t("Transcription Provider", appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $infoTopic) { topic in
            Alert(
                title: Text(topic.title(language: appLanguage)),
                message: Text(topic.message(language: appLanguage)),
                dismissButton: .default(Text(L10n.t("OK", appLanguage)))
            )
        }
        .task {
            settings = store.localTranscriptionGatewaySettings
            apiKey = (try? KeychainStore.transcriptionProviderAPIKey()) ?? ""
        }
    }

    private func save() {
        do {
            try TranscriptionProviderConnectionWorkflow().save(settings: settings, apiKey: apiKey)
            store.setLocalTranscriptionGatewaySettings(AppSettings.localTranscriptionGatewaySettings)
            testResult = .saved
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func testConnection() {
        guard !isTestingConnection else {
            return
        }

        isTestingConnection = true
        testResult = nil
        let settings = settings
        let apiKey = apiKey
        Task {
            do {
                let info = try await TranscriptionProviderConnectionWorkflow().testAndSave(
                    mode: mode,
                    settings: settings,
                    apiKey: apiKey
                )
                store.setLocalTranscriptionGatewaySettings(AppSettings.localTranscriptionGatewaySettings)
                testResult = .success(model: info.model ?? settings.normalizedModel)
            } catch let error as LocalTranscriptionGatewayError {
                testResult = .failure(error.localizedDescription)
            } catch {
                testResult = .failure(error.localizedDescription)
            }
            isTestingConnection = false
        }
    }

    private func infoButton(_ topic: TranscriptionSettingsInfoTopic) -> some View {
        Button {
            infoTopic = topic
        } label: {
            Image(systemName: "info.circle")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(topic.title(language: appLanguage)) \(L10n.t("Details", appLanguage))")
    }
}

private enum TranscriptionSettingsInfoTopic: Identifiable {
    case testConnection
    case credentials

    var id: String {
        switch self {
        case .testConnection:
            return "testConnection"
        case .credentials:
            return "credentials"
        }
    }

    func title(language: AppResolvedLanguage) -> String {
        switch self {
        case .testConnection:
            return L10n.t("Test Connection", language)
        case .credentials:
            return L10n.t("API Key", language)
        }
    }

    func message(language: AppResolvedLanguage) -> String {
        switch self {
        case .testConnection:
            return L10n.t("Test Connection calls /v1/models. It does not upload audio.", language)
        case .credentials:
            return L10n.t("The API key stays in this iPhone Keychain. Base URL and model stay in local settings only.", language)
        }
    }
}

private enum TranscriptionProviderConnectionTestResult: Equatable {
    case success(model: String)
    case saved
    case failure(String)

    var systemImage: String {
        switch self {
        case .success, .saved:
            return "checkmark.circle.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .success, .saved:
            return .green
        case .failure:
            return .orange
        }
    }

    func title(language: AppResolvedLanguage) -> String {
        switch self {
        case .success:
            return L10n.t("Connection works", language)
        case .saved:
            return L10n.t("Saved", language)
        case .failure:
            return L10n.t("Connection failed", language)
        }
    }

    func detail(language: AppResolvedLanguage) -> String {
        switch self {
        case .success(let model):
            return "\(L10n.t("Provider responded with model", language)) \(model). \(L10n.t("Saved to this iPhone Keychain.", language))"
        case .saved:
            return L10n.t("Transcription provider settings were saved on this iPhone.", language)
        case .failure(let message):
            return message
        }
    }
}

private extension TranscriptionProviderMode {
    var compactTitleKey: String {
        switch normalizedForSettingsUI {
        case .iPhoneOnDevice:
            return "On-device"
        case .localGateway, .customOpenAICompatible:
            return "Endpoint"
        }
    }
}

private struct AIProviderProfileRow: View {
    @Environment(\.appLanguage) private var appLanguage

    let profile: AIProviderProfile

    var body: some View {
        HStack(spacing: 12) {
            Text(profile.displayName)
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            SettingsStatusBadge(model: badge)
        }
        .frame(minHeight: 30)
        .accessibilityElement(children: .combine)
    }

    private var badge: SettingsStatusBadgeModel {
        if profile.isEnabled && profile.isConfiguredForRequests {
            return SettingsStatusBadgeModel(
                title: L10n.t("Enabled", appLanguage),
                systemImage: "checkmark",
                tone: .success
            )
        }

        if profile.isEnabled {
            return SettingsStatusBadgeModel(
                title: L10n.t("Needs setup", appLanguage),
                systemImage: "exclamationmark.triangle",
                tone: .warning
            )
        }

        return SettingsStatusBadgeModel(
            title: L10n.t("Off", appLanguage),
            systemImage: "pause",
            tone: .neutral
        )
    }
}

private struct AIProviderProfileEditorView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss

    @State private var profile: AIProviderProfile
    @State private var apiKey = ""
    @State private var testResult: ProviderConnectionTestResult?
    @State private var isTestingConnection = false
    @State private var showsDeleteConfirmation = false
    private let isNewProfile: Bool

    init(existingProfile: AIProviderProfile) {
        _profile = State(initialValue: existingProfile)
        isNewProfile = false
    }

    init(preset: AIProviderPreset) {
        _profile = State(initialValue: AIProviderProfile(
            id: UUID().uuidString,
            kind: preset.kind,
            displayName: preset.displayName,
            baseURLString: preset.defaultBaseURLString,
            model: preset.defaultModel,
            isEnabled: true,
            sortOrder: Int.max
        ))
        isNewProfile = true
    }

    var body: some View {
        Form {
            Section(L10n.t("Profile", appLanguage)) {
                Toggle(L10n.t("Enabled", appLanguage), isOn: $profile.isEnabled)
                TextField(L10n.t("Name", appLanguage), text: $profile.displayName)
                LabeledContent(L10n.t("Provider", appLanguage), value: profile.preset.displayName)
            }

            Section(L10n.t("Connection", appLanguage)) {
                TextField(L10n.t("Base URL", appLanguage), text: $profile.baseURLString)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                TextField(L10n.t("Model", appLanguage), text: $profile.model)
                    .textInputAutocapitalization(.never)
                SecureField(L10n.t("API Key", appLanguage), text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .textContentType(.password)

                Button {
                    testConnection()
                } label: {
                    HStack {
                        if isTestingConnection {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark.circle")
                        }
                        Text(L10n.t(isTestingConnection ? "Testing Connection" : "Test Connection", appLanguage))
                    }
                }
                .disabled(!canSave || isTestingConnection)

                if let testResult {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(testResult.title(language: appLanguage))
                                .font(.footnote.weight(.semibold))
                            Text(testResult.detail(language: appLanguage))
                                .font(.footnote)
                        }
                    } icon: {
                        Image(systemName: testResult.systemImage)
                    }
                    .foregroundStyle(testResult.tint)
                }
            }

            Section(L10n.t("Capabilities", appLanguage)) {
                LabeledContent(
                    L10n.t("Text analysis", appLanguage),
                    value: L10n.t("Supported", appLanguage)
                )
                LabeledContent(
                    L10n.t("Audio input", appLanguage),
                    value: profile.preset.supportsAudioInput ? L10n.t("Supported", appLanguage) : L10n.t("Not supported", appLanguage)
                )
                LabeledContent(
                    L10n.t("Transcription", appLanguage),
                    value: profile.preset.supportsSpeechTranscription ? L10n.t("Supported", appLanguage) : L10n.t("Advanced only", appLanguage)
                )
            }

            if !isNewProfile {
                Section {
                    Button(L10n.t("Delete Provider", appLanguage), role: .destructive) {
                        showsDeleteConfirmation = true
                    }
                }
            }
        }
        .navigationTitle(profile.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L10n.t("Save", appLanguage)) {
                    save()
                }
                .disabled(!canSave)
            }
        }
        .task {
            apiKey = (try? KeychainStore.aiProviderAPIKey(profileId: profile.id)) ?? ""
        }
        .alert(L10n.t("Delete Provider?", appLanguage), isPresented: $showsDeleteConfirmation) {
            Button(L10n.t("Delete", appLanguage), role: .destructive) {
                store.deleteAIProviderProfile(id: profile.id)
                dismiss()
            }
            Button(L10n.t("Cancel", appLanguage), role: .cancel) {}
        } message: {
            Text(L10n.t("This removes the provider profile and clears its API key from this iPhone Keychain.", appLanguage))
        }
    }

    private var canSave: Bool {
        !profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !profile.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !profile.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        do {
            if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try KeychainStore.clearAIProviderAPIKey(profileId: profile.id)
            } else {
                try KeychainStore.saveAIProviderAPIKey(apiKey, profileId: profile.id)
            }
            store.saveAIProviderProfile(profile)
            dismiss()
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func testConnection() {
        guard !isTestingConnection else {
            return
        }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            testResult = .failure(.missingKey)
            return
        }

        isTestingConnection = true
        testResult = nil
        let profile = profile
        Task {
            do {
                try await AITextAnalysisClient().testConnection(profile: profile, apiKey: trimmedKey)
                store.clearAIProviderFailureState(profileId: profile.id)
                testResult = .success
            } catch let error as AITextAnalysisError {
                testResult = .failure(ProviderConnectionFailure(error: error))
            } catch {
                testResult = .failure(.network)
            }
            isTestingConnection = false
        }
    }
}

private enum ProviderConnectionTestResult: Equatable {
    case success
    case failure(ProviderConnectionFailure)

    var systemImage: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .success:
            return .green
        case .failure:
            return .orange
        }
    }

    func title(language: AppResolvedLanguage) -> String {
        switch self {
        case .success:
            return L10n.t("Connection works", language)
        case .failure(let failure):
            return failure.title(language: language)
        }
    }

    func detail(language: AppResolvedLanguage) -> String {
        switch self {
        case .success:
            return L10n.t("The provider accepted a small text analysis request. Save this profile to use it.", language)
        case .failure(let failure):
            return failure.detail(language: language)
        }
    }
}

private enum ProviderConnectionFailure: Equatable {
    case missingKey
    case invalidURL
    case invalidKey
    case modelNotFound
    case rateLimited
    case unavailable
    case invalidResponse
    case network
    case other(String)

    init(error: AITextAnalysisError) {
        switch error {
        case .invalidProviderURL:
            self = .invalidURL
        case .externalProcessingConsentRequired:
            self = .other(error.localizedDescription)
        case .missingAPIKey:
            self = .missingKey
        case .unsupportedResponse:
            self = .invalidResponse
        case .noConfiguredProvider:
            self = .other(error.localizedDescription)
        case .provider(let statusCode, let message):
            if statusCode == 401 || statusCode == 403 {
                self = .invalidKey
            } else if statusCode == 404 {
                self = .modelNotFound
            } else if statusCode == 429 {
                self = .rateLimited
            } else if statusCode >= 500 {
                self = .unavailable
            } else {
                self = .other(message)
            }
        }
    }

    func title(language: AppResolvedLanguage) -> String {
        switch self {
        case .missingKey:
            return L10n.t("API key is missing", language)
        case .invalidURL:
            return L10n.t("Base URL is invalid", language)
        case .invalidKey:
            return L10n.t("Invalid API key", language)
        case .modelNotFound:
            return L10n.t("Model not found", language)
        case .rateLimited:
            return L10n.t("Rate limited", language)
        case .unavailable:
            return L10n.t("Provider unavailable", language)
        case .invalidResponse:
            return L10n.t("Invalid response", language)
        case .network:
            return L10n.t("Network failed", language)
        case .other:
            return L10n.t("Connection failed", language)
        }
    }

    func detail(language: AppResolvedLanguage) -> String {
        switch self {
        case .missingKey:
            return L10n.t("Enter an API key before testing. The test does not save it.", language)
        case .invalidURL:
            return L10n.t("Check the provider base URL and try again.", language)
        case .invalidKey:
            return L10n.t("Check the API key or provider permissions.", language)
        case .modelNotFound:
            return L10n.t("Check that the model name exists for this provider.", language)
        case .rateLimited:
            return L10n.t("The provider is rate limiting requests. Try again later.", language)
        case .unavailable:
            return L10n.t("The provider returned a temporary server error. Try again later.", language)
        case .invalidResponse:
            return L10n.t("The provider responded, but not with the expected JSON test result.", language)
        case .network:
            return L10n.t("Check your network connection and base URL.", language)
        case .other(let message):
            return message
        }
    }
}
