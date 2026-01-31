import ArgumentParser
import Foundation
import FocusCore

struct UninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Uninstall launchd agent"
    )

    func run() throws {
        let plistPath = Config.launchdPlistPath

        // plist 파일 존재 확인
        guard FileManager.default.fileExists(atPath: plistPath.path) else {
            print("Launchd agent is not installed.")
            return
        }

        // launchctl로 언로드
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", plistPath.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let message = errorMessage, !message.isEmpty {
                print("Warning: launchctl unload failed: \(message)")
            }
            // 언로드 실패해도 plist 삭제는 시도
        }

        // plist 파일 삭제
        try FileManager.default.removeItem(at: plistPath)

        print("Focus daemon launchd agent uninstalled.")
        print("The daemon will no longer start automatically on login.")
    }
}
