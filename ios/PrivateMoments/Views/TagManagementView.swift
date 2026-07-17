import SwiftUI

struct TagManagementView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.appLanguage) private var appLanguage
    @State private var cleanupConfirmation: TagCleanupSuggestion?
    @State private var isWorking = false

    var body: some View {
        Form {
            Section(L10n.t("Areas", appLanguage)) {
                ForEach(visibleAreas) { area in
                    NavigationLink {
                        TagAreaDetailView(area: area)
                    } label: {
                        TagAreaRow(
                            area: area,
                            topicCount: topics(in: area).count,
                            usageCount: usageCount(in: area)
                        )
                    }
                }
            }

            if !cleanupSuggestions.isEmpty {
                Section(L10n.t("Cleanup Suggestions", appLanguage)) {
                    ForEach(cleanupSuggestions) { suggestion in
                        Button {
                            cleanupConfirmation = suggestion
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(suggestion.title(language: appLanguage), systemImage: suggestion.systemImage)
                                    .foregroundStyle(.primary)
                                Text(suggestion.detail(language: appLanguage))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(isWorking)
                    }
                }
            }

            if !archivedTopicTags.isEmpty {
                Section(L10n.t("Archived", appLanguage)) {
                    ForEach(archivedTopicTags) { tag in
                        NavigationLink {
                            TagDetailManagementView(tagId: tag.id)
                        } label: {
                            TagManagementRow(tag: tag, usageCount: usageCount(for: tag))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

        }
        .navigationTitle(L10n.t("Tags", appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            L10n.t("Apply Cleanup?", appLanguage),
            isPresented: Binding(
                get: { cleanupConfirmation != nil },
                set: { isPresented in
                    if !isPresented {
                        cleanupConfirmation = nil
                    }
                }
            ),
            presenting: cleanupConfirmation
        ) { suggestion in
            Button(L10n.t("Apply", appLanguage)) {
                Task {
                    await applyCleanup(suggestion)
                }
            }
            Button(L10n.t("Cancel", appLanguage), role: .cancel) {
                cleanupConfirmation = nil
            }
        } message: { suggestion in
            Text(suggestion.confirmationMessage(language: appLanguage))
        }
    }

    private var topicTags: [TimelineTag] {
        store.tags
            .filter { $0.type == "topic" && !$0.isArchived }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var archivedTopicTags: [TimelineTag] {
        store.tags
            .filter { $0.type == "topic" && $0.isArchived }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func usageCount(for tag: TimelineTag) -> Int {
        store.tagUsageCounts[tag.id] ?? 0
    }

    private var visibleAreas: [TopicTagArea] {
        TopicTagArea.displayAreas
    }

    private func topics(in area: TopicTagArea) -> [TimelineTag] {
        topicTags.filter { $0.resolvedArea == area }
    }

    private func usageCount(in area: TopicTagArea) -> Int {
        topics(in: area).reduce(0) { total, tag in
            total + usageCount(for: tag)
        }
    }

    private var cleanupSuggestions: [TagCleanupSuggestion] {
        let mergeSuggestions = TagCleanupSuggestion.mergeSuggestions(from: topicTags)
        let areaSuggestions = topicTags.compactMap(TagCleanupSuggestion.areaSuggestion(for:))
        return Array((mergeSuggestions + areaSuggestions).prefix(12))
    }

    private func applyCleanup(_ suggestion: TagCleanupSuggestion) async {
        isWorking = true
        defer {
            isWorking = false
            cleanupConfirmation = nil
        }

        switch suggestion.kind {
        case .merge(let sourceId, let targetId):
            guard let source = store.tags.first(where: { $0.id == sourceId }),
                  let target = store.tags.first(where: { $0.id == targetId }) else {
                return
            }
            _ = await store.mergeTopicTag(source, into: target)
        case .moveArea(let tagId, let area):
            guard let tag = store.tags.first(where: { $0.id == tagId }) else {
                return
            }
            _ = await store.updateTag(tag, name: tag.name, areaId: area.rawValue)
        }
    }
}

private struct AddTagRequest: Identifiable {
    let type: String
    let area: TopicTagArea?
    let id = UUID()
}

private struct TagAreaRow: View {
    @Environment(\.appLanguage) private var appLanguage

    let area: TopicTagArea
    let topicCount: Int
    let usageCount: Int

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(area.localizedTitle(language: appLanguage))
                Text("\(topicCount) \(L10n.t("topics", appLanguage)) · \(usageCount) \(L10n.t("uses", appLanguage))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: area.symbolName)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TagAreaDetailView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.appLanguage) private var appLanguage

    let area: TopicTagArea

    @State private var searchText = ""
    @State private var addTagRequest: AddTagRequest?

    var body: some View {
        Form {
            Section {
                TextField(L10n.t("Search Topics", appLanguage), text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section(area.localizedTitle(language: appLanguage)) {
                if filteredTopics.isEmpty {
                    Text(L10n.t("No topic tags yet", appLanguage))
                        .foregroundStyle(.secondary)
                }

                ForEach(filteredTopics) { tag in
                    NavigationLink {
                        TagDetailManagementView(tagId: tag.id)
                    } label: {
                        TagManagementRow(tag: tag, usageCount: store.tagUsageCounts[tag.id] ?? 0)
                    }
                }

                Button {
                    addTagRequest = AddTagRequest(type: "topic", area: area)
                } label: {
                    Label(L10n.t("Add Topic Tag", appLanguage), systemImage: "plus")
                }
            }
        }
        .navigationTitle(area.localizedTitle(language: appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $addTagRequest) { request in
            AddTagSheet(type: request.type, area: request.area)
                .environmentObject(store)
        }
    }

    private var filteredTopics: [TimelineTag] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.activeTopicTags
            .filter { $0.resolvedArea == area }
            .filter { query.isEmpty || $0.name.lowercased().contains(query) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

private struct TagCleanupSuggestion: Identifiable {
    enum Kind {
        case merge(sourceId: String, targetId: String)
        case moveArea(tagId: String, area: TopicTagArea)
    }

    let id: String
    let kind: Kind
    let sourceName: String
    let targetName: String?
    let targetArea: TopicTagArea?

    var systemImage: String {
        switch kind {
        case .merge:
            return "arrow.triangle.merge"
        case .moveArea:
            return "folder"
        }
    }

    func title(language: AppResolvedLanguage) -> String {
        switch kind {
        case .merge:
            return L10n.t("Merge similar topics", language)
        case .moveArea:
            return L10n.t("Move topic to area", language)
        }
    }

    func detail(language: AppResolvedLanguage) -> String {
        switch kind {
        case .merge:
            return "\(sourceName) → \(targetName ?? "")"
        case .moveArea:
            return "\(sourceName) → \(targetArea?.localizedTitle(language: language) ?? "")"
        }
    }

    func confirmationMessage(language: AppResolvedLanguage) -> String {
        switch kind {
        case .merge:
            return "\(L10n.t("Archive", language)) \"\(sourceName)\" \(L10n.t("and keep it as an alias of", language)) \"\(targetName ?? "")\"."
        case .moveArea:
            return "\(L10n.t("Move", language)) \"\(sourceName)\" \(L10n.t("to", language)) \(targetArea?.localizedTitle(language: language) ?? "")."
        }
    }

    static func mergeSuggestions(from tags: [TimelineTag]) -> [TagCleanupSuggestion] {
        var suggestions: [TagCleanupSuggestion] = []
        let sortedTags = tags.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        for leftIndex in sortedTags.indices {
            for rightIndex in sortedTags.indices where rightIndex > leftIndex {
                let left = sortedTags[leftIndex]
                let right = sortedTags[rightIndex]
                guard isSimilar(left.name, right.name) else {
                    continue
                }

                let target = preferredMergeTarget(left, right)
                let source = target.id == left.id ? right : left
                suggestions.append(
                    TagCleanupSuggestion(
                        id: "merge-\(source.id)-\(target.id)",
                        kind: .merge(sourceId: source.id, targetId: target.id),
                        sourceName: source.name,
                        targetName: target.name,
                        targetArea: nil
                    )
                )
            }
        }

        return Array(suggestions.prefix(8))
    }

    static func areaSuggestion(for tag: TimelineTag) -> TagCleanupSuggestion? {
        guard tag.isTopic, !TopicTagArea.isFixedAreaId(tag.areaId) else {
            return nil
        }

        let area = TopicTagArea.inferredArea(forTopicName: tag.name)

        return TagCleanupSuggestion(
            id: "area-\(tag.id)-\(area.rawValue)",
            kind: .moveArea(tagId: tag.id, area: area),
            sourceName: tag.name,
            targetName: nil,
            targetArea: area
        )
    }

    private static func preferredMergeTarget(_ left: TimelineTag, _ right: TimelineTag) -> TimelineTag {
        let leftCompact = compact(left.name)
        let rightCompact = compact(right.name)
        if leftCompact.count != rightCompact.count {
            return leftCompact.count < rightCompact.count ? left : right
        }

        return left.name.localizedStandardCompare(right.name) == .orderedAscending ? left : right
    }

    private static func isSimilar(_ left: String, _ right: String) -> Bool {
        let leftNormalized = LocalDatabase.normalizedTagName(left)
        let rightNormalized = LocalDatabase.normalizedTagName(right)
        if leftNormalized == rightNormalized {
            return true
        }

        let leftCompact = compact(left)
        let rightCompact = compact(right)
        guard leftCompact.count >= 3, rightCompact.count >= 3 else {
            return false
        }

        return leftCompact == rightCompact
            || leftCompact.contains(rightCompact)
            || rightCompact.contains(leftCompact)
    }

    private static func compact(_ value: String) -> String {
        LocalDatabase.normalizedTagName(value)
            .replacingOccurrences(of: "[\\s\\p{P}\\p{S}_]+", with: "", options: .regularExpression)
    }

}

private struct BatchTagDeleteConfirmation: Identifiable {
    let tags: [TimelineTag]
    let id = UUID()
}

private struct TagManagementRow: View {
    @Environment(\.appLanguage) private var appLanguage

    let tag: TimelineTag
    let usageCount: Int

    var body: some View {
        HStack(spacing: 10) {
            if tag.type == "primary" {
                TimelineTagChip(tag: tag, compact: true)
            } else {
                Label(L10n.tagName(tag, language: appLanguage), systemImage: "tag")
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Text("\(usageCount)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct SelectableTagManagementRow: View {
    let tag: TimelineTag
    let usageCount: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.body)
                .foregroundStyle(isSelected ? .blue : .secondary)

            TagManagementRow(tag: tag, usageCount: usageCount)
        }
        .contentShape(Rectangle())
    }
}

private struct TagDetailManagementView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage

    let tagId: String

    @State private var name = ""
    @State private var colorHex = ""
    @State private var aliasText = ""
    @State private var mergeTargetTagId: String?
    @State private var area = TopicTagArea.life
    @State private var isWorking = false
    @State private var tagPendingDeletion: TimelineTag?

    var body: some View {
        Form {
            if let tag {
                Section(L10n.t("Tag", appLanguage)) {
                    LabeledContent(L10n.t("Type", appLanguage), value: tag.type == "primary" ? L10n.t("Primary", appLanguage) : L10n.t("Topic", appLanguage))
                    LabeledContent(L10n.t("Usage", appLanguage), value: "\(store.tagUsageCounts[tag.id] ?? 0)")

                    if tag.isDefaultPrimaryTag {
                        LabeledContent(L10n.t("Name", appLanguage), value: L10n.tagName(tag, language: appLanguage))
                    } else {
                        TextField(L10n.t("Name", appLanguage), text: $name)
                    }

                    if tag.type == "primary" {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.t("Color", appLanguage))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TagColorPalette(selection: $colorHex)
                        }
                    } else {
                        Picker(L10n.t("Area", appLanguage), selection: $area) {
                            ForEach(TopicTagArea.displayAreas) { item in
                                Text(item.localizedTitle(language: appLanguage)).tag(item)
                            }
                        }
                    }

                    Button(L10n.t("Save Changes", appLanguage)) {
                        Task {
                            await save(tag)
                        }
                    }
                    .disabled(isWorking || !canSave(tag))
                }

                if tag.type == "topic" {
                    aliasesSection(tag)

                    if !tag.isArchived {
                        mergeSection(tag)
                    }
                }

                Section {
                    if tag.isArchived {
                        Button(L10n.t("Restore", appLanguage)) {
                            Task {
                                await runAndDismiss {
                                    await store.restoreTag(tag)
                                }
                            }
                        }

                        if !tag.isDefaultPrimaryTag {
                            Button(L10n.t("Delete Permanently", appLanguage), role: .destructive) {
                                tagPendingDeletion = tag
                            }
                        }
                    } else if !tag.isDefaultPrimaryTag {
                        Button(L10n.t("Archive", appLanguage), role: .destructive) {
                            Task {
                                await runAndDismiss {
                                    await store.archiveTag(tag)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(tag.map { L10n.tagName($0, language: appLanguage) } ?? L10n.t("Tag", appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            L10n.t("Delete Tag Permanently?", appLanguage),
            isPresented: Binding(
                get: { tagPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        tagPendingDeletion = nil
                    }
                }
            ),
            presenting: tagPendingDeletion
        ) { tag in
            Button(L10n.t("Delete", appLanguage), role: .destructive) {
                Task {
                    await runAndDismiss {
                        await store.deleteTag(tag)
                    }
                    tagPendingDeletion = nil
                }
            }
            Button(L10n.t("Cancel", appLanguage), role: .cancel) {
                tagPendingDeletion = nil
            }
        } message: { tag in
            Text("\(L10n.t("This removes", appLanguage)) \"\(L10n.tagName(tag, language: appLanguage))\" \(L10n.t("from Tags, aliases, and moments. The name will be available again for a new Primary or Topic Tag.", appLanguage))")
        }
        .onAppear(perform: reset)
        .onChange(of: tagId) { _, _ in
            reset()
        }
    }

    private var tag: TimelineTag? {
        store.tags.first { $0.id == tagId }
    }

    private var activeTopicTargets: [TimelineTag] {
        store.activeTopicTags.filter { $0.id != tagId }
    }

    private func aliasesSection(_ tag: TimelineTag) -> some View {
        Section(L10n.t("Aliases", appLanguage)) {
            let aliases = store.aliasesByTagId[tag.id] ?? []
            if aliases.isEmpty {
                Text(L10n.t("No aliases", appLanguage))
                    .foregroundStyle(.secondary)
            }

            ForEach(aliases) { alias in
                HStack {
                    Text(alias.alias)
                    Spacer()
                    Button(role: .destructive) {
                        Task {
                            await store.deleteTagAlias(alias)
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack {
                TextField(L10n.t("Add alias", appLanguage), text: $aliasText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button(L10n.t("Add", appLanguage)) {
                    Task {
                        await addAlias(tag)
                    }
                }
                .disabled(isWorking || aliasText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func mergeSection(_ tag: TimelineTag) -> some View {
        Section(L10n.t("Merge", appLanguage)) {
            if activeTopicTargets.isEmpty {
                Text(L10n.t("No target topic tags", appLanguage))
                    .foregroundStyle(.secondary)
            } else {
                Picker(L10n.t("Merge Into", appLanguage), selection: $mergeTargetTagId) {
                    Text(L10n.t("Choose", appLanguage)).tag(nil as String?)
                    ForEach(activeTopicTargets) { target in
                        Text(L10n.tagName(target, language: appLanguage)).tag(Optional(target.id))
                    }
                }

                Button(L10n.t("Merge and Archive This Tag", appLanguage), role: .destructive) {
                    Task {
                        await merge(tag)
                    }
                }
                .disabled(isWorking || mergeTargetTagId == nil)
            }
        }
    }

    private func reset() {
        guard let tag else {
            return
        }

        name = tag.name
        colorHex = tag.colorHex ?? ""
        area = tag.resolvedArea
        mergeTargetTagId = nil
        aliasText = ""
    }

    private func canSave(_ tag: TimelineTag) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return false
        }

        guard tag.type != "primary" || colorHex.isEmpty || isValidTagColorHex(colorHex) else {
            return false
        }

        if tag.isDefaultPrimaryTag && trimmedName != tag.name {
            return false
        }

        return trimmedName != tag.name
            || (tag.type == "primary" && colorHex != (tag.colorHex ?? ""))
            || (tag.type == "topic" && area != tag.resolvedArea)
    }

    private func save(_ tag: TimelineTag) async {
        await run {
            await store.updateTag(
                tag,
                name: name,
                colorHex: colorHex.isEmpty ? nil : colorHex,
                areaId: tag.type == "topic" ? area.rawValue : nil
            )
        }
    }

    private func addAlias(_ tag: TimelineTag) async {
        let succeeded = await run {
            await store.createTagAlias(tag: tag, alias: aliasText)
        }

        if succeeded {
            aliasText = ""
        }
    }

    private func merge(_ tag: TimelineTag) async {
        guard let mergeTargetTagId,
              let target = store.tags.first(where: { $0.id == mergeTargetTagId }) else {
            return
        }

        await runAndDismiss {
            await store.mergeTopicTag(tag, into: target)
        }
    }

    @discardableResult
    private func run(_ action: () async -> Bool) async -> Bool {
        isWorking = true
        let succeeded = await action()
        isWorking = false
        return succeeded
    }

    private func runAndDismiss(_ action: () async -> Bool) async {
        if await run(action) {
            dismiss()
        }
    }
}

private struct AddTagSheet: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage

    let type: String
    let area: TopicTagArea?

    @State private var name = ""
    @State private var colorHex = "#DDEBD8"
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t(type == "primary" ? "Primary Tag" : "Topic Tag", appLanguage)) {
                    TextField(L10n.t("Name", appLanguage), text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if type == "primary" {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.t("Color", appLanguage))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TagColorPalette(selection: $colorHex)
                        }
                    } else if let area {
                        LabeledContent(L10n.t("Area", appLanguage), value: area.localizedTitle(language: appLanguage))
                    }

                    if let duplicateTag {
                        TagDuplicateNotice(tag: duplicateTag, requestedType: type)
                    }
                }
            }
            .navigationTitle(L10n.t("New Tag", appLanguage))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("Cancel", appLanguage)) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("Add", appLanguage)) {
                        Task {
                            await add()
                        }
                    }
                    .disabled(isWorking || trimmedName.isEmpty || !canAdd)
                }
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var duplicateTag: TimelineTag? {
        let normalizedName = LocalDatabase.normalizedTagName(trimmedName)
        guard !normalizedName.isEmpty else {
            return nil
        }

        return store.tags.first { $0.normalizedName == normalizedName }
    }

    private var canAdd: Bool {
        duplicateTag == nil && (type != "primary" || isValidTagColorHex(colorHex))
    }

    private func add() async {
        isWorking = true
        let tag = await store.createTag(
            type: type,
            name: name,
            colorHex: type == "primary" ? colorHex : nil,
            areaId: type == "topic" ? (area ?? TopicTagArea.inferredArea(forTopicName: name)).rawValue : nil
        )
        isWorking = false

        if tag != nil {
            dismiss()
        }
    }
}

private struct TagDuplicateNotice: View {
    @Environment(\.appLanguage) private var appLanguage

    let tag: TimelineTag
    let requestedType: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L10n.t("Tag already exists", appLanguage), systemImage: "exclamationmark.circle")
                .font(.subheadline.weight(.semibold))

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.orange)
        .padding(.vertical, 4)
    }

    private var message: String {
        let existingType = L10n.t(tag.type == "primary" ? "Primary Tag" : "Topic Tag", appLanguage)
        let requestedTypeTitle = L10n.t(requestedType == "primary" ? "Primary Tag" : "Topic Tag", appLanguage)

        if tag.isArchived {
            return "\"\(L10n.tagName(tag, language: appLanguage))\" \(L10n.t("is archived under", appLanguage)) \(existingType). \(L10n.t("Restore it from the Archived section instead of creating a duplicate.", appLanguage))"
        }

        if tag.type == requestedType {
            return "\"\(L10n.tagName(tag, language: appLanguage))\" \(L10n.t("is already in", appLanguage)) \(existingType)."
        }

        return "\"\(L10n.tagName(tag, language: appLanguage))\" \(L10n.t("already exists as a", appLanguage)) \(existingType). \(L10n.t("Tag names are shared across", appLanguage)) \(requestedTypeTitle) \(L10n.t("and", appLanguage)) \(existingType)."
    }
}

private struct BatchPrimaryTagColorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage

    let selectedCount: Int
    let onApply: (String) -> Void

    @State private var colorHex: String

    init(
        selectedCount: Int,
        initialColorHex: String,
        onApply: @escaping (String) -> Void
    ) {
        self.selectedCount = selectedCount
        self.onApply = onApply
        _colorHex = State(initialValue: initialColorHex.isEmpty ? "#EF4444" : initialColorHex)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t("Selected Primary Tags", appLanguage)) {
                    LabeledContent(L10n.t("Tags", appLanguage), value: "\(selectedCount)")
                    Text(L10n.t("This updates only the color of selected primary tags.", appLanguage))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(L10n.t("Color", appLanguage)) {
                    TagColorPalette(selection: $colorHex)
                }
            }
            .navigationTitle(L10n.t("Apply Color", appLanguage))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("Cancel", appLanguage)) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("Apply", appLanguage)) {
                        onApply(colorHex)
                        dismiss()
                    }
                    .disabled(!isValidTagColorHex(colorHex))
                }
            }
        }
    }
}

private let tagColorPresets: [String] = [
    // Soft defaults kept for the existing quiet tag style.
    "#D7E3F4",
    "#E3DCF4",
    "#DDEBD8",
    "#F4DEE4",
    "#E7E2DA",
    "#F0E4D4",
    // High-contrast standard colors.
    "#EF4444",
    "#F97316",
    "#F59E0B",
    "#EAB308",
    "#84CC16",
    "#22C55E",
    "#10B981",
    "#14B8A6",
    "#06B6D4",
    "#0EA5E9",
    "#3B82F6",
    "#2563EB",
    "#6366F1",
    "#8B5CF6",
    "#A855F7",
    "#D946EF",
    "#EC4899",
    "#F43F5E"
]

private struct TagColorPalette: View {
    @Environment(\.appLanguage) private var appLanguage

    @Binding var selection: String

    private let columns = Array(repeating: GridItem(.fixed(36), spacing: 12), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(tagColorPresets, id: \.self) { colorHex in
                    Button {
                        selection = colorHex
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(hex: colorHex) ?? Color.secondary.opacity(0.22))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary.opacity(isSelected(colorHex) ? 0.42 : 0.16), lineWidth: 1)
                                )

                            if isSelected(colorHex) {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("Tag color", appLanguage))
                    .accessibilityValue(L10n.t(isSelected(colorHex) ? "Selected" : "Not selected", appLanguage))
                }
            }

            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hex: selection) ?? Color.secondary.opacity(0.18))
                    .frame(width: 28, height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                    )

                TextField("#RRGGBB", text: hexBinding)
                    .font(.footnote.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.t("Custom HEX color", appLanguage))

            if !selection.isEmpty && !isValidTagColorHex(selection) {
                Text(L10n.t("Invalid HEX", appLanguage))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private var hexBinding: Binding<String> {
        Binding(
            get: { selection },
            set: { selection = normalizedTagColorHexInput($0) }
        )
    }

    private func isSelected(_ colorHex: String) -> Bool {
        selection.caseInsensitiveCompare(colorHex) == .orderedSame
    }
}

private func normalizedTagColorHexInput(_ rawValue: String) -> String {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return ""
    }

    let hexDigits = trimmed
        .uppercased()
        .filter { $0.isHexDigit }
        .prefix(6)

    guard !hexDigits.isEmpty else {
        return ""
    }

    return "#\(String(hexDigits))"
}

private func isValidTagColorHex(_ value: String) -> Bool {
    Color(hex: value) != nil
}
