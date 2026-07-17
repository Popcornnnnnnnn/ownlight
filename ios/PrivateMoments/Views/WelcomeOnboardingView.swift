import SwiftUI

struct WelcomeOnboardingView: View {
    @Environment(\.appLanguage) private var appLanguage

    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 36)

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.14))
                        .frame(width: 78, height: 78)

                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(spacing: 10) {
                    Text(title)
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 13) {
                WelcomeOnboardingPoint(
                    systemImage: "lock.shield",
                    title: pointOneTitle,
                    detail: pointOneDetail
                )
                WelcomeOnboardingPoint(
                    systemImage: "iphone",
                    title: pointTwoTitle,
                    detail: pointTwoDetail
                )
                WelcomeOnboardingPoint(
                    systemImage: "sparkles",
                    title: pointThreeTitle,
                    detail: pointThreeDetail
                )
            }
            .padding(.top, 4)

            Spacer(minLength: 24)

            Button {
                onStart()
            } label: {
                Text(startTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 42)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.accentColor)
                    )
            }
            .buttonStyle(.plain)
            .contentShape(Capsule())
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 34)
        .background(Color(.systemBackground))
    }

    private var title: String {
        appLanguage == .simplifiedChinese ? "只给自己的时间线" : "A timeline only for you"
    }

    private var subtitle: String {
        appLanguage == .simplifiedChinese
            ? "记录生活里的 private moments，不需要观众，也不需要账号。"
            : "Capture private moments without an audience, an account, or a public feed."
    }

    private var pointOneTitle: String {
        appLanguage == .simplifiedChinese ? "默认私密" : "Private by default"
    }

    private var pointOneDetail: String {
        appLanguage == .simplifiedChinese
            ? "没有好友关系、公开评论或互动通知。"
            : "No friends, public comments, or social notifications."
    }

    private var pointTwoTitle: String {
        appLanguage == .simplifiedChinese ? "本机优先" : "Local-first"
    }

    private var pointTwoDetail: String {
        appLanguage == .simplifiedChinese
            ? "内容先保存在这台 iPhone。"
            : "Your moments start on this iPhone."
    }

    private var pointThreeTitle: String {
        appLanguage == .simplifiedChinese ? "AI 可选" : "AI is optional"
    }

    private var pointThreeDetail: String {
        appLanguage == .simplifiedChinese
            ? "之后可以在 Settings 中按需配置。"
            : "Configure it later in Settings if you want it."
    }

    private var startTitle: String {
        appLanguage == .simplifiedChinese ? "Start" : "Start"
    }
}

private struct WelcomeOnboardingPoint: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
