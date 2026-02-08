import Foundation

/// ConfigWatcher 에러 타입
public enum ConfigWatcherError: Error, LocalizedError {
    case failedToCreateFile(String)
    case failedToOpenFile(String)

    public var errorDescription: String? {
        switch self {
        case .failedToCreateFile(let path):
            return "Failed to create config file: \(path)"
        case .failedToOpenFile(let path):
            return "Failed to open file for watching: \(path)"
        }
    }
}

/// 설정 파일 변경 감시
public final class ConfigWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let path: URL
    private let onChange: () -> Void
    private var debounceWorkItem: DispatchWorkItem?
    private var retryTimer: DispatchSourceTimer?

    /// 디바운스 간격 (밀리초)
    private let debounceInterval: Int = 100

    private func log(_ message: String, level: LogLevel = .notice) {
        Logger.log("ConfigWatcher", message, level: level)
    }

    public init(path: URL, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    /// 감시 시작
    public func start() throws {
        // 이미 감시 중이면 무시
        guard source == nil else { return }

        // 설정 디렉토리 확인 및 생성
        let directory = path.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        // 파일이 없으면 기본 설정 파일 생성 (감시 대상 필요)
        if !FileManager.default.fileExists(atPath: path.path) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(ExclusionConfig.default)
            guard FileManager.default.createFile(atPath: path.path, contents: data) else {
                throw ConfigWatcherError.failedToCreateFile(path.path)
            }
            // 파일 생성 후 검증
            guard FileManager.default.fileExists(atPath: path.path),
                  let written = FileManager.default.contents(atPath: path.path),
                  written == data else {
                try? FileManager.default.removeItem(atPath: path.path)
                throw ConfigWatcherError.failedToCreateFile(path.path)
            }
        }

        let fd = open(path.path, O_EVTONLY)
        guard fd >= 0 else {
            throw ConfigWatcherError.failedToOpenFile(path.path)
        }

        // fd가 열린 후 실패 시 정리를 보장하는 플래그
        var sourceCreated = false
        defer {
            if !sourceCreated {
                close(fd)
            }
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.handleChange()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        self.source = source
        sourceCreated = true
    }

    /// 감시 중지
    public func stop() {
        retryTimer?.cancel()
        retryTimer = nil
        source?.cancel()
        source = nil
    }

    /// atomic save 재시도 최대 횟수
    private let maxRetries = 3

    /// atomic save 재시도 간격 (밀리초)
    private let retryInterval = 500

    private func handleChange() {
        // 이전 디바운스 작업 취소
        debounceWorkItem?.cancel()

        // 파일이 삭제/이동된 경우: atomic save일 수 있으므로 재시도
        if !FileManager.default.fileExists(atPath: path.path) {
            log("Config file not found, waiting for atomic save to complete...", level: .info)
            waitForFile(retriesLeft: maxRetries)
            return
        }

        // 새 디바운스 작업 예약
        let workItem = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        debounceWorkItem = workItem

        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(debounceInterval),
            execute: workItem
        )
    }

    private func waitForFile(retriesLeft: Int) {
        // 기존 타이머 정리
        retryTimer?.cancel()
        retryTimer = nil

        guard retriesLeft > 0 else {
            log("Config file not restored after retries, continuing with last config", level: .warning)
            return
        }

        var remainingRetries = retriesLeft
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(retryInterval), repeating: .milliseconds(retryInterval))

        timer.setEventHandler { [weak self] in
            guard let self else {
                timer.cancel()
                return
            }

            if FileManager.default.fileExists(atPath: self.path.path) {
                log("Config file restored, reloading", level: .info)
                timer.cancel()
                self.retryTimer = nil
                // 파일이 돌아왔으면 감시 재시작 후 변경 알림
                self.source?.cancel()
                self.source = nil
                do {
                    try self.start()
                    self.onChange()
                } catch {
                    // start() 실패 시 source는 이미 nil 상태
                    // 설정 변경 자동 감지만 비활성화되며, 현재 로드된 설정은 유지됨
                    log("Failed to restart watcher: \(error.localizedDescription). Auto-reload disabled until daemon restart.", level: .error)
                }
            } else {
                remainingRetries -= 1
                if remainingRetries <= 0 {
                    log("Config file not restored after retries, continuing with last config", level: .warning)
                    timer.cancel()
                    self.retryTimer = nil
                }
            }
        }

        timer.resume()
        retryTimer = timer
    }
}
