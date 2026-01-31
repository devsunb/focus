import Testing
import Foundation
@testable import FocusCore

@Suite("Database Tests")
struct DatabaseTests {
    @Test("Insert and fetch session")
    func insertAndFetchSession() throws {
        let db = try Database(inMemory: true)

        let session = Session(
            bundleId: "com.apple.Safari",
            appName: "Safari",
            windowTitle: "Apple",
            startedAt: Date()
        )

        let inserted = try db.insertSession(session)
        #expect(inserted.id != nil)

        let fetched = try db.fetchSession(id: inserted.id!)
        #expect(fetched != nil)
        #expect(fetched?.bundleId == "com.apple.Safari")
        #expect(fetched?.appName == "Safari")
        #expect(fetched?.windowTitle == "Apple")
    }

    @Test("End session")
    func endSession() throws {
        let db = try Database(inMemory: true)

        let session = Session(
            bundleId: "com.apple.Safari",
            appName: "Safari",
            startedAt: Date()
        )

        let inserted = try db.insertSession(session)
        #expect(inserted.endedAt == nil)

        try db.endSession(id: inserted.id!)

        let fetched = try db.fetchSession(id: inserted.id!)
        #expect(fetched?.endedAt != nil)
    }

    @Test("Fetch current session")
    func fetchCurrentSession() throws {
        let db = try Database(inMemory: true)

        // 종료된 세션 추가
        var session1 = Session(
            bundleId: "com.apple.Safari",
            appName: "Safari",
            startedAt: Date().addingTimeInterval(-3600)
        )
        session1.endedAt = Date().addingTimeInterval(-1800)
        _ = try db.insertSession(session1)

        // 현재 진행 중인 세션 추가
        let session2 = Session(
            bundleId: "com.apple.Terminal",
            appName: "Terminal",
            startedAt: Date()
        )
        _ = try db.insertSession(session2)

        let current = try db.fetchCurrentSession()
        #expect(current != nil)
        #expect(current?.bundleId == "com.apple.Terminal")
        #expect(current?.endedAt == nil)
    }

    @Test("Delete orphaned sessions")
    func deleteOrphanedSessions() throws {
        let db = try Database(inMemory: true)

        // 미종료 세션 여러 개 추가
        let session1 = Session(
            bundleId: "com.apple.Safari",
            appName: "Safari",
            startedAt: Date().addingTimeInterval(-3600)
        )
        _ = try db.insertSession(session1)

        let session2 = Session(
            bundleId: "com.apple.Terminal",
            appName: "Terminal",
            startedAt: Date().addingTimeInterval(-1800)
        )
        _ = try db.insertSession(session2)

        let count = try db.deleteOrphanedSessions()
        #expect(count == 2)

        // 삭제되었으므로 세션이 없어야 함
        let sessions = try db.fetchRecentSessions()
        #expect(sessions.isEmpty)
    }

    @Test("Close all open sessions")
    func closeAllOpenSessions() throws {
        let db = try Database(inMemory: true)

        // 미종료 세션 추가
        let session = Session(
            bundleId: "com.apple.Safari",
            appName: "Safari",
            startedAt: Date().addingTimeInterval(-3600)
        )
        _ = try db.insertSession(session)

        let count = try db.closeAllOpenSessions()
        #expect(count == 1)

        let current = try db.fetchCurrentSession()
        #expect(current == nil)

        // 세션은 삭제되지 않고 종료만 됨
        let sessions = try db.fetchRecentSessions()
        #expect(sessions.count == 1)
        #expect(sessions.first?.endedAt != nil)
    }

    @Test("Fetch sessions for date")
    func fetchSessionsForDate() throws {
        let db = try Database(inMemory: true)

        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        // 오늘 세션
        var session1 = Session(
            bundleId: "com.apple.Safari",
            appName: "Safari",
            startedAt: today
        )
        session1.endedAt = today.addingTimeInterval(3600)
        _ = try db.insertSession(session1)

        // 어제 세션
        var session2 = Session(
            bundleId: "com.apple.Terminal",
            appName: "Terminal",
            startedAt: yesterday
        )
        session2.endedAt = yesterday.addingTimeInterval(3600)
        _ = try db.insertSession(session2)

        let todaySessions = try db.fetchSessions(for: today)
        #expect(todaySessions.count == 1)
        #expect(todaySessions[0].bundleId == "com.apple.Safari")

        let yesterdaySessions = try db.fetchSessions(for: yesterday)
        #expect(yesterdaySessions.count == 1)
        #expect(yesterdaySessions[0].bundleId == "com.apple.Terminal")
    }

    @Test("Search sessions")
    func searchSessions() throws {
        let db = try Database(inMemory: true)

        var session1 = Session(
            bundleId: "com.apple.Safari",
            appName: "Safari",
            windowTitle: "Apple - Homepage",
            startedAt: Date()
        )
        session1.endedAt = Date().addingTimeInterval(3600)
        _ = try db.insertSession(session1)

        var session2 = Session(
            bundleId: "com.google.Chrome",
            appName: "Chrome",
            windowTitle: "Google Search",
            startedAt: Date()
        )
        session2.endedAt = Date().addingTimeInterval(1800)
        _ = try db.insertSession(session2)

        // 앱 이름으로 검색
        let safariResults = try db.searchSessions(query: "Safari")
        #expect(safariResults.count == 1)

        // 창 제목으로 검색
        let googleResults = try db.searchSessions(query: "Google")
        #expect(googleResults.count == 1)

        // 일치하는 것 없음
        let noResults = try db.searchSessions(query: "Firefox")
        #expect(noResults.isEmpty)
    }

