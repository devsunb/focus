import Foundation
import GRDB

/// 데이터베이스 관리자
public final class Database: Sendable {
    private let dbQueue: DatabaseQueue

    /// SQL LIKE 패턴의 특수문자 이스케이프
    /// - Parameter string: 이스케이프할 문자열
    /// - Returns: %, _, \ 문자가 이스케이프된 문자열
    private static func escapeLikePattern(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    public init(inMemory: Bool = false) throws {
        if inMemory {
            dbQueue = try DatabaseQueue()
        } else {
            try Config.ensureDataDirectory()
            dbQueue = try DatabaseQueue(path: Config.databasePath.path)
        }
        try migrate()
    }

    // MARK: - Migration

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_sessions") { db in
            try db.create(table: "sessions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("bundleId", .text).notNull()
                t.column("appName", .text).notNull()
                t.column("windowTitle", .text)
                t.column("startedAt", .datetime).notNull()
                t.column("endedAt", .datetime)
            }

            try db.create(index: "idx_sessions_startedAt", on: "sessions", columns: ["startedAt"])
            try db.create(index: "idx_sessions_bundleId", on: "sessions", columns: ["bundleId"])
            try db.create(index: "idx_sessions_bundleId_startedAt", on: "sessions", columns: ["bundleId", "startedAt"])
            try db.create(index: "idx_sessions_windowTitle", on: "sessions", columns: ["windowTitle"])
        }

