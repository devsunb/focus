import Testing
import Foundation

/// CLI 커맨드 통합 테스트
/// swift build 후 바이너리를 실행하여 커맨드 동작을 검증합니다.
@Suite("Command Integration Tests")
struct CommandTests {

    private func focusPath() -> String {
        // 빌드 산출물 경로에서 focus 바이너리 찾기
        let buildDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // FocusCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // project root
            .appendingPathComponent(".build/debug/focus")
        return buildDir.path
    }

    private func run(_ arguments: [String]) throws -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: focusPath())
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        return (process.terminationStatus, stdout, stderr)
    }

    // MARK: - SummaryCommand Validation

    @Test("summary: date argument and --from are mutually exclusive")
    func summaryDateAndFromExclusive() throws {
        let result = try run(["summary", "2026-01-29", "--from", "2026-01-28"])
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("Cannot use both"))
    }

    @Test("summary: --to requires --from")
    func summaryToRequiresFrom() throws {
        let result = try run(["summary", "--to", "2026-01-29"])
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("--to requires --from"))
    }

    @Test("summary: invalid date format")
    func summaryInvalidDate() throws {
        let result = try run(["summary", "not-a-date"])
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("Invalid date format"))
    }

    // MARK: - LogCommand Validation

    @Test("log: --date and --from are mutually exclusive")
    func logDateAndFromExclusive() throws {
        let result = try run(["log", "--date", "2026-01-29", "--from", "2026-01-28"])
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("Cannot use --date with --from/--to"))
    }

    // MARK: - DeleteCommand Validation

    @Test("delete: requires at least one option")
    func deleteRequiresOption() throws {
        let result = try run(["delete"])
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("Specify --id"))
    }

    @Test("delete: --id and --all are mutually exclusive")
    func deleteIdAndAllExclusive() throws {
        let result = try run(["delete", "--id", "1", "--all"])
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("Use only one of"))
    }

    @Test("delete: --app and --id are mutually exclusive")
    func deleteAppAndIdExclusive() throws {
        let result = try run(["delete", "--app", "Safari", "--id", "1"])
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("Cannot use --app with --id"))
    }

    @Test("delete: --app and --all are mutually exclusive")
    func deleteAppAndAllExclusive() throws {
        let result = try run(["delete", "--app", "Safari", "--all"])
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("Cannot use --app with --all"))
    }

    // MARK: - Relative Time Acceptance

    @Test("summary: accepts relative time as date argument")
    func summaryRelativeTime() throws {
        let result = try run(["summary", "3h"])
        // 성공 (exit 0) 또는 "No activity" (데이터 없음) — validation 에러 아님
        #expect(!result.stderr.contains("Invalid"))
    }

    @Test("summary: accepts relative time with --from")
    func summaryRelativeTimeFrom() throws {
        let result = try run(["summary", "--from", "1w"])
        #expect(!result.stderr.contains("Invalid"))
    }

    @Test("log: accepts relative time with --date")
    func logRelativeTime() throws {
        let result = try run(["log", "--date", "2d"])
        #expect(!result.stderr.contains("Invalid"))
    }

    @Test("log: accepts relative time with --from")
    func logRelativeTimeFrom() throws {
        let result = try run(["log", "--from", "1d", "--to", "30m"])
        #expect(!result.stderr.contains("Invalid"))
    }

    @Test("delete: accepts relative time with --date (dry run)")
    func deleteRelativeTime() throws {
        let result = try run(["delete", "--date", "1h"])
        // dry run이므로 삭제는 안 됨, validation 에러 없어야 함
        #expect(!result.stderr.contains("Invalid"))
    }

    // MARK: - Help Output

    @Test("top-level --help lists subcommands")
    func helpListsSubcommands() throws {
        let result = try run(["--help"])
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("summary"))
        #expect(result.stdout.contains("log"))
        #expect(result.stdout.contains("delete"))
        #expect(result.stdout.contains("install"))
        #expect(result.stdout.contains("uninstall"))
    }
}