    @Test("Calculate total seconds for date")
    func totalSecondsForDate() throws {
        let db = try Database(inMemory: true)

        // 오늘 오전 9시로 고정 (시간대 문제 방지)
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 9
        components.minute = 0
        let baseTime = calendar.date(from: components)!

        // 1시간 세션 (9:00 - 10:00)
        var session1 = Session(
            bundleId: "com.apple.Safari",
            appName: "Safari",
            startedAt: baseTime
        )
        session1.endedAt = baseTime.addingTimeInterval(3600)
        _ = try db.insertSession(session1)

        // 30분 세션 (10:00 - 10:30)
        var session2 = Session(
            bundleId: "com.apple.Terminal",
            appName: "Terminal",
            startedAt: baseTime.addingTimeInterval(3600)
        )
        session2.endedAt = baseTime.addingTimeInterval(5400)
        _ = try db.insertSession(session2)

        let total = try db.totalSeconds(for: baseTime)
        #expect(total == 5400) // 1.5시간
    }

    @Test("App summaries for date")
    func appSummariesForDate() throws {
        let db = try Database(inMemory: true)

        // 오늘 오전 9시로 고정 (시간대 문제 방지)
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 9
        components.minute = 0
        let baseTime = calendar.date(from: components)!

        // Safari 세션 2개 (9:00-10:00, 10:00-11:00)
        var session1 = Session(
            bundleId: "com.apple.Safari",
            appName: "Safari",
            startedAt: baseTime
        )
        session1.endedAt = baseTime.addingTimeInterval(3600)
        _ = try db.insertSession(session1)

        var session2 = Session(
            bundleId: "com.apple.Safari",
            appName: "Safari",
            startedAt: baseTime.addingTimeInterval(3600)
        )
        session2.endedAt = baseTime.addingTimeInterval(7200)
        _ = try db.insertSession(session2)

        // Terminal 세션 1개 (11:00-11:30)
        var session3 = Session(
            bundleId: "com.apple.Terminal",
            appName: "Terminal",
            startedAt: baseTime.addingTimeInterval(7200)
        )
        session3.endedAt = baseTime.addingTimeInterval(9000)
        _ = try db.insertSession(session3)

        let summaries = try db.appSummaries(for: baseTime)
        #expect(summaries.count == 2)

        // Safari가 더 많은 시간이므로 첫 번째
        #expect(summaries[0].bundleId == "com.apple.Safari")
        #expect(summaries[0].totalSeconds == 7200)
        #expect(summaries[0].sessionCount == 2)

        #expect(summaries[1].bundleId == "com.apple.Terminal")
        #expect(summaries[1].totalSeconds == 1800)
        #expect(summaries[1].sessionCount == 1)
    }

    // MARK: - Concurrency Tests

    @Test("Concurrent session insertions are serialized correctly")
    func concurrentInsertions() async throws {
        let db = try Database(inMemory: true)
        let insertCount = 100

        // 여러 Task에서 동시에 세션 삽입
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<insertCount {
                group.addTask {
                    var session = Session(
                        bundleId: "com.test.app\(i % 10)",
                        appName: "App\(i % 10)",
                        startedAt: Date()
                    )
                    session.endedAt = Date().addingTimeInterval(Double(i))
                    _ = try? db.insertSession(session)
                }
            }
        }

        let sessions = try db.fetchRecentSessions(limit: 1000)
        #expect(sessions.count == insertCount)
    }

    @Test("Concurrent reads and writes don't cause data corruption")
    func concurrentReadsAndWrites() async throws {
        let db = try Database(inMemory: true)

        // 초기 데이터 삽입
        for i in 0..<10 {
            var session = Session(
                bundleId: "com.test.app",
                appName: "TestApp",
                startedAt: Date().addingTimeInterval(Double(i) * -3600)
            )
            session.endedAt = Date().addingTimeInterval(Double(i) * -3600 + 1800)
            _ = try db.insertSession(session)
        }

        // 동시에 읽기/쓰기 수행
        await withTaskGroup(of: Void.self) { group in
            // 읽기 작업들
            for _ in 0..<20 {
                group.addTask {
                    _ = try? db.fetchRecentSessions()
                    _ = try? db.appSummaries(for: Date())
                    _ = try? db.totalSeconds(for: Date())
                }
            }
            // 쓰기 작업들
            for i in 0..<20 {
                group.addTask {
                    var session = Session(
                        bundleId: "com.concurrent.app",
                        appName: "ConcurrentApp",
                        startedAt: Date()
                    )
                    session.endedAt = Date().addingTimeInterval(Double(i))
                    _ = try? db.insertSession(session)
                }
            }
        }

        // 데이터 무결성 확인
        let sessions = try db.fetchRecentSessions(limit: 1000)
        #expect(sessions.count == 30) // 초기 10 + 동시 쓰기 20
    }

    @Test("Concurrent endSession calls are handled correctly")
    func concurrentEndSession() async throws {
        let db = try Database(inMemory: true)

        // 세션 생성
        let session = Session(
            bundleId: "com.test.app",
            appName: "TestApp",
            startedAt: Date()
        )
        let inserted = try db.insertSession(session)
        let sessionId = inserted.id!

        // 여러 Task에서 동시에 같은 세션 종료 시도
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try? db.endSession(id: sessionId)
                }
            }
        }

        // 세션이 정상적으로 종료되었는지 확인
        let fetched = try db.fetchSession(id: sessionId)
        #expect(fetched?.endedAt != nil)
    }
}
