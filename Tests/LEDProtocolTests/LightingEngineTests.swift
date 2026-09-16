import XCTest

@testable import LEDProtocol

final class LightingEngineTests: XCTestCase {
    func testLanguageResolutionSupportsRegionalPreferencesAndEnglishFallback() {
        XCTAssertEqual(AppLanguage.resolve(["es-MX", "en-US"]), "es")
        XCTAssertEqual(AppLanguage.resolve(["en-GB", "es"]), "en")
        XCTAssertEqual(AppLanguage.resolve(["fr-FR", "es_ES"]), "es")
        XCTAssertEqual(AppLanguage.resolve(["de-DE"]), "en")
        XCTAssertEqual(AppLanguage.resolve([]), "en")
    }

    func testNotificationFlashHasThreePulsesAndFinishes() {
        for (time, hex) in [(0.1, 0xFF0000), (0.4, 0), (0.7, 0x00FF00), (1.0, 0), (1.3, 0x0000FF), (1.6, 0)] {
            XCTAssertEqual(NotificationFlash.color(elapsed: time)?.hex, hex)
        }
        XCTAssertNil(NotificationFlash.color(elapsed: -1))
        XCTAssertNil(NotificationFlash.color(elapsed: 1.8))
        XCTAssertNil(NotificationFlash.color(elapsed: 20))
    }

