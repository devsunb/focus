import Testing
@testable import FocusCore

@Suite("DurationFormatter Tests")
struct DurationFormatterTests {
    // MARK: - detailed() Tests

    @Test("detailed with zero seconds")
    func detailedZero() {
        #expect(DurationFormatter.detailed(0) == "0s")
    }

    @Test("detailed with seconds only")
    func detailedSecondsOnly() {
        #expect(DurationFormatter.detailed(45) == "45s")
        #expect(DurationFormatter.detailed(1) == "1s")
        #expect(DurationFormatter.detailed(59) == "59s")
    }

    @Test("detailed with minutes and seconds")
    func detailedMinutesAndSeconds() {
        #expect(DurationFormatter.detailed(60) == "1m 0s")
        #expect(DurationFormatter.detailed(90) == "1m 30s")
        #expect(DurationFormatter.detailed(330) == "5m 30s")
        #expect(DurationFormatter.detailed(3599) == "59m 59s")
    }

    @Test("detailed with hours, minutes and seconds")
    func detailedHoursMinutesSeconds() {
        #expect(DurationFormatter.detailed(3600) == "1h 0m 0s")
        #expect(DurationFormatter.detailed(3661) == "1h 1m 1s")
        #expect(DurationFormatter.detailed(7323) == "2h 2m 3s")
        #expect(DurationFormatter.detailed(86399) == "23h 59m 59s")
    }

    // MARK: - compact() Tests

    @Test("compact with zero seconds shows 0m")
    func compactZero() {
        #expect(DurationFormatter.compact(0) == "0m")
        #expect(DurationFormatter.compact(-1) == "0m")
    }

    @Test("compact rounds up to nearest minute")
    func compactRoundsUp() {
        #expect(DurationFormatter.compact(1) == "1m")   // 1초 → 1분
        #expect(DurationFormatter.compact(30) == "1m")  // 30초 → 1분
        #expect(DurationFormatter.compact(59) == "1m")  // 59초 → 1분
        #expect(DurationFormatter.compact(60) == "1m")  // 60초 → 1분
        #expect(DurationFormatter.compact(61) == "2m")  // 61초 → 2분
        #expect(DurationFormatter.compact(119) == "2m") // 119초 → 2분
        #expect(DurationFormatter.compact(120) == "2m") // 120초 → 2분
    }

    @Test("compact with minutes only")
    func compactMinutesOnly() {
        #expect(DurationFormatter.compact(300) == "5m")
        #expect(DurationFormatter.compact(1500) == "25m")
        #expect(DurationFormatter.compact(3540) == "59m")  // 59분 정확히
        #expect(DurationFormatter.compact(3599) == "1h 0m")  // 59분 59초 → 올림 60분 → 1h 0m
    }

    @Test("compact with hours and minutes")
    func compactHoursAndMinutes() {
        #expect(DurationFormatter.compact(3600) == "1h 0m")
        #expect(DurationFormatter.compact(3601) == "1h 1m")  // 1시간 1초 → 1시간 1분
        #expect(DurationFormatter.compact(3900) == "1h 5m")
        #expect(DurationFormatter.compact(7320) == "2h 2m")
    }
}
