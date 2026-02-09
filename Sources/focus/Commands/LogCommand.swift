import ArgumentParser
import Foundation
import FocusCore

struct LogCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "log",
        abstract: "Show and search session log"
    )

    @Argument(help: "Search query (searches app name and window title)")
    var query: String?

    @Option(name: .long, help: "Filter by app name")
    var app: String?

    @Option(name: .long, help: "Filter by date or relative time (YYYY-MM-DD or 1w2d3h)")
    var date: String?

    @Option(name: .long, help: "From date/time (YYYY-MM-DD, \"YYYY-MM-DD HH:mm\", or 1w2d3h)")
    var from: String?

    @Option(name: .long, help: "To date/time (YYYY-MM-DD, \"YYYY-MM-DD HH:mm\", or 1w2d3h; default: now)")
    var to: String?

    @Option(name: .shortAndLong, help: "Maximum number of results")
    var limit: Int = 50

    @Flag(name: .shortAndLong, help: "Verbose output with full session details")
    var verbose: Bool = false

    @Flag(name: .shortAndLong, help: "Output as JSON")
    var json: Bool = false

    func validate() throws {
        if date != nil && (from != nil || to != nil) {
            throw ValidationError("Cannot use --date with --from/--to")
        }
    }

    func run() throws {
        let database = try Database()
        let (startDate, endDate) = try parseDateRange()

        let sessions = try database.searchSessions(
            query: query,
            app: app,
            from: startDate,
            to: endDate,
            limit: limit
        )

        if sessions.isEmpty {
            print("No sessions found\(filterDescription).")
            return
        }

        if json {
            try outputJSON(sessions)
            return
        }

        printHeader(count: sessions.count)

        if verbose {
            printVerbose(sessions)
        } else {
            printCompact(sessions)
        }
    }

    // MARK: - Date Parsing

    private func parseDateRange() throws -> (start: Date?, end: Date?) {
        guard date != nil || from != nil else {
            return (nil, nil)
        }
        guard let range = DateUtils.parseDateOptions(date: date, from: from, to: to) else {
            throw ValidationError("Invalid date format. Use YYYY-MM-DD, \"YYYY-MM-DD HH:mm\", or 1w2d3h")
        }
        return (range.start, range.end)
    }

    // MARK: - Output

    private func printHeader(count: Int) {
        print("Sessions\(filterDescription) (\(count) total)")
        print("═══════════════════════════════════════════════════════════════")
    }

    private func printCompact(_ sessions: [Session]) {
        print("")
        var lastDisplayedDate: String? = nil

        for session in sessions.reversed() {
            let startDate = DateUtils.formatDate(session.startedAt)
            let startTimeOnly = DateUtils.formatTime(session.startedAt)
            let duration = DurationFormatter.detailed(Int(session.currentDuration))

            // 시작 시간: 날짜가 이전과 같으면 생략
            let startTime: String
            if startDate == lastDisplayedDate {
                startTime = startTimeOnly
            } else {
                startTime = DateUtils.formatDateTime(session.startedAt)
                lastDisplayedDate = startDate
            }

            // 종료 시간: 날짜가 넘어가면 날짜 표시
            let endTime: String
            if let endedAt = session.endedAt {
                let endDate = DateUtils.formatDate(endedAt)
                if endDate != startDate {
                    endTime = DateUtils.formatDateTime(endedAt)
                    lastDisplayedDate = endDate
                } else {
                    endTime = DateUtils.formatTime(endedAt)
                }
            } else {
                endTime = "now"
            }

            let titlePart = session.windowTitle.map { " \($0)" } ?? ""

            print("[\(startTime) - \(endTime)] \(session.appName) (\(duration))\(titlePart)")
        }

        printTotal(sessions)
    }

    private func printVerbose(_ sessions: [Session]) {
        for session in sessions.reversed() {
            SessionFormatter.printSession(session)
        }
        print("")
        printTotal(sessions)
    }

    private func printTotal(_ sessions: [Session]) {
        let totalSeconds = sessions.reduce(0) { $0 + Int($1.currentDuration) }
        print("")
        print("───────────────────────────────────────────────────────────────")
        print("Total: \(DurationFormatter.detailed(totalSeconds))")
    }

    private func outputJSON(_ sessions: [Session]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(sessions)
        print(String(data: data, encoding: .utf8) ?? "[]")
    }

    // MARK: - Description

    private var filterDescription: String {
        var parts: [String] = []

        if let query = query {
            parts.append("for '\(query)'")
        }
        if let app = app {
            parts.append("app '\(app)'")
        }
        if let dateStr = date {
            parts.append("on \(dateStr)")
        } else if let fromStr = from {
            parts.append("from \(fromStr) to \(to ?? "now")")
        }

        return parts.isEmpty ? "" : " " + parts.joined(separator: ", ")
    }
}