    func testAlternationUsesWholeStripRGBInOrder() {
        let palette = LightPalette.rgb.colors(base: .init(hex: 0))
        for (time, expected) in [(0.0, 0xFF0000), (1.0, 0x00FF00), (2.0, 0x0000FF), (3.0, 0xFF0000)] {
            XCTAssertEqual(
                AnimationRenderer.color(style: .jump, palette: palette, elapsed: time, speed: 1).hex, expected
            )
        }
    }
    func testEveryAnimationIsBoundedAndHandlesEmptyPalette() {
        for style in AnimationStyle.allCases {
            for i in 0..<150 {
                let color = AnimationRenderer.color(
                    style: style, palette: [], elapsed: Double(i) / 15, speed: 3)
                XCTAssertTrue((0...0xFFFFFF).contains(color.hex))
            }
        }
    }
    func testBreathingAndFadeActuallyChangeIntensity() {
        let color = AmbientRGB(hex: 0xFF0000)
        let low = AnimationRenderer.color(style: .breathe, palette: [color], elapsed: 0, speed: 1)
        let high = AnimationRenderer.color(style: .breathe, palette: [color], elapsed: 1, speed: 1)
        XCTAssertLessThan(low.red, high.red)
        let blend = AnimationRenderer.color(
            style: .fade, palette: [.init(hex: 0xFF0000), .init(hex: 0x0000FF)], elapsed: 1, speed: 1)
        XCTAssertEqual(blend.red, 128)
        XCTAssertEqual(blend.blue, 128)
    }
    func testDominantScreenColorDoesNotAverageComplementaryColorsToGray() {
        let pixels =
            Array(repeating: AmbientRGB(hex: 0xFF0000), count: 6)
            + Array(repeating: AmbientRGB(hex: 0x00FFFF), count: 4)
        XCTAssertEqual(
            ScreenColorAnalyzer.color(pixels: pixels, style: .dominant, saturation: 1).hex, 0xFF0000)
        XCTAssertNotEqual(
            ScreenColorAnalyzer.color(pixels: pixels, style: .average, saturation: 1).hex, 0xFF0000)
        XCTAssertEqual(ScreenColorAnalyzer.color(pixels: [], style: .dominant, saturation: 1).hex, 0)
    }
    func testNeutralAndBlackScreenRemainNeutralAndBlack() {
        XCTAssertEqual(
            ScreenColorAnalyzer.color(pixels: [.init(hex: 0x808080)], style: .dominant, saturation: 2).hex,
            0x808080)
        XCTAssertEqual(
            ScreenColorAnalyzer.color(pixels: [.init(hex: 0)], style: .dominant, saturation: 2).hex, 0)
    }
    func testAudioSeparatesLowAndHighFrequencyAndPreservesSilence() {
        func tone(_ frequency: Double) -> [Float] {
            (0..<4800).map { Float(sin(Double($0) * 2 * .pi * frequency / 48000) * 0.4) }
        }
        var lowAnalyzer = AudioAnalyzer()
        var highAnalyzer = AudioAnalyzer()
        var silentAnalyzer = AudioAnalyzer()
        let bass = lowAnalyzer.process(tone(80), sampleRate: 48000)
        let treble = highAnalyzer.process(tone(9000), sampleRate: 48000)
        XCTAssertGreaterThan(bass.bass, bass.treble * 3)
        XCTAssertGreaterThan(treble.treble, treble.bass * 3)
        XCTAssertEqual(silentAnalyzer.process(Array(repeating: 0, count: 2048), sampleRate: 48000).volume, 0)
    }
    func testAudioEnvelopesGoDarkInSilence() {
        for style in MusicStyle.allCases {
            var envelope = AudioLightEnvelope()
            let loud = envelope.color(
                levels: .init(bass: 0.2, mid: 0.1, treble: 0.05, volume: 0.3), style: style,
                base: .init(hex: 0xFF8855), sensitivity: 1, delta: 0.07)
            XCTAssertNotEqual(loud.hex, 0)
            XCTAssertEqual(
                envelope.color(
                    levels: .init(), style: style, base: .init(hex: 0xFFFFFF), sensitivity: 4, delta: 0.07
                ).hex, 0)
        }
    }
    func testMusicChangesColorWithRepeatedBassAttacks() {
        var envelope = AudioLightEnvelope()
        let base = AmbientRGB(hex: 0xFF0000)
        let hit = AudioLevels(bass: 0.3, mid: 0.03, treble: 0.01, volume: 0.35)
        let first = envelope.color(levels: hit, style: .beat, base: base, sensitivity: 1.2, delta: 0.067)
        for _ in 0..<12 {
            _ = envelope.color(levels: .init(), style: .beat, base: base, sensitivity: 1.2, delta: 0.067)
        }
        let second = envelope.color(levels: hit, style: .beat, base: base, sensitivity: 1.2, delta: 0.067)
        XCTAssertNotEqual(first.hex, second.hex)
        XCTAssertNotEqual(second.hex, base.hex)
    }
    func testSustainedToneDoesNotCycleColorsLikeATimer() {
        var envelope = AudioLightEnvelope()
        let tone = AudioLevels(bass: 0.2, mid: 0.01, treble: 0.01, volume: 0.21)
        var settled = AmbientRGB(hex: 0)
        for _ in 0..<100 {
            settled = envelope.color(
                levels: tone, style: .beat, base: .init(hex: 0), sensitivity: 1.2, delta: 0.067)
        }
        for _ in 0..<100 {
            XCTAssertEqual(
                envelope.color(
                    levels: tone, style: .beat, base: .init(hex: 0), sensitivity: 1.2, delta: 0.067), settled)
        }
    }
    func testMusicFrequencyColorsSeparateBassMidAndTreble() {
        var outputs: [AmbientRGB] = []
        for bands in [
            AudioLevels(bass: 0.3, mid: 0.01, treble: 0.01, volume: 0.3),
            AudioLevels(bass: 0.01, mid: 0.3, treble: 0.01, volume: 0.3),
            AudioLevels(bass: 0.01, mid: 0.01, treble: 0.3, volume: 0.3),
        ] {
            var envelope = AudioLightEnvelope()
            var color = AmbientRGB(hex: 0)
            for _ in 0..<60 {
                color = envelope.color(
                    levels: bands, style: .spectrum, base: .init(hex: 0), sensitivity: 1.2, delta: 0.067)
            }
            outputs.append(color)
        }
        XCTAssertGreaterThan(outputs[0].red, outputs[0].blue * 3)
        XCTAssertGreaterThan(outputs[1].green, outputs[1].red * 3)
        XCTAssertGreaterThan(outputs[2].blue, outputs[2].green * 3)
    }
    func testSchedulesAdvancePastTodayAndDisabledRulesDoNotRun() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 22, minute: 0))!
        var rule = LightSchedule(hour: 22, minute: 0, sceneID: "off")
        let next = rule.nextDate(after: now, calendar: calendar)!
        XCTAssertEqual(calendar.component(.day, from: next), 17)
        rule.enabled = false
        XCTAssertNil(rule.nextDate(after: now, calendar: calendar))
        XCTAssertNil(
            LightSchedule(hour: 25, minute: 0, sceneID: "off").nextDate(after: now, calendar: calendar))
    }
    func testGameThemeOnlyIdentifiesAppNotGameEvents() {
        XCTAssertEqual(GameTheme.detect(appName: "Minecraft"), .blocks)
        XCTAssertEqual(GameTheme.detect(appName: "Safari"), .neutral)
    }
}
