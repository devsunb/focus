import Foundation

/// 로그 레벨 (os.Logger 호환)
public enum LogLevel: Int, Comparable {
    case fault = -3    // 치명적 오류 (앱 크래시 수준)
    case error = -2    // 에러
    case warning = -1  // 경고
    case notice = 0    // 주목할 정보 (기본 레벨)
    case info = 1      // 일반 정보
    case debug = 2     // 디버그

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var symbol: String {
        String(String(describing: self).prefix(1).uppercased())
    }

    var ansiColor: String {
        switch self {
        case .fault, .error: return "\u{1B}[31m"
        case .warning: return "\u{1B}[33m"
        case .notice, .info: return "\u{1B}[34m"
        case .debug: return "\u{1B}[90m"
        }
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
    public static var level: LogLevel = .notice

    /// 기본 로그 (notice 레벨)
    public static func log(_ tag: String, _ message: String) {
        log(tag, message, level: .notice)
    }

    /// 레벨 지정 로그
    public static func log(_ tag: String, _ message: String, level: LogLevel) {
        guard level <= Self.level else { return }

        lock.lock()
        defer { lock.unlock() }

        // DateFormatter는 thread-safe하지 않으므로 lock 내부에서 접근
        let timestamp = formatter.string(from: Date())
        let line = "\(timestamp) \(level.ansiColor)\(level.symbol)\u{1B}[0m [\(tag)] \(message)\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardOutput.write(data)
            // 버퍼 플러시로 즉시 출력 보장
            fflush(stdout)
        }
    }

    /// 치명적 오류 로그
    public static func fault(_ tag: String, _ message: String) {
        log(tag, message, level: .fault)
    }

    /// 에러 로그
    public static func error(_ tag: String, _ message: String) {
        log(tag, message, level: .error)
    }

    /// 경고 로그
    public static func warning(_ tag: String, _ message: String) {
        log(tag, message, level: .warning)
    }

    /// 주목할 정보 로그 (기본 레벨)
    public static func notice(_ tag: String, _ message: String) {
        log(tag, message, level: .notice)
    }

    /// 일반 정보 로그
    public static func info(_ tag: String, _ message: String) {
        log(tag, message, level: .info)
    }

    /// 디버그 로그
    public static func debug(_ tag: String, _ message: String) {
        log(tag, message, level: .debug)
    }
}
