import Testing
import Foundation
@testable import FocusCore

@Suite("ExclusionConfig Tests")
struct ExclusionConfigTests {
    // MARK: - App Exclusion Tests

    @Test("shouldExcludeApp returns true for exact match")
    func excludeAppExactMatch() {
        let config = ExclusionConfig(
            excludedApps: [ExcludedApp(bundleId: "com.apple.loginwindow")],
            excludedWindows: []
        )
        #expect(config.shouldExcludeApp(bundleId: "com.apple.loginwindow") == true)
    }

    @Test("shouldExcludeApp returns false for non-matching bundleId")
    func excludeAppNoMatch() {
        let config = ExclusionConfig(
            excludedApps: [ExcludedApp(bundleId: "com.apple.loginwindow")],
            excludedWindows: []
        )
        #expect(config.shouldExcludeApp(bundleId: "com.apple.Safari") == false)
    }

    @Test("shouldExcludeApp returns false for empty config")
    func excludeAppEmptyConfig() {
        let config = ExclusionConfig(excludedApps: [], excludedWindows: [])
        #expect(config.shouldExcludeApp(bundleId: "com.apple.Safari") == false)
    }

    // MARK: - Window Exclusion Tests

    @Test("shouldExcludeWindow matches exact title pattern")
    func excludeWindowExactTitle() {
        let config = ExclusionConfig(
            excludedApps: [],
            excludedWindows: [
                ExcludedWindow(bundleId: "com.apple.Safari", titlePattern: "Private Browsing")
            ]
        )
        #expect(config.shouldExcludeWindow(bundleId: "com.apple.Safari", title: "Private Browsing") == true)
        #expect(config.shouldExcludeWindow(bundleId: "com.apple.Safari", title: "Public Browsing") == false)
    }

    @Test("shouldExcludeWindow matches wildcard pattern with *")
    func excludeWindowWildcardPattern() {
        let config = ExclusionConfig(
            excludedApps: [],
            excludedWindows: [
                ExcludedWindow(bundleId: "com.apple.Safari", titlePattern: "*Private*")
            ]
        )
        #expect(config.shouldExcludeWindow(bundleId: "com.apple.Safari", title: "Private Browsing") == true)
        #expect(config.shouldExcludeWindow(bundleId: "com.apple.Safari", title: "Safari - Private Window") == true)
        #expect(config.shouldExcludeWindow(bundleId: "com.apple.Safari", title: "Normal Window") == false)
    }

    @Test("shouldExcludeWindow matches single character with ?")
    func excludeWindowSingleCharPattern() {
        let config = ExclusionConfig(
            excludedApps: [],
            excludedWindows: [
                ExcludedWindow(bundleId: "com.example.app", titlePattern: "Tab ?")
            ]
        )
        #expect(config.shouldExcludeWindow(bundleId: "com.example.app", title: "Tab 1") == true)
        #expect(config.shouldExcludeWindow(bundleId: "com.example.app", title: "Tab A") == true)
        #expect(config.shouldExcludeWindow(bundleId: "com.example.app", title: "Tab 12") == false)
    }

    @Test("shouldExcludeWindow with bundleId wildcard matches all apps")
    func excludeWindowAllApps() {
        let config = ExclusionConfig(
            excludedApps: [],
            excludedWindows: [
                ExcludedWindow(bundleId: "*", titlePattern: "*password*", caseSensitive: false)
            ]
        )
        #expect(config.shouldExcludeWindow(bundleId: "com.apple.Safari", title: "Enter Password") == true)
        #expect(config.shouldExcludeWindow(bundleId: "com.google.Chrome", title: "Password Manager") == true)
        #expect(config.shouldExcludeWindow(bundleId: "com.apple.Safari", title: "Normal Page") == false)
    }

    @Test("shouldExcludeWindow respects caseSensitive flag")
    func excludeWindowCaseSensitive() {
        let caseSensitiveConfig = ExclusionConfig(
            excludedApps: [],
            excludedWindows: [
                ExcludedWindow(bundleId: "com.apple.Safari", titlePattern: "*Password*", caseSensitive: true)
            ]
        )
        #expect(caseSensitiveConfig.shouldExcludeWindow(bundleId: "com.apple.Safari", title: "Password") == true)
        #expect(caseSensitiveConfig.shouldExcludeWindow(bundleId: "com.apple.Safari", title: "password") == false)

        let caseInsensitiveConfig = ExclusionConfig(
            excludedApps: [],
            excludedWindows: [
                ExcludedWindow(bundleId: "com.apple.Safari", titlePattern: "*Password*", caseSensitive: false)
            ]
        )
        #expect(caseInsensitiveConfig.shouldExcludeWindow(bundleId: "com.apple.Safari", title: "Password") == true)
        #expect(caseInsensitiveConfig.shouldExcludeWindow(bundleId: "com.apple.Safari", title: "password") == true)
        #expect(caseInsensitiveConfig.shouldExcludeWindow(bundleId: "com.apple.Safari", title: "PASSWORD") == true)
    }

