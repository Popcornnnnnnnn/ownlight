import Foundation

enum MomentTextMarkdown {
    static let aiTitleMaxCharacters = 40

    struct RenderingOptions: Equatable {
        var mathRenderingEnabled: Bool
        var remoteImagesEnabled: Bool
        var rawHTMLRenderingEnabled: Bool

        static var appSettings: RenderingOptions {
            RenderingOptions(
                mathRenderingEnabled: AppSettings.markdownMathRenderingEnabled,
                remoteImagesEnabled: AppSettings.markdownRemoteImagesEnabled,
                rawHTMLRenderingEnabled: AppSettings.markdownRawHTMLRenderingEnabled
            )
        }
    }

    enum LineKind: Equatable {
        case heading(level: Int, text: String)
        case link(URL)
        case paragraph(String)
        case blank
    }

    struct Line: Equatable {
        let kind: LineKind
    }

    enum RenderedLineKind: Equatable {
        case heading(level: Int, text: String)
        case link(URL)
        case markdown(String)
        case unorderedList(indentLevel: Int, text: String)
        case orderedList(indentLevel: Int, marker: String, text: String)
        case taskList(indentLevel: Int, marker: String, text: String)
        case quote(String)
        case codeFence(String)
        case codeLine(String)
        case blank
    }

    struct RenderedLine: Equatable {
        let kind: RenderedLineKind
    }

    enum InlineSpan: Equatable {
        case text(String)
        case inlineMath(String)
    }

    struct ListItem: Equatable {
        let indentLevel: Int
        let checked: Bool?
        let marker: String?
        let text: String
        let sourceLineIndex: Int?

        init(
            indentLevel: Int,
            checked: Bool? = nil,
            marker: String? = nil,
            text: String,
            sourceLineIndex: Int? = nil
        ) {
            self.indentLevel = indentLevel
            self.checked = checked
            self.marker = marker
            self.text = text
            self.sourceLineIndex = sourceLineIndex
        }
    }

    enum RenderedBlockKind: Equatable {
        case heading(level: Int, text: String)
        case paragraph([InlineSpan])
        case link(URL)
        case image(alt: String, source: String)
        case unorderedList([ListItem])
        case orderedList([ListItem])
        case taskList([ListItem])
        case quote([InlineSpan])
        case codeBlock(language: String?, code: String)
        case table(headers: [String], rows: [[String]])
        case mathBlock(String)
        case htmlBlock(markdown: String)
        case blank
    }

    struct RenderedBlock: Equatable {
        let kind: RenderedBlockKind
    }

    enum LineStyle: Equatable {
        case heading(level: Int)
    }

    struct TextEdit: Equatable {
        let replacementRange: NSRange
        let replacementText: String
        let selectedRange: NSRange
    }

