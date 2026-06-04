import XCTest
@testable import Crux

final class AIPromptPresetTests: XCTestCase {

    func testEveryNonCustomPresetHasBundledPrompt() {
        for preset in AIPromptPreset.allCases where preset != .custom {
            let prompt = preset.systemPrompt
            XCTAssertFalse(
                prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Preset \(preset.id) shipped an empty prompt"
            )
            XCTAssertGreaterThan(prompt.count, 40, "Preset \(preset.id) prompt looks too short")
        }
    }

    func testCustomPresetShipsEmptyPromptByDefault() {
        XCTAssertEqual(AIPromptPreset.custom.systemPrompt, "")
    }

    func testRawValueRoundTrip() {
        for preset in AIPromptPreset.allCases {
            XCTAssertEqual(AIPromptPreset(rawValue: preset.id), preset)
        }
    }

    func testAllPresetsHaveDistinctSymbols() {
        let symbols = AIPromptPreset.allCases.map { $0.symbolName }
        XCTAssertEqual(Set(symbols).count, symbols.count)
    }

    func testAllPresetsHaveDistinctDisplayNames() {
        let names = AIPromptPreset.allCases.map { $0.displayName }
        XCTAssertEqual(Set(names).count, names.count)
    }
}
