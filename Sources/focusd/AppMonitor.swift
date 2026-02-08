import AppKit
import ApplicationServices
import FocusCore

private func log(_ message: String, level: LogLevel = .notice) {
    Logger.log("AppMonitor", message, level: level)
}

/// 앱 및 창 모니터링
@MainActor
final class AppMonitor {
    private let recorder: SessionRecorder
    private var currentApp: AppInfo?
    private var axObserver: AXObserver?
    private var observedElement: AXUIElement?
    private var hasAccessibilityPermission = false

    /// 제외 설정
    private var exclusionConfig: ExclusionConfig

    init(recorder: SessionRecorder, exclusionConfig: ExclusionConfig = .default) {
        self.recorder = recorder
        self.exclusionConfig = exclusionConfig
    }

    /// 제외 설정 업데이트 (현재 세션이 새 규칙에 해당하면 종료)
    func updateExclusionConfig(_ config: ExclusionConfig) {
        self.exclusionConfig = config

        // 현재 진행 중인 세션이 새 제외 규칙에 해당하는지 확인
        guard let current = currentApp else { return }

        let shouldExclude = config.shouldExcludeApp(bundleId: current.bundleId)
            || current.windowTitle.map({ config.shouldExcludeWindow(bundleId: current.bundleId, title: $0) }) ?? false

        if shouldExclude {
            // 비동기 작업 전 bundleId 캡처 (경쟁 조건 방지)
            let capturedBundleId = current.bundleId

            Task {
                do {
                    try await recorder.endCurrentSessionWithLog()
                    // 비동기 작업 완료 후 여전히 같은 앱인지 확인
                    guard self.currentApp?.bundleId == capturedBundleId else { return }

                    if config.shouldExcludeApp(bundleId: capturedBundleId) {
                        currentApp = nil
                        removeAXObserver()
                    }
                    // 윈도우만 제외된 경우 currentApp은 유지 (타이틀 변경 감시 계속)
                } catch {
                    log("Error ending session after config update: \(error)", level: .error)
                }
            }
        }
    }

    /// 모니터링 시작
    func start() {
        checkAccessibilityPermission()
        setupAppActivationObserver()
        setupSleepWakeObserver()
        captureCurrentApp()
    }

