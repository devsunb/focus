import Foundation

/// 로그 레벨
public enum LogLevel: Int, Comparable {
    case info = 0    // 필수 로그 (시작/종료, 에러, 설정)
    case debug = 1   // 상세 로그 (앱/타이틀 변경)

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// 타임스탬프가 포함된 로그 출력
public enum Logger {
    private static let lock = NSLock()
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// 현재 로그 레벨 (이 레벨 이하만 출력)
    public static var level: LogLevel = .info

    /// 기본 로그 (info 레벨)
    public static func log(_ tag: String, _ message: String) {
        log(tag, message, level: .info)
    }

    /// 레벨 지정 로그
    public static func log(_ tag: String, _ message: String, level: LogLevel) {
        guard level <= Self.level else { return }

        lock.lock()
        defer { lock.unlock() }

        // DateFormatter는 thread-safe하지 않으므로 lock 내부에서 접근
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] [\(tag)] \(message)\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardOutput.write(data)
            // 버퍼 플러시로 즉시 출력 보장
            fflush(stdout)
        }
    }

    /// 디버그 로그 (verbose 모드에서만 출력)
    public static func debug(_ tag: String, _ message: String) {
        log(tag, message, level: .debug)
    }
}
