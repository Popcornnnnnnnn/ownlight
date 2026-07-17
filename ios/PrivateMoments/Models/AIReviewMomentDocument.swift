import Foundation

struct AIReviewMomentDocument: Equatable {
    struct Section: Equatable {
        var title: String
        var lines: [String]
    }

    var title: String
    var metadataSummary: String?
    var sections: [Section]
    var keywords: [String]
    var rangeText: String?
    var timelinePreview: String

    static func parse(_ text: String) -> AIReviewMomentDocument {
        var title: String?
        var metadataSummary: String?
        var sections: [Section] = []
        var currentSectionTitle: String?
        var currentSectionLines: [String] = []
        var keywords: [String] = []
        var rangeText: String?
        var mode: ParseMode = .body

        func flushSection() {
            let lines = currentSectionLines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else {
                currentSectionLines = []
                return
            }

            sections.append(Section(title: currentSectionTitle ?? "Overview", lines: lines))
            currentSectionLines = []
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            if line.hasPrefix("# ") {
                if title == nil {
                    title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                continue
            }

            if line.hasPrefix("## ") {
                flushSection()
                let heading = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                if heading.caseInsensitiveCompare("Keywords") == .orderedSame {
                    mode = .keywords
                    currentSectionTitle = nil
                } else {
                    mode = .body
                    currentSectionTitle = heading.isEmpty ? "Overview" : heading
                }
                continue
            }

            if let parsedRange = parsedRangeText(from: line) {
                rangeText = parsedRange
                continue
            }

            if metadataSummary == nil, isMetadataSummary(line) {
                metadataSummary = line
                continue
            }

            switch mode {
            case .body:
                currentSectionLines.append(cleanContentLine(line))
            case .keywords:
                keywords.append(cleanContentLine(line))
            }
        }

        flushSection()

        let resolvedTitle = title?.isEmpty == false ? title! : "Weekly Review"
        let preview = sections
            .flatMap(\.lines)
            .first { !$0.isEmpty } ?? resolvedTitle

        return AIReviewMomentDocument(
            title: resolvedTitle,
            metadataSummary: metadataSummary,
            sections: sections,
            keywords: keywords.filter { !$0.isEmpty },
            rangeText: rangeText,
            timelinePreview: preview
        )
    }

    private enum ParseMode {
        case body
        case keywords
    }

    private static func cleanContentLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") {
            return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    private static func parsedRangeText(from line: String) -> String? {
        guard line.lowercased().hasPrefix("range:") else {
            return nil
        }

        let value = String(line.dropFirst("Range:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func isMetadataSummary(_ line: String) -> Bool {
        line.range(
            of: #"^\d+\s+moments?\s+·\s+\d+\s+comments?$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}

extension TimelinePost {
    var isAIReviewMoment: Bool {
        aiReviewId != nil
    }

    var aiReviewId: String? {
        guard id.hasPrefix("review-") else {
            return nil
        }

        let reviewId = String(id.dropFirst("review-".count))
        return reviewId.isEmpty ? nil : reviewId
    }
}
