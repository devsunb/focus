import Foundation
import FocusCore

private func log(_ message: String) {
    Logger.log("SessionRecorder", message)
}

private func debug(_ message: String) {
    Logger.debug("SessionRecorder", message)
}

/// 세션 기록 관리
actor SessionRecorder {
    // Database는 Sendable이고 let이므로 nonisolated 메서드에서 안전하게 접근 가능
    private let database: Database
    private var currentSession: Session?

    init(database: Database) {
        self.database = database
    }

    /// 시작 시 미종료 세션 삭제 (비정상 종료로 인한 orphan)
    nonisolated func deleteOrphanedSessions() throws {
        let count = try database.deleteOrphanedSessions()
        if count > 0 {
            log("Deleted \(count) orphaned sessions (unknown end time)")
        }
    }

    /// 종료 시 모든 열린 세션 닫기 (시그널 핸들러에서 동기 호출용)
    nonisolated func closeAllSessions() throws {
        let count = try database.closeAllOpenSessions()
        if count > 0 {
            log("Closed \(count) open sessions")
        }
        // NOTE: currentSession은 actor-isolated이므로 여기서 nil로 설정할 수 없지만,
        // 이 메서드는 shutdown 직전에만 호출되므로 문제없음
    }

    /// 앱 변경 시 호출
    func onAppChanged(to appInfo: AppInfo) async throws {
        // 이전 세션 종료
        if let current = currentSession {
            try await endCurrentSession()
            debug("Ended: \(current.appName)")
        }

        // 새 세션 시작
        let session = Session(
            bundleId: appInfo.bundleId,
            appName: appInfo.appName,
            windowTitle: appInfo.windowTitle
        )
        currentSession = try database.insertSession(session)
        debug("Started: \(appInfo.appName) - \(appInfo.windowTitle ?? "(no title)")")
    }

    /// 창 제목 변경 시 호출
    func onWindowTitleChanged(to title: String, for appInfo: AppInfo) async throws {
        guard let current = currentSession else {
            // 데몬 시작 직후 등 아직 세션이 생성되지 않은 상태에서
            // 창 제목 변경 이벤트가 먼저 도착할 수 있음. 이 경우 새 세션을 시작한다.
            debug("Title changed but no session exists - creating new session for \(appInfo.appName)")
            try await onAppChanged(to: AppInfo(
                bundleId: appInfo.bundleId,
                appName: appInfo.appName,
                windowTitle: title
            ))
            return
        }

        // 같은 앱의 제목 변경인 경우에만 처리
        guard current.bundleId == appInfo.bundleId else {
            return
        }

        // 제목이 실제로 변경되었는지 확인
        guard current.windowTitle != title else {
            return
        }

        // 이전 세션 종료하고 새 세션 시작
        debug("Ended: \(current.appName)")
        try await endCurrentSession()

        let session = Session(
            bundleId: appInfo.bundleId,
            appName: appInfo.appName,
            windowTitle: title
        )
        currentSession = try database.insertSession(session)
        debug("Title changed: \(appInfo.appName) - \(title)")
    }

    /// 현재 세션 종료
    @discardableResult
    func endCurrentSession() async throws -> Session? {
        guard let current = currentSession, let id = current.id else {
            return nil
        }
        try database.endSession(id: id)
        currentSession = nil
        return current
    }

    /// 현재 세션 종료 (로그 포함)
    func endCurrentSessionWithLog() async throws {
        if let ended = try await endCurrentSession() {
            debug("Ended: \(ended.appName)")
        }
    }

}
