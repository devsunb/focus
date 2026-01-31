import Foundation

/// 세션 출력 포맷 유틸리티
public enum SessionFormatter {
    // DateFormatter는 thread-safe하지 않으므로 lock으로 보호.
    // 현재 CLI(단일 스레드)와 데몬(actor 격리) 모두 동시 접근이 없지만,
    // 향후 사용 패턴 변경에 대비한 방어적 프로그래밍.
    private static let lock = NSLock()
    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// 날짜/시간 포맷: "yyyy-MM-dd HH:mm:ss"
    public static func formatDateTime(_ date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return dateTimeFormatter.string(from: date)
    }

    /// 세션 상세 정보 출력
    public static func printSession(_ session: Session, showOngoingLabel: Bool = false) {
        let startTime = formatDateTime(session.startedAt)
        let endTime = session.endedAt.map { formatDateTime($0) } ?? "(ongoing)"
        let duration = DurationFormatter.detailed(Int(session.currentDuration))
        let ongoing = (showOngoingLabel && session.endedAt == nil) ? " ← ONGOING" : ""

        print("")
        print("ID: \(session.id ?? 0)\(ongoing)")
        print("  App:      \(session.appName) (\(session.bundleId))")
        if let title = session.windowTitle {
            print("  Window:   \(title)")
        }
        print("  Start:    \(startTime)")
        print("  End:      \(endTime)")
        print("  Duration: \(duration)")
    }
}
