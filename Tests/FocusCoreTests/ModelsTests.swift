import Testing
import Foundation
@testable import FocusCore

@Suite("Models Tests")
struct ModelsTests {
    // MARK: - Session Tests

    @Test("Session duration calculation")
    func sessionDuration() {
        let startedAt = Date()
        let endedAt = startedAt.addingTimeInterval(3600)

        var session = Session(
            bundleId: "com.apple.Safari",
            appName: "Safari",
            startedAt: startedAt,
            endedAt: endedAt
        )

        #expect(session.duration == 3600)

        // 진행 중인 세션은 duration이 nil
        session.endedAt = nil
        #expect(session.duration == nil)
    }

    @Test("Session current duration")
    func sessionCurrentDuration() {
        let startedAt = Date().addingTimeInterval(-1800) // 30분 전

        let session = Session(
            bundleId: "com.apple.Safari",
            appName: "Safari",
            startedAt: startedAt
        )

        // 현재 시간 기준으로 계산되므로 대략 1800초
        let duration = session.currentDuration
        #expect(duration >= 1799 && duration <= 1801)
    }

    // MARK: - AppInfo Tests

    @Test("AppInfo equality")
    func appInfoEquality() {
        let info1 = AppInfo(bundleId: "com.apple.Safari", appName: "Safari", windowTitle: "Apple")
        let info2 = AppInfo(bundleId: "com.apple.Safari", appName: "Safari", windowTitle: "Apple")
        let info3 = AppInfo(bundleId: "com.apple.Safari", appName: "Safari", windowTitle: "Google")

        #expect(info1 == info2)
        #expect(info1 != info3)
    }

    // MARK: - DaemonStatus Tests

    @Test("DaemonStatus initialization")
    func daemonStatusInit() {
        let status = DaemonStatus(
            isRunning: true,
            pid: 1234,
            todayTotalSeconds: 7200,
            uptimeSeconds: 3600
        )

        #expect(status.isRunning == true)
        #expect(status.pid == 1234)
        #expect(status.todayTotalSeconds == 7200)
        #expect(status.uptimeSeconds == 3600)
        #expect(status.currentSession == nil)
    }

    // MARK: - AppSummary Tests

    @Test("AppSummary formatted duration")
    func appSummaryFormattedDuration() {
        let summary1 = AppSummary(
            bundleId: "com.apple.Safari",
            appName: "Safari",
            totalSeconds: 7320, // 2시간 2분
            sessionCount: 5
        )

        #expect(summary1.formattedDuration == "2h 2m")

        let summary2 = AppSummary(
            bundleId: "com.apple.Terminal",
            appName: "Terminal",
            totalSeconds: 1500, // 25분
            sessionCount: 3
        )

        #expect(summary2.formattedDuration == "25m")

        let summary3 = AppSummary(
            bundleId: "com.apple.Notes",
            appName: "Notes",
            totalSeconds: 30, // 30초
            sessionCount: 1
        )

        // 1분 미만은 1분으로 표시
        #expect(summary3.formattedDuration == "1m")
    }
}
