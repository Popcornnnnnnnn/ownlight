import AVFoundation
import PhotosUI
import SwiftUI

struct CheckInsView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.appLanguage) private var appLanguage

    @State private var mode: CheckInsMode = .today
    @State private var isManagePresented = false
    @State private var itemEditorRoute: CheckInItemEditorRoute?
    @State private var itemInsightsRoute: CheckInItemInsightsRoute?
    @State private var contentItem: CheckInItem?
    @State private var detailRoute: CheckInEntryDetailRoute?
    @State private var undoEntry: CheckInEntry?
    @State private var historyFilterItemId: String?

    private var today: Date {
        Date()
    }

    private var activeItems: [CheckInItem] {
        store.checkInItems.filter { $0.deletedAt == nil && $0.archivedAt == nil }
    }

    private var historyFilterItems: [CheckInItem] {
        store.checkInItems
            .filter { $0.deletedAt == nil }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.name < rhs.name
                }

                return lhs.sortOrder < rhs.sortOrder
            }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !store.isReady {
                    ProgressView()
                } else if activeItems.isEmpty {
                    ContentUnavailableView {
                        Text(L10n.t("Create your first check-in.", appLanguage))
                    } actions: {
                        Button(L10n.t("Create", appLanguage)) {
                            itemEditorRoute = CheckInItemEditorRoute(itemId: nil)
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        CheckInTopDivider()
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                            .padding(.bottom, 2)

                        List {
                            if mode == .today {
                                todaySections
                            } else {
                                historySections
                            }
                        }
                        .listStyle(.plain)
                        .listRowSeparatorTint(CheckInListSeparators.rowTint)
                        .scrollContentBackground(.hidden)
                    }
                    .background(Color(.systemBackground))
                }
            }
            .navigationTitle(L10n.t("Check-ins", appLanguage))
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    TopActionButton(
                        title: mode.toggleTitle(language: appLanguage),
                        systemImage: mode.toggleSystemImage,
                        accessibilityIdentifier: "checkIns.modeToggleButton"
                    ) {
                        mode = mode == .today ? .history : .today
                    }

                    TopActionButton(
                        title: L10n.t("Manage check-ins", appLanguage),
                        systemImage: "slider.horizontal.3",
                        accessibilityIdentifier: "checkIns.manageButton"
                    ) {
                        isManagePresented = true
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let undoEntry {
                    CheckInUndoBar(entry: undoEntry) {
                        Task {
                            await store.deleteCheckInEntry(undoEntry)
                            self.undoEntry = nil
                        }
                    } dismiss: {
                        self.undoEntry = nil
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                }
            }
            .sheet(isPresented: $isManagePresented) {
                CheckInManageView(onEdit: { item in
                    itemEditorRoute = CheckInItemEditorRoute(itemId: item.id)
                }, onAdd: {
                    itemEditorRoute = CheckInItemEditorRoute(itemId: nil)
                })
            }
            .sheet(item: $itemEditorRoute) { route in
                CheckInItemEditorView(item: route.itemId.flatMap(store.checkInItem))
            }
            .sheet(item: $itemInsightsRoute) { route in
                if let item = store.checkInItem(id: route.itemId) {
                    CheckInItemInsightsView(item: item)
                }
            }
            .sheet(item: $contentItem) { item in
                CheckInContentEntryView(item: item)
            }
            .sheet(item: $detailRoute) { route in
                CheckInEntryDetailView(entryId: route.entryId)
            }
        }
    }

    @ViewBuilder
    private var todaySections: some View {
        let scheduled = activeItems.filter { $0.isScheduled(on: today) }
        let unscheduled = activeItems.filter { !$0.isScheduled(on: today) }
        let scheduledRows = scheduled.map { item in
            CheckInTodayRowModel(item: item, entries: store.entries(for: item, on: today))
        }
        let pendingRows = scheduledRows.filter { !$0.isCompletedOnce }
        let completedRows = scheduledRows.filter(\.isCompletedOnce)
        let unscheduledWithEntries = unscheduled
            .map { CheckInTodayRowModel(item: $0, entries: store.entries(for: $0, on: today)) }
            .filter { !$0.entries.isEmpty }
        let hiddenRows = unscheduled
            .filter { store.entries(for: $0, on: today).isEmpty }
            .map { CheckInTodayRowModel(item: $0, entries: []) }

        if !pendingRows.isEmpty {
            Section {
                ForEach(pendingRows) { row in
                    CheckInTodayRow(
                        row: row,
                        onTap: { handlePrimaryTap(row) },
                        onOpenInsights: { itemInsightsRoute = CheckInItemInsightsRoute(itemId: row.item.id) },
                        onAddContent: { contentItem = row.item }
                    )
                }
            }
        }

        if !completedRows.isEmpty || !unscheduledWithEntries.isEmpty {
            Section {
                ForEach(completedRows + unscheduledWithEntries) { row in
                    CheckInTodayRow(
                        row: row,
                        onTap: { handlePrimaryTap(row) },
                        onOpenInsights: { itemInsightsRoute = CheckInItemInsightsRoute(itemId: row.item.id) },
                        onAddContent: { contentItem = row.item }
                    )
                }
            }
        }

        if !hiddenRows.isEmpty {
            Section {
                DisclosureGroup(L10n.t("Not scheduled", appLanguage)) {
                    ForEach(hiddenRows) { row in
                        CheckInTodayRow(
                            row: row,
                            onTap: { handlePrimaryTap(row) },
                            onOpenInsights: { itemInsightsRoute = CheckInItemInsightsRoute(itemId: row.item.id) },
                            onAddContent: { contentItem = row.item }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var historySections: some View {
        let allEntries = store.checkInFeedEntries.sorted { lhs, rhs in
            if lhs.occurredAt == rhs.occurredAt {
                return lhs.id > rhs.id
            }

            return lhs.occurredAt > rhs.occurredAt
        }
        let entries = allEntries.filter { entry in
            historyFilterItemId == nil || entry.item.id == historyFilterItemId
        }

        if allEntries.isEmpty {
            Section {
                ContentUnavailableView(L10n.t("No check-ins yet", appLanguage), systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
        } else {
            Section {
                CheckInHistoryFilterBar(
                    items: historyFilterItems,
                    selectedItemId: $historyFilterItemId
                )
            }

            Section {
                CheckInHistorySummary(entries: entries)
            }

            if entries.isEmpty {
                Section {
                    ContentUnavailableView(
                        L10n.t("No check-ins for this item", appLanguage),
                        systemImage: selectedHistoryFilterSymbol
                    )
                    .frame(maxWidth: .infinity)
                }
            } else {
                Section {
                    ForEach(entries) { entry in
                        Button {
                            detailRoute = CheckInEntryDetailRoute(entryId: entry.id)
                        } label: {
                            CheckInHistoryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var selectedHistoryFilterSymbol: String {
        guard let historyFilterItemId,
              let item = store.checkInItem(id: historyFilterItemId) else {
            return "line.3.horizontal.decrease.circle"
        }

        return item.symbolName
    }

    private func handlePrimaryTap(_ row: CheckInTodayRowModel) {
        if row.item.recordMode == .oncePerDay, let entry = row.entries.first {
            detailRoute = CheckInEntryDetailRoute(entryId: entry.id)
            return
        }

        Task {
            if let entry = await store.recordCheckIn(item: row.item) {
                undoEntry = entry
            }
        }
    }
}

private enum CheckInListSeparators {
    static let rowTint = Color(uiColor: .separator).opacity(0.16)
    static let topTint = Color(uiColor: .separator).opacity(0.20)
}

private struct CheckInTopDivider: View {
    var body: some View {
        Rectangle()
            .fill(CheckInListSeparators.topTint)
            .frame(height: 0.5)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

private enum CheckInsMode {
    case today
    case history

    func toggleTitle(language: AppResolvedLanguage) -> String {
        switch self {
        case .today:
            return L10n.t("History", language)
        case .history:
            return L10n.t("Today", language)
        }
    }

    var toggleSystemImage: String {
        switch self {
        case .today:
            return "clock.arrow.circlepath"
        case .history:
            return "sun.max"
        }
    }
}

private struct CheckInTodayRowModel: Identifiable {
    let item: CheckInItem
    let entries: [CheckInEntry]

    var id: String {
        item.id
    }

    var isCompletedOnce: Bool {
        item.recordMode == .oncePerDay && !entries.isEmpty
    }
}

private struct CheckInTodayRow: View {
    @Environment(\.appLanguage) private var appLanguage

    let row: CheckInTodayRowModel
    let onTap: () -> Void
    let onOpenInsights: () -> Void
    let onAddContent: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                Image(systemName: leadingImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 36, height: 36)
                    .background(iconColor.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.isCompletedOnce ? L10n.t("Open check-in", appLanguage) : L10n.t("Check in", appLanguage))

            Button(action: onOpenInsights) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(row.item.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if row.item.recordMode == .multiplePerDay, !row.entries.isEmpty {
                            Text("\(row.entries.count)")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(iconColor)
                                .padding(.horizontal, 6)
                                .frame(height: 18)
                                .background(iconColor.opacity(0.12), in: Capsule())
                        }
                    }

                    if let latest = row.entries.first {
                        Text(subtitle(for: latest))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(row.item.defaultShowInTimeline ? L10n.t("Shows in Timeline", appLanguage) : L10n.t("Private to check-ins", appLanguage))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button(action: onAddContent) {
                Image(systemName: "ellipsis.bubble")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("Add content", appLanguage))
        }
        .contentShape(Rectangle())
    }

    private var leadingImage: String {
        row.isCompletedOnce ? "checkmark.circle.fill" : row.item.symbolName
    }

    private var iconColor: Color {
        Color(hex: row.item.colorHex) ?? .accentColor
    }

    private func subtitle(for entry: CheckInEntry) -> String {
        let time = DateFormatter.checkInTime.string(from: entry.occurredAt)
        if entry.hasNote {
            return "\(time) · \(entry.note)"
        }

        return time
    }
}

struct CheckInTimelineRow: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.appLanguage) private var appLanguage

    let checkIn: CheckInFeedEntry
    var showsDate = true
    var showTagsInTimeline = true
    let onOpenDetail: () -> Void

    var body: some View {
        Button(action: onOpenDetail) {
            VStack(alignment: .leading, spacing: 9) {
                if showsDate {
                    HStack(spacing: 8) {
                        Text(MomentDateFormatter.timelineLabel(for: checkIn.occurredAt, language: appLanguage))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if showTagsInTimeline, let tag = checkIn.tag {
                            TimelineTagChip(tag: tag, compact: true)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: checkIn.item.symbolName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(iconColor)
                        .frame(width: 30, height: 30)
                        .background(iconColor.opacity(0.14), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(checkIn.item.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)

                        if checkIn.entry.hasNote {
                            Text(checkIn.entry.note)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(5)
                        }

                        let imageMedia = checkIn.media.filter(\.isImage)
                        if !imageMedia.isEmpty {
                            LazyVGrid(columns: imageGridColumns, alignment: .leading, spacing: 6) {
                                ForEach(imageMedia) { media in
                                    CheckInImageThumbnail(media: media)
                                        .frame(width: 58, height: 58)
                                }
                            }
                            .padding(.top, checkIn.entry.hasNote ? 4 : 2)
                        }

                        if let audio = checkIn.media.first(where: \.isAudio) {
                            CheckInAudioAttachmentView(media: audio)
                                .padding(.top, checkIn.entry.hasNote ? 4 : 2)

                            if let summary = displayedSummary(for: audio) {
                                CheckInSummaryCard(summary: summary, compact: true)
                                    .padding(.top, 6)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var iconColor: Color {
        Color(hex: checkIn.item.colorHex) ?? .accentColor
    }

    private var imageGridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 58, maximum: 72), spacing: 6)
        ]
    }

    private func displayedSummary(for media: CheckInMedia) -> CheckInAISummary? {
        guard store.showCheckInSummaries else {
            return nil
        }

        guard let summary = store.checkInAISummary(mediaId: media.id), summary.isReady, summary.hasDisplayContent else {
            return nil
        }

        return summary
    }
}

private struct CheckInUndoBar: View {
    @Environment(\.appLanguage) private var appLanguage

    let entry: CheckInEntry
    let undo: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(L10n.t("Checked in", appLanguage))
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
            Button(L10n.t("Undo", appLanguage), action: undo)
                .font(.subheadline.weight(.semibold))
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    }
}

private struct CheckInManageView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage

    let onEdit: (CheckInItem) -> Void
    let onAdd: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.checkInItems.filter { $0.deletedAt == nil }) { item in
                        Button {
                            dismiss()
                            onEdit(item)
                        } label: {
                            CheckInManageRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                        .accessibilityLabel("\(L10n.t("Edit check-in", appLanguage)): \(item.name)")
                    }
                }
            }
            .navigationTitle(L10n.t("Manage", appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .listSectionSpacing(.compact)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("Done", appLanguage)) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    TopActionButton(
                        title: L10n.t("New check-in", appLanguage),
                        systemImage: "plus",
                        accessibilityIdentifier: "checkIns.manage.newButton"
                    ) {
                        dismiss()
                        onAdd()
                    }
                }
            }
        }
    }
}

private struct CheckInManageRow: View {
    @Environment(\.appLanguage) private var appLanguage

    let item: CheckInItem

    var body: some View {
        HStack(spacing: 11) {
            SettingsHomeIcon(systemImage: item.symbolName, color: iconColor)

            Text(item.name)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.86)

            Spacer(minLength: 0)

            Text(statusTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
    }

    private var iconColor: Color {
        Color(hex: item.colorHex) ?? .accentColor
    }

    private var statusTitle: String {
        if item.isArchived {
            return L10n.t("Archived", appLanguage)
        }

        return item.recordMode.title(language: appLanguage)
    }
}

private struct CheckInItemEditorRoute: Identifiable {
    let itemId: String?

    var id: String {
        itemId ?? "new"
    }
}

private struct CheckInItemInsightsRoute: Identifiable {
    let itemId: String

    var id: String {
        itemId
    }
}

private struct CheckInItemEditorView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage

    let item: CheckInItem?

    @State private var name: String
    @State private var symbolName: String
    @State private var colorHex: String
    @State private var recordMode: CheckInRecordMode
    @State private var timeVisualization: CheckInTimeVisualization
    @State private var dayStartHour: Int
    @State private var activeWeekdays: Set<Int>
    @State private var defaultShowInTimeline: Bool
    @State private var tagId: String
    @State private var isSaving = false
    @State private var isDeleteConfirmationPresented = false
    @State private var selectedIconCategoryId: String
    @State private var iconSearchText = ""

    init(item: CheckInItem?) {
        self.item = item
        let initialSymbolName = item?.symbolName ?? CheckInSymbolValidator.fallbackSymbolName
        _name = State(initialValue: item?.name ?? "")
        _symbolName = State(initialValue: initialSymbolName)
        _colorHex = State(initialValue: item?.colorHex ?? "#61B88D")
        _recordMode = State(initialValue: item?.recordMode ?? .oncePerDay)
        _timeVisualization = State(initialValue: item?.timeVisualization ?? .none)
        _dayStartHour = State(initialValue: item?.dayStartHour ?? 0)
        _activeWeekdays = State(initialValue: Set(item?.activeWeekdays ?? [1, 2, 3, 4, 5, 6, 7]))
        _defaultShowInTimeline = State(initialValue: item?.defaultShowInTimeline ?? false)
        _tagId = State(initialValue: item?.tagId ?? "")
        _selectedIconCategoryId = State(initialValue: CheckInIconCatalog.categoryId(containing: initialSymbolName))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.t("Name", appLanguage), text: $name)
                    Picker(L10n.t("Mode", appLanguage), selection: $recordMode) {
                        ForEach(CheckInRecordMode.allCases) { mode in
                            Label(mode.title(language: appLanguage), systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }
                    .onChange(of: recordMode) { _, newValue in
                        if newValue == .multiplePerDay, timeVisualization == .timeLine {
                            timeVisualization = .timeHeatmap
                        }
                        if newValue == .multiplePerDay {
                            dayStartHour = 0
                        }
                    }

                    Picker(L10n.t("Time visualization", appLanguage), selection: $timeVisualization) {
                        ForEach(availableTimeVisualizations) { mode in
                            Label(mode.title(language: appLanguage), systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }

                    if recordMode == .oncePerDay {
                        Picker(L10n.t("Daily reset", appLanguage), selection: $dayStartHour) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(Self.resetLabel(for: hour)).tag(hour)
                            }
                        }
                    }
                }

                Section(L10n.t("Icon", appLanguage)) {
                    CheckInSelectedIconPreview(symbolName: symbolName, colorHex: colorHex, language: appLanguage)

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField(L10n.t("Search icons", appLanguage), text: $iconSearchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !iconSearchText.isEmpty {
                            Button {
                                iconSearchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.t("Clear", appLanguage))
                        }
                    }

                    Picker(L10n.t("Category", appLanguage), selection: $selectedIconCategoryId) {
                        Text(L10n.t("All icons", appLanguage)).tag(CheckInIconCategory.allId)
                        ForEach(CheckInIconCatalog.categories) { category in
                            Text(L10n.t(category.title, appLanguage)).tag(category.id)
                        }
                    }
                    .pickerStyle(.menu)

                    CheckInIconPresetGrid(
                        selection: $symbolName,
                        presets: visibleIconPresets,
                        language: appLanguage
                    )

                    if visibleIconPresets.isEmpty {
                        Text(L10n.t("No matching icons", appLanguage))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }

                    DisclosureGroup(L10n.t("Advanced", appLanguage)) {
                        TextField(L10n.t("SF Symbol name", appLanguage), text: $symbolName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        if !isIconSymbolValid {
                            Label(
                                L10n.t("Enter a valid SF Symbol name.", appLanguage),
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }
                    }
                }

                Section(L10n.t("Color", appLanguage)) {
                    CheckInColorPresetGrid(selection: $colorHex)
                    TextField("HEX", text: $colorHex)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: colorHex) { _, newValue in
                            colorHex = normalizedHexInput(newValue)
                        }
                }

                Section(L10n.t("Schedule", appLanguage)) {
                    WeekdayToggleGrid(selection: $activeWeekdays)
                }

                Section {
                    Toggle(L10n.t("Show in Timeline by default", appLanguage), isOn: $defaultShowInTimeline)
                    Picker(L10n.t("Tag", appLanguage), selection: $tagId) {
                        Text(L10n.t("None", appLanguage)).tag("")
                        ForEach(store.activeTopicTags) { tag in
                            Text(L10n.tagName(tag, language: appLanguage)).tag(tag.id)
                        }
                    }
                }

                if item != nil {
                    Section {
                        Button(L10n.t("Archive", appLanguage)) {
                            if let item {
                                Task {
                                    await store.archiveCheckInItem(item)
                                    dismiss()
                                }
                            }
                        }

                        Button(L10n.t("Delete", appLanguage), role: .destructive) {
                            isDeleteConfirmationPresented = true
                        }
                    }
                }
            }
            .navigationTitle(item == nil ? L10n.t("New check-in", appLanguage) : L10n.t("Edit check-in", appLanguage))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("Cancel", appLanguage)) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("Save", appLanguage)) {
                        save()
                    }
                    .disabled(isSaving || !canSave)
                }
            }
            .alert(L10n.t("Delete check-in?", appLanguage), isPresented: $isDeleteConfirmationPresented) {
                Button(L10n.t("Cancel", appLanguage), role: .cancel) {}
                Button(L10n.t("Delete", appLanguage), role: .destructive) {
                    if let item {
                        Task {
                            await store.deleteCheckInItem(item)
                            dismiss()
                        }
                    }
                }
            } message: {
                Text(L10n.t("This also removes its check-in history.", appLanguage))
            }
        }
    }

    private var visibleIconPresets: [CheckInIconPreset] {
        CheckInIconCatalog.presets(categoryId: selectedIconCategoryId, query: iconSearchText)
    }

    private var isIconSymbolValid: Bool {
        CheckInSymbolValidator.isValid(symbolName)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isIconSymbolValid
    }

    private var availableTimeVisualizations: [CheckInTimeVisualization] {
        CheckInTimeVisualization.allCases.filter { mode in
            !(recordMode == .multiplePerDay && mode == .timeLine)
        }
    }

    private var normalizedTimeVisualization: CheckInTimeVisualization {
        if recordMode == .multiplePerDay, timeVisualization == .timeLine {
            return .timeHeatmap
        }

        return timeVisualization
    }

    private var normalizedDayStartHour: Int {
        recordMode == .oncePerDay ? CheckInDayBoundary.normalizedHour(dayStartHour) : 0
    }

    private func save() {
        let normalizedSymbolName = CheckInSymbolValidator.normalized(symbolName)
        guard normalizedSymbolName == symbolName.trimmingCharacters(in: .whitespacesAndNewlines) else {
            symbolName = normalizedSymbolName
            return
        }

        isSaving = true
        Task {
            let didSave: Bool
            if var item {
                item.name = name
                item.symbolName = normalizedSymbolName
                item.colorHex = colorHex
                item.recordMode = recordMode
                item.timeVisualization = normalizedTimeVisualization
                item.dayStartHour = normalizedDayStartHour
                item.activeWeekdays = Array(activeWeekdays)
                item.defaultShowInTimeline = defaultShowInTimeline
                item.tagId = tagId.isEmpty ? nil : tagId
                didSave = await store.updateCheckInItem(item)
            } else {
                didSave = await store.createCheckInItem(
                    name: name,
                    symbolName: normalizedSymbolName,
                    colorHex: colorHex,
                    recordMode: recordMode,
                    timeVisualization: normalizedTimeVisualization,
                    dayStartHour: normalizedDayStartHour,
                    activeWeekdays: Array(activeWeekdays),
                    defaultShowInTimeline: defaultShowInTimeline,
                    tagId: tagId.isEmpty ? nil : tagId
                )
            }
            isSaving = false
            if didSave {
                dismiss()
            }
        }
    }

    private func normalizedHexInput(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
            trimmed = "#\(trimmed)"
        }
        if trimmed.count > 7 {
            trimmed = String(trimmed.prefix(7))
        }
        return trimmed
    }

    private static func resetLabel(for hour: Int) -> String {
        String(format: "%02d:00", CheckInDayBoundary.normalizedHour(hour))
    }
}

private struct CheckInSelectedIconPreview: View {
    let symbolName: String
    let colorHex: String
    let language: AppResolvedLanguage

    private var trimmedSymbolName: String {
        symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        CheckInSymbolValidator.isValid(symbolName)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isValid ? trimmedSymbolName : "exclamationmark.triangle")
                .font(.title3.weight(.semibold))
                .frame(width: 38, height: 38)
                .foregroundStyle(isValid ? Color(hex: colorHex) ?? .accentColor : .orange)
                .background(
                    (isValid ? Color(hex: colorHex) ?? .accentColor : .orange).opacity(0.14),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(isValid ? L10n.t("Selected icon", language) : L10n.t("Invalid icon", language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(isValid ? trimmedSymbolName : L10n.t("Choose a preset or enter a valid SF Symbol name.", language))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CheckInIconPresetGrid: View {
    @Binding var selection: String
    let presets: [CheckInIconPreset]
    let language: AppResolvedLanguage

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(presets) { preset in
                Button {
                    selection = preset.symbolName
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: preset.symbolName)
                            .font(.body.weight(.semibold))
                        Text(L10n.t(preset.title, language))
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .foregroundStyle(selection == preset.symbolName ? Color.accentColor : Color.secondary)
                    .background(
                        selection == preset.symbolName ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t(preset.title, language))
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CheckInColorPreset: Identifiable {
    let hex: String

    var id: String {
        hex
    }

    static let all: [CheckInColorPreset] = [
        CheckInColorPreset(hex: "#D94F45"),
        CheckInColorPreset(hex: "#E07A2F"),
        CheckInColorPreset(hex: "#F2B705"),
        CheckInColorPreset(hex: "#2EAD67"),
        CheckInColorPreset(hex: "#008C7A"),
        CheckInColorPreset(hex: "#2F80ED"),
        CheckInColorPreset(hex: "#7B61FF"),
        CheckInColorPreset(hex: "#C23883"),
        CheckInColorPreset(hex: "#5C6670"),
        CheckInColorPreset(hex: "#111827")
    ]
}

private struct CheckInColorPresetGrid: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
            ForEach(CheckInColorPreset.all) { preset in
                Button {
                    selection = preset.hex
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(hex: preset.hex) ?? .accentColor)
                            .frame(width: 32, height: 32)
                        if selection.uppercased() == preset.hex {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        selection.uppercased() == preset.hex ? Color(hex: preset.hex)?.opacity(0.14) ?? Color.accentColor.opacity(0.14) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct WeekdayToggleGrid: View {
    @Binding var selection: Set<Int>

    private var symbols: [(Int, String)] {
        let formatter = DateFormatter()
        let names = formatter.shortStandaloneWeekdaySymbols ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return names.enumerated().map { index, name in
            (index + 1, name)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(symbols, id: \.0) { weekday, title in
                Button {
                    if selection.contains(weekday), selection.count > 1 {
                        selection.remove(weekday)
                    } else {
                        selection.insert(weekday)
                    }
                } label: {
                    Text(String(title.prefix(1)))
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(selection.contains(weekday) ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08), in: Capsule())
                        .foregroundStyle(selection.contains(weekday) ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct CheckInContentEntryView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage

    let item: CheckInItem

    @State private var note = ""
    @State private var showInTimeline: Bool
    @State private var occurredAt = Date()
    @State private var isSaving = false
    @State private var capturedImageData: Data?
    @State private var audioDraft: PreparedMomentMedia?
    @State private var isCameraPresented = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var mediaError: String?
    @StateObject private var audioRecorder = AudioRecorderController()

    init(item: CheckInItem) {
        self.item = item
        _showInTimeline = State(initialValue: item.defaultShowInTimeline)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(L10n.t("Time", appLanguage), selection: $occurredAt, in: ...Date())
                        .environment(\.locale, MomentDateFormatter.twentyFourHourLocale(for: appLanguage))
                    Toggle(L10n.t("Show in Timeline", appLanguage), isOn: $showInTimeline)
                }

                Section(L10n.t("Note", appLanguage)) {
                    PlainTextListEditor(text: $note)
                        .frame(minHeight: 110)
                }

                Section(L10n.t("Media", appLanguage)) {
                    if let capturedImageData, let image = UIImage(data: capturedImageData) {
                        CheckInCapturedImagePreview(image: image) {
                            self.capturedImageData = nil
                        }
                    }

                    if audioRecorder.isRecording {
                        CheckInRecordingStatusView(audioRecorder: audioRecorder)
                    }

                    if let audioDraft {
                        CheckInDraftAudioPreview(media: audioDraft) {
                            audioRecorder.discard()
                            self.audioDraft = nil
                        }
                    }

                    PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 1, matching: .images) {
                        Label(L10n.t("Add Photos", appLanguage), systemImage: "photo.on.rectangle.angled")
                    }
                    .disabled(audioDraft != nil || audioRecorder.isRecording)

                    Button {
                        isCameraPresented = true
                    } label: {
                        Label(L10n.t("Use Camera", appLanguage), systemImage: "camera")
                    }
                    .disabled(!CameraPicker.isAvailable || audioDraft != nil || audioRecorder.isRecording)

                    Button {
                        toggleRecording()
                    } label: {
                        Label(
                            L10n.t(audioRecorder.isRecording ? "Stop Recording" : "Record Audio", appLanguage),
                            systemImage: audioRecorder.isRecording ? "stop.circle" : "mic"
                        )
                    }
                    .disabled(capturedImageData != nil && !audioRecorder.isRecording)
                }
            }
            .navigationTitle(item.name)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("Cancel", appLanguage)) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("Save", appLanguage)) {
                        save()
                    }
                    .disabled(isSaving || audioRecorder.isRecording)
                }
            }
            .sheet(isPresented: $isCameraPresented) {
                CameraPicker { data in
                    capturedImageData = data
                    audioRecorder.discard()
                    audioDraft = nil
                }
            }
            .onChange(of: selectedPhotoItems) { _, items in
                guard !items.isEmpty else {
                    return
                }

                Task {
                    capturedImageData = await loadSelectedPhoto(from: items)
                    audioRecorder.discard()
                    audioDraft = nil
                    selectedPhotoItems = []
                }
            }
            .alert(L10n.t("Media unavailable", appLanguage), isPresented: mediaErrorBinding) {
                Button(L10n.t("OK", appLanguage), role: .cancel) {}
            } message: {
                Text(mediaError ?? "")
            }
        }
    }

    private var mediaErrorBinding: Binding<Bool> {
        Binding(
            get: { mediaError != nil || audioRecorder.errorMessage != nil },
            set: { _ in
                mediaError = nil
                audioRecorder.errorMessage = nil
            }
        )
    }

    private func loadSelectedPhoto(from items: [PhotosPickerItem]) async -> Data? {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                return data
            }
        }

        return nil
    }

    private func toggleRecording() {
        if audioRecorder.isRecording {
            audioRecorder.stop()
            guard let url = audioRecorder.recordedURL else {
                return
            }

            Task {
                do {
                    audioDraft = try await AudioMediaInspector.preparedAudio(from: url)
                    capturedImageData = nil
                } catch {
                    mediaError = error.localizedDescription
                }
            }
            return
        }

        capturedImageData = nil
        audioDraft = nil
        audioRecorder.start()
    }

    private func save() {
        isSaving = true
        Task {
            if await store.recordCheckIn(
                item: item,
                note: note,
                occurredAt: occurredAt,
                showInTimeline: showInTimeline,
                imageData: capturedImageData,
                audioDraft: audioDraft
            ) != nil {
                dismiss()
            }
            isSaving = false
        }
    }
}
