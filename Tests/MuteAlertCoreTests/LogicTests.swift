import XCTest
@testable import MuteAlertCore

final class LogicTests: XCTestCase {
    func testLabels() {
        XCTAssertFalse(Match.label("Unmute", "mute"))
        XCTAssertTrue(Match.label("Turn off microphone (⌘ D)", "turn off microphone"))
        XCTAssertTrue(Match.label("(1) Meet – abc", "meet -|meet –"))
        XCTAssertFalse(Match.label("Google Search", "meet -|meet –"))
    }
    func testSpeechGateAndCooldown() {
        var gate = SpeechGate()
        XCTAssertFalse(gate.update(now: 1, peak: 0.5, muted: true, canHear: true, threshold: 0.1, delay: 0.5))
        XCTAssertTrue(gate.update(now: 2, peak: 0.5, muted: true, canHear: true, threshold: 0.1, delay: 0.5))
        XCTAssertFalse(gate.update(now: 3, peak: 0.5, muted: true, canHear: true, threshold: 0.1, delay: 0.5))
        XCTAssertFalse(gate.update(now: 14, peak: 0.5, muted: true, canHear: false, threshold: 0.1, delay: 0.5))
    }
    func testVersionsAndReportValidation() {
        XCTAssertLessThan(Version("0.1.9")!, Version("v0.2.0")!)
        XCTAssertNil(Version("latest"))
        XCTAssertNil(SteelSeriesState.muted(report: []))
        var report = [UInt8](repeating: 0, count: 64)
        report[0] = 6; report[1] = 0xB0; report[15] = 8; report[9] = 1
        XCTAssertEqual(SteelSeriesState.muted(report: report), true)
        report[9] = 2
        XCTAssertNil(SteelSeriesState.muted(report: report))
    }
}
