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
    public static func dateRange(from fromStr: String, to toStr: String?) -> (start: Date, end: Date)? {
        guard let (fromDate, fromHasTime) = parse(fromStr) else {
            return nil
        }

        let calendar = Calendar.current
        let startDate = fromHasTime ? fromDate : calendar.startOfDay(for: fromDate)

        let endDate: Date
        if let toStr = toStr {
            guard let (toDate, toHasTime) = parse(toStr) else {
                return nil
            }
            let startOfToDay = calendar.startOfDay(for: toDate)
            endDate = toHasTime ? toDate : (calendar.date(byAdding: .day, value: 1, to: startOfToDay)
                ?? startOfToDay.addingTimeInterval(86400))
        } else {
            endDate = Date()
        }

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
    ///   - date: 특정 날짜 (YYYY-MM-DD)
    ///   - from: 시작 날짜/시간
    ///   - to: 종료 날짜/시간 (nil이면 현재)
    /// - Returns: 날짜 범위 또는 nil (모든 옵션이 nil인 경우)
    public static func parseDateOptions(date: String?, from: String?, to: String?) -> (start: Date, end: Date)? {
        if let dateStr = date {
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
