import XCTest
@testable import Crux

/// Covers the reader appearance pipeline introduced with the Aa popover:
/// theme-aware CSS generation, custom color overrides, font-stack mapping,
/// margin clamping, and the JS string encoding used for live style swaps.
final class ReaderAppearanceCSSTests: XCTestCase {

    // MARK: - Helpers

    private func css(
        fontFamily: String = "System",
        fontSize: Double = 16,
        lineHeight: Double = 1.6,
        paragraphSpacing: Double = 1.2,
        marginWidth: Double = 60,
        theme: AppTheme = .system,
        backgroundColor: String? = nil,
        textColor: String? = nil
    ) -> String {
        ReaderResources.generateCustomCSS(
            fontFamily: fontFamily,
            fontSize: fontSize,
            lineHeight: lineHeight,
            paragraphSpacing: paragraphSpacing,
            marginWidth: marginWidth,
            theme: theme,
            backgroundColor: backgroundColor ?? theme.backgroundColor,
            textColor: textColor ?? theme.textColor
        )
    }

    // MARK: - Theme palettes

    func testSystemThemeEmitsNoColorPalette() {
        // System defers colors entirely to reader.css (light palette +
        // prefers-color-scheme dark override) so the page can track the OS
        // appearance without a reload.
        let result = css(theme: .system)
        XCTAssertFalse(result.contains("--crux-bg"), "System theme must not pin a background")
        XCTAssertFalse(result.contains("--crux-text:"), "System theme must not pin a text color")
        XCTAssertFalse(result.contains("--crux-accent"), "System theme must not pin an accent")
    }

    func testSystemThemeIgnoresUntouchedFactoryColors() {
        // Fresh installs (and stores that predate the theme system) hold
        // factory #FFFFFF/#000000 without the user ever opening a color
        // picker. Those must not pin black-on-white into OS dark mode.
        let result = css(theme: .system, backgroundColor: "#FFFFFF", textColor: "#000000")
        XCTAssertFalse(result.contains("--crux-bg"))
        XCTAssertFalse(result.contains("--crux-text:"))
    }

    func testSystemThemeHonorsDeliberateCustomColors() {
        let result = css(theme: .system, backgroundColor: "#FAF0E6", textColor: "#333333")
        XCTAssertTrue(result.contains("--crux-bg: #FAF0E6;"))
        XCTAssertTrue(result.contains("--crux-text: #333333;"))
    }

    func testExplicitThemeEmitsFullPalette() {
        let result = css(theme: .sepia)
        XCTAssertTrue(result.contains("--crux-bg: #F4ECD8;"))
        XCTAssertTrue(result.contains("--crux-text: #5C4B37;"))
        // The whole point of the palette: accents/highlights are themed too.
        XCTAssertTrue(result.contains("--crux-accent:"))
        XCTAssertTrue(result.contains("--crux-highlight:"))
        XCTAssertTrue(result.contains("--crux-highlight-hover:"))
        XCTAssertTrue(result.contains("--crux-selection:"))
        XCTAssertTrue(result.contains("--crux-rule:"))
        XCTAssertTrue(result.contains("--crux-text-muted:"))
    }

    func testEveryNonSystemThemeHasAPalette() {
        for theme in AppTheme.allCases where theme != .system {
            XCTAssertNotNil(theme.readerPalette, "\(theme.rawValue) should define a reader palette")
        }
        XCTAssertNil(AppTheme.system.readerPalette)
    }

