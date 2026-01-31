import AppKit
import FocusCore

private func log(_ message: String) {
    Logger.log("focusd", message)
}

// MARK: - Daemon Context

/// 데몬 전역 상태 (signal handler에서 접근해야 하므로 전역 필요)
enum DaemonContext {
    static var appMonitor: AppMonitor?
    static var sessionRecorder: SessionRecorder?
    static var configWatcher: ConfigWatcher?
    static var signalSources: [DispatchSourceSignal] = []
}

// MARK: - Main

@main
struct FocusDaemon {
    static func main() {
        let args = CommandLine.arguments

        // help 옵션
        if args.contains("-h") || args.contains("--help") {
            printUsage()
            exit(0)
        }

        // verbose 옵션
        if args.contains("-v") || args.contains("--verbose") {
            Logger.level = .debug
        }

        log("Starting Focus Daemon...")

        // 데이터 디렉토리 확인
        do {
            try Config.ensureDataDirectory()
        } catch {
            log("Failed to create data directory: \(error)")
            exit(1)
        }

        // PID 파일 생성
        writePidFile()

        // 시그널 핸들러 설정
        setupSignalHandlers()

        // 데이터베이스 초기화
        let database: Database
        do {
            database = try Database()
            log("Database initialized at \(Config.databasePath.path)")
        } catch {
            log("Failed to initialize database: \(error)")
            exit(1)
        }

        // 세션 레코더 초기화
        let recorder = SessionRecorder(database: database)
        DaemonContext.sessionRecorder = recorder

        // 미종료 세션 삭제 (이전 비정상 종료로 인한 orphan)
        do {
            try recorder.deleteOrphanedSessions()
        } catch {
            log("Warning: Failed to delete orphaned sessions: \(error)")
        }

        // 제외 설정 로드
        let exclusionConfig = ExclusionConfig.load(from: Config.configFilePath)
        log("Exclusion config loaded: \(exclusionConfig.excludedApps.count) apps, \(exclusionConfig.excludedWindows.count) windows")

        // 앱 모니터 시작
        let monitor = AppMonitor(recorder: recorder, exclusionConfig: exclusionConfig)
        DaemonContext.appMonitor = monitor
        monitor.start()
        log("App monitoring started")

        // 설정 파일 변경 감시 시작
        let watcher = ConfigWatcher(path: Config.configFilePath) {
            let newConfig = ExclusionConfig.load(from: Config.configFilePath)
            log("Exclusion config reloaded: \(newConfig.excludedApps.count) apps, \(newConfig.excludedWindows.count) windows")
            Task { @MainActor in
                DaemonContext.appMonitor?.updateExclusionConfig(newConfig)
            }
        }
        do {
            try watcher.start()
            DaemonContext.configWatcher = watcher
            log("Config watcher started for \(Config.configFilePath.path)")
        } catch {
            log("Warning: Config watcher failed to start: \(error.localizedDescription)")
            log("Config changes will not be detected automatically")
        }

        log("Daemon is running. Press Ctrl+C to stop.")

        // NSApplication 이벤트 루프 실행
        NSApplication.shared.run()
    }
}

// MARK: - PID File

private func writePidFile() {
    let pid = getpid()
    let startTime = ISO8601DateFormatter().string(from: Date())
    let content = "\(pid)\n\(startTime)"

    do {
        try content.write(to: Config.pidFilePath, atomically: true, encoding: .utf8)
        log("PID file written: \(Config.pidFilePath.path)")
    } catch {
        log("Warning: Failed to write PID file: \(error)")
    }
}

private func removePidFile() {
    try? FileManager.default.removeItem(at: Config.pidFilePath)
}

// MARK: - Signal Handlers

private func setupSignalHandlers() {
    // 기본 시그널 핸들러 무시 (DispatchSource에서 처리)
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)

    let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sigintSource.setEventHandler {
        print("")  // 줄바꿈
        log("Received SIGINT")
        shutdown()
    }
    sigintSource.resume()
    DaemonContext.signalSources.append(sigintSource)

    let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    sigtermSource.setEventHandler {
        print("")  // 줄바꿈
        log("Received SIGTERM")
        shutdown()
    }
    sigtermSource.resume()
    DaemonContext.signalSources.append(sigtermSource)
}

// MARK: - Shutdown

/// 메인 스레드에서 호출됨 (DispatchSource 이벤트 핸들러)
private func shutdown() {
    log("Shutting down...")

    // 5초 후 강제 종료 (DB 락 등으로 무한 대기 방지)
    DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
        log("Shutdown timeout reached, forcing exit")
        exit(1)
    }

    // AppMonitor 정리 (메인 큐에서 실행되므로 MainActor로 격리)
    MainActor.assumeIsolated {
        DaemonContext.appMonitor?.stop()
    }

    // 현재 열린 세션 종료
    if let recorder = DaemonContext.sessionRecorder {
        do {
            try recorder.closeAllSessions()
        } catch {
            log("Warning: Failed to close sessions: \(error)")
        }
    }

    // 시그널 소스 정리
    for source in DaemonContext.signalSources {
        source.cancel()
    }

    // 설정 감시 중지
    DaemonContext.configWatcher?.stop()

    // PID 파일 삭제
    removePidFile()

    log("Goodbye!")
    exit(0)
}

// MARK: - Usage

private func printUsage() {
    print("""
        USAGE: focusd [options]

        OPTIONS:
          -v, --verbose    상세 로그 출력 (앱/타이틀 변경)
          -h, --help       도움말 출력
        """)
}
