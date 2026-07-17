import SwiftUI
import UIKit

struct WeeklyReviewListView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.appLanguage) private var appLanguage

    var body: some View {
        List {
            if store.aiAnalysisEnabled {
                Section {
                    Button {
                        Task {
                            await store.generateWeeklyReview()
                        }
                    } label: {
                        if store.isReviewGenerationInFlight {
                            Label(L10n.t("Generating review", appLanguage), systemImage: "hourglass")
                        } else {
                            Label(L10n.t("Generate Last 7 Days", appLanguage), systemImage: "sparkles")
                        }
                    }
                    .disabled(store.isLoadingReviews || store.isReviewGenerationInFlight)
                }
            }

            Section(L10n.t("Recent Reviews", appLanguage)) {
                if store.isLoadingReviews && store.weeklyReviews.isEmpty {
                    ProgressView()
                } else if store.weeklyReviews.isEmpty {
                    ContentUnavailableView(
                        store.aiAnalysisEnabled
                            ? L10n.t("No weekly reviews yet", appLanguage)
                            : L10n.t("AI Analysis is off", appLanguage),
                        systemImage: "doc.text.magnifyingglass",
                        description: store.aiAnalysisEnabled
                            ? nil
                            : Text(L10n.t("Turn on AI & Analysis to generate weekly reviews.", appLanguage))
                    )
                } else {
                    ForEach(store.weeklyReviews) { review in
                        NavigationLink {
                            WeeklyReviewDetailView(review: review)
                        } label: {
                            WeeklyReviewRow(review: review)
                        }
                        .disabled(store.isReviewGenerationInFlight || store.isReviewMutationInFlight(review))
                    }
                    .onDelete { offsets in
                        Task {
                            await store.deleteReviews(at: offsets)
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.t("Reviews", appLanguage))
        .task {
            await store.refreshReviews()
        }
        .refreshable {
            await store.refreshReviews()
        }
    }
}

private struct WeeklyReviewRow: View {
    @Environment(\.appLanguage) private var appLanguage

    let review: ReviewPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(review.content.title?.isEmpty == false ? review.content.title! : L10n.t("Weekly Review", appLanguage))
                .font(.headline)
                .lineLimit(2)

            if let subtitle = review.content.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let oneLiner = review.content.oneLiner, !oneLiner.isEmpty {
                Text(oneLiner)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if let errorMessage = review.errorMessage, review.status == "failed" {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text(rangeTitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }

    private var rangeTitle: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        if let start = review.parsedRangeStart, let end = review.parsedRangeEnd {
            return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
        }

        return review.status.capitalized
    }
}

struct WeeklyReviewDetailView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss

    let review: ReviewPayload

    @State private var selectedMomentId: String?
    @State private var selectedFeedbackTypes: Set<String>
    @State private var customGuidanceDraft: String
    @State private var savedCustomGuidanceText: String?
    @State private var feedbackInFlightType: String?
    @State private var showDeleteConfirmation = false
    @State private var didCopyReviewText = false

    init(review: ReviewPayload) {
        self.review = review
        _selectedFeedbackTypes = State(initialValue: Set(review.feedback?.selectedTypes ?? []))
        _customGuidanceDraft = State(initialValue: review.feedback?.customNote ?? "")
        _savedCustomGuidanceText = State(initialValue: review.feedback?.customNote?.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if review.status == "ready" {
                    reviewBody
                } else {
                    statusBody
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
        }
        .navigationTitle(L10n.t("Weekly Review", appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let reviewCopyText, !reviewCopyText.isEmpty {
                        Button {
                            copyReviewText(reviewCopyText)
                        } label: {
                            Label(L10n.t(didCopyReviewText ? "Copied" : "Copy text", appLanguage), systemImage: didCopyReviewText ? "checkmark" : "doc.on.doc")
                        }
                    }

                    Button {
                        Task {
                            await store.regenerateReview(review)
                        }
                    } label: {
                        if isBusy {
                            Label(L10n.t("Regenerating review", appLanguage), systemImage: "hourglass")
                        } else {
                            Label(L10n.t("Regenerate", appLanguage), systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isBusy || store.isLoadingReviews)

                    Button {
                        Task {
                            await store.publishReviewAsMoment(review)
                        }
                    } label: {
                        Label(L10n.t("Publish as Moment", appLanguage), systemImage: "square.and.arrow.up")
                    }
                    .disabled(isBusy || review.status != "ready" || review.publishedPostId != nil)

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label(L10n.t("Delete Review", appLanguage), systemImage: "trash")
                    }
                    .disabled(isBusy)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: selectedMomentBinding) { item in
            NavigationStack {
                MomentDetailView(postId: item.id)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(L10n.t("Done", appLanguage)) {
                                selectedMomentId = nil
                            }
                        }
                    }
            }
        }
        .alert(L10n.t("Delete review?", appLanguage), isPresented: $showDeleteConfirmation) {
            Button(L10n.t("Delete", appLanguage), role: .destructive) {
                Task {
                    await store.deleteReview(review)
                    dismiss()
                }
            }
            Button(L10n.t("Cancel", appLanguage), role: .cancel) {}
        }
    }

    private var isBusy: Bool {
        store.isReviewGenerationInFlight || store.isReviewMutationInFlight(review)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(review.content.title?.isEmpty == false ? review.content.title! : L10n.t("Weekly Review", appLanguage))
                .font(.largeTitle.weight(.semibold))
                .fontDesign(.rounded)

            if let subtitle = review.content.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            } else if let oneLiner = review.content.oneLiner, !oneLiner.isEmpty {
                Text(oneLiner)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if let sourceLabel {
                Text(sourceLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }

            if isBusy {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(L10n.t("Regenerating review", appLanguage))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var reviewBody: some View {
        if let bodyMarkdown = review.content.bodyMarkdown, !bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            SelectableMomentTextView(text: bodyMarkdown, style: .detail)
        }

        if let keywords = review.content.keywords, !keywords.isEmpty {
            ReviewSection(title: L10n.t("Keywords", appLanguage), systemImage: "number") {
                Text(keywords.prefix(5).map(\.label).joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
        }

        if let notableMoments = review.content.notableMoments, !notableMoments.isEmpty {
            ReviewSection(title: L10n.t("Worth Revisiting", appLanguage), systemImage: "bookmark") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(notableMoments) { notable in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(notable.title)
                                    .font(.headline)

                                Spacer(minLength: 0)

                                if let firstMomentId = notable.momentIds.first, store.item(id: firstMomentId) != nil {
                                    Button {
                                        selectedMomentId = firstMomentId
                                    } label: {
                                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                                            .font(.caption2.weight(.semibold))
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel(L10n.t("Open moment preview", appLanguage))
                                }
                            }

                            if !notable.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(notable.note)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }

        if let uncertainty = review.content.uncertainty, !uncertainty.isEmpty {
            ReviewSection(title: L10n.t("Uncertainty", appLanguage), systemImage: "questionmark.circle") {
                bulletGroup(title: nil, items: uncertainty)
            }
        }

        feedbackControls
    }

    private var statusBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            if review.status == "generating" {
                ProgressView()
                Text(L10n.t("Generating review", appLanguage))
                    .foregroundStyle(.secondary)
            } else {
                Text(review.errorMessage ?? L10n.t("Review failed", appLanguage))
                    .foregroundStyle(.secondary)
                Button(isBusy ? L10n.t("Regenerating review", appLanguage) : L10n.t("Regenerate", appLanguage)) {
                    Task {
                        await store.regenerateReview(review)
                    }
                }
                .disabled(isBusy)
            }
        }
    }

    private var feedbackControls: some View {
        ReviewSection(title: L10n.t("Feedback", appLanguage), systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 12) {
                FlowLayout(spacing: 8) {
                    feedbackButton("Useful", type: "useful")
                    feedbackButton("Too much inference", type: "too_much_inference")
                    feedbackButton("Too dry", type: "too_dry")
                    feedbackButton("Missed the point", type: "missed_point")
                    feedbackButton("Hide this theme", type: "hide_theme")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("High-priority guidance for next review", appLanguage))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    TextEditor(text: $customGuidanceDraft)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 92)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
                        )

                    HStack(spacing: 10) {
                        Button(L10n.t("Save guidance", appLanguage)) {
                            Task {
                                await saveCustomGuidance()
                            }
                        }
                        .buttonStyle(ReviewFeedbackButtonStyle(
                            isSaved: savedCustomGuidanceText == trimmedCustomGuidance && !trimmedCustomGuidance.isEmpty,
                            isSubmitting: feedbackInFlightType == "custom_guidance"
                        ))
                        .disabled(feedbackInFlightType != nil || trimmedCustomGuidance.isEmpty)

                        Button(L10n.t("Clear guidance", appLanguage)) {
                            Task {
                                await clearCustomGuidance()
                            }
                        }
                        .buttonStyle(ReviewFeedbackButtonStyle(
                            isSaved: false,
                            isSubmitting: feedbackInFlightType == "custom_guidance"
                        ))
                        .disabled(feedbackInFlightType != nil || (savedCustomGuidanceText == nil && trimmedCustomGuidance.isEmpty))
                    }
                }

                Text(L10n.t("These feedback choices affect later weekly reviews. The text guidance is treated as a stronger adjustment request for the next draft.", appLanguage))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func feedbackButton(_ title: String, type: String) -> some View {
        Button(L10n.t(title, appLanguage)) {
            Task {
                await toggleFeedback(type: type)
            }
        }
        .buttonStyle(ReviewFeedbackButtonStyle(
            isSaved: selectedFeedbackTypes.contains(type),
            isSubmitting: feedbackInFlightType == type
        ))
        .disabled(feedbackInFlightType != nil)
    }

    private var trimmedCustomGuidance: String {
        customGuidanceDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func toggleFeedback(type: String) async {
        let shouldEnable = !selectedFeedbackTypes.contains(type)
        feedbackInFlightType = type
        let updatedReview = await store.sendReviewFeedback(review: review, type: type, enabled: shouldEnable)
        feedbackInFlightType = nil
        guard let updatedReview else {
            return
        }

        applyFeedbackState(from: updatedReview)
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.8)
    }

    private func saveCustomGuidance() async {
        guard !trimmedCustomGuidance.isEmpty else {
            return
        }

        feedbackInFlightType = "custom_guidance"
        let updatedReview = await store.sendReviewFeedback(
            review: review,
            type: "custom_guidance",
            enabled: true,
            note: trimmedCustomGuidance
        )
        feedbackInFlightType = nil
        guard let updatedReview else {
            return
        }

        applyFeedbackState(from: updatedReview)
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.85)
    }

    private func clearCustomGuidance() async {
        feedbackInFlightType = "custom_guidance"
        let updatedReview = await store.sendReviewFeedback(
            review: review,
            type: "custom_guidance",
            enabled: false,
            note: nil
        )
        feedbackInFlightType = nil
        guard let updatedReview else {
            return
        }

        applyFeedbackState(from: updatedReview)
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
    }

    private func applyFeedbackState(from updatedReview: ReviewPayload) {
        selectedFeedbackTypes = Set(updatedReview.feedback?.selectedTypes ?? [])
        customGuidanceDraft = updatedReview.feedback?.customNote ?? ""
        let trimmedSaved = updatedReview.feedback?.customNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        savedCustomGuidanceText = trimmedSaved.isEmpty ? nil : trimmedSaved
    }

    private var reviewCopyText: String? {
        var sections: [String] = []

        if let title = review.content.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            sections.append(title)
        }

        if let subtitle = review.content.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !subtitle.isEmpty {
            sections.append(subtitle)
        }

        if let bodyMarkdown = review.content.bodyMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines), !bodyMarkdown.isEmpty {
            sections.append(bodyMarkdown)
        }

        if let keywords = review.content.keywords?.map(\.label), !keywords.isEmpty {
            sections.append("\(L10n.t("Keywords", appLanguage))\n\(keywords.joined(separator: " · "))")
        }

        if let notableMoments = review.content.notableMoments, !notableMoments.isEmpty {
            let notableText = notableMoments
                .map { notable in
                    let note = notable.note.trimmingCharacters(in: .whitespacesAndNewlines)
                    return note.isEmpty ? notable.title : "\(notable.title)\n\(note)"
                }
                .joined(separator: "\n\n")
            sections.append("\(L10n.t("Worth Revisiting", appLanguage))\n\(notableText)")
        }

        if let uncertainty = review.content.uncertainty, !uncertainty.isEmpty {
            sections.append("\(L10n.t("Uncertainty", appLanguage))\n\(uncertainty.map { "• \($0)" }.joined(separator: "\n"))")
        }

        let joined = sections.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    private var sourceLabel: String? {
        AIProviderSourceFormatter.label(
            provider: review.provider,
            model: review.model,
            language: appLanguage
        )
    }

    private func copyReviewText(_ text: String) {
        UIPasteboard.general.string = text
        didCopyReviewText = true

        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                didCopyReviewText = false
            }
        }
    }

    private func bulletGroup(title: String?, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title, !items.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(item)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var selectedMomentBinding: Binding<TimelineItem?> {
        Binding(
            get: {
                guard let selectedMomentId else {
                    return nil
                }
                return store.item(id: selectedMomentId)
            },
            set: { value in
                selectedMomentId = value?.id
            }
        )
    }

    private var rangeTitle: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        if let start = review.parsedRangeStart, let end = review.parsedRangeEnd {
            return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
        }

        return review.rangeMode
    }
}

private struct ReviewFeedbackButtonStyle: ButtonStyle {
    let isSaved: Bool
    let isSubmitting: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSaved ? Color.accentColor : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(borderColor(isPressed: configuration.isPressed), lineWidth: isSaved ? 1.2 : 1)
            )
            .scaleEffect(configuration.isPressed && !isSubmitting ? 0.985 : 1)
            .opacity(isSubmitting ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.16), value: isSaved)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isSaved {
            return Color.accentColor.opacity(isPressed ? 0.2 : 0.14)
        }
        if isSubmitting {
            return Color.secondary.opacity(0.12)
        }
        return isPressed ? Color.secondary.opacity(0.14) : Color.secondary.opacity(0.06)
    }

    private func borderColor(isPressed: Bool) -> Color {
        if isSaved {
            return Color.accentColor.opacity(isPressed ? 0.7 : 0.9)
        }
        if isPressed {
            return Color.secondary.opacity(0.42)
        }
        return Color.secondary.opacity(0.22)
    }
}

private struct ReviewSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var size = CGSize(width: maxWidth, height: 0)
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let subviewSize = subview.sizeThatFits(.unspecified)
            if rowWidth > 0 && rowWidth + spacing + subviewSize.width > maxWidth {
                size.height += rowHeight + spacing
                rowWidth = subviewSize.width
                rowHeight = subviewSize.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + subviewSize.width
                rowHeight = max(rowHeight, subviewSize.height)
            }
        }

        size.height += rowHeight
        return size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var point = CGPoint(x: bounds.minX, y: bounds.minY)
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let subviewSize = subview.sizeThatFits(.unspecified)
            if point.x > bounds.minX && point.x + subviewSize.width > bounds.maxX {
                point.x = bounds.minX
                point.y += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(
                at: point,
                proposal: ProposedViewSize(width: subviewSize.width, height: subviewSize.height)
            )
            point.x += subviewSize.width + spacing
            rowHeight = max(rowHeight, subviewSize.height)
        }
    }
}
