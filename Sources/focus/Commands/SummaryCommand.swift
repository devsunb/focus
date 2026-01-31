import ArgumentParser
import Foundation
import FocusCore

struct SummaryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "summary",
        abstract: "Show usage summary by app"
    )

    @Argument(help: "Date to show (YYYY-MM-DD, default: today)")
    var date: String?

    @Option(name: .long, help: "From date/time (YYYY-MM-DD or \"YYYY-MM-DD HH:mm\")")
    var from: String?

    @Option(name: .long, help: "To date/time (default: now)")
    var to: String?

    @Flag(name: .shortAndLong, help: "Show summary by window")
    var window: Bool = false

    @Flag(name: .shortAndLong, help: "Output as JSON")
    var json: Bool = false

    func validate() throws {
        if date != nil && from != nil {
            throw ValidationError("Cannot use both date argument and --from option")
        }
        if to != nil && from == nil {
            throw ValidationError("--to requires --from option")
        }
    }

    func run() throws {
        let database = try Database()

        if let fromStr = from {
            try showRange(database: database, fromStr: fromStr, toStr: to)
        } else {
            try showSingleDay(database: database)
        }
    }

    // MARK: - Single Day

    private func showSingleDay(database: Database) throws {
        let targetDate: Date
        if let dateStr = date {
            guard let (parsed, _) = DateUtils.parse(dateStr) else {
                throw ValidationError("Invalid date format. Use YYYY-MM-DD.")
            }
            targetDate = parsed
        } else {
            targetDate = Date()
        }

        let header = window
            ? "Window Summary for \(formatDate(targetDate))"
            : "Usage Summary for \(formatDate(targetDate))"
        let emptyMessage = "No activity recorded for \(formatDate(targetDate))."

        if window {
            try showSummary(database.windowSummaries(for: targetDate), header: header, emptyMessage: emptyMessage)
        } else {
            try showSummary(database.appSummaries(for: targetDate), header: header, emptyMessage: emptyMessage)
        }
    }

    // MARK: - Date Range

    private func showRange(database: Database, fromStr: String, toStr: String?) throws {
        guard let (startDate, endDate) = DateUtils.dateRange(from: fromStr, to: toStr) else {
            throw ValidationError("Invalid date format. Use YYYY-MM-DD or \"YYYY-MM-DD HH:mm\"")
        }

        let toDisplay = toStr ?? "now"
        let header = window
            ? "Window Summary from \(fromStr) to \(toDisplay)"
            : "Usage Summary from \(fromStr) to \(toDisplay)"
        let emptyMessage = "No activity recorded from \(fromStr) to \(toDisplay)."

        if window {
            try showSummary(database.windowSummaries(from: startDate, to: endDate), header: header, emptyMessage: emptyMessage)
        } else {
            try showSummary(database.appSummaries(from: startDate, to: endDate), header: header, emptyMessage: emptyMessage)
        }
    }

    // MARK: - Common Summary Display

    private func showSummary<S: SummaryRecord>(_ summaries: [S], header: String, emptyMessage: String) throws {
        if summaries.isEmpty {
            print(emptyMessage)
            return
        }

        if json {
            try outputJSON(summaries.map { s in
                CodableSummary(
                    bundleId: s.bundleId,
                    appName: s.appName,
                    displayLabel: s.displayLabel,
                    totalSeconds: s.totalSeconds,
                    sessionCount: s.sessionCount
                )
            })
            return
        }

        print(header)
        print("═══════════════════════════════════════════════════════════════")
        print("")

        let totalSeconds = summaries.reduce(0) { $0 + $1.totalSeconds }

        for summary in summaries {
            let percentage = totalSeconds > 0
                ? Int(Double(summary.totalSeconds) / Double(totalSeconds) * 100)
                : 0

            let bar = progressBar(percentage: percentage)
            let duration = summary.formattedDuration.padding(toLength: 8, withPad: " ", startingAt: 0)
            print("\(duration)  \(String(format: "%3d", percentage))%  \(bar)  \(summary.displayLabel)")
        }

        printTotal(totalSeconds)
    }

    // MARK: - Output Helpers

    private struct CodableSummary: Codable {
        var bundleId: String
        var appName: String
        var displayLabel: String
        var totalSeconds: Int64
        var sessionCount: Int
    }

    private func outputJSON<T: Encodable>(_ data: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let jsonData = try encoder.encode(data)
        print(String(data: jsonData, encoding: .utf8) ?? "[]")
    }

    private func printTotal(_ totalSeconds: Int64) {
        print("")
        print("───────────────────────────────────────────────────────────────")
        print("Total: \(DurationFormatter.compact(Int(clamping: totalSeconds)))")
    }

    private static let dateDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd (EEEE)"
        return formatter
    }()

    /// CLI는 단일 스레드로 실행되므로 DateFormatter 접근에 lock 불필요
    private func formatDate(_ date: Date) -> String {
        Self.dateDisplayFormatter.string(from: date)
    }

    private func progressBar(percentage: Int, width: Int = 20) -> String {
        let filled = min(percentage * width / 100, width)
        return String(repeating: "█", count: filled)
            + String(repeating: "░", count: width - filled)
    }
}
