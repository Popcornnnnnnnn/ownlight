import XCTest
@testable import PrivateMoments

final class MarkdownRenderingSettingsTests: XCTestCase {
    private var savedMathRendering = false
    private var savedRemoteImages = false
    private var savedRawHTML = false

    override func setUp() {
        super.setUp()
        savedMathRendering = AppSettings.markdownMathRenderingEnabled
        savedRemoteImages = AppSettings.markdownRemoteImagesEnabled
        savedRawHTML = AppSettings.markdownRawHTMLRenderingEnabled
        UserDefaults.standard.removeObject(forKey: AppSettings.KeysForTesting.markdownMathRenderingEnabled)
        UserDefaults.standard.removeObject(forKey: AppSettings.KeysForTesting.markdownRemoteImagesEnabled)
        UserDefaults.standard.removeObject(forKey: AppSettings.KeysForTesting.markdownRawHTMLRenderingEnabled)
    }

    override func tearDown() {
        AppSettings.markdownMathRenderingEnabled = savedMathRendering
        AppSettings.markdownRemoteImagesEnabled = savedRemoteImages
        AppSettings.markdownRawHTMLRenderingEnabled = savedRawHTML
        super.tearDown()
    }

    func testAdvancedMarkdownRenderingOptionsDefaultToOff() {
        XCTAssertFalse(AppSettings.markdownMathRenderingEnabled)
        XCTAssertFalse(AppSettings.markdownRemoteImagesEnabled)
        XCTAssertFalse(AppSettings.markdownRawHTMLRenderingEnabled)
    }

    func testSafeRenderingSourceDoesNotRenderRemoteImagesByDefault() {
        let source = "Look\n\n![diagram](https://example.com/private.png)"
        let rendered = MomentTextMarkdown.renderingSource(
            source,
            options: .init(
                mathRenderingEnabled: false,
                remoteImagesEnabled: false,
                rawHTMLRenderingEnabled: false
            )
        )

        XCTAssertEqual(rendered, "Look\n\n[diagram](https://example.com/private.png)")
    }

    func testSearchableTextStripsCommonMarkdownSyntax() {
        let source = """
        ## Heading
        **bold** and `code`
        - first
        [link](https://example.com)
        """

        XCTAssertEqual(
            MomentTextMarkdown.searchableText(source),
            "Heading\nbold and code\nfirst\nlink"
        )
    }

    func testMathOptionStylesLatexSourceWithoutChangingDefault() {
        let source = "Inline $x^2$.\n\n$$\ny = mx + b\n$$"

        XCTAssertEqual(
            MomentTextMarkdown.renderingSource(
                source,
                options: .init(
                    mathRenderingEnabled: false,
                    remoteImagesEnabled: false,
                    rawHTMLRenderingEnabled: false
                )
            ),
            source
        )
        XCTAssertEqual(
            MomentTextMarkdown.renderingSource(
                source,
                options: .init(
                    mathRenderingEnabled: true,
                    remoteImagesEnabled: false,
                    rawHTMLRenderingEnabled: false
                )
            ),
            "Inline `x^2`.\n\n\n```latex\ny = mx + b\n```\n"
        )
    }

    func testRawHTMLIsEscapedByDefault() {
        XCTAssertEqual(
            MomentTextMarkdown.renderingSource(
                "<script>alert(1)</script>\n<div>note</div>",
                options: .init(
                    mathRenderingEnabled: false,
                    remoteImagesEnabled: false,
                    rawHTMLRenderingEnabled: false
                )
            ),
            "&lt;script&gt;alert(1)&lt;/script&gt;\n&lt;div&gt;note&lt;/div&gt;"
        )
    }
}
