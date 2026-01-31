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
}
