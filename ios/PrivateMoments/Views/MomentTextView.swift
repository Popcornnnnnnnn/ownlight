import SwiftUI
import UIKit

struct MomentTextView: View {
    enum Style: Equatable {
        case timeline
        case detail
        case preview

        var heading1Font: Font {
            switch self {
            case .timeline:
                return .title3.weight(.semibold)
            case .detail:
                return .title2.weight(.semibold)
            case .preview:
                return .headline.weight(.semibold)
            }
        }

        var heading2Font: Font {
            switch self {
            case .timeline:
                return .headline.weight(.semibold)
            case .detail:
                return .title3.weight(.semibold)
            case .preview:
                return .subheadline.weight(.semibold)
            }
        }

        var lineSpacing: CGFloat {
            switch self {
            case .timeline:
                return 5
            case .detail:
                return 7
            case .preview:
                return 3
            }
        }

        var blankHeight: CGFloat {
            switch self {
            case .timeline:
                return 4
            case .detail:
                return 6
            case .preview:
                return 2
            }
        }

        var bodyFont: Font {
            switch self {
            case .timeline, .detail:
                return .body
            case .preview:
                return .subheadline
            }
        }

        var monospacedFont: Font {
            switch self {
            case .timeline, .detail:
                return .system(.body, design: .monospaced)
            case .preview:
                return .system(.subheadline, design: .monospaced)
            }
        }

        var bodyUIFont: UIFont {
            switch self {
            case .timeline, .detail:
                return UIFont.preferredFont(forTextStyle: .body)
            case .preview:
                return UIFont.preferredFont(forTextStyle: .subheadline)
            }
        }

        var heading1UIFont: UIFont {
            switch self {
            case .timeline:
                return scaledUIFont(textStyle: .title3, weight: .semibold)
            case .detail:
                return scaledUIFont(textStyle: .title2, weight: .semibold)
            case .preview:
                return scaledUIFont(textStyle: .headline, weight: .semibold)
            }
        }

        var heading2UIFont: UIFont {
            switch self {
            case .timeline:
                return scaledUIFont(textStyle: .headline, weight: .semibold)
            case .detail:
                return scaledUIFont(textStyle: .title3, weight: .semibold)
            case .preview:
                return scaledUIFont(textStyle: .subheadline, weight: .semibold)
            }
        }

        var bodyLineSpacing: CGFloat {
            switch self {
            case .timeline:
                return 5
            case .detail:
                return 7
            case .preview:
                return 3
            }
        }

