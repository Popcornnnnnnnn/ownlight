import SwiftUI

struct RootView: View {
    @Environment(\.appLanguage) private var appLanguage
    @EnvironmentObject private var playbackCenter: MediaPlaybackCenter
    @EnvironmentObject private var store: TimelineStore
    @State private var selectedTab: RootTab = .timeline
    @State private var calendarTimelineRoute: CalendarTimelineRoute?
    @State private var isShareImportComposerPresented = false
    @State private var shareImportComposerPresentationID = UUID()
    @State private var isSettingsPresented = false
    @StateObject private var shareImportAudioRecorder = AudioRecorderController()

    var body: some View {
        TabView(selection: $selectedTab) {
            TimelineView(
                calendarRoute: $calendarTimelineRoute,
                onOpenSettings: { presentSettings() }
            )
                .tabItem {
                    Label(L10n.t("Timeline", appLanguage), systemImage: "rectangle.stack")
                }
                .tag(RootTab.timeline)

            CalendarView(
                onSelectDay: { route in
                    playbackCenter.pause()
                    calendarTimelineRoute = route
                    selectedTab = .timeline
                },
                onOpenSettings: { presentSettings() }
            )
                .tabItem {
                    Label(L10n.t("Calendar", appLanguage), systemImage: "calendar")
                }
                .tag(RootTab.calendar)

            CheckInsView()
                .tabItem {
                    Label(L10n.t("Check-ins", appLanguage), systemImage: "checkmark.circle")
                }
                .tag(RootTab.checkIns)
        }
        .sheet(isPresented: $isShareImportComposerPresented) {
            ComposerView(audioRecorder: shareImportAudioRecorder)
                .id(shareImportComposerPresentationID)
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
        .sheet(item: aiExternalProcessingConsentBinding) { _ in
            AIExternalProcessingConsentView(
                onAccept: { store.acceptAIExternalProcessingConsent() },
                onDecline: { store.declineAIExternalProcessingConsent() }
            )
        }
        .fullScreenCover(item: welcomeOnboardingBinding) { _ in
            WelcomeOnboardingView {
                store.acceptWelcomeOnboarding()
            }
        }
        .task {
            presentShareImportComposerIfNeeded()
            store.showAIExternalProcessingConsentIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .presentComposerForShareImport)) { _ in
            presentShareImportComposerIfNeeded(force: true)
        }
        .onChange(of: selectedTab) { _, _ in
            playbackCenter.pause()
        }
    }

    private func presentShareImportComposerIfNeeded(force: Bool = false) {
        guard force || ShareImportInbox.hasPendingImports() else {
            return
        }
        playbackCenter.pause()
        if !isShareImportComposerPresented {
            shareImportComposerPresentationID = UUID()
        }
        isShareImportComposerPresented = true
    }

    private func presentSettings() {
        playbackCenter.pause()
        isSettingsPresented = true
    }

    private var aiExternalProcessingConsentBinding: Binding<AIExternalProcessingConsentRequest?> {
        Binding(
            get: {
                if isSettingsPresented || isShareImportComposerPresented {
                    return nil
                }
                return store.aiExternalProcessingConsentRequest
            },
            set: { newValue in
                store.aiExternalProcessingConsentRequest = newValue
            }
        )
    }

    private var welcomeOnboardingBinding: Binding<WelcomeOnboardingRequest?> {
        Binding(
            get: {
                if isSettingsPresented || isShareImportComposerPresented {
                    return nil
                }
                return store.welcomeOnboardingRequest
            },
            set: { newValue in
                store.welcomeOnboardingRequest = newValue
            }
        )
    }
}

private enum RootTab: Hashable {
    case timeline
    case calendar
    case checkIns
}