        try migrator.migrate(dbQueue)
    }

    // MARK: - Session CRUD

    /// 새 세션 저장
    @discardableResult
    public func insertSession(_ session: Session) throws -> Session {
        try dbQueue.write { db in
            try session.insert(db)
            let id = db.lastInsertedRowID
            return Session(
                id: id,
                bundleId: session.bundleId,
                appName: session.appName,
                windowTitle: session.windowTitle,
                startedAt: session.startedAt,
                endedAt: session.endedAt
            )
        }
    }

    /// 세션 업데이트
    public func updateSession(_ session: Session) throws {
        try dbQueue.write { db in
            try session.update(db)
        }
    }

    /// 세션 종료 (endedAt 설정)
    public func endSession(id: Int64, at date: Date = Date()) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE sessions SET endedAt = ? WHERE id = ?",
                arguments: [date, id]
            )
        }
    }

    /// ID로 세션 조회
    public func fetchSession(id: Int64) throws -> Session? {
        try dbQueue.read { db in
            try Session.fetchOne(db, key: id)
        }
    }

    /// 현재 진행 중인 세션 (endedAt이 NULL인 가장 최근 세션)
    public func fetchCurrentSession() throws -> Session? {
        try dbQueue.read { db in
            try Session
                .filter(Session.Columns.endedAt == nil)
                .order(Session.Columns.startedAt.desc)
                .fetchOne(db)
        }
    }

    /// 미종료 세션 모두 종료 (정상 종료 시 사용)
    public func closeAllOpenSessions(at date: Date = Date()) throws -> Int {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE sessions SET endedAt = ? WHERE endedAt IS NULL",
                arguments: [date]
            )
            return db.changesCount
        }
    }

    /// 미종료 세션 모두 삭제 (비정상 종료 복구용 - 정확한 종료 시간을 알 수 없음)
    public func deleteOrphanedSessions() throws -> Int {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM sessions WHERE endedAt IS NULL")
            return db.changesCount
        }
    }

    // MARK: - Query

    /// 특정 날짜의 세션 조회 (사용자 현재 시간대 기준)
    public func fetchSessions(for date: Date) throws -> [Session] {
        let (startOfDay, endOfDay) = Self.dayRange(for: date)

        return try dbQueue.read { db in
            try Session
                .filter(Session.Columns.startedAt >= startOfDay)
                .filter(Session.Columns.startedAt < endOfDay)
                .order(Session.Columns.startedAt.asc)
                .fetchAll(db)
        }
    }

    /// 날짜 범위의 세션 조회
    public func fetchSessions(from startDate: Date, to endDate: Date) throws -> [Session] {
        try dbQueue.read { db in
            try Session
                .filter(Session.Columns.startedAt >= startDate)
                .filter(Session.Columns.startedAt < endDate)
                .order(Session.Columns.startedAt.asc)
                .fetchAll(db)
        }
    }

    /// 검색 (앱 이름 또는 창 제목, 날짜 필터 지원)
    public func searchSessions(
        query: String? = nil,
        app: String? = nil,
        from startDate: Date? = nil,
        to endDate: Date? = nil,
        limit: Int = 100
    ) throws -> [Session] {
        return try dbQueue.read { db in
            var baseQuery = Session.all()

            // 텍스트 검색 (query)
            if let query = query, !query.isEmpty {
                let pattern = "%\(Self.escapeLikePattern(query))%"
                baseQuery = baseQuery.filter(
                    sql: "(appName LIKE ? ESCAPE '\\' OR windowTitle LIKE ? ESCAPE '\\')",
                    arguments: [pattern, pattern]
                )
            }

            // 앱 이름 필터
            if let app = app, !app.isEmpty {
                let appPattern = "%\(Self.escapeLikePattern(app))%"
                baseQuery = baseQuery.filter(
                    sql: "appName LIKE ? ESCAPE '\\'",
                    arguments: [appPattern]
                )
            }

            // 날짜 범위 필터
            if let start = startDate {
                baseQuery = baseQuery.filter(Session.Columns.startedAt >= start)
            }
            if let end = endDate {
                baseQuery = baseQuery.filter(Session.Columns.startedAt < end)
            }

            return try baseQuery
                .order(Session.Columns.startedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// 최근 세션 조회
    public func fetchRecentSessions(limit: Int = 50) throws -> [Session] {
        try dbQueue.read { db in
            try Session
                .order(Session.Columns.startedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Delete

    /// ID로 세션 삭제
    @discardableResult
    public func deleteSession(id: Int64) throws -> Bool {
        try dbQueue.write { db in
            try Session.deleteOne(db, key: id)
        }
    }

    /// 날짜 범위의 세션 삭제
    @discardableResult
    public func deleteSessions(from startDate: Date, to endDate: Date) throws -> Int {
        try dbQueue.write { db in
            try Session
                .filter(Session.Columns.startedAt >= startDate)
                .filter(Session.Columns.startedAt < endDate)
                .deleteAll(db)
        }
    }

    /// 전체 세션 수
    public func countAllSessions() throws -> Int {
        try dbQueue.read { db in
            try Session.fetchCount(db)
        }
    }

    /// 모든 세션 삭제
    @discardableResult
    public func deleteAllSessions() throws -> Int {
        try dbQueue.write { db in
            try Session.deleteAll(db)
        }
    }

    /// 앱 이름으로 세션 조회 (부분 일치, 옵션으로 날짜 범위 필터)
    public func fetchSessions(byAppName appName: String, from startDate: Date? = nil, to endDate: Date? = nil) throws -> [Session] {
        let pattern = "%\(Self.escapeLikePattern(appName))%"
        return try dbQueue.read { db in
            var query = Session.filter(sql: "appName LIKE ? ESCAPE '\\'", arguments: [pattern])
            if let start = startDate {
                query = query.filter(Session.Columns.startedAt >= start)
            }
            if let end = endDate {
                query = query.filter(Session.Columns.startedAt < end)
            }
            return try query
                .order(Session.Columns.startedAt.desc)
                .fetchAll(db)
        }
    }

    /// 앱 이름으로 세션 삭제 (부분 일치, 옵션으로 날짜 범위 필터)
    @discardableResult
    public func deleteSessions(byAppName appName: String, from startDate: Date? = nil, to endDate: Date? = nil) throws -> Int {
        let pattern = "%\(Self.escapeLikePattern(appName))%"
        return try dbQueue.write { db in
            var query = Session.filter(sql: "appName LIKE ? ESCAPE '\\'", arguments: [pattern])
            if let start = startDate {
                query = query.filter(Session.Columns.startedAt >= start)
            }
            if let end = endDate {
                query = query.filter(Session.Columns.startedAt < end)
            }
            return try query.deleteAll(db)
        }
    }

    // MARK: - Aggregation

    /// SQL 집계용 duration 표현식 (초 단위)
    /// - Parameter now: 현재 시각 (쿼리 내 일관성을 위해 호출 시점에 명시적 전달 필수)
    private static func durationExpression(now: Date) -> SQL {
        SQL("""
            strftime('%s', COALESCE(\(Session.Columns.endedAt), \(now))) \
            - strftime('%s', \(Session.Columns.startedAt))
            """)
    }

    /// 날짜의 시작/끝 계산 (사용자 현재 시간대 기준)
    /// - Note: autoupdatingCurrent 사용으로 시스템 시간대 변경이 실시간 반영됨
    private static func dayRange(for date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.autoupdatingCurrent
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)
            ?? startOfDay.addingTimeInterval(86400)
        return (startOfDay, endOfDay)
    }

    /// 특정 날짜의 총 사용 시간 (초) - SQL 집계
    public func totalSeconds(for date: Date) throws -> Int64 {
        let (startOfDay, endOfDay) = Self.dayRange(for: date)
        let now = Date()

        return try dbQueue.read { db in
            let request: SQLRequest<Row> = """
                SELECT COALESCE(SUM(\(Self.durationExpression(now: now))), 0) as totalSeconds
                FROM \(Session.self)
                WHERE \(Session.Columns.startedAt) >= \(startOfDay)
                  AND \(Session.Columns.startedAt) < \(endOfDay)
                """
            let row = try request.fetchOne(db)
            return row?["totalSeconds"] ?? 0
        }
    }

    /// 앱별 사용 시간 요약 (SQL 집계로 성능 최적화)
    public func appSummaries(for date: Date) throws -> [AppSummary] {
        let (startOfDay, endOfDay) = Self.dayRange(for: date)
        let now = Date()

        return try dbQueue.read { db in
            let request: SQLRequest<AppSummary> = """
                SELECT \(Session.Columns.bundleId), \(Session.Columns.appName),
                       SUM(\(Self.durationExpression(now: now))) as totalSeconds,
                       COUNT(*) as sessionCount
                FROM \(Session.self)
                WHERE \(Session.Columns.startedAt) >= \(startOfDay)
                  AND \(Session.Columns.startedAt) < \(endOfDay)
                GROUP BY \(Session.Columns.bundleId)
                ORDER BY totalSeconds DESC
                """
            return try request.fetchAll(db)
        }
    }

    /// 앱별 사용 시간 요약 - 날짜 범위 (SQL 집계)
    public func appSummaries(from startDate: Date, to endDate: Date) throws -> [AppSummary] {
        let now = Date()
        return try dbQueue.read { db in
            let request: SQLRequest<AppSummary> = """
                SELECT \(Session.Columns.bundleId), \(Session.Columns.appName),
                       SUM(\(Self.durationExpression(now: now))) as totalSeconds,
                       COUNT(*) as sessionCount
                FROM \(Session.self)
                WHERE \(Session.Columns.startedAt) >= \(startDate)
                  AND \(Session.Columns.startedAt) < \(endDate)
                GROUP BY \(Session.Columns.bundleId)
                ORDER BY totalSeconds DESC
                """
            return try request.fetchAll(db)
        }
    }

    /// 창별 사용 시간 요약 (SQL 집계로 성능 최적화)
    public func windowSummaries(for date: Date) throws -> [WindowSummary] {
        let (startOfDay, endOfDay) = Self.dayRange(for: date)
        let now = Date()

        return try dbQueue.read { db in
            let windowTitleExpr: SQL = SQL("COALESCE(\(Session.Columns.windowTitle), '')")
            let request: SQLRequest<WindowSummary> = """
                SELECT \(Session.Columns.bundleId), \(Session.Columns.appName),
                       \(windowTitleExpr) as windowTitle,
                       SUM(\(Self.durationExpression(now: now))) as totalSeconds,
                       COUNT(*) as sessionCount
                FROM \(Session.self)
                WHERE \(Session.Columns.startedAt) >= \(startOfDay)
                  AND \(Session.Columns.startedAt) < \(endOfDay)
                GROUP BY \(Session.Columns.bundleId), \(windowTitleExpr)
                ORDER BY totalSeconds DESC
                """
            return try request.fetchAll(db)
        }
    }

    /// 창별 사용 시간 요약 - 날짜 범위 (SQL 집계)
    public func windowSummaries(from startDate: Date, to endDate: Date) throws -> [WindowSummary] {
        let now = Date()
        return try dbQueue.read { db in
            let windowTitleExpr: SQL = SQL("COALESCE(\(Session.Columns.windowTitle), '')")
            let request: SQLRequest<WindowSummary> = """
                SELECT \(Session.Columns.bundleId), \(Session.Columns.appName),
                       \(windowTitleExpr) as windowTitle,
                       SUM(\(Self.durationExpression(now: now))) as totalSeconds,
                       COUNT(*) as sessionCount
                FROM \(Session.self)
                WHERE \(Session.Columns.startedAt) >= \(startDate)
                  AND \(Session.Columns.startedAt) < \(endDate)
                GROUP BY \(Session.Columns.bundleId), \(windowTitleExpr)
                ORDER BY totalSeconds DESC
                """
            return try request.fetchAll(db)
        }
    }

    /// 세션 배열에서 창별 요약 집계 (메모리 내 집계용)
    public func aggregateWindowSummaries(from sessions: [Session]) -> [WindowSummary] {
        // bundleId + windowTitle을 키로 사용
        var summaries: [String: (bundleId: String, appName: String, windowTitle: String, totalSeconds: Int64, count: Int)] = [:]

        for session in sessions {
            let title = session.windowTitle ?? ""
            let key = "\(session.bundleId)|\(title)"
            let duration = Int64(session.currentDuration)

            if let existing = summaries[key] {
                summaries[key] = (
                    bundleId: existing.bundleId,
                    appName: existing.appName,
                    windowTitle: existing.windowTitle,
                    totalSeconds: existing.totalSeconds + duration,
                    count: existing.count + 1
                )
            } else {
                summaries[key] = (
                    bundleId: session.bundleId,
                    appName: session.appName,
                    windowTitle: title,
                    totalSeconds: duration,
                    count: 1
                )
            }
        }

        return summaries.values.map { data in
            WindowSummary(
                bundleId: data.bundleId,
                appName: data.appName,
                windowTitle: data.windowTitle,
                totalSeconds: data.totalSeconds,
                sessionCount: data.count
            )
        }.sorted { $0.totalSeconds > $1.totalSeconds }
    }
}