        private func scaledUIFont(textStyle: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
            let base = UIFont.preferredFont(forTextStyle: textStyle)
            let font = UIFont.systemFont(ofSize: base.pointSize, weight: weight)
            return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: font)
        }

    }

    let text: String
    let style: Style
    var onToggleTaskItem: ((MomentTextMarkdown.ListItem) -> Void)? = nil

    private var blocks: [MomentTextMarkdown.RenderedBlock] {
        MomentTextMarkdown.renderableBlocks(for: text)
    }

    var body: some View {
        renderedBody
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .allowsHitTesting(style != .preview)
    }

    private var renderedBody: some View {
        VStack(alignment: .leading, spacing: style.lineSpacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                renderedBlock(block)
            }
        }
    }

    @ViewBuilder
    private func renderedBlock(_ block: MomentTextMarkdown.RenderedBlock) -> some View {
        switch block.kind {
        case .heading(let level, let text):
            inlineMarkdownText(text)
                .font(level == 1 ? style.heading1Font : style.heading2Font)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 1)

        case .link(let url):
            MomentLinkCard(url: url, style: style)

        case .paragraph(let spans):
            inlineSpanText(spans)
                .font(style.bodyFont)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

        case .image(let alt, let source):
            MomentMarkdownImage(alt: alt, source: source, style: style)

        case .unorderedList(let items):
            listBlock(items: items, ordered: false)

        case .orderedList(let items):
            listBlock(items: items, ordered: true)

        case .taskList(let items):
            taskListBlock(items: items)

        case .quote(let spans):
            quoteLine(spans)

        case .codeBlock(let language, let code):
            MomentCodeBlock(language: language, code: code, style: style)

        case .table(let headers, let rows):
            MomentMarkdownTable(headers: headers, rows: rows, style: style)

        case .mathBlock(let formula):
            MomentMathBlock(formula: formula, style: style)

        case .htmlBlock(let markdown):
            MomentHTMLBlock(markdown: markdown, style: style)

        case .blank:
            Spacer()
                .frame(height: style.blankHeight)
        }
    }

    private func inlineMarkdownText(_ source: String) -> Text {
        if let attributed = MomentTextMarkdown.inlineAttributedString(for: source) {
            return Text(attributed)
        }

        return Text(source)
    }

    private func inlineSpanText(_ spans: [MomentTextMarkdown.InlineSpan]) -> Text {
        spans.reduce(Text("")) { result, span in
            switch span {
            case .text(let text):
                return result + inlineMarkdownText(text)
            case .inlineMath(let formula):
                return result + Text(MomentMathDisplay.displayText(formula)).font(style.monospacedFont)
            }
        }
    }

    private func listBlock(items: [MomentTextMarkdown.ListItem], ordered: Bool) -> some View {
        VStack(alignment: .leading, spacing: max(3, style.lineSpacing - 2)) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let marker = ordered ? (item.marker ?? "\(index + 1).") : "•"
                listLine(marker: marker, text: item.text, indentLevel: item.indentLevel)
            }
        }
    }

    private func taskListBlock(items: [MomentTextMarkdown.ListItem]) -> some View {
        VStack(alignment: .leading, spacing: max(3, style.lineSpacing - 2)) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    taskListCheckbox(for: item)

                    inlineMarkdownText(item.text)
                        .font(style.bodyFont)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, CGFloat(item.indentLevel) * 14)
            }
        }
    }

    @ViewBuilder
    private func taskListCheckbox(for item: MomentTextMarkdown.ListItem) -> some View {
        let iconName = item.checked == true ? "checkmark.square.fill" : "square"
        let iconColor = item.checked == true ? Color.accentColor : Color.secondary

        if let onToggleTaskItem,
           item.sourceLineIndex != nil,
           style == .detail {
            Button {
                onToggleTaskItem(item)
            } label: {
                Image(systemName: iconName)
                    .font(style.bodyFont.weight(.semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 32, height: 28, alignment: .center)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.checked == true ? "Mark task incomplete" : "Mark task complete")
        } else {
            Image(systemName: iconName)
                .font(style.bodyFont.weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: 20, alignment: .center)
        }
    }

    private func listLine(marker: String, text: String, indentLevel: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker)
                .font(style.bodyFont)
                .foregroundStyle(.secondary)
                .frame(minWidth: marker.count > 1 ? 30 : 14, alignment: .trailing)

            inlineMarkdownText(text)
                .font(style.bodyFont)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, CGFloat(indentLevel) * 14)
    }

    private func quoteLine(_ spans: [MomentTextMarkdown.InlineSpan]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Rectangle()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 3, height: style.bodyUIFont.lineHeight)

            inlineSpanText(spans)
                .font(style.bodyFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SelectableMomentTextView: UIViewRepresentable {
    let text: String
    let style: MomentTextView.Style

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.dataDetectorTypes = []
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.required, for: .vertical)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let attributed = MomentTextAttributedBuilder.attributedText(for: text, style: style)
        if !(uiView.attributedText?.isEqual(to: attributed) ?? false) {
            uiView.attributedText = attributed
        }
        uiView.linkTextAttributes = [
            .foregroundColor: UIColor.link,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else {
            return nil
        }

        let targetSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        let fittingSize = uiView.sizeThatFits(targetSize)
        return CGSize(width: width, height: ceil(fittingSize.height))
    }
}

private enum MomentTextAttributedBuilder {
    static func attributedText(for text: String, style: MomentTextView.Style) -> NSAttributedString {
        let attributed = NSMutableAttributedString()
        let lines = MomentTextMarkdown.renderableLines(for: text)

        for (index, line) in lines.enumerated() {
            attributed.append(renderedLine(line, style: style))
            if index < lines.count - 1 {
                attributed.append(NSAttributedString(string: "\n"))
            }
        }

        return attributed
    }

