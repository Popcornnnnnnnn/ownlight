import XCTest
@testable import PrivateMoments

final class MomentTextMarkdownTests: XCTestCase {
    func testParsesOnlyLineLeadingHeadings() {
        let lines = MomentTextMarkdown.parse("## Voice note title\nbody\n- item\n not a heading")

        XCTAssertEqual(
            lines.map(\.kind),
            [
                .heading(level: 2, text: "Voice note title"),
                .paragraph("body"),
                .paragraph("- item"),
                .paragraph(" not a heading")
            ]
        )
    }

    func testDetectsExistingLeadingTitleAfterBlankLines() {
        XCTAssertTrue(MomentTextMarkdown.hasLeadingTitle("\n\n# Existing title\nbody"))
        XCTAssertFalse(MomentTextMarkdown.hasLeadingTitle("\n\nbody\n## Later heading"))
        XCTAssertFalse(MomentTextMarkdown.hasLeadingTitle("##   "))
    }

    func testAITitleNormalizationAndInsertion() {
        XCTAssertEqual(MomentTextMarkdown.normalizedAITitle("## 康复训练复盘"), "康复训练复盘")
        XCTAssertNil(MomentTextMarkdown.normalizedAITitle(String(repeating: "题", count: 41)))
        XCTAssertEqual(
            MomentTextMarkdown.insertingAITitle("康复训练复盘", into: "今天练了肩胛控制"),
            "## 康复训练复盘\n\n今天练了肩胛控制"
        )
    }

    func testSearchableTextStripsHeadingMarkers() {
        XCTAssertEqual(
            MomentTextMarkdown.searchableText("## 面试复盘\n- 沟通节奏"),
            "面试复盘\n沟通节奏"
        )
    }

    func testParsesStandaloneHTTPURLsAsLinks() {
        let lines = MomentTextMarkdown.parse("微信文章\nhttps://mp.weixin.qq.com/s/example\nnot https://example.com inline")

        XCTAssertEqual(
            lines.map(\.kind),
            [
                .paragraph("微信文章"),
                .link(URL(string: "https://mp.weixin.qq.com/s/example")!),
                .paragraph("not https://example.com inline")
            ]
        )
        XCTAssertEqual(
            MomentTextMarkdown.searchableText("https://mp.weixin.qq.com/s/example"),
            "https://mp.weixin.qq.com/s/example"
        )
    }

    func testComplexMarkdownRenderingSourceCoversCommonSyntax() {
        let source = """
        # Markdown Showcase

        **Bold**, _italic_, ~~deleted~~, and `inline code`.

        [Example link](https://example.com/private-moments)

        > A small quote.

        - [x] Done item
        - [ ] Pending item

        | Feature | State |
        | --- | --- |
        | Tables | system markdown |

        ```swift
        let title = "Moment"
        ```

        ![remote chart](https://example.com/chart.png)

        <div class="note">raw html</div>

        Inline math $E=mc^2$ and display math:

        $$
        y = mx + b
        $$
        """

        let safeSource = MomentTextMarkdown.renderingSource(
            source,
            options: .init(
                mathRenderingEnabled: false,
                remoteImagesEnabled: false,
                rawHTMLRenderingEnabled: false
            )
        )

        XCTAssertTrue(safeSource.contains("[remote chart](https://example.com/chart.png)"))
        XCTAssertFalse(safeSource.contains("![remote chart]"))
        XCTAssertTrue(safeSource.contains("&lt;div class=\"note\"&gt;raw html&lt;/div&gt;"))
        XCTAssertTrue(safeSource.contains("Inline math $E=mc^2$"))
        XCTAssertNotNil(
            MomentTextMarkdown.attributedString(
                for: source,
                options: .init(
                    mathRenderingEnabled: false,
                    remoteImagesEnabled: false,
                    rawHTMLRenderingEnabled: false
                )
            )
        )

        let mathSource = MomentTextMarkdown.renderingSource(
            source,
            options: .init(
                mathRenderingEnabled: true,
                remoteImagesEnabled: false,
                rawHTMLRenderingEnabled: false
            )
        )

        XCTAssertTrue(mathSource.contains("Inline math `E=mc^2`"))
        XCTAssertTrue(mathSource.contains("```latex\ny = mx + b\n```"))

        let searchable = MomentTextMarkdown.searchableText(source)
        XCTAssertTrue(searchable.contains("Markdown Showcase"))
        XCTAssertTrue(searchable.contains("Example link"))
        XCTAssertTrue(searchable.contains("remote chart"))
        XCTAssertFalse(searchable.contains("https://example.com/chart.png"))
    }

    func testRenderableLinesPreserveBlockBoundariesAndMarkers() {
        let source = """
        # Markdown Showcase

        Paragraph with **bold** text.
        - Bullet item
          - Nested bullet
        1. Numbered item
        - [x] Done item
        > A small quote.
        ```swift
        let title = "Moment"
        ```
        """

        XCTAssertEqual(
            MomentTextMarkdown.renderableLines(for: source).map(\.kind),
            [
                .heading(level: 1, text: "Markdown Showcase"),
                .blank,
                .markdown("Paragraph with **bold** text."),
                .unorderedList(indentLevel: 0, text: "Bullet item"),
                .unorderedList(indentLevel: 1, text: "Nested bullet"),
                .orderedList(indentLevel: 0, marker: "1.", text: "Numbered item"),
                .taskList(indentLevel: 0, marker: "[x]", text: "Done item"),
                .quote("A small quote."),
                .codeFence("```swift"),
                .codeLine("let title = \"Moment\""),
                .codeFence("```")
            ]
        )
    }

