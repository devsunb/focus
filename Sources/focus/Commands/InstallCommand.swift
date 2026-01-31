import ArgumentParser
import Foundation
import FocusCore

struct InstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install as launchd agent (auto-start on login)"
    )

    func run() throws {
        let plistPath = Config.launchdPlistPath

        // 이미 설치되어 있는지 확인
        if FileManager.default.fileExists(atPath: plistPath.path) {
            print("Launchd agent is already installed at \(plistPath.path)")
            print("Use 'focus uninstall' to remove it first.")
            throw ExitCode.failure
        }

        // focusd 경로 찾기
        let daemonPath = try findDaemonPath()

        // plist 내용 생성
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(Config.launchdLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(daemonPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>\(Config.logFilePath.path)</string>
            <key>StandardErrorPath</key>
            <string>\(Config.logFilePath.path)</string>
        </dict>
        </plist>
        """

        // 데이터 디렉토리 생성
        try Config.ensureDataDirectory()

        // LaunchAgents 디렉토리 확인
        let launchAgentsDir = plistPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

        // plist 파일 작성
        try plist.write(to: plistPath, atomically: true, encoding: .utf8)

        // launchctl로 로드
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", "-w", plistPath.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            print("Focus daemon installed as launchd agent.")
            print("It will start automatically on login.")
            print("")
            print("Plist: \(plistPath.path)")
            print("Logs:  \(Config.logFilePath.path)")
        } else {
            // 에러 메시지 읽기
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

            // 실패 시 plist 파일 정리
            try? FileManager.default.removeItem(at: plistPath)

            if let message = errorMessage, !message.isEmpty {
                print("Failed to load launchd agent: \(message)")
            } else {
                print("Failed to load launchd agent (exit code: \(process.terminationStatus))")
            }
            throw ExitCode.failure
        }
    }

    private func findDaemonPath() throws -> String {
        // 1. 같은 디렉토리에서 찾기
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let sameDir = executableURL.deletingLastPathComponent()
            .appendingPathComponent("focusd")

        if FileManager.default.isExecutableFile(atPath: sameDir.path) {
            return sameDir.path
        }

        // 2. PATH에서 찾기
        let env = ProcessInfo.processInfo.environment
        if let path = env["PATH"] {
            for dir in path.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(dir))
                    .appendingPathComponent("focusd")
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate.path
                }
            }
        }

        throw ValidationError("Cannot find focusd executable. Please install it to a directory in PATH first.")
    }
}