    private static func renderedLine(
        _ line: MomentTextMarkdown.RenderedLine,
        style: MomentTextView.Style
    ) -> NSAttributedString {
        switch line.kind {
        case .heading(let level, let text):
            return attributedMarkdownLine(
                text,
                fallbackFont: level == 1 ? style.heading1UIFont : style.heading2UIFont,
                color: UIColor.label,
                lineSpacing: style.bodyLineSpacing
            )

        case .link(let url):
            return NSAttributedString(
                string: url.absoluteString,
                attributes: [
                    .font: style.bodyUIFont,
                    .foregroundColor: UIColor.link,
                    .link: url,
                    .paragraphStyle: paragraphStyle(lineSpacing: style.bodyLineSpacing),
                ]
            )

        case .markdown(let text):
            return attributedMarkdownLine(
                text,
                fallbackFont: style.bodyUIFont,
                color: UIColor.label,
                lineSpacing: style.bodyLineSpacing
            )

        case .unorderedList(let indentLevel, let text):
            return attributedListLine(
                marker: "•",
                text: text,
                indentLevel: indentLevel,
                style: style
            )

        case .orderedList(let indentLevel, let marker, let text),
             .taskList(let indentLevel, let marker, let text):
            return attributedListLine(
                marker: marker,
                text: text,
                indentLevel: indentLevel,
                style: style
            )

        case .quote(let text):
            return attributedMarkdownLine(
                "> \(text)",
                fallbackFont: style.bodyUIFont,
                color: UIColor.secondaryLabel,
                lineSpacing: style.bodyLineSpacing
            )

        case .codeFence(let text), .codeLine(let text):
            return NSAttributedString(
                string: text,
                attributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: style.bodyUIFont.pointSize, weight: .regular),
                    .foregroundColor: UIColor.secondaryLabel,
                    .paragraphStyle: paragraphStyle(lineSpacing: style.bodyLineSpacing),
                ]
            )

        case .blank:
            return NSAttributedString(string: "")
        }
    }

    private static func attributedListLine(
        marker: String,
        text: String,
        indentLevel: Int,
        style: MomentTextView.Style
    ) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: "\(String(repeating: "  ", count: indentLevel))\(marker) ",
            attributes: [
                .font: style.bodyUIFont,
                .foregroundColor: UIColor.secondaryLabel,
                .paragraphStyle: paragraphStyle(lineSpacing: style.bodyLineSpacing),
            ]
        )
        attributed.append(
            attributedMarkdownLine(
                text,
                fallbackFont: style.bodyUIFont,
                color: UIColor.label,
                lineSpacing: style.bodyLineSpacing
            )
        )
        return attributed
    }

    private static func attributedMarkdownLine(
        _ text: String,
        fallbackFont: UIFont,
        color: UIColor,
        lineSpacing: CGFloat
    ) -> NSAttributedString {
        let attributed: NSMutableAttributedString
        if let markdown = MomentTextMarkdown.inlineAttributedString(for: text) {
            attributed = NSMutableAttributedString(attributedString: NSAttributedString(markdown))
        } else {
            attributed = NSMutableAttributedString(string: text)
        }

        let fullRange = NSRange(location: 0, length: attributed.length)
        if attributed.length > 0 {
            attributed.addAttribute(.foregroundColor, value: color, range: fullRange)
            attributed.addAttribute(
                .paragraphStyle,
                value: paragraphStyle(lineSpacing: lineSpacing),
                range: fullRange
            )
            attributed.enumerateAttribute(.font, in: fullRange) { value, range, _ in
                if value == nil {
                    attributed.addAttribute(.font, value: fallbackFont, range: range)
                }
            }
        }

        return attributed
    }

    private static func paragraphStyle(lineSpacing: CGFloat) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.paragraphSpacing = 0
        return paragraph
    }
}

private struct MomentLinkCard: View {
    let url: URL
    let style: MomentTextView.Style

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color.secondary.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle)
                        .font(style == .detail ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(url.absoluteString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, style == .detail ? 12 : 10)
            .padding(.vertical, style == .detail ? 10 : 8)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
    }

    private var displayTitle: String {
        if let host = url.host, !host.isEmpty {
            return host.replacingOccurrences(of: "www.", with: "")
        }

        return "Link"
    }
}

private struct MomentCodeBlock: View {
    let language: String?
    let code: String
    let style: MomentTextView.Style

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                if let language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(code.isEmpty ? " " : code)
                    .font(style.monospacedFont)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
            }
            .padding(.horizontal, style == .detail ? 12 : 10)
            .padding(.vertical, style == .detail ? 10 : 8)
        }
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 0.6)
        )
    }
}