    static func parse(_ text: String) -> [Line] {
        text.components(separatedBy: .newlines).map { rawLine in
            if let heading = heading(in: rawLine) {
                return Line(kind: .heading(level: heading.level, text: heading.text))
            }

            if let url = standaloneURL(in: rawLine) {
                return Line(kind: .link(url))
            }

            if rawLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return Line(kind: .blank)
            }

            return Line(kind: .paragraph(rawLine))
        }
    }

    static func hasLeadingTitle(_ text: String) -> Bool {
        for rawLine in text.components(separatedBy: .newlines) {
            if rawLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }

            return heading(in: rawLine) != nil
        }

        return false
    }

    static func searchableText(_ text: String) -> String {
        renderingSource(
            text,
            options: .init(
                mathRenderingEnabled: false,
                remoteImagesEnabled: false,
                rawHTMLRenderingEnabled: false
            )
        )
        .components(separatedBy: .newlines)
        .map(searchableLine)
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    static func renderingSource(_ text: String, options: RenderingOptions = .appSettings) -> String {
        var source = text

        if options.mathRenderingEnabled {
            source = stylingMathSource(in: source)
        }

        if !options.remoteImagesEnabled {
            source = replacingImageSyntaxWithLinks(in: source)
        }

        if !options.rawHTMLRenderingEnabled {
            source = escapingRawHTML(in: source)
        }

        return source
    }

    static func renderableLines(
        for text: String,
        options: RenderingOptions = .appSettings
    ) -> [RenderedLine] {
        let source = renderingSource(text, options: options)
        var isInsideCodeBlock = false

        return source.components(separatedBy: .newlines).map { rawLine in
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                return RenderedLine(kind: .blank)
            }

            if isCodeFence(trimmed) {
                isInsideCodeBlock.toggle()
                return RenderedLine(kind: .codeFence(trimmed))
            }

            if isInsideCodeBlock {
                return RenderedLine(kind: .codeLine(rawLine))
            }

            if let heading = renderingHeading(in: rawLine) {
                return RenderedLine(kind: .heading(level: heading.level, text: heading.text))
            }

            if let url = standaloneURL(in: rawLine) {
                return RenderedLine(kind: .link(url))
            }

            if let taskListItem = taskListItem(in: rawLine) {
                return RenderedLine(
                    kind: .taskList(
                        indentLevel: taskListItem.indentLevel,
                        marker: taskListItem.checked ? "[x]" : "[ ]",
                        text: taskListItem.text
                    )
                )
            }

            if let orderedListItem = orderedListItem(in: rawLine) {
                return RenderedLine(
                    kind: .orderedList(
                        indentLevel: orderedListItem.indentLevel,
                        marker: orderedListItem.marker,
                        text: orderedListItem.text
                    )
                )
            }

            if let unorderedListItem = unorderedListItem(in: rawLine) {
                return RenderedLine(
                    kind: .unorderedList(
                        indentLevel: unorderedListItem.indentLevel,
                        text: unorderedListItem.text
                    )
                )
            }

            if let quote = quoteLine(in: rawLine) {
                return RenderedLine(kind: .quote(quote))
            }

            return RenderedLine(kind: .markdown(rawLine))
        }
    }

    static func renderableBlocks(
        for text: String,
        options: RenderingOptions = .appSettings
    ) -> [RenderedBlock] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [RenderedBlock] = []
        var index = 0

        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                blocks.append(RenderedBlock(kind: .blank))
                index += 1
                continue
            }

            if let codeBlock = codeBlock(in: lines, startingAt: index) {
                blocks.append(
                    RenderedBlock(
                        kind: .codeBlock(
                            language: codeBlock.language,
                            code: codeBlock.code
                        )
                    )
                )
                index = codeBlock.nextIndex
                continue
            }

            if options.mathRenderingEnabled,
               let mathBlock = mathBlock(in: lines, startingAt: index) {
                blocks.append(RenderedBlock(kind: .mathBlock(mathBlock.formula)))
                index = mathBlock.nextIndex
                continue
            }

            if let table = tableBlock(in: lines, startingAt: index) {
                blocks.append(RenderedBlock(kind: .table(headers: table.headers, rows: table.rows)))
                index = table.nextIndex
                continue
            }

            if let heading = renderingHeading(in: rawLine) {
                blocks.append(RenderedBlock(kind: .heading(level: heading.level, text: heading.text)))
                index += 1
                continue
            }

            if let image = imageSyntax(in: rawLine) {
                blocks.append(RenderedBlock(kind: .image(alt: image.alt, source: image.source)))
                index += 1
                continue
            }

            if let url = standaloneURL(in: rawLine) {
                blocks.append(RenderedBlock(kind: .link(url)))
                index += 1
                continue
            }

            if let html = htmlBlock(in: lines, startingAt: index, options: options) {
                blocks.append(RenderedBlock(kind: .htmlBlock(markdown: html.markdown)))
                index = html.nextIndex
                continue
            }

            if let taskList = listBlock(in: lines, startingAt: index, kind: .task) {
                blocks.append(RenderedBlock(kind: .taskList(taskList.items)))
                index = taskList.nextIndex
                continue
            }

            if let orderedList = listBlock(in: lines, startingAt: index, kind: .ordered) {
                blocks.append(RenderedBlock(kind: .orderedList(orderedList.items)))
                index = orderedList.nextIndex
                continue
            }

            if let unorderedList = listBlock(in: lines, startingAt: index, kind: .unordered) {
                blocks.append(RenderedBlock(kind: .unorderedList(unorderedList.items)))
                index = unorderedList.nextIndex
                continue
            }

            if let quote = quoteLine(in: rawLine) {
                blocks.append(RenderedBlock(kind: .quote(inlineSpans(in: quote, options: options))))
                index += 1
                continue
            }

            blocks.append(RenderedBlock(kind: .paragraph(inlineSpans(in: rawLine, options: options))))
            index += 1
        }

        return compactBlankBlocks(blocks)
    }

    static func attributedString(
        for text: String,
        options: RenderingOptions = .appSettings
    ) -> AttributedString? {
        try? AttributedString(
            markdown: renderingSource(text, options: options),
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )
    }

    static func inlineAttributedString(
        for text: String,
        options: RenderingOptions = .appSettings
    ) -> AttributedString? {
        try? AttributedString(
            markdown: renderingSource(text, options: options),
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )
    }

    static func normalizedAITitle(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let withoutMarkdownMarker = value.replacingOccurrences(
            of: #"^\s*#{1,6}\s*"#,
            with: "",
            options: .regularExpression
        )
        let normalized = withoutMarkdownMarker
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !normalized.isEmpty,
              normalized.count <= aiTitleMaxCharacters else {
            return nil
        }

        return normalized
    }

    static func insertingAITitle(_ title: String, into text: String) -> String {
        let heading = "## \(title)"
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return heading
        }

        return "\(heading)\n\n\(text)"
    }

    static func togglingLineStyle(
        _ style: LineStyle,
        in text: String,
        selectedRange: NSRange
    ) -> TextEdit? {
        guard selectedRange.length >= 0,
              isValid(range: selectedRange, in: text),
              let line = currentLine(in: text, selectedRange: selectedRange) else {
            return nil
        }

        let currentLine = line.text
        let selectedOffset = max(0, selectedRange.location - line.contentRange.location)

        switch style {
        case .heading(let level):
            return headingToggleEdit(
                level: level,
                currentLine: currentLine,
                lineRange: line.contentRange,
                selectedOffset: selectedOffset
            )
        }
    }

    static func togglingTaskListItem(in text: String, sourceLineIndex: Int) -> String? {
        guard sourceLineIndex >= 0 else {
            return nil
        }

        var lines = text.components(separatedBy: .newlines)
        guard lines.indices.contains(sourceLineIndex),
              let toggledLine = toggledTaskListLine(lines[sourceLineIndex]) else {
            return nil
        }

        lines[sourceLineIndex] = toggledLine
        return lines.joined(separator: "\n")
    }

    private static func heading(in line: String) -> (level: Int, text: String)? {
        let prefix: String
        let level: Int

        if line.hasPrefix("## ") {
            prefix = "## "
            level = 2
        } else if line.hasPrefix("# ") {
            prefix = "# "
            level = 1
        } else {
            return nil
        }

        let text = String(line.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            return nil
        }

        return (level, text)
    }

    private static func renderingHeading(in line: String) -> (level: Int, text: String)? {
        let trimmedLeading = line.drop { $0 == " " || $0 == "\t" }
        let markerCount = trimmedLeading.prefix { $0 == "#" }.count
        guard (1...6).contains(markerCount) else {
            return nil
        }

        let afterMarkers = trimmedLeading.dropFirst(markerCount)
        guard afterMarkers.first == " " else {
            return nil
        }

        let text = String(afterMarkers.dropFirst())
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"\s+#{1,6}$"#,
                with: "",
                options: .regularExpression
            )

        guard !text.isEmpty else {
            return nil
        }

        return (min(markerCount, 2), text)
    }

    private enum ListBlockKind {
        case unordered
        case ordered
        case task
    }

    private static func codeBlock(
        in lines: [String],
        startingAt startIndex: Int
    ) -> (language: String?, code: String, nextIndex: Int)? {
        let opening = lines[startIndex].trimmingCharacters(in: .whitespaces)
        guard isCodeFence(opening) else {
            return nil
        }

        let fence = String(opening.prefix(3))
        let language = String(opening.dropFirst(3))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var codeLines: [String] = []
        var index = startIndex + 1

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(fence) {
                return (
                    language: language.isEmpty ? nil : language,
                    code: codeLines.joined(separator: "\n"),
                    nextIndex: index + 1
                )
            }
            codeLines.append(lines[index])
            index += 1
        }

        return (
            language: language.isEmpty ? nil : language,
            code: codeLines.joined(separator: "\n"),
            nextIndex: lines.count
        )
    }

    private static func mathBlock(
        in lines: [String],
        startingAt startIndex: Int
    ) -> (formula: String, nextIndex: Int)? {
        guard lines[startIndex].trimmingCharacters(in: .whitespaces) == "$$" else {
            return nil
        }

        var formulaLines: [String] = []
        var index = startIndex + 1
        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces) == "$$" {
                return (
                    formula: formulaLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                    nextIndex: index + 1
                )
            }
            formulaLines.append(lines[index])
            index += 1
        }

        return nil
    }

    private static func tableBlock(
        in lines: [String],
        startingAt startIndex: Int
    ) -> (headers: [String], rows: [[String]], nextIndex: Int)? {
        guard startIndex + 1 < lines.count else {
            return nil
        }

        let header = tableCells(in: lines[startIndex])
        let delimiter = tableCells(in: lines[startIndex + 1])
        guard header.count >= 2,
              delimiter.count == header.count,
              delimiter.allSatisfy(isTableDelimiterCell) else {
            return nil
        }

        var rows: [[String]] = []
        var index = startIndex + 2
        while index < lines.count {
            let cells = tableCells(in: lines[index])
            guard cells.count >= 2 else {
                break
            }

            if cells.count == header.count {
                rows.append(cells)
            } else if cells.count < header.count {
                rows.append(cells + Array(repeating: "", count: header.count - cells.count))
            } else {
                rows.append(Array(cells.prefix(header.count)))
            }
            index += 1
        }

        return (headers: header, rows: rows, nextIndex: index)
    }

    private static func tableCells(in line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else {
            return []
        }

        var body = trimmed
        if body.hasPrefix("|") {
            body.removeFirst()
        }
        if body.hasSuffix("|") {
            body.removeLast()
        }

        return body
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func isTableDelimiterCell(_ value: String) -> Bool {
        value.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
    }

    private static func imageSyntax(in line: String) -> (alt: String, source: String)? {
        guard let groups = matchingGroups(
            in: line.trimmingCharacters(in: .whitespaces),
            pattern: #"^!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)$"#
        ) else {
            return nil
        }

        return (alt: groups[0], source: groups[1])
    }

    private static func htmlBlock(
        in lines: [String],
        startingAt startIndex: Int,
        options: RenderingOptions
    ) -> (markdown: String, nextIndex: Int)? {
        let trimmed = lines[startIndex].trimmingCharacters(in: .whitespaces)
        guard looksLikeRawHTML(trimmed) else {
            return nil
        }

        var htmlLines: [String] = [lines[startIndex]]
        var index = startIndex + 1
        while index < lines.count {
            let next = lines[index].trimmingCharacters(in: .whitespaces)
            guard looksLikeRawHTML(next) else {
                break
            }
            htmlLines.append(lines[index])
            index += 1
        }

        let html = htmlLines.joined(separator: "\n")
        if options.rawHTMLRenderingEnabled {
            return (markdown: htmlToMarkdown(html), nextIndex: index)
        }

        return (markdown: htmlToMarkdown(escapingUnsafeHTML(in: html)), nextIndex: index)
    }

    private static func listBlock(
        in lines: [String],
        startingAt startIndex: Int,
        kind: ListBlockKind
    ) -> (items: [ListItem], nextIndex: Int)? {
        var items: [ListItem] = []
        var index = startIndex

        while index < lines.count {
            let line = lines[index]
            let item: ListItem?
            switch kind {
            case .unordered:
                if taskListItem(in: line) != nil {
                    item = nil
                } else if let parsed = unorderedListItem(in: line) {
                    item = ListItem(
                        indentLevel: parsed.indentLevel,
                        checked: nil,
                        marker: nil,
                        text: parsed.text,
                        sourceLineIndex: index
                    )
                } else {
                    item = nil
                }

            case .ordered:
                if let parsed = orderedListItem(in: line) {
                    item = ListItem(
                        indentLevel: parsed.indentLevel,
                        checked: nil,
                        marker: parsed.marker,
                        text: parsed.text,
                        sourceLineIndex: index
                    )
                } else {
                    item = nil
                }

            case .task:
                if let parsed = taskListItem(in: line) {
                    item = ListItem(
                        indentLevel: parsed.indentLevel,
                        checked: parsed.checked,
                        marker: nil,
                        text: parsed.text,
                        sourceLineIndex: index
                    )
                } else {
                    item = nil
                }
            }

            guard let item else {
                break
            }

            items.append(item)
            index += 1
        }

        guard !items.isEmpty else {
            return nil
        }

        return (items: items, nextIndex: index)
    }

    private static func inlineSpans(in line: String, options: RenderingOptions) -> [InlineSpan] {
        guard options.mathRenderingEnabled,
              let regex = try? NSRegularExpression(pattern: #"(?<!\$)\$([^\n$]+)\$(?!\$)"#) else {
            return [.text(line)]
        }

        let nsLine = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
        guard !matches.isEmpty else {
            return [.text(line)]
        }

        var spans: [InlineSpan] = []
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                spans.append(.text(nsLine.substring(with: NSRange(location: cursor, length: match.range.location - cursor))))
            }
            let formula = nsLine.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            spans.append(.inlineMath(formula))
            cursor = match.range.location + match.range.length
        }

        if cursor < nsLine.length {
            spans.append(.text(nsLine.substring(from: cursor)))
        }

        return spans.filter { span in
            switch span {
            case .text(let value):
                return !value.isEmpty
            case .inlineMath(let value):
                return !value.isEmpty
            }
        }
    }

    private static func compactBlankBlocks(_ blocks: [RenderedBlock]) -> [RenderedBlock] {
        var result: [RenderedBlock] = []
        for block in blocks {
            if block.kind == .blank, result.last?.kind == .blank {
                continue
            }
            result.append(block)
        }
        return result
    }

    private static func isCodeFence(_ trimmedLine: String) -> Bool {
        trimmedLine.hasPrefix("```") || trimmedLine.hasPrefix("~~~")
    }

    private static func taskListItem(
        in line: String
    ) -> (indentLevel: Int, checked: Bool, text: String)? {
        guard let groups = matchingGroups(
            in: line,
            pattern: #"^(\s*)[-*+]\s+\[([ xX])\]\s+(.+)$"#
        ) else {
            return nil
        }

        return (
            indentLevel: indentLevel(from: groups[0]),
            checked: groups[1].lowercased() == "x",
            text: groups[2]
        )
    }

    private static func toggledTaskListLine(_ line: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"^(\s*[-*+]\s+\[)([ xX])(\]\s+.+)$"#) else {
            return nil
        }

        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, range: range),
              match.range.location == 0,
              match.range.length == range.length,
              match.numberOfRanges == 4,
              let markerRange = Range(match.range(at: 2), in: line) else {
            return nil
        }

        let marker = String(line[markerRange])
        let nextMarker = marker.lowercased() == "x" ? " " : "x"
        var result = line
        result.replaceSubrange(markerRange, with: nextMarker)
        return result
    }

    private static func unorderedListItem(in line: String) -> (indentLevel: Int, text: String)? {
        guard let groups = matchingGroups(in: line, pattern: #"^(\s*)[-*+]\s+(.+)$"#) else {
            return nil
        }

        return (indentLevel: indentLevel(from: groups[0]), text: groups[1])
    }

    private static func orderedListItem(
        in line: String
    ) -> (indentLevel: Int, marker: String, text: String)? {
        guard let groups = matchingGroups(in: line, pattern: #"^(\s*)(\d+[.)])\s+(.+)$"#) else {
            return nil
        }

        return (
            indentLevel: indentLevel(from: groups[0]),
            marker: groups[1],
            text: groups[2]
        )
    }

    private static func quoteLine(in line: String) -> String? {
        guard let groups = matchingGroups(in: line, pattern: #"^\s{0,3}>\s?(.*)$"#) else {
            return nil
        }

        return groups[0]
    }

    private static func indentLevel(from whitespace: String) -> Int {
        let width = whitespace.reduce(0) { result, character in
            result + (character == "\t" ? 4 : 1)
        }
        return max(0, min(width / 2, 4))
    }

    private static func matchingGroups(in line: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, range: range),
              match.range.location == 0,
              match.range.length == range.length,
              match.numberOfRanges > 1 else {
            return nil
        }

        return (1..<match.numberOfRanges).map { index in
            let groupRange = match.range(at: index)
            guard groupRange.location != NSNotFound else {
                return ""
            }
            return nsLine.substring(with: groupRange)
        }
    }

    private static func searchableLine(_ rawLine: String) -> String {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else {
            return ""
        }

        line = line.replacingOccurrences(
            of: #"^\s{0,3}#{1,6}\s+"#,
            with: "",
            options: .regularExpression
        )
        line = line.replacingOccurrences(
            of: #"^\s{0,3}>\s?"#,
            with: "",
            options: .regularExpression
        )
        line = line.replacingOccurrences(
            of: #"^\s{0,3}[-*+]\s+"#,
            with: "",
            options: .regularExpression
        )
        line = line.replacingOccurrences(
            of: #"^\s{0,3}\d+[.)]\s+"#,
            with: "",
            options: .regularExpression
        )
        line = line.replacingOccurrences(
            of: #"\[([^\]]+)\]\(([^)]+)\)"#,
            with: "$1",
            options: .regularExpression
        )
        line = line.replacingOccurrences(
            of: #"(^|[^*])\*\*([^*]+)\*\*"#,
            with: "$1$2",
            options: .regularExpression
        )
        line = line.replacingOccurrences(
            of: #"(^|[^_])__([^_]+)__"#,
            with: "$1$2",
            options: .regularExpression
        )
        line = line.replacingOccurrences(
            of: #"`([^`]+)`"#,
            with: "$1",
            options: .regularExpression
        )
        line = line.replacingOccurrences(
            of: #"~~([^~]+)~~"#,
            with: "$1",
            options: .regularExpression
        )
        line = line.replacingOccurrences(of: "\\*", with: "*")
        line = line.replacingOccurrences(of: "\\_", with: "_")
        line = line.replacingOccurrences(of: "\\`", with: "`")

        return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacingImageSyntaxWithLinks(in text: String) -> String {
        let pattern = #"!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let nsText = text as NSString
        let matches = regex.matches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        )

        var result = text
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3,
                  let fullRange = Range(match.range(at: 0), in: result),
                  let altRange = Range(match.range(at: 1), in: text),
                  let urlRange = Range(match.range(at: 2), in: text) else {
                continue
            }

            let alt = String(text[altRange])
            let url = String(text[urlRange])
            let label = alt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? url : alt
            result.replaceSubrange(fullRange, with: "[\(label)](\(url))")
        }

        return result
    }

    private static func stylingMathSource(in text: String) -> String {
        let displayPattern = #"(?s)\$\$(.*?)\$\$"#
        let inlinePattern = #"(?<!\$)\$([^\n$]+)\$(?!\$)"#
        var result = text

        if let displayRegex = try? NSRegularExpression(pattern: displayPattern) {
            let nsText = result as NSString
            let matches = displayRegex.matches(
                in: result,
                range: NSRange(location: 0, length: nsText.length)
            )

            for match in matches.reversed() {
                guard match.numberOfRanges >= 2,
                      let fullRange = Range(match.range(at: 0), in: result),
                      let formulaRange = Range(match.range(at: 1), in: result) else {
                    continue
                }

                let formula = String(result[formulaRange])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                result.replaceSubrange(fullRange, with: "\n```latex\n\(formula)\n```\n")
            }
        }

        if let inlineRegex = try? NSRegularExpression(pattern: inlinePattern) {
            let nsText = result as NSString
            let matches = inlineRegex.matches(
                in: result,
                range: NSRange(location: 0, length: nsText.length)
            )

            for match in matches.reversed() {
                guard match.numberOfRanges >= 2,
                      let fullRange = Range(match.range(at: 0), in: result),
                      let formulaRange = Range(match.range(at: 1), in: result) else {
                    continue
                }

                let formula = String(result[formulaRange])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                result.replaceSubrange(fullRange, with: "`\(formula)`")
            }
        }

        return result
    }

    private static func escapingRawHTML(in text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard looksLikeRawHTML(trimmed) else {
                    return line
                }

                return line
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")
            }
            .joined(separator: "\n")
    }

    private static func escapingUnsafeHTML(in text: String) -> String {
        let lowercased = text.lowercased()
        guard lowercased.contains("<script")
                || lowercased.contains("<iframe")
                || lowercased.contains("<style") else {
            return text
        }

        return text
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func htmlToMarkdown(_ html: String) -> String {
        var result = html

        let replacements: [(String, String)] = [
            (#"(?i)<\s*br\s*/?\s*>"#, "\n"),
            (#"(?i)<\s*/\s*(p|div|section|article|li|ul|ol|blockquote|h[1-6])\s*>"#, "\n"),
            (#"(?i)<\s*(p|div|section|article|li|ul|ol|blockquote|h[1-6])(?:\s+[^>]*)?>"#, ""),
            (#"(?i)<\s*(strong|b)(?:\s+[^>]*)?>"#, "**"),
            (#"(?i)<\s*/\s*(strong|b)\s*>"#, "**"),
            (#"(?i)<\s*(em|i)(?:\s+[^>]*)?>"#, "_"),
            (#"(?i)<\s*/\s*(em|i)\s*>"#, "_"),
            (#"(?i)<\s*code(?:\s+[^>]*)?>"#, "`"),
            (#"(?i)<\s*/\s*code\s*>"#, "`"),
            (#"(?i)<\s*mark(?:\s+[^>]*)?>"#, "**"),
            (#"(?i)<\s*/\s*mark\s*>"#, "**")
        ]

        for (pattern, replacement) in replacements {
            result = result.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }

        result = result.replacingOccurrences(
            of: #"(?i)<\s*a(?:\s+[^>]*)href\s*=\s*['"]([^'"]+)['"][^>]*>(.*?)<\s*/\s*a\s*>"#,
            with: "[$2]($1)",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?s)<[^>]+>"#,
            with: "",
            options: .regularExpression
        )

        return result
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikeRawHTML(_ trimmedLine: String) -> Bool {
        guard trimmedLine.hasPrefix("<") else {
            return false
        }

        let lowercased = trimmedLine.lowercased()
        return lowercased.hasPrefix("<script")
            || lowercased.hasPrefix("<iframe")
            || lowercased.hasPrefix("<style")
            || lowercased.range(of: #"^</?[a-z][a-z0-9-]*(\s|>|/>)"#, options: .regularExpression) != nil
    }

    private static func standaloneURL(in line: String) -> URL? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }

        return url
    }

    private static func headingMarker(in line: String) -> (level: Int, length: Int)? {
        if line.hasPrefix("## ") {
            return (2, 3)
        }

        if line.hasPrefix("# ") {
            return (1, 2)
        }

        return nil
    }

    private static func currentLine(
        in text: String,
        selectedRange: NSRange
    ) -> (contentRange: NSRange, text: String)? {
        let nsText = text as NSString
        let safeLocation = min(selectedRange.location, text.utf16.count)
        let rawLineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
        var contentLength = rawLineRange.length

        if contentLength > 0 {
            let rawLine = nsText.substring(with: rawLineRange)
            if rawLine.hasSuffix("\r\n") {
                contentLength -= 2
            } else if rawLine.hasSuffix("\n") || rawLine.hasSuffix("\r") {
                contentLength -= 1
            }
        }

        let contentRange = NSRange(location: rawLineRange.location, length: max(0, contentLength))
        return (contentRange, nsText.substring(with: contentRange))
    }

    private static func headingToggleEdit(
        level: Int,
        currentLine: String,
        lineRange: NSRange,
        selectedOffset: Int
    ) -> TextEdit {
        let nextPrefix = String(repeating: "#", count: level) + " "

        if let currentHeading = headingMarker(in: currentLine),
           currentHeading.level == level {
            let nextLine = String(currentLine.dropFirst(currentHeading.length))
            let nextOffset = adjustedOffsetAfterRemovingPrefix(
                selectedOffset,
                prefixLength: currentHeading.length
            )
            return TextEdit(
                replacementRange: lineRange,
                replacementText: nextLine,
                selectedRange: NSRange(location: lineRange.location + nextOffset, length: 0)
            )
        }

        let oldPrefixLength = headingMarker(in: currentLine)?.length ?? 0
        let baseLine = String(currentLine.dropFirst(oldPrefixLength))
        let nextLine = nextPrefix + baseLine
        let nextOffset = adjustedOffsetAfterReplacingPrefix(
            selectedOffset,
            oldPrefixLength: oldPrefixLength,
            newPrefixLength: nextPrefix.utf16.count
        )

        return TextEdit(
            replacementRange: lineRange,
            replacementText: nextLine,
            selectedRange: NSRange(location: lineRange.location + nextOffset, length: 0)
        )
    }

    private static func adjustedOffsetAfterRemovingPrefix(_ offset: Int, prefixLength: Int) -> Int {
        guard offset >= prefixLength else {
            return 0
        }

        return offset - prefixLength
    }

    private static func adjustedOffsetAfterReplacingPrefix(
        _ offset: Int,
        oldPrefixLength: Int,
        newPrefixLength: Int
    ) -> Int {
        guard offset >= oldPrefixLength else {
            return newPrefixLength
        }

        return newPrefixLength + offset - oldPrefixLength
    }

    private static func isValid(range: NSRange, in text: String) -> Bool {
        guard range.location >= 0,
              range.length >= 0,
              range.location <= text.utf16.count,
              range.location + range.length <= text.utf16.count else {
            return false
        }

        return Range(range, in: text) != nil
    }
}
