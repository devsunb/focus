import Testing
import Foundation
@testable import FocusCore

@Suite("DateUtils Tests")
struct DateUtilsTests {
    // MARK: - parse() Tests

    @Test("parse date only format")
    func parseDateOnly() {
        let result = DateUtils.parse("2024-03-15")
        #expect(result != nil)
        #expect(result?.hasTime == false)

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: result!.date)
        #expect(components.year == 2024)
        #expect(components.month == 3)
        #expect(components.day == 15)
    }

    @Test("parse datetime with minutes")
    func parseDateTimeMinutes() {
        let result = DateUtils.parse("2024-03-15 14:30")
        #expect(result != nil)
        #expect(result?.hasTime == true)

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result!.date)
        #expect(components.year == 2024)
        #expect(components.month == 3)
        #expect(components.day == 15)
        #expect(components.hour == 14)
        #expect(components.minute == 30)
    }

    @Test("parse datetime with seconds")
    func parseDateTimeSeconds() {
        let result = DateUtils.parse("2024-03-15 14:30:45")
        #expect(result != nil)
        #expect(result?.hasTime == true)

        let calendar = Calendar.current
        let components = calendar.dateComponents([.second], from: result!.date)
        #expect(components.second == 45)
    }

    @Test("parse invalid format returns nil")
    func parseInvalid() {
        #expect(DateUtils.parse("invalid") == nil)
        #expect(DateUtils.parse("15-03-2024") == nil)
        #expect(DateUtils.parse("") == nil)
        #expect(DateUtils.parse("abc-de-fg") == nil)
    }

    // MARK: - dateRange() Tests

    @Test("dateRange with date only expands to day boundaries")
    func dateRangeDateOnly() {
        let result = DateUtils.dateRange(from: "2024-03-15", to: nil)
        #expect(result != nil)

        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute, .second], from: result!.start)
        #expect(startComponents.hour == 0)
        #expect(startComponents.minute == 0)
        #expect(startComponents.second == 0)
    }

    @Test("dateRange with datetime preserves time")
    func dateRangeDateTimePreservesTime() {
        let result = DateUtils.dateRange(from: "2024-03-15 14:30", to: nil)
        #expect(result != nil)

        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute], from: result!.start)
        #expect(startComponents.hour == 14)
        #expect(startComponents.minute == 30)
    }

    @Test("dateRange with invalid from returns nil")
    func dateRangeInvalidFrom() {
        #expect(DateUtils.dateRange(from: "invalid", to: nil) == nil)
    }

    @Test("dateRange with invalid to returns nil")
    func dateRangeInvalidTo() {
        #expect(DateUtils.dateRange(from: "2024-03-15", to: "invalid") == nil)
    }

    @Test("dateRange to date only expands to end of day")
    func dateRangeToDateExpands() {
        let result = DateUtils.dateRange(from: "2024-03-15", to: "2024-03-16")
        #expect(result != nil)

        // to가 날짜만이면 그 다음날 시작으로 확장됨
        let calendar = Calendar.current
        let endComponents = calendar.dateComponents([.year, .month, .day, .hour], from: result!.end)
        #expect(endComponents.year == 2024)
        #expect(endComponents.month == 3)
        #expect(endComponents.day == 17)  // 16일 + 1일
        #expect(endComponents.hour == 0)
    }

    @Test("dateRange same date for from and to covers full day")
    func dateRangeSameDate() {
        let result = DateUtils.dateRange(from: "2026-02-01", to: "2026-02-01")
        #expect(result != nil)

        let calendar = Calendar.current

        // start = 2026-02-01 00:00:00
        let startComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: result!.start)
        #expect(startComponents.year == 2026)
        #expect(startComponents.month == 2)
        #expect(startComponents.day == 1)
        #expect(startComponents.hour == 0)
        #expect(startComponents.minute == 0)
        #expect(startComponents.second == 0)

        // end = 2026-02-02 00:00:00 (다음날 자정, exclusive)
        let endComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: result!.end)
        #expect(endComponents.year == 2026)
        #expect(endComponents.month == 2)
        #expect(endComponents.day == 2)
        #expect(endComponents.hour == 0)
        #expect(endComponents.minute == 0)
        #expect(endComponents.second == 0)

        // 2026-02-01 23:59:59는 범위 안 (startedAt < end)
        let lastSecond = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1, hour: 23, minute: 59, second: 59))!
        #expect(lastSecond >= result!.start)
        #expect(lastSecond < result!.end)

        // 2026-02-02 00:00:00은 범위 밖
        let nextDayMidnight = calendar.date(from: DateComponents(year: 2026, month: 2, day: 2, hour: 0, minute: 0, second: 0))!
        #expect(!(nextDayMidnight >= result!.start && nextDayMidnight < result!.end))
    }

    // MARK: - parseRelativeTime() Tests

    @Test("parseRelativeTime single unit")
    func parseRelativeTimeSingle() {
        #expect(DateUtils.parseRelativeTime("1w") == 604800)
        #expect(DateUtils.parseRelativeTime("2d") == 172800)
        #expect(DateUtils.parseRelativeTime("3h") == 10800)
        #expect(DateUtils.parseRelativeTime("30m") == 1800)
        #expect(DateUtils.parseRelativeTime("45s") == 45)
    }

    @Test("parseRelativeTime combined units")
    func parseRelativeTimeCombined() {
        // 1w2d3h4m5s = 604800 + 172800 + 10800 + 240 + 5 = 788645
        #expect(DateUtils.parseRelativeTime("1w2d3h4m5s") == 788645)
        #expect(DateUtils.parseRelativeTime("1h30m") == 5400)
        #expect(DateUtils.parseRelativeTime("2d12h") == 216000)
    }

    @Test("parseRelativeTime duplicate units are summed")
    func parseRelativeTimeDuplicate() {
        // 1h1h = 3600 + 3600 = 7200
        #expect(DateUtils.parseRelativeTime("1h1h") == 7200)
    }

    @Test("parseRelativeTime invalid formats return nil")
    func parseRelativeTimeInvalid() {
        #expect(DateUtils.parseRelativeTime("") == nil)
        #expect(DateUtils.parseRelativeTime("abc") == nil)
        #expect(DateUtils.parseRelativeTime("1x") == nil)
        #expect(DateUtils.parseRelativeTime("h1") == nil)
        #expect(DateUtils.parseRelativeTime("1") == nil)
        #expect(DateUtils.parseRelativeTime("0s") == nil) // 0은 의미 없음
        #expect(DateUtils.parseRelativeTime("2024-01-15") == nil)
    }

    @Test("parseRelativeTime large values")
    func parseRelativeTimeLargeValues() {
        #expect(DateUtils.parseRelativeTime("52w") == 52.0 * 604800)
        #expect(DateUtils.parseRelativeTime("365d") == 365.0 * 86400)
    }

    @Test("isRelativeTime correctly identifies relative strings")
    func isRelativeTime() {
        #expect(DateUtils.isRelativeTime("1w") == true)
        #expect(DateUtils.isRelativeTime("3h30m") == true)
        #expect(DateUtils.isRelativeTime("2024-01-15") == false)
        #expect(DateUtils.isRelativeTime("invalid") == false)
    }

    // MARK: - dateRange() with Relative Time

    @Test("dateRange with relative from")
    func dateRangeRelativeFrom() {
        let before = Date()
        let result = DateUtils.dateRange(from: "1h", to: nil)
        let after = Date()

        #expect(result != nil)
        let (start, end) = result!

        // start는 약 1시간 전
        let expectedStart = before.addingTimeInterval(-3600)
        #expect(abs(start.timeIntervalSince(expectedStart)) < 1)

        // end는 now
        #expect(end >= before && end <= after)
    }

    @Test("dateRange with relative from and relative to")
    func dateRangeRelativeFromTo() {
        let before = Date()
        let result = DateUtils.dateRange(from: "2h", to: "1h")

        #expect(result != nil)
        let (start, end) = result!

        // start는 약 2시간 전, end는 약 1시간 전
        let expectedStart = before.addingTimeInterval(-7200)
        let expectedEnd = before.addingTimeInterval(-3600)
        #expect(abs(start.timeIntervalSince(expectedStart)) < 1)
        #expect(abs(end.timeIntervalSince(expectedEnd)) < 1)
    }

    @Test("dateRange inverted range returns nil")
    func dateRangeInvertedRange() {
        // from이 to보다 뒤 → nil
        #expect(DateUtils.dateRange(from: "1h", to: "2h") == nil)
        #expect(DateUtils.dateRange(from: "2024-03-16", to: "2024-03-15") == nil)
    }

    // MARK: - Inclusive to Boundary

    @Test("dateRange to with time is inclusive (adds 1 second)")
    func dateRangeToTimeInclusive() {
        let result = DateUtils.dateRange(from: "2024-03-15", to: "2024-03-15 14:30")
        #expect(result != nil)

        let calendar = Calendar.current
        let endComponents = calendar.dateComponents([.hour, .minute, .second], from: result!.end)
        #expect(endComponents.hour == 14)
        #expect(endComponents.minute == 30)
        #expect(endComponents.second == 1)  // +1초
    }

    @Test("dateRange to with seconds is inclusive (adds 1 second)")
    func dateRangeToSecondsInclusive() {
        let result = DateUtils.dateRange(from: "2024-03-15", to: "2024-03-15 14:30:30")
        #expect(result != nil)

        let calendar = Calendar.current
        let endComponents = calendar.dateComponents([.hour, .minute, .second], from: result!.end)
        #expect(endComponents.hour == 14)
        #expect(endComponents.minute == 30)
        #expect(endComponents.second == 31)  // +1초
    }

    // MARK: - parseDateOptions() with Relative Time

    @Test("parseDateOptions with relative date")
    func parseDateOptionsRelativeDate() {
        let before = Date()
        let result = DateUtils.parseDateOptions(date: "2h", from: nil, to: nil)
        let after = Date()

        #expect(result != nil)
        let (start, end) = result!

        // start는 약 2시간 전, end는 now
        let expectedStart = before.addingTimeInterval(-7200)
        #expect(abs(start.timeIntervalSince(expectedStart)) < 1)
        #expect(end >= before && end <= after)
    }

    @Test("parseDateOptions with relative from")
    func parseDateOptionsRelativeFrom() {
        let before = Date()
        let result = DateUtils.parseDateOptions(date: nil, from: "1d", to: nil)
        let after = Date()

        #expect(result != nil)
        let (start, end) = result!

        let expectedStart = before.addingTimeInterval(-86400)
        #expect(abs(start.timeIntervalSince(expectedStart)) < 1)
        #expect(end >= before && end <= after)
    }
}
