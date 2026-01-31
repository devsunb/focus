import Foundation

/// 전역 경로 및 설정 상수
public enum Config {
    /// 데이터 디렉토리: ~/.local/share/focus
    public static var dataDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/focus")
    }

    /// SQLite 데이터베이스 경로
    public static var databasePath: URL {
        dataDirectory.appendingPathComponent("focus.db")
    }

    /// PID 파일 경로
    public static var pidFilePath: URL {
        dataDirectory.appendingPathComponent("focusd.pid")
    }

    /// 로그 파일 경로
    public static var logFilePath: URL {
        dataDirectory.appendingPathComponent("focusd.log")
    }

    /// 설정 파일 경로: ~/.config/focus/config.json
    public static var configFilePath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/focus/config.json")
    }

    /// launchd plist 라벨
    public static let launchdLabel = "dev.sunb.focus"

    /// launchd plist 설치 경로
    public static var launchdPlistPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent("\(launchdLabel).plist")
    }

    /// 데이터 디렉토리가 없으면 생성
    public static func ensureDataDirectory() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: dataDirectory.path) {
            try fm.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        }
    }
}