private struct MomentMathBlock: View {
    let formula: String
    let style: MomentTextView.Style

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "function")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("Math")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(displayLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(style.monospacedFont)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: true, vertical: true)
                    }
                }
            }
        }
        .padding(.horizontal, style == .detail ? 12 : 10)
        .padding(.vertical, style == .detail ? 10 : 8)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.accentColor.opacity(0.16), lineWidth: 0.6)
        )
    }

    private var displayLines: [String] {
        let lines = formula
            .components(separatedBy: .newlines)
            .map { MomentMathDisplay.displayText($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? [" "] : lines
    }
}

private enum MomentMathDisplay {
    static func displayText(_ source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return trimmed
        }

        var output = trimmed
        output = replacingFractions(in: output)
        output = output
            .replacingOccurrences(of: "\\sum", with: "Σ")
            .replacingOccurrences(of: "\\int", with: "∫")
            .replacingOccurrences(of: "\\sqrt", with: "√")
            .replacingOccurrences(of: "\\times", with: "×")
            .replacingOccurrences(of: "\\cdot", with: "·")
            .replacingOccurrences(of: "\\leq", with: "≤")
            .replacingOccurrences(of: "\\geq", with: "≥")
            .replacingOccurrences(of: "\\neq", with: "≠")
            .replacingOccurrences(of: "\\approx", with: "≈")
            .replacingOccurrences(of: "\\pi", with: "π")
        output = replacingBracedScripts(in: output, marker: "^", transform: superscript)
        output = replacingBracedScripts(in: output, marker: "_", transform: subscriptText)
        output = replacingSingleCharacterScripts(in: output, marker: "^", transform: superscript)
        output = replacingSingleCharacterScripts(in: output, marker: "_", transform: subscriptText)
        return output
    }

    private static func replacingFractions(in text: String) -> String {
        replacingRegex(
            in: text,
            pattern: #"\\frac\{([^{}]+)\}\{([^{}]+)\}"#
        ) { match, nsText in
            guard match.numberOfRanges == 3 else {
                return nil
            }
            let numerator = nsText.substring(with: match.range(at: 1))
            let denominator = nsText.substring(with: match.range(at: 2))
            return "\(numerator) / \(denominator)"
        }
    }

    private static func replacingBracedScripts(
        in text: String,
        marker: String,
        transform: (String) -> String
    ) -> String {
        replacingRegex(
            in: text,
            pattern: #"\#(marker)\{([^{}]+)\}"#
        ) { match, nsText in
            guard match.numberOfRanges == 2 else {
                return nil
            }
            return transform(nsText.substring(with: match.range(at: 1)))
        }
    }

    private static func replacingSingleCharacterScripts(
        in text: String,
        marker: String,
        transform: (String) -> String
    ) -> String {
        replacingRegex(
            in: text,
            pattern: #"\#(marker)([A-Za-z0-9+\-=()])"#
        ) { match, nsText in
            guard match.numberOfRanges == 2 else {
                return nil
            }
            return transform(nsText.substring(with: match.range(at: 1)))
        }
    }

    private static func replacingRegex(
        in text: String,
        pattern: String,
        transform: (NSTextCheckingResult, NSString) -> String?
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        var output = text
        let matches = regex.matches(in: output, range: NSRange(location: 0, length: (output as NSString).length))
        for match in matches.reversed() {
            let nsOutput = output as NSString
            guard let replacement = transform(match, nsOutput) else {
                continue
            }
            output = nsOutput.replacingCharacters(in: match.range, with: replacement)
        }
        return output
    }

    private static func superscript(_ source: String) -> String {
        convert(source, using: [
            "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
            "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾",
            "a": "ᵃ", "b": "ᵇ", "c": "ᶜ", "d": "ᵈ", "e": "ᵉ", "f": "ᶠ", "g": "ᵍ", "h": "ʰ", "i": "ⁱ", "j": "ʲ",
            "k": "ᵏ", "l": "ˡ", "m": "ᵐ", "n": "ⁿ", "o": "ᵒ", "p": "ᵖ", "r": "ʳ", "s": "ˢ", "t": "ᵗ", "u": "ᵘ",
            "v": "ᵛ", "w": "ʷ", "x": "ˣ", "y": "ʸ", "z": "ᶻ"
        ])
    }

    private static func subscriptText(_ source: String) -> String {
        convert(source, using: [
            "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
            "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎",
            "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ", "j": "ⱼ", "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ",
            "o": "ₒ", "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ", "u": "ᵤ", "v": "ᵥ", "x": "ₓ"
        ])
    }

    private static func convert(_ source: String, using map: [String: String]) -> String {
        source.map { character in
            let key = String(character)
            return map[key] ?? key
        }.joined()
    }
}

