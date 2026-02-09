import ArgumentParser
import Foundation
import FocusCore

struct DeleteCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete session data"
    )

    @Option(name: .long, help: "Delete session by ID")
    var id: Int64?

    @Option(name: .long, help: "Delete sessions by app name (partial match)")
    var app: String?

    @Option(name: .long, help: "Delete sessions on date or relative time (YYYY-MM-DD or 1w2d3h)")
    var date: String?

    @Option(name: .long, help: "Delete sessions from (YYYY-MM-DD, \"YYYY-MM-DD HH:mm\", or 1w2d3h)")
    var from: String?

    @Option(name: .long, help: "Delete sessions to (YYYY-MM-DD, \"YYYY-MM-DD HH:mm\", or 1w2d3h; default: now)")
    var to: String?

    @Flag(name: .long, help: "Delete all sessions")
    var all: Bool = false

    @Flag(name: [.customShort("y"), .long], help: "Actually delete (default: dry run)")
    var yes: Bool = false

    func validate() throws {
        // --app은 단독 사용하거나 --date 또는 --from/--to와 조합 가능
        if let app, app.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("--app value cannot be empty")
        }

        if app != nil {
            // --app과 함께 사용 불가: --id, --all
            if id != nil {
                throw ValidationError("Cannot use --app with --id")
            }
            if all {
                throw ValidationError("Cannot use --app with --all")
            }
            // --date와 --from/--to는 동시 사용 불가
            if date != nil && (from != nil || to != nil) {
                throw ValidationError("Cannot use --date with --from/--to")
            }
            return
        }

        // --app 없이 사용하는 경우: 기존 로직
        let optionCount = [id != nil, date != nil, (from != nil || to != nil), all]
            .filter { $0 }.count

        if optionCount == 0 {
            throw ValidationError("Specify --id, --app, --date, --from/--to, or --all")
        }
        if optionCount > 1 {
            throw ValidationError("Use only one of --id, --app, --date, --from/--to, or --all")
        }
    }

    func run() throws {
        let database = try Database()

        if let id = id {
            try deleteById(database: database, id: id)
        } else if let appName = app {
            try deleteByAppName(database: database, appName: appName)
        } else if let dateStr = date {
            if DateUtils.isRelativeTime(dateStr) {
                try deleteByRelativeDate(database: database, relativeStr: dateStr)
            } else {
                try deleteByDate(database: database, dateStr: dateStr)
            }
        } else if let fromStr = from {
            try deleteByRange(database: database, fromStr: fromStr, toStr: to)
        } else if all {
            try deleteAll(database: database)
        }
    }

    /// 날짜 범위 파싱 헬퍼
    private func parseDateRange() throws -> (start: Date, end: Date)? {
        guard date != nil || from != nil else {
            return nil
        }
        guard let range = DateUtils.parseDateOptions(date: date, from: from, to: to) else {
            throw ValidationError("Invalid date format. Use YYYY-MM-DD, \"YYYY-MM-DD HH:mm\", or 1w2d3h")
        }
        return range
    }

    private func deleteById(database: Database, id: Int64) throws {
        guard let session = try database.fetchSession(id: id) else {
            print("Session \(id) not found.")
            return
        }

        printSessionsToDelete([session])

        if yes {
            if try database.deleteSession(id: id) {
                print("Deleted 1 session.")
            }
        } else {
            printDryRunHint()
        }
    }

    private func deleteByAppName(database: Database, appName: String) throws {
        let dateRange = try parseDateRange()
        let sessions = try database.fetchSessions(
            byAppName: appName,
            from: dateRange?.start,
            to: dateRange?.end
        )

        if sessions.isEmpty {
            var message = "No sessions found for app '\(appName)'"
            if let dateStr = date {
                message += " on \(dateStr)"
            } else if let fromStr = from {
                message += " from \(fromStr) to \(to ?? "now")"
            }
            print("\(message).")
            return
        }

        printSessionsToDelete(sessions)

        if yes {
            let count = try database.deleteSessions(
                byAppName: appName,
                from: dateRange?.start,
                to: dateRange?.end
            )
            print("Deleted \(count) sessions.")
        } else {
            printDryRunHint()
        }
    }

    private func deleteByRelativeDate(database: Database, relativeStr: String) throws {
        guard let (startDate, endDate) = DateUtils.parseDateOptions(date: relativeStr, from: nil, to: nil) else {
            throw ValidationError("Invalid relative time format. Use 1w2d3h4m5s.")
        }

        let fromDisplay = DateUtils.formatDateTime(startDate)
        let toDisplay = DateUtils.formatDateTime(endDate)
        let sessions = try database.fetchSessions(from: startDate, to: endDate)
        if sessions.isEmpty {
            print("No sessions found from \(fromDisplay) to \(toDisplay).")
            return
        }

        printSessionsToDelete(sessions)

        if yes {
            let count = try database.deleteSessions(from: startDate, to: endDate)
            print("Deleted \(count) sessions.")
        } else {
            printDryRunHint()
        }
    }

    private func deleteByDate(database: Database, dateStr: String) throws {
        guard let (date, _) = DateUtils.parse(dateStr) else {
            throw ValidationError("Invalid date format. Use YYYY-MM-DD or 1w2d3h")
        }

        let sessions = try database.fetchSessions(for: date)
        if sessions.isEmpty {
            print("No sessions found for \(dateStr).")
            return
        }

        printSessionsToDelete(sessions)

        if yes {
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: date)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)
                ?? startOfDay.addingTimeInterval(86400)

            let count = try database.deleteSessions(from: startOfDay, to: endOfDay)
            print("Deleted \(count) sessions.")
        } else {
            printDryRunHint()
        }
    }

    private func deleteByRange(database: Database, fromStr: String, toStr: String?) throws {
        guard let (startDate, endDate) = DateUtils.dateRange(from: fromStr, to: toStr) else {
            throw ValidationError("Invalid date format. Use YYYY-MM-DD, \"YYYY-MM-DD HH:mm\", or 1w2d3h")
        }

        let toDisplay = toStr ?? "now"
        let sessions = try database.fetchSessions(from: startDate, to: endDate)
        if sessions.isEmpty {
            print("No sessions found in range \(fromStr) to \(toDisplay).")
            return
        }

        printSessionsToDelete(sessions)

        if yes {
            let count = try database.deleteSessions(from: startDate, to: endDate)
            print("Deleted \(count) sessions.")
        } else {
            printDryRunHint()
        }
    }

    private func deleteAll(database: Database) throws {
        let totalCount = try database.countAllSessions()
        if totalCount == 0 {
            print("No sessions to delete.")
            return
        }

        let sessions = try database.fetchRecentSessions(limit: 100)
        printSessionsToDelete(sessions, totalCount: totalCount, showAllWarning: true)

        if yes {
            let count = try database.deleteAllSessions()
            print("Deleted \(count) sessions.")
        } else {
            printDryRunHint()
        }
    }

    private func printSessionsToDelete(_ sessions: [Session], totalCount: Int? = nil, showAllWarning: Bool = false) {
        let ongoingCount = sessions.filter { $0.endedAt == nil }.count
        let displayCount = totalCount ?? sessions.count

        print("Sessions to delete (\(displayCount) total)")
        print("═══════════════════════════════════════════════════════════════")

        if ongoingCount > 0 {
            print("")
            print("⚠️  WARNING: \(ongoingCount) ongoing session(s) will be deleted.")
            print("   The daemon will not auto-start a new session until the next app switch.")
            print("")
        }

        // 최대 10개만 표시
        let displaySessions = sessions.prefix(10)
        for session in displaySessions {
            printSession(session)
        }

        if sessions.count > 10 {
            print("... and \(sessions.count - 10) more sessions")
            print("")
        }

        if showAllWarning {
            print("⚠️  This will delete ALL sessions. This cannot be undone.")
            print("")
        }
    }

    private func printSession(_ session: Session) {
        SessionFormatter.printSession(session, showOngoingLabel: true)
    }

    private func printDryRunHint() {
        print("")
        print("This is a dry run. Add --yes (-y) to actually delete.")
    }

}
