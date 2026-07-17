import SwiftUI

@main
struct PrivateMomentsApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = TimelineStore()
    @StateObject private var playbackCenter = MediaPlaybackCenter()
    @StateObject private var videoAutoplayCenter = TimelineVideoAutoplayCenter()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let screenshotRoute = AppStoreScreenshotRoute.current {
                AppStoreScreenshotHost(route: screenshotRoute)
                    .environmentObject(store)
                    .environmentObject(playbackCenter)
                    .environmentObject(videoAutoplayCenter)
                    .environment(\.appLanguage, store.resolvedAppLanguage)
                    .preferredColorScheme(store.appAppearanceMode.colorScheme)
                    .task {
                        await store.bootstrap()
                    }
            } else {
                appRootView
            }
            #else
            appRootView
            #endif
        }
    }

    private var appRootView: some View {
        RootView()
                .environmentObject(store)
                .environmentObject(playbackCenter)
                .environmentObject(videoAutoplayCenter)
                .environment(\.appLanguage, store.resolvedAppLanguage)
                .preferredColorScheme(store.appAppearanceMode.colorScheme)
                .task {
                    await store.bootstrap()
                    if scenePhase == .active {
                        store.startCloudKitForegroundSyncLoop()
                    }
                    presentShareImportIfNeeded()
                }
                .onOpenURL { url in
                    handleOpenURL(url)
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else {
                        playbackCenter.pause()
                        videoAutoplayCenter.stop()
                        store.stopCloudKitForegroundSyncLoop()
                        return
                    }

                    presentShareImportIfNeeded()

                    Task { @MainActor in
                        await store.syncPendingWorkIfNeeded()
                        await store.syncCloudKitPendingWorkIfNeeded(reason: "foreground")
                        store.startCloudKitForegroundSyncLoop()
                    }
                }
    }

    private func handleOpenURL(_ url: URL) {
        guard url.scheme == ShareImportConstants.urlScheme else {
            return
        }
        presentShareImportIfNeeded(force: true)
    }

    private func presentShareImportIfNeeded(force: Bool = false) {
        guard force || ShareImportInbox.hasPendingImports() else {
            return
        }

        NotificationCenter.default.post(name: .presentComposerForShareImport, object: nil)
    }
}