private struct MomentHTMLBlock: View {
    let markdown: String
    let style: MomentTextView.Style

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HTML")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(markdown.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                if let attributed = MomentTextMarkdown.inlineAttributedString(for: line) {
                    Text(attributed)
                        .font(style.bodyFont)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(line)
                        .font(style.bodyFont)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, style == .detail ? 12 : 10)
        .padding(.vertical, style == .detail ? 10 : 8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 0.6)
        )
    }
}

private struct MomentMarkdownTable: View {
    let headers: [String]
    let rows: [[String]]
    let style: MomentTextView.Style

    var body: some View {
        let widths = columnWidths
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                tableRow(headers, isHeader: true, columnWidths: widths)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    tableRow(row, isHeader: false, columnWidths: widths)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 0.6)
            )
        }
    }

    private var columnWidths: [CGFloat] {
        (0..<headers.count).map { index in
            let values = [headers[index]] + rows.map { row in
                index < row.count ? row[index] : ""
            }
            let widestText = values
                .map { measuredWidth(for: $0, isHeader: $0 == headers[index]) }
                .max() ?? 0
            return min(maxColumnWidth, max(minColumnWidth, ceil(widestText + 20)))
        }
    }

    private var minColumnWidth: CGFloat {
        style == .detail ? 118 : 104
    }

    private var maxColumnWidth: CGFloat {
        style == .detail ? 230 : 190
    }

    private func measuredWidth(for text: String, isHeader: Bool) -> CGFloat {
        let baseFont = style.bodyUIFont
        let font = isHeader
            ? UIFont.systemFont(ofSize: baseFont.pointSize, weight: .semibold)
            : baseFont
        let normalized = text.replacingOccurrences(of: "`", with: "")
        return (normalized as NSString).size(withAttributes: [.font: font]).width
    }

    private func tableRow(_ cells: [String], isHeader: Bool, columnWidths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<headers.count, id: \.self) { index in
                let cellWidth = index < columnWidths.count ? columnWidths[index] : minColumnWidth
                Text(index < cells.count ? cells[index] : "")
                    .font(isHeader ? style.bodyFont.weight(.semibold) : style.bodyFont)
                    .foregroundStyle(isHeader ? .primary : .secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: max(cellWidth - 20, 44), alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(isHeader ? Color.secondary.opacity(0.09) : Color.clear)
                    .overlay(alignment: .trailing) {
                        if index < headers.count - 1 {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.12))
                                .frame(width: 0.6)
                        }
                    }
                    .overlay(alignment: .leading) {
                        if index > 0 {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.12))
                            .frame(width: 0.6)
                        }
                    }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 0.6)
        }
    }
}

private struct MomentMarkdownImage: View {
    let alt: String
    let source: String
    let style: MomentTextView.Style

    var body: some View {
        Group {
            if let assetName {
                builtInImage(assetName: assetName)
            } else if let url = URL(string: source),
                      let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https" {
                remoteImage(url)
            } else {
                fallbackImage(title: alt.isEmpty ? source : alt, subtitle: source)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var assetName: String? {
        guard source.lowercased().hasPrefix("asset:") else {
            return nil
        }
        return String(source.dropFirst("asset:".count))
    }

    @ViewBuilder
    private func builtInImage(assetName: String) -> some View {
        if let image = UIImage(named: assetName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: style == .detail ? 150 : 118)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            fallbackImage(title: alt.isEmpty ? "Built-in image" : alt, subtitle: assetName)
        }
    }

    @ViewBuilder
    private func remoteImage(_ url: URL) -> some View {
        if AppSettings.markdownRemoteImagesEnabled {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    fallbackImage(title: alt.isEmpty ? "Loading image" : alt, subtitle: url.host ?? url.absoluteString)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: style == .detail ? 170 : 124)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                case .failure:
                    fallbackImage(title: alt.isEmpty ? "Image unavailable" : alt, subtitle: url.absoluteString)
                @unknown default:
                    fallbackImage(title: alt.isEmpty ? "Image" : alt, subtitle: url.absoluteString)
                }
            }
        } else {
            MomentLinkCard(url: url, style: style)
        }
    }

    private func fallbackImage(title: String, subtitle: String) -> some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.22),
                    Color(.systemTeal).opacity(0.16),
                    Color.secondary.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack(alignment: .bottom, spacing: 10) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(style == .detail ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: style == .detail ? 150 : 112)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 0.6)
        )
    }
}
