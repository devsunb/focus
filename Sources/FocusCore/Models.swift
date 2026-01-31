import Foundation
import GRDB

// MARK: - Session Model

/// 앱 사용 세션
public struct Session: Codable, Identifiable, Equatable, Sendable {
    public var id: Int64?
    public var bundleId: String
    public var appName: String
    public var windowTitle: String?
    public var startedAt: Date
    public var endedAt: Date?

    public init(
        id: Int64? = nil,
        bundleId: String,
        appName: String,
        windowTitle: String? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil
    ) {
        self.id = id
        self.bundleId = bundleId
        self.appName = appName
        self.windowTitle = windowTitle
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    /// 세션 지속 시간 (초)
    public var duration: TimeInterval? {
        guard let endedAt else { return nil }
        return max(0, endedAt.timeIntervalSince(startedAt))
    }

    /// 현재 진행 중인 세션의 지속 시간 (음수 방지)
    public var currentDuration: TimeInterval {
        let end = endedAt ?? Date()
        return max(0, end.timeIntervalSince(startedAt))
    }
}

// MARK: - GRDB Extensions

extension Session: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "sessions" }

    public enum Columns: String, ColumnExpression {
        case id, bundleId, appName, windowTitle, startedAt, endedAt
    }
}

// MARK: - AppInfo

/// 현재 활성 앱 정보
public struct AppInfo: Codable, Equatable, Sendable {
    public var bundleId: String
    public var appName: String
    public var windowTitle: String?

    public init(bundleId: String, appName: String, windowTitle: String? = nil) {
        self.bundleId = bundleId
        self.appName = appName
        self.windowTitle = windowTitle
    }
}

// MARK: - Daemon Status

/// 데몬 상태 정보
public struct DaemonStatus: Codable, Sendable {
    public var isRunning: Bool
    public var pid: Int32?
    public var currentSession: Session?
    public var todayTotalSeconds: Int64
    public var uptimeSeconds: Int?

    public init(
        isRunning: Bool,
        pid: Int32? = nil,
        currentSession: Session? = nil,
        todayTotalSeconds: Int64 = 0,
        uptimeSeconds: Int? = nil
    ) {
        self.isRunning = isRunning
        self.pid = pid
        self.currentSession = currentSession
        self.todayTotalSeconds = todayTotalSeconds
        self.uptimeSeconds = uptimeSeconds
    }
}

// MARK: - Summary Protocol

/// AppSummary와 WindowSummary의 공통 인터페이스
public protocol SummaryRecord: Sendable {
    var bundleId: String { get }
    var appName: String { get }
    /// SQL 집계 결과를 담는 필드. Int64로 명시하여 장기간 누적 데이터의 오버플로우 방지.
    var totalSeconds: Int64 { get }
    var sessionCount: Int { get }
    var formattedDuration: String { get }
    var displayLabel: String { get }
}

// MARK: - App Summary

/// 앱별 사용 시간 요약
public struct AppSummary: SummaryRecord, FetchableRecord {
    public var bundleId: String
    public var appName: String
    public var totalSeconds: Int64
    public var sessionCount: Int

    public init(bundleId: String, appName: String, totalSeconds: Int64, sessionCount: Int) {
        self.bundleId = bundleId
        self.appName = appName
        self.totalSeconds = totalSeconds
        self.sessionCount = sessionCount
    }

    public init(row: Row) {
        // 방어적 타입 캐스팅: SQL 쿼리 오류 시 크래시 방지
        bundleId = row["bundleId"] as String? ?? ""
        appName = row["appName"] as String? ?? ""
        totalSeconds = row["totalSeconds"] as Int64? ?? 0
        sessionCount = row["sessionCount"] as Int? ?? 0
    }

    public var formattedDuration: String {
        DurationFormatter.compact(Int(clamping: totalSeconds))
    }

    public var displayLabel: String { appName }
}

/// 창별 사용 시간 요약
public struct WindowSummary: SummaryRecord, FetchableRecord {
    public var bundleId: String
    public var appName: String
    public var windowTitle: String
    public var totalSeconds: Int64
    public var sessionCount: Int

    public init(bundleId: String, appName: String, windowTitle: String, totalSeconds: Int64, sessionCount: Int) {
        self.bundleId = bundleId
        self.appName = appName
        self.windowTitle = windowTitle
        self.totalSeconds = totalSeconds
        self.sessionCount = sessionCount
    }

    public init(row: Row) {
        // 방어적 타입 캐스팅: SQL 쿼리 오류 시 크래시 방지
        bundleId = row["bundleId"] as String? ?? ""
        appName = row["appName"] as String? ?? ""
        windowTitle = row["windowTitle"] as String? ?? ""
        totalSeconds = row["totalSeconds"] as Int64? ?? 0
        sessionCount = row["sessionCount"] as Int? ?? 0
    }

    public var formattedDuration: String {
        DurationFormatter.compact(Int(clamping: totalSeconds))
    }

    public var displayLabel: String {
        let title = windowTitle.isEmpty ? "(no title)" : windowTitle
        return "\(appName): \(title)"
    }
}
