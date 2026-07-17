import SwiftUI

struct DataICloudSettingsView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.appLanguage) private var appLanguage
    @State private var alert: DataICloudAlert?
    @State private var cloudKitSnapshot = CloudKitAccountStatusSnapshot.notConfigured
    @State private var isCheckingCloudKit = false
    @State private var isICloudSyncEnabled = AppSettings.iCloudSyncEnabled
    @State private var isRunningSync = false
    @State private var lastSyncSummary: String?

    private let accountStatusService = CloudKitAccountStatusService()

    var body: some View {
        Form {
            Section {
                LabeledContent(
                    L10n.t("Account", appLanguage),
                    value: cloudKitSnapshot.accountStatusTitle(language: appLanguage)
                )

                Toggle(isOn: iCloudSyncToggleBinding) {
                    Text(L10n.t("iCloud Sync", appLanguage))
                }

                Text(cloudKitSnapshot.guidanceMessage(language: appLanguage))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let lastSyncSummary {
                    Text(lastSyncSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task {
                        await syncNow()
                    }
                } label: {
                    HStack {
                        Text(L10n.t("Sync Now", appLanguage))
                        Spacer()
                        if isRunningSync {
                            ProgressView()
                        }
                    }
                }
                .disabled(!canRunCloudKitAction || isRunningSync)

                if shouldShowCheckAgain {
                    Button {
                        Task {
                            await refreshCloudKitStatus()
                        }
                    } label: {
                        HStack {
                            Text(L10n.t("Check Again", appLanguage))
                            Spacer()
                            if isCheckingCloudKit {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isCheckingCloudKit)
                }
            } header: {
                Text(L10n.t("iCloud", appLanguage))
            } footer: {
                Text(L10n.t("iCloud Sync is off by default. It uses your iCloud private database and does not require a separate Ownlight account.", appLanguage))
            }
        }
        .navigationTitle(L10n.t("iCloud", appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshCloudKitStatus()
        }
        .alert(item: $alert) { alert in
            alert.alert(language: appLanguage) {
                Task {
                    await enableICloudSync()
                }
            } keepOff: {
                setICloudSyncEnabled(false)
            }
        }
    }

    private var iCloudSyncToggleBinding: Binding<Bool> {
        Binding(
            get: { isICloudSyncEnabled },
            set: { newValue in
                if newValue {
                    guard cloudKitSnapshot.canEnableSync else {
                        setICloudSyncEnabled(false)
                        alert = .notice(.cannotEnable(cloudKitSnapshot.accountStatusTitle(language: appLanguage)))
                        return
                    }
                    alert = .enableConfirmation
                } else {
                    setICloudSyncEnabled(false)
                }
            }
        )
    }

    private var canRunCloudKitAction: Bool {
        isICloudSyncEnabled
            && cloudKitSnapshot.canEnableSync
            && store.database != nil
    }

    private var shouldShowCheckAgain: Bool {
        !cloudKitSnapshot.canEnableSync
    }

    private func setICloudSyncEnabled(_ isEnabled: Bool) {
        AppSettings.iCloudSyncEnabled = isEnabled
        isICloudSyncEnabled = isEnabled
        lastSyncSummary = isEnabled
            ? L10n.t("iCloud Sync is on.", appLanguage)
            : L10n.t("iCloud Sync is off.", appLanguage)
        if isEnabled {
            Task {
                await syncNow(turnOffOnLocalArchiveConflict: true)
                if isICloudSyncEnabled {
                    store.startCloudKitForegroundSyncLoop()
                }
            }
        } else {
            store.cancelCloudKitAutoSync()
        }
    }

    @MainActor
    private func enableICloudSync() async {
        setICloudSyncEnabled(true)
    }

    @MainActor
    @discardableResult
    private func syncNow(turnOffOnLocalArchiveConflict: Bool = false) async -> Bool {
        guard !isRunningSync else {
            return false
        }

        isRunningSync = true
        defer {
            isRunningSync = false
        }

        do {
            let result = try await makeCoordinator().syncNow()
            try await store.reload()
            store.refreshSyncedPreferencesFromAppSettings()
            lastSyncSummary = result.displaySummary(language: appLanguage)
            return true
        } catch {
            if turnOffOnLocalArchiveConflict,
               let coordinatorError = error as? CloudKitSyncCoordinatorError,
               coordinatorError == .nonEmptyLocalLibraryWithExistingCloudArchive {
                AppSettings.iCloudSyncEnabled = false
                isICloudSyncEnabled = false
                lastSyncSummary = L10n.t("iCloud Sync is off.", appLanguage)
                store.cancelCloudKitAutoSync()
            }
            let message = CloudKitSyncUserMessage.message(for: error)
            lastSyncSummary = message.body(language: appLanguage)
            alert = .notice(.error(message))
            return false
        }
    }

    private func makeCoordinator() throws -> CloudKitSyncCoordinator {
        guard let database = store.database else {
            throw DataICloudSettingsError.databaseUnavailable
        }

        return try CloudKitSyncCoordinator(database: database)
    }

    @MainActor
    private func refreshCloudKitStatus() async {
        guard !isCheckingCloudKit else {
            return
        }

        isCheckingCloudKit = true
        cloudKitSnapshot = await accountStatusService.loadAccountStatus()
        isCheckingCloudKit = false
    }
}

private enum DataICloudAlert: Identifiable, Equatable {
    case enableConfirmation
    case notice(DataICloudNotice)

    var id: String {
        switch self {
        case .enableConfirmation:
            return "enable-confirmation"
        case .notice(let notice):
            return "notice-\(notice.id)"
        }
    }

    func alert(
        language: AppResolvedLanguage,
        turnOn: @escaping () -> Void,
        keepOff: @escaping () -> Void
    ) -> Alert {
        switch self {
        case .enableConfirmation:
            return Alert(
                title: Text(L10n.t("Turn on iCloud Sync?", language)),
                message: Text(L10n.t("Ownlight will use your iCloud private database. Your current local library will be queued for private iCloud sync in small background batches. Your local data stays on this iPhone.", language)),
                primaryButton: .default(Text(L10n.t("Turn On", language)), action: turnOn),
                secondaryButton: .cancel(Text(L10n.t("Keep Off", language)), action: keepOff)
            )
        case .notice(let notice):
            return Alert(
                title: Text(notice.title(language: language)),
                message: Text(notice.message(language: language)),
                dismissButton: .default(Text(L10n.t("OK", language)))
            )
        }
    }
}

private enum DataICloudNotice: Identifiable, Equatable {
    case cannotEnable(String)
    case error(CloudKitSyncUserMessage)

    var id: String {
        switch self {
        case .cannotEnable:
            return "cannot-enable"
        case .error:
            return "error"
        }
    }

    func title(language: AppResolvedLanguage) -> String {
        switch self {
        case .cannotEnable:
            return L10n.t("iCloud Sync unavailable", language)
        case .error(let message):
            return message.title(language: language)
        }
    }

    func message(language: AppResolvedLanguage) -> String {
        switch self {
        case .cannotEnable(let status):
            return String(
                format: L10n.t("iCloud is not ready on this device yet. Current status: %@.", language),
                status
            )
        case .error(let message):
            return message.body(language: language)
        }
    }
}

private enum DataICloudSettingsError: LocalizedError {
    case databaseUnavailable

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable:
            return "Local database is not ready yet."
        }
    }
}

private extension CloudKitAccountStatusSnapshot {
    func accountStatusTitle(language: AppResolvedLanguage) -> String {
        switch state {
        case .notConfigured:
            return L10n.t("Not configured", language)
        case .available:
            return L10n.t("Available", language)
        case .noAccount:
            return L10n.t("Sign in required", language)
        case .restricted:
            return L10n.t("Restricted", language)
        case .temporarilyUnavailable:
            return L10n.t("Temporarily unavailable", language)
        case .couldNotDetermine:
            return L10n.t("Could not determine", language)
        }
    }

    func guidanceMessage(language: AppResolvedLanguage) -> String {
        switch state {
        case .notConfigured:
            return L10n.t("iCloud Sync is not configured for this build yet.", language)
        case .available:
            return L10n.t("iCloud is available. Turn on iCloud Sync when you are ready.", language)
        case .noAccount:
            return L10n.t("Sign in to iCloud in iOS Settings to use iCloud Sync.", language)
        case .restricted:
            return L10n.t("iCloud is restricted on this device. Ownlight remains available locally.", language)
        case .temporarilyUnavailable:
            return L10n.t("iCloud is temporarily unavailable. Ownlight remains available locally.", language)
        case .couldNotDetermine:
            return L10n.t("Ownlight could not determine iCloud status. Try again later.", language)
        }
    }
}
