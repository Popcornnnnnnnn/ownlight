import SwiftUI

#if DEBUG
enum AppStoreScreenshotRoute: String {
    case timeline
    case summary
    case markdown
    case calendar
    case tags
    case iCloud = "icloud"

    static var current: AppStoreScreenshotRoute? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--private-moments-screenshot-route"),
              arguments.indices.contains(arguments.index(after: index)) else {
            return nil
        }

        return AppStoreScreenshotRoute(rawValue: arguments[arguments.index(after: index)])
    }
}

struct AppStoreScreenshotHost: View {
    @EnvironmentObject private var store: TimelineStore
    @EnvironmentObject private var playbackCenter: MediaPlaybackCenter
    @Environment(\.appLanguage) private var appLanguage

    let route: AppStoreScreenshotRoute

    var body: some View {
        Group {
            if store.isReady {
                screenshotContent
            } else {
                ProgressView()
            }
        }
    }

    @ViewBuilder
    private var screenshotContent: some View {
        switch route {
        case .timeline:
            TimelineView(calendarRoute: .constant(nil), onOpenSettings: {})
        case .summary:
            if let media = store.items.first(where: { $0.id == "demo-post-audio-summary" })?.media.first,
               let summary = store.items
                    .first(where: { $0.id == "demo-post-audio-summary" })?
                    .aiSummaries
                    .first(where: { $0.mediaId == media.id }) {
                AISummarySheet(media: media, summary: summary, onRegenerate: {}, onDelete: {})
            } else {
                ContentUnavailableView(L10n.t("Summary unavailable", appLanguage), systemImage: "sparkles")
            }
        case .markdown:
            NavigationStack {
                MomentDetailView(postId: "demo-post-markdown-showcase")
            }
        case .calendar:
            CalendarView(onSelectDay: { _ in }, onOpenSettings: {})
        case .tags:
            NavigationStack {
                TagManagementView()
            }
        case .iCloud:
            NavigationStack {
                ScreenshotICloudSettingsView()
            }
        }
    }
}

private struct ScreenshotICloudSettingsView: View {
    @Environment(\.appLanguage) private var appLanguage
    @State private var isSyncEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $isSyncEnabled) {
                    Text(L10n.t("iCloud Sync", appLanguage))
                }

                Text(localText(
                    zh: "开启后会使用你的 iCloud 私有数据库，不需要单独的 Ownlight 账号。",
                    en: "Uses your private iCloud database and does not require a separate Ownlight account."
                ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button(L10n.t("Sync Now", appLanguage)) {}
                    .disabled(false)
            } header: {
                Text(L10n.t("iCloud", appLanguage))
            }

            Section {
                LabeledContent(localText(zh: "账号", en: "Account"), value: localText(zh: "可用", en: "Available"))
                LabeledContent(localText(zh: "状态", en: "Status"), value: localText(zh: "已开启", en: "On"))
                LabeledContent(localText(zh: "最近同步", en: "Last sync"), value: localText(zh: "刚刚", en: "Just now"))
                LabeledContent(localText(zh: "后台同步", en: "Background sync"), value: localText(zh: "自动", en: "Automatic"))
            } header: {
                Text(localText(zh: "同步状态", en: "Sync Status"))
            }

            Section {
                syncScopeRow(icon: "rectangle.stack", title: localText(zh: "文字、照片、语音和视频", en: "Text, photos, audio, and video"))
                syncScopeRow(icon: "bubble.left.and.bubble.right", title: localText(zh: "评论、收藏、置顶和删除", en: "Comments, favorites, pins, and deletes"))
                syncScopeRow(icon: "tag", title: localText(zh: "标签、分类方向和打卡", en: "Tags, areas, and check-ins"))
                syncScopeRow(icon: "sparkles", title: localText(zh: "AI 摘要和回顾", en: "AI summaries and reviews"))
            } header: {
                Text(localText(zh: "同步内容", en: "What Syncs"))
            } footer: {
                Text(L10n.t("Ownlight will use your iCloud private database. Your current local library will be queued for private iCloud sync in small background batches. Your local data stays on this iPhone.", appLanguage))
            }
        }
        .navigationTitle(L10n.t("iCloud", appLanguage))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func localText(zh: String, en: String) -> String {
        appLanguage == .simplifiedChinese ? zh : en
    }

    private func syncScopeRow(icon: String, title: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.blue)
        }
    }
}
#endif
