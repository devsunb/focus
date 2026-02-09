import Foundation

public enum DateUtils {
    private static let lock = NSLock()

    // MARK: - Formatters (private, thread-unsafe)

    /// "yyyy-MM-dd HH:mm" 형식 (출력 및 파싱용)
    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    /// "yyyy-MM-dd" 형식 (출력 및 파싱용)
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// "HH:mm" 형식 (시간만 출력용)
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// "yyyy-MM-dd HH:mm:ss" 형식 (파싱용)
    private static let dateTimeSecondsFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    // MARK: - Relative Time Parsing

    /// `1w2d3h4m5s` 형식의 상대 시간 문자열을 초 단위 TimeInterval로 변환
    /// - 지원 단위: w(주), d(일), h(시), m(분), s(초)
    /// - 중복 단위 허용 (합산)
    /// - DateFormatter 미사용으로 lock 불필요
    public static func parseRelativeTime(_ str: String) -> TimeInterval? {
        let trimmed = str.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // 전체 문자열이 (숫자+단위) 반복으로만 구성되는지 검증
        let fullPattern = try! NSRegularExpression(pattern: #"^(\d+[wdhms])+$"#)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard fullPattern.firstMatch(in: trimmed, range: range) != nil else {
            return nil
        }

        // 개별 (숫자, 단위) 추출
        let unitPattern = try! NSRegularExpression(pattern: #"(\d+)([wdhms])"#)
        let matches = unitPattern.matches(in: trimmed, range: range)

        let multipliers: [Character: TimeInterval] = [
            "w": 604800, "d": 86400, "h": 3600, "m": 60, "s": 1,
        ]

        var total: TimeInterval = 0
        for match in matches {
            let numberRange = Range(match.range(at: 1), in: trimmed)!
            let unitRange = Range(match.range(at: 2), in: trimmed)!
            guard let value = Double(trimmed[numberRange]),
                  let multiplier = multipliers[trimmed[unitRange].first!] else {
                return nil
            }
            total += value * multiplier
        }

        return total > 0 ? total : nil
    }

    /// 문자열이 relative time 형식인지 확인
    public static func isRelativeTime(_ str: String) -> Bool {
        parseRelativeTime(str) != nil
    }

    // MARK: - Thread-safe Format Methods

    public static func formatDateTime(_ date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return dateTimeFormatter.string(from: date)
    }

    public static func formatDate(_ date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return dateFormatter.string(from: date)
    }

    public static func formatTime(_ date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return timeFormatter.string(from: date)
    }

    /// 날짜/시간 문자열 파싱
    /// - Returns: (date, hasTime) 튜플. hasTime은 시간이 포함되었는지 여부
    public static func parse(_ str: String) -> (date: Date, hasTime: Bool)? {
        lock.lock()
        defer { lock.unlock() }

        // 시간 포함 형식
        if let date = dateTimeSecondsFormatter.date(from: str) {
            return (date, true)
        }
        if let date = dateTimeFormatter.date(from: str) {
            return (date, true)
        }

        // 날짜만
        if let date = dateFormatter.date(from: str) {
            return (date, false)
        }

        return nil
    }

    /// 날짜 범위 계산. 시간이 없으면 날짜 경계로 확장
    /// - relative time: `1w2d3h` → `(now - interval, now)`
    /// - `to`에 시간 명시(HH:mm 또는 HH:mm:ss): +1초로 inclusive 경계
    /// - `to`가 date-only: 다음날 00:00:00 (기존 동작)
    /// - 범위 역전 시 nil 반환
    public static func dateRange(from fromStr: String, to toStr: String?) -> (start: Date, end: Date)? {
        let now = Date()

        // from 파싱: relative → absolute 순서
        let startDate: Date
        if let interval = parseRelativeTime(fromStr) {
            startDate = now.addingTimeInterval(-interval)
        } else if let (fromDate, fromHasTime) = parse(fromStr) {
            let calendar = Calendar.current
            startDate = fromHasTime ? fromDate : calendar.startOfDay(for: fromDate)
        } else {
            return nil
        }

        // to 파싱
        let endDate: Date
        if let toStr = toStr {
            if let interval = parseRelativeTime(toStr) {
                endDate = now.addingTimeInterval(-interval)
            } else if let (toDate, toHasTime) = parse(toStr) {
                if toHasTime {
                    // 시간 명시 → +1초 (inclusive 경계)
                    endDate = toDate.addingTimeInterval(1)
                } else {
                    // date-only → 다음날 00:00:00
                    let calendar = Calendar.current
                    let startOfToDay = calendar.startOfDay(for: toDate)
                    endDate = calendar.date(byAdding: .day, value: 1, to: startOfToDay)
                        ?? startOfToDay.addingTimeInterval(86400)
                }
            } else {
                return nil
            }
        } else {
            endDate = now
        }

        // 범위 역전 검증
        guard startDate < endDate else { return nil }

        return (startDate, endDate)
    }

    /// 특정 날짜를 하루 전체 범위로 변환
    public static func dayRange(for date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)
            ?? startOfDay.addingTimeInterval(86400)
        return (startOfDay, endOfDay)
    }

    /// CLI 옵션 파싱: --date 또는 --from/--to 조합을 날짜 범위로 변환
    /// - Parameters:
    ///   - date: 특정 날짜 (YYYY-MM-DD) 또는 relative time (1w2d3h)
    ///   - from: 시작 날짜/시간 또는 relative time
    ///   - to: 종료 날짜/시간 또는 relative time (nil이면 현재)
    /// - Returns: 날짜 범위 또는 nil (모든 옵션이 nil인 경우)
    public static func parseDateOptions(date: String?, from: String?, to: String?) -> (start: Date, end: Date)? {
        if let dateStr = date {
            // relative time: (now - interval, now)
            if let interval = parseRelativeTime(dateStr) {
                let now = Date()
                return (now.addingTimeInterval(-interval), now)
            }
            guard let (parsedDate, _) = parse(dateStr) else {
                return nil
            }
            return dayRange(for: parsedDate)
        } else if let fromStr = from {
            return dateRange(from: fromStr, to: to)
        }
        return nil
    }
}