    /// 모니터링 중지
    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        removeAXObserver()
    }

    // MARK: - Accessibility Permission

    private func checkAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        hasAccessibilityPermission = trusted

        if trusted {
            log("Accessibility permission granted - window title tracking enabled")
        } else {
            log("Accessibility permission not granted - only app switching will be tracked", level: .warning)
            log("Grant permission in System Settings > Privacy & Security > Accessibility", level: .warning)
        }
    }

    // MARK: - App Activation Observer

    private func setupAppActivationObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    // MARK: - Sleep/Wake Observer

    private func setupSleepWakeObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func systemWillSleep(_ notification: Notification) {
        log("System will sleep - ending current session", level: .info)
        Task {
            do {
                try await recorder.endCurrentSessionWithLog()
                currentApp = nil
                removeAXObserver()
            } catch {
                log("Error ending session on sleep: \(error)", level: .error)
            }
        }
    }

    @objc private func systemDidWake(_ notification: Notification) {
        log("System did wake - resuming monitoring", level: .info)
        captureCurrentApp()
    }

    @objc private func appDidActivate(_ notification: Notification) {
        Task {
            await handleAppActivation(notification)
        }
    }

    private func handleAppActivation(_ notification: Notification) async {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        let bundleId = app.bundleIdentifier ?? "unknown"

        // 제외할 앱인 경우 세션 종료만 하고 새 세션 시작하지 않음
        if exclusionConfig.shouldExcludeApp(bundleId: bundleId) {
            if currentApp != nil {
                do {
                    try await recorder.endCurrentSessionWithLog()
                    currentApp = nil
                    removeAXObserver()
                } catch {
                    log("Error ending session for ignored app: \(error)", level: .error)
                }
            }
            return
        }

        let appName = app.localizedName.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown"

        // 창 제목 가져오기 (접근성 권한 있을 때만)
        var windowTitle: String? = nil
        if hasAccessibilityPermission {
            windowTitle = getWindowTitle(for: app)
            setupAXObserver(for: app)
        }

        let appInfo = AppInfo(bundleId: bundleId, appName: appName, windowTitle: windowTitle)

        // 같은 앱이면 무시
        if let current = currentApp, current.bundleId == appInfo.bundleId && current.windowTitle == appInfo.windowTitle {
            return
        }

        // 제외할 윈도우인 경우 세션 종료만 하고 새 세션 시작하지 않음
        if let title = windowTitle, exclusionConfig.shouldExcludeWindow(bundleId: bundleId, title: title) {
            if currentApp != nil {
                do {
                    try await recorder.endCurrentSessionWithLog()
                    currentApp = appInfo
                    removeAXObserver()
                    setupAXObserver(for: app)  // 윈도우 제목 변경 감시 유지
                } catch {
                    log("Error ending session for excluded window: \(error)", level: .error)
                }
            }
            return
        }

        let previousApp = currentApp
        currentApp = appInfo

        do {
            try await recorder.onAppChanged(to: appInfo)
        } catch {
            currentApp = previousApp  // 실패 시 롤백
            log("Error recording app change: \(error)", level: .error)
        }
    }

    // MARK: - Current App Capture

    private func captureCurrentApp() {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            log("Could not get frontmost application at startup", level: .warning)
            return
        }

        let bundleId = app.bundleIdentifier ?? "unknown"

        // 제외할 앱이면 캡처하지 않음
        if exclusionConfig.shouldExcludeApp(bundleId: bundleId) {
            return
        }

        let appName = app.localizedName.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown"

        var windowTitle: String? = nil
        if hasAccessibilityPermission {
            windowTitle = getWindowTitle(for: app)
            setupAXObserver(for: app)
        }

        let appInfo = AppInfo(bundleId: bundleId, appName: appName, windowTitle: windowTitle)

        // 제외할 윈도우이면 캡처하지 않음 (단, 앱 정보는 유지하여 제목 변경 감시)
        if let title = windowTitle, exclusionConfig.shouldExcludeWindow(bundleId: bundleId, title: title) {
            currentApp = appInfo
            return
        }

        currentApp = appInfo

        Task {
            do {
                try await recorder.onAppChanged(to: appInfo)
            } catch {
                currentApp = nil  // 실패 시 롤백 (시작 시점이므로 이전 앱 없음)
                log("Error recording initial app: \(error)", level: .error)
            }
        }
    }

    // MARK: - AXObserver for Window Title

    private func getWindowTitle(for app: NSRunningApplication) -> String? {
        let element = AXUIElementCreateApplication(app.processIdentifier)

        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &focusedWindow)

        guard result == .success, let window = focusedWindow else {
            return nil
        }

        // CFTypeRef → AXUIElement 변환 (CFGetTypeID 검사로 타입 안전성 보장)
        guard CFGetTypeID(window) == AXUIElementGetTypeID() else {
            return nil
        }
        // swiftlint:disable:next force_cast
        let windowElement = window as! AXUIElement

        var title: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &title)

        guard titleResult == .success, let titleString = title as? String else {
            return nil
        }

        return titleString.isEmpty ? nil : titleString
    }

    private func setupAXObserver(for app: NSRunningApplication) {
        removeAXObserver()

        let pid = app.processIdentifier
        var observer: AXObserver?

        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let monitor = Unmanaged<AppMonitor>.fromOpaque(refcon).takeUnretainedValue()

            Task { @MainActor in
                monitor.handleTitleChange(element: element)
            }
        }

        let result = AXObserverCreate(pid, callback, &observer)
        guard result == .success, let observer else {
            return
        }

        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        let addResult1 = AXObserverAddNotification(observer, element, kAXFocusedWindowChangedNotification as CFString, refcon)
        let addResult2 = AXObserverAddNotification(observer, element, kAXTitleChangedNotification as CFString, refcon)

        // 알림 등록 실패 시 무시 (앱 전환 시 재시도되므로 대부분 무시해도 됨)
        guard addResult1 == .success || addResult2 == .success else {
            log("AX notification failed (\(addResult1.rawValue), \(addResult2.rawValue)) - usually safe to ignore", level: .debug)
            return
        }

        // RunLoop에 등록하기 전에 observer 저장 (실패해도 정리 가능하도록)
        self.axObserver = observer
        self.observedElement = element

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private func removeAXObserver() {
        guard let observer = axObserver else { return }

        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)

        if let element = observedElement {
            AXObserverRemoveNotification(observer, element, kAXFocusedWindowChangedNotification as CFString)
            AXObserverRemoveNotification(observer, element, kAXTitleChangedNotification as CFString)
        }

        axObserver = nil
        observedElement = nil
    }

    private func handleTitleChange(element: AXUIElement) {
        guard let currentApp else { return }

        var title: CFTypeRef?
        var titleElement = element

        // 먼저 focused window에서 제목 시도
        if let app = NSWorkspace.shared.frontmostApplication {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var focusedWindow: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success,
               let window = focusedWindow,
               CFGetTypeID(window) == AXUIElementGetTypeID() {
                // swiftlint:disable:next force_cast
                titleElement = window as! AXUIElement
            }
        }

        let result = AXUIElementCopyAttributeValue(titleElement, kAXTitleAttribute as CFString, &title)
        guard result == .success, let titleString = title as? String, !titleString.isEmpty else {
            return
        }

        // 같은 제목이면 무시
        if currentApp.windowTitle == titleString {
            return
        }

        // 비동기 작업 전 상태 캡처 (경쟁 조건 방지)
        let capturedBundleId = currentApp.bundleId
        let capturedAppName = currentApp.appName
        let capturedWindowTitle = currentApp.windowTitle

        // 제외할 윈도우인 경우 세션 종료만 하고 새 세션 시작하지 않음
        if exclusionConfig.shouldExcludeWindow(bundleId: capturedBundleId, title: titleString) {
            Task {
                do {
                    try await recorder.endCurrentSessionWithLog()
                    // 비동기 작업 완료 후 여전히 같은 앱인지 확인
                    guard self.currentApp?.bundleId == capturedBundleId else { return }
                    self.currentApp = AppInfo(
                        bundleId: capturedBundleId,
                        appName: capturedAppName,
                        windowTitle: titleString
                    )
                } catch {
                    log("Error ending session for excluded window: \(error)", level: .error)
                }
            }
            return
        }

        Task {
            do {
                let appInfo = AppInfo(bundleId: capturedBundleId, appName: capturedAppName, windowTitle: capturedWindowTitle)
                try await recorder.onWindowTitleChanged(to: titleString, for: appInfo)
                // 비동기 작업 완료 후 여전히 같은 앱인지 확인
                guard self.currentApp?.bundleId == capturedBundleId else { return }
                self.currentApp = AppInfo(
                    bundleId: capturedBundleId,
                    appName: capturedAppName,
                    windowTitle: titleString
                )
            } catch {
                log("Error recording title change: \(error)", level: .error)
            }
        }
    }
}