    @Test("shouldExcludeWindow returns false when bundleId doesn't match")
    func excludeWindowBundleMismatch() {
        let config = ExclusionConfig(
            excludedApps: [],
            excludedWindows: [
                ExcludedWindow(bundleId: "com.apple.Safari", titlePattern: "*Private*")
            ]
        )
        #expect(config.shouldExcludeWindow(bundleId: "com.google.Chrome", title: "Private Window") == false)
    }

    // MARK: - Glob Pattern Tests

    @Test("glob pattern escapes regex special characters")
    func globPatternEscapesRegex() {
        let config = ExclusionConfig(
            excludedApps: [],
            excludedWindows: [
                ExcludedWindow(bundleId: "*", titlePattern: "File (1).txt")
            ]
        )
        #expect(config.shouldExcludeWindow(bundleId: "com.example.app", title: "File (1).txt") == true)
        #expect(config.shouldExcludeWindow(bundleId: "com.example.app", title: "File 1.txt") == false)
    }

    @Test("glob pattern with prefix and suffix wildcards")
    func globPatternPrefixSuffix() {
        let config = ExclusionConfig(
            excludedApps: [],
            excludedWindows: [
                ExcludedWindow(bundleId: "*", titlePattern: "*.md")
            ]
        )
        #expect(config.shouldExcludeWindow(bundleId: "com.example.app", title: "README.md") == true)
        #expect(config.shouldExcludeWindow(bundleId: "com.example.app", title: "document.md") == true)
        #expect(config.shouldExcludeWindow(bundleId: "com.example.app", title: "file.txt") == false)
    }

    // MARK: - JSON Loading Tests

    @Test("load returns default config when file doesn't exist")
    func loadDefaultWhenMissing() {
        let nonexistentPath = URL(fileURLWithPath: "/nonexistent/config.json")
        let config = ExclusionConfig.load(from: nonexistentPath)
        #expect(config == ExclusionConfig.default)
    }

    @Test("load parses valid JSON correctly")
    func loadValidJSON() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let configPath = tempDir.appendingPathComponent("test-config-\(UUID().uuidString).json")

        let json = """
        {
            "excludedApps": [
                {"bundleId": "com.test.app", "comment": "Test app"}
            ],
            "excludedWindows": [
                {"bundleId": "com.test.app", "titlePattern": "*secret*", "caseSensitive": false, "comment": "Secret windows"}
            ]
        }
        """
        try json.write(to: configPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: configPath) }

        let config = ExclusionConfig.load(from: configPath)
        #expect(config.excludedApps.count == 1)
        #expect(config.excludedApps[0].bundleId == "com.test.app")
        #expect(config.excludedWindows.count == 1)
        #expect(config.excludedWindows[0].titlePattern == "*secret*")
        #expect(config.excludedWindows[0].caseSensitive == false)
    }

    @Test("load returns default config for invalid JSON")
    func loadInvalidJSON() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let configPath = tempDir.appendingPathComponent("test-invalid-\(UUID().uuidString).json")

        try "{ invalid json }".write(to: configPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: configPath) }

        let config = ExclusionConfig.load(from: configPath)
        #expect(config == ExclusionConfig.default)
    }

    @Test("caseSensitive defaults to true when not specified")
    func caseSensitiveDefaultsTrue() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let configPath = tempDir.appendingPathComponent("test-default-\(UUID().uuidString).json")

        let json = """
        {
            "excludedApps": [],
            "excludedWindows": [
                {"bundleId": "com.test.app", "titlePattern": "*test*"}
            ]
        }
        """
        try json.write(to: configPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: configPath) }

        let config = ExclusionConfig.load(from: configPath)
        #expect(config.excludedWindows[0].caseSensitive == true)
    }
}

// MARK: - ConfigWatcher Tests

@Suite("ConfigWatcher Tests")
struct ConfigWatcherTests {
    @Test("start creates config file if not exists")
    func startCreatesFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("configwatcher-test-\(UUID().uuidString)")
        let configPath = tempDir.appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var callCount = 0
        let watcher = ConfigWatcher(path: configPath) { callCount += 1 }
        try watcher.start()
        defer { watcher.stop() }