    func testCustomColorsOverrideThemePalette() {
        // A hand-picked page color (Settings color pickers) must win over
        // the theme palette — emitted after it, so the later rule applies.
        let result = css(theme: .sepia, backgroundColor: "#123456", textColor: "#ABCDEF")
        XCTAssertTrue(result.contains("--crux-bg: #123456;"))
        XCTAssertTrue(result.contains("--crux-text: #ABCDEF;"))
        // Later declaration wins in CSS: the override must appear after the
        // palette's value for the same variable.
        let paletteRange = result.range(of: "--crux-bg: #F4ECD8;")
        let overrideRange = result.range(of: "--crux-bg: #123456;")
        XCTAssertNotNil(paletteRange)
        XCTAssertNotNil(overrideRange)
        if let p = paletteRange, let o = overrideRange {
            XCTAssertTrue(p.lowerBound < o.lowerBound, "Override must come after the palette default")
        }
    }

    func testMatchingCustomColorsAreNotDuplicated() {
        let result = css(theme: .dark)
        // Colors equal to the theme's own defaults shouldn't be re-emitted
        // as overrides (count the variable once).
        let occurrences = result.components(separatedBy: "--crux-bg:").count - 1
        XCTAssertEqual(occurrences, 1)
    }

    // MARK: - Fonts

    func testDefaultFontKeepsReaderCSSStack() {
        // "System" means "use the book default" — reader.css's literary
        // serif stack — so no --crux-font-body override is emitted.
        XCTAssertNil(ReaderResources.fontStack(for: "System"))
        XCTAssertFalse(css(fontFamily: "System").contains("--crux-font-body"))
    }

    func testKnownFontsMapToCuratedStacks() {
        XCTAssertEqual(
            ReaderResources.fontStack(for: "New York"),
            "ui-serif, \"New York\", Georgia, serif"
        )
        XCTAssertTrue(ReaderResources.fontStack(for: "San Francisco")?.contains("system-ui") ?? false)
    }

    func testUnknownFontFallsBackToQuotedSerif() {
        XCTAssertEqual(ReaderResources.fontStack(for: "Comic Sans MS"),
                       "\"Comic Sans MS\", Georgia, serif")
        XCTAssertTrue(css(fontFamily: "Comic Sans MS").contains("--crux-font-body: \"Comic Sans MS\", Georgia, serif;"))
    }

    // MARK: - Layout values

    func testTypographyValuesAreEmitted() {
        let result = css(fontSize: 19, lineHeight: 1.8, paragraphSpacing: 1.4)
        XCTAssertTrue(result.contains("font-size: 19.0px;"))
        XCTAssertTrue(result.contains("line-height: 1.8;"))
        XCTAssertTrue(result.contains("margin-bottom: 1.4em;"))
    }

    func testMarginIsScopedToMacOSAndClamped() {
        let result = css(marginWidth: 80)
        XCTAssertTrue(result.contains("[data-platform=\"macos\"]"),
                      "Margins must not leak into the iOS layout")
        XCTAssertTrue(result.contains("padding-left: 80px;"))

        XCTAssertTrue(css(marginWidth: -20).contains("padding-left: 0px;"))
        XCTAssertTrue(css(marginWidth: 9999).contains("padding-left: 400px;"))
    }

    // MARK: - Live-swap JS encoding

    func testJavaScriptStringLiteralEscapesHostileContent() throws {
        let hostile = "body { content: \"</style><script>alert('x')</script>\n\\\" }"
        let literal = try XCTUnwrap(WebViewCoordinator.javaScriptStringLiteral(hostile))
        XCTAssertTrue(literal.hasPrefix("\""))
        XCTAssertTrue(literal.hasSuffix("\""))
        // Raw newlines or unescaped quotes inside the literal would break
        // the injected script.
        let inner = String(literal.dropFirst().dropLast())
        XCTAssertFalse(inner.contains("\n"))
        XCTAssertFalse(inner.replacingOccurrences(of: "\\\"", with: "").contains("\""))
    }

    func testStyleTagCarriesStableIdForLiveSwap() throws {
        let html = try XCTUnwrap(
            ReaderResources.buildHTML(content: "<p>Hello</p>", customCSS: "body { color: red; }")
        )
        XCTAssertTrue(html.contains("<style id=\"crux-custom-css\">"),
                      "Live appearance swaps target this id")
    }
}