    func testRenderableBlocksCoverRichMarkdownSyntax() {
        let source = """
        - [x] Done item
        - [ ] Pending item

        ```swift
        let title = "Moment"
        ```

        | Feature | State |
        | --- | --- |
        | Task list | rendered |

        Inline math $E=mc^2$ stays in the sentence.

        $$
        y = mx + b
        $$

        <div><strong>HTML</strong> block</div>

        ![Built-in image](asset:markdown-showcase)
        """

        XCTAssertEqual(
            MomentTextMarkdown.renderableBlocks(
                for: source,
                options: .init(
                    mathRenderingEnabled: true,
                    remoteImagesEnabled: true,
                    rawHTMLRenderingEnabled: true
                )
            ).map(\.kind),
            [
                .taskList([
                    .init(indentLevel: 0, checked: true, text: "Done item", sourceLineIndex: 0),
                    .init(indentLevel: 0, checked: false, text: "Pending item", sourceLineIndex: 1)
                ]),
                .blank,
                .codeBlock(language: "swift", code: "let title = \"Moment\""),
                .blank,
                .table(
                    headers: ["Feature", "State"],
                    rows: [["Task list", "rendered"]]
                ),
                .blank,
                .paragraph([
                    .text("Inline math "),
                    .inlineMath("E=mc^2"),
                    .text(" stays in the sentence.")
                ]),
                .blank,
                .mathBlock("y = mx + b"),
                .blank,
                .htmlBlock(markdown: "**HTML** block"),
                .blank,
                .image(alt: "Built-in image", source: "asset:markdown-showcase")
            ]
        )
    }

    func testRenderableTaskListItemsCarrySourceLineIndexes() {
        let source = """
        # Plan

        - [x] First task
          - [ ] Nested task
        body
        """

        let blocks = MomentTextMarkdown.renderableBlocks(for: source)

        XCTAssertEqual(
            blocks.map(\.kind),
            [
                .heading(level: 1, text: "Plan"),
                .blank,
                .taskList([
                    .init(indentLevel: 0, checked: true, text: "First task", sourceLineIndex: 2),
                    .init(indentLevel: 1, checked: false, text: "Nested task", sourceLineIndex: 3)
                ]),
                .paragraph([.text("body")])
            ]
        )
    }

    func testTogglesTaskListItemBySourceLineIndex() {
        let source = """
        # Plan
        - [x] Done task
          - [ ] Nested task
        - [X] Uppercase task
        - ordinary bullet
        """

        XCTAssertEqual(
            MomentTextMarkdown.togglingTaskListItem(in: source, sourceLineIndex: 1),
            """
            # Plan
            - [ ] Done task
              - [ ] Nested task
            - [X] Uppercase task
            - ordinary bullet
            """
        )

        XCTAssertEqual(
            MomentTextMarkdown.togglingTaskListItem(in: source, sourceLineIndex: 2),
            """
            # Plan
            - [x] Done task
              - [x] Nested task
            - [X] Uppercase task
            - ordinary bullet
            """
        )

        XCTAssertEqual(
            MomentTextMarkdown.togglingTaskListItem(in: source, sourceLineIndex: 3),
            """
            # Plan
            - [x] Done task
              - [ ] Nested task
            - [ ] Uppercase task
            - ordinary bullet
            """
        )

        XCTAssertNil(MomentTextMarkdown.togglingTaskListItem(in: source, sourceLineIndex: 4))
        XCTAssertNil(MomentTextMarkdown.togglingTaskListItem(in: source, sourceLineIndex: 99))
    }

    func testTogglesHeadingOnCurrentLine() {
        let text = "first\nsecond"
        let selection = NSRange(location: 7, length: 0)

        XCTAssertEqual(
            MomentTextMarkdown.togglingLineStyle(.heading(level: 2), in: text, selectedRange: selection),
            .init(
                replacementRange: NSRange(location: 6, length: 6),
                replacementText: "## second",
                selectedRange: NSRange(location: 10, length: 0)
            )
        )
    }

    func testHeadingToggleReplacesOrRemovesExistingMarker() {
        XCTAssertEqual(
            MomentTextMarkdown.togglingLineStyle(
                .heading(level: 1),
                in: "## second",
                selectedRange: NSRange(location: 4, length: 0)
            ),
            .init(
                replacementRange: NSRange(location: 0, length: 9),
                replacementText: "# second",
                selectedRange: NSRange(location: 3, length: 0)
            )
        )

        XCTAssertEqual(
            MomentTextMarkdown.togglingLineStyle(
                .heading(level: 1),
                in: "# second",
                selectedRange: NSRange(location: 3, length: 0)
            ),
            .init(
                replacementRange: NSRange(location: 0, length: 8),
                replacementText: "second",
                selectedRange: NSRange(location: 1, length: 0)
            )
        )
    }

}