        #expect(FileManager.default.fileExists(atPath: configPath.path))
    }

    @Test("onChange is called when file content changes")
    func onChangeCalledOnWrite() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("configwatcher-test-\(UUID().uuidString)")
        let configPath = tempDir.appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let expectation = Expectation()
        let watcher = ConfigWatcher(path: configPath) {
            expectation.signal()
        }
        try watcher.start()
        defer { watcher.stop() }

        // 파일 수정
        let newConfig = """
        {"excludedApps": [{"bundleId": "com.test"}], "excludedWindows": []}
        """
        try newConfig.write(to: configPath, atomically: false, encoding: .utf8)

        // debounce(100ms) + 여유
        try await Task.sleep(for: .milliseconds(200))
        #expect(expectation.didSignal)
    }

    @Test("atomic save triggers onChange after file reappears")
    func atomicSaveRetry() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("configwatcher-test-\(UUID().uuidString)")
        let configPath = tempDir.appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let expectation = Expectation()
        let watcher = ConfigWatcher(path: configPath) {
            expectation.signal()
        }
        try watcher.start()
        defer { watcher.stop() }

        // atomic save 시뮬레이션: 삭제 → 잠시 대기 → 재생성
        try FileManager.default.removeItem(at: configPath)

        // 짧은 대기 후 파일 재생성 (retry 간격 500ms보다 짧게)
        try await Task.sleep(for: .milliseconds(200))
        let newConfig = """
        {"excludedApps": [], "excludedWindows": []}
        """
        try newConfig.write(to: configPath, atomically: false, encoding: .utf8)

        // retry(500ms) + debounce(100ms) + 여유
        try await Task.sleep(for: .milliseconds(800))
        #expect(expectation.didSignal)
    }

    @Test("start throws error when file cannot be opened")
    func startFailsOnInvalidPath() {
        // 읽기 전용 디렉토리에서 파일 생성 불가 (디렉토리 생성 실패 시 NSCocoaErrorDomain 에러)
        let invalidPath = URL(fileURLWithPath: "/nonexistent-dir-\(UUID())/config.json")

        let watcher = ConfigWatcher(path: invalidPath) {}
        #expect(throws: (any Error).self) {
            try watcher.start()
        }
    }

    @Test("rapid consecutive writes trigger single debounced callback")
    func rapidWritesDebounced() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("configwatcher-test-\(UUID().uuidString)")
        let configPath = tempDir.appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let counter = CallCounter()
        let watcher = ConfigWatcher(path: configPath) {
            counter.increment()
        }
        try watcher.start()
        defer { watcher.stop() }

        // 빠르게 연속 쓰기 (debounce 100ms보다 짧은 간격)
        for i in 0..<5 {
            let config = """
            {"excludedApps": [{"bundleId": "com.test.\(i)"}], "excludedWindows": []}
            """
            try config.write(to: configPath, atomically: false, encoding: .utf8)
            try await Task.sleep(for: .milliseconds(20))
        }

        // debounce 완료 대기
        try await Task.sleep(for: .milliseconds(200))

        let finalCount = counter.value

        // debounce로 인해 1-2회만 호출되어야 함 (5회 모두 호출되지 않음)
        #expect(finalCount >= 1 && finalCount <= 2)
    }

    @Test("stop cancels pending retry timer")
    func stopCancelsRetryTimer() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("configwatcher-test-\(UUID().uuidString)")
        let configPath = tempDir.appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var callCount = 0
        let watcher = ConfigWatcher(path: configPath) {
            callCount += 1
        }
        try watcher.start()

        // 파일 삭제로 retry 트리거
        try FileManager.default.removeItem(at: configPath)
        try await Task.sleep(for: .milliseconds(100))

        // retry 완료 전에 stop
        watcher.stop()

        // 파일 재생성
        let config = """
        {"excludedApps": [], "excludedWindows": []}
        """
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try config.write(to: configPath, atomically: false, encoding: .utf8)

        // retry 타이머가 취소되었으므로 콜백 호출 안 됨
        try await Task.sleep(for: .milliseconds(700))
        #expect(callCount == 0)
    }

    @Test("restart after stop works correctly")
    func restartAfterStop() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("configwatcher-test-\(UUID().uuidString)")
        let configPath = tempDir.appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let expectation = Expectation()
        let watcher = ConfigWatcher(path: configPath) {
            expectation.signal()
        }

        // 시작 → 중지 → 재시작
        try watcher.start()
        watcher.stop()
        try watcher.start()
        defer { watcher.stop() }

        // 파일 수정
        let config = """
        {"excludedApps": [{"bundleId": "com.restart.test"}], "excludedWindows": []}
        """
        try config.write(to: configPath, atomically: false, encoding: .utf8)

        try await Task.sleep(for: .milliseconds(200))
        #expect(expectation.didSignal)
    }
}

/// 테스트용 간단한 Expectation 헬퍼
private final class Expectation: @unchecked Sendable {
    private var _didSignal = false
    private let lock = NSLock()

    var didSignal: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _didSignal
    }

    func signal() {
        lock.lock()
        defer { lock.unlock() }
        _didSignal = true
    }
}

/// 테스트용 스레드 안전 카운터
private final class CallCounter: @unchecked Sendable {
    private var _value = 0
    private let lock = NSLock()

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        _value += 1
    }
}
