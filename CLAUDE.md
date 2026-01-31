# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

Swift 기반 macOS 스크린 타임 추적 도구. 데몬(`focusd`)이 백그라운드에서 앱 사용을 모니터링하고, CLI(`focus`)로 제어 및 조회합니다.

## 아키텍처

```
┌─────────────┐                            ┌─────────────┐
│   focus     │ ──── Direct DB Access ──── │   focusd    │
│   (CLI)     │                            │  (Daemon)   │
└─────────────┘                            └─────────────┘
       │                                          │
       └──────────────┬───────────────────────────┘
                      ▼
      ┌─────────────────────────────────────────────────────────┐
      │                      FocusCore                          │
      │  ┌──────────┐  ┌──────────┐  ┌─────────────────────┐   │
      │  │ Config   │  │ Models   │  │ Database (GRDB)     │   │
      │  └──────────┘  └──────────┘  └─────────────────────┘   │
      │  ┌──────────┐  ┌──────────┐  ┌─────────────────────┐   │
      │  │ Logger   │  │DateUtils │  │ ExclusionConfig     │   │
      │  └──────────┘  └──────────┘  └─────────────────────┘   │
      └─────────────────────────────────────────────────────────┘
```

## 디렉토리 구조

```
Sources/
├── FocusCore/           # 공유 라이브러리
│   ├── Config.swift           # 경로 상수 (~/.local/share/focus/, ~/.config/focus/)
│   ├── Models.swift           # Session, AppInfo, DaemonStatus, SummaryRecord 타입
│   ├── Database.swift         # GRDB 기반 SQLite 레이어
│   ├── DurationFormatter.swift    # 시간 포맷 유틸리티 (detailed/compact)
│   ├── ExclusionConfig.swift      # 제외 설정 모델 및 glob 패턴 매칭
│   ├── ConfigWatcher.swift        # 설정 파일 변경 감시 (FSEvents)
│   ├── Logger.swift               # 스레드 안전 로깅 (NSLock 기반)
│   ├── DateUtils.swift            # 스레드 안전 날짜 파싱 및 범위 계산
│   └── SessionFormatter.swift     # 세션 출력 포맷팅
├── focusd/              # 데몬 프로세스
│   ├── main.swift           # 진입점, 시그널 핸들러
│   ├── AppMonitor.swift     # NSWorkspace + AXObserver 모니터링
│   └── SessionRecorder.swift    # 세션 기록 actor
└── focus/               # CLI 도구
    ├── main.swift           # ArgumentParser 기반 CLI
    └── Commands/
        ├── SummaryCommand.swift   # 앱/윈도우별 사용 시간 요약
        ├── LogCommand.swift       # 세션 로그 검색 및 조회
        ├── DeleteCommand.swift    # 세션 데이터 삭제
        ├── InstallCommand.swift   # launchd 에이전트 설치
        └── UninstallCommand.swift # launchd 에이전트 제거

Tests/
└── FocusCoreTests/      # 테스트 스위트 (Swift Testing 프레임워크)
    ├── DatabaseTests.swift          # GRDB 통합 테스트
    ├── ExclusionConfigTests.swift   # 제외 로직 및 glob 패턴 테스트
    ├── DateUtilsTests.swift         # 날짜 파싱 및 범위 계산 테스트
    ├── DurationFormatterTests.swift # 시간 포맷 테스트
    ├── ModelsTests.swift            # 데이터 모델 테스트
    └── CommandTests.swift           # CLI 커맨드 파싱 테스트
```

## 핵심 패턴

### Swift Concurrency

- `SessionRecorder`: actor로 구현하여 데이터 레이스 방지
- `AppMonitor`: MainActor에서 실행 (AppKit 요구사항)

### GRDB 사용

- `Session`: `FetchableRecord`, `PersistableRecord` 프로토콜 준수
- `Columns` enum으로 타입 안전한 쿼리
- `lastInsertedRowID`로 auto-increment ID 획득

### DurationFormatter

- `detailed(_:)`: 상세 포맷 "1h 2m 3s" - 상태, 로그, 삭제 확인용
- `compact(_:)`: 간략 포맷 "1h 2m" - 타임라인, 검색용

### ExclusionConfig

- 제외할 앱/윈도우 설정을 `~/.config/focus/config.json`에서 로드
- `ConfigWatcher`가 파일 변경 감시, 실시간 반영 (데몬 재시작 불필요)
- glob 패턴: `*` (0개 이상 문자), `?` (단일 문자) 지원
- 기본값: `com.apple.loginwindow`만 제외

### Logger

- `NSLock` 기반 스레드 안전 로깅
- `LogLevel`: `.info`, `.debug` 지원
- 데몬(`focusd`)에서 주로 사용

### DateUtils

- 스레드 안전 날짜 파싱 및 포맷팅 (`NSLock` 기반)
- `parse(_:)`: "YYYY-MM-DD" 또는 "YYYY-MM-DD HH:mm" 형식 지원
- `parseDateOptions()`: CLI의 `--date`, `--from`, `--to` 옵션 처리

## 빌드 및 테스트

```bash
swift build                                                     # 빌드
swift test                                                      # 전체 테스트
swift test --filter FocusCoreTests.TestClassName/testMethodName # 단일 테스트
swift build -c release                                          # 릴리스 빌드
```

테스트 타겟은 `FocusCoreTests` 하나뿐입니다.

### CFTypeRef → AXUIElement 캐스트

AppMonitor에서 `CFTypeRef`를 `AXUIElement`로 변환할 때 `as!` force cast를 사용합니다.
CoreFoundation 타입은 Swift 브리징 특성상 `as?` 조건부 캐스트가 항상 성공하여 컴파일 에러가 발생하므로,
`CFGetTypeID` 검사 후 `as!`를 사용하는 것이 올바른 패턴입니다.

### ConfigWatcher 에러 처리

`ConfigWatcher.start()`는 throws 함수입니다. 데몬에서는 설정 감시 실패가 치명적이지 않으므로
do-catch로 감싸서 경고만 출력하고 계속 실행합니다. 설정 변경 자동 감지만 비활성화됩니다.

## 주의사항

- `focusd`는 AppKit RunLoop이 필요하므로 GUI 앱처럼 동작
- 접근성 권한 없으면 창 제목 추적 불가 (앱 전환만 추적)
- launchd plist 경로는 `~/Library/LaunchAgents/dev.sunb.focus.plist`

## 설계 결정

### 고아 세션 삭제 정책

데몬이 비정상 종료(크래시, 강제 종료 등)되면 열린 세션(`endedAt`이 NULL인 세션)이 남습니다.
다음 데몬 시작 시 이 "고아 세션"들은 **복구 대신 삭제**됩니다.

**이유**: 데이터 정확도 우선
- 크래시 시점의 정확한 종료 시간을 알 수 없음
- 부정확한 추정 시간(예: PID 파일의 마지막 갱신 시간)을 기록하면 통계가 왜곡됨
- 사용자에게 "대략적인" 데이터보다 정확한 데이터가 더 가치 있음

**영향**: 드물게 발생하는 크래시 시 해당 세션의 데이터 손실 가능

### config.json 스키마 버전 관리 미적용

설정 파일(`~/.config/focus/config.json`)에 별도 버전 필드를 두지 않습니다.

**이유**: 현재 설정 구조가 단순하고(excludedApps, excludedWindows) 확장 가능성이 낮음.
향후 구조 변경이 필요하면 새 필드 추가 시 기본값 폴백으로 하위 호환성을 유지하거나,
그때 버전 필드를 도입하면 충분합니다.

### 코드 리뷰 시 오탐 주의 사항

다음 항목들은 문제가 아니므로 이슈로 보고하지 말 것:

- **deleteSession 반환값**: GRDB `deleteOne`은 row 존재 시 true, 부재 시 false를 반환. fetch와 delete 사이 race는 실제로 발생하지 않음 (CLI 단일 실행)
- **Delete 명령어 fetch-delete 타이밍**: 세션 조회 후 삭제 전에 데몬이 세션을 종료할 수 있음. 표시된 정보와 실제 삭제 시점의 세션 상태가 다를 수 있으나 ID 기반 삭제로 데이터 무결성 문제 없음
- **ConfigWatcher 시작 순서**: AppMonitor보다 뒤에 시작하지만, 초기 `ExclusionConfig.load()`로 설정이 이미 로드된 상태이므로 문제없음
- **AXObserver 콜백 메모리 안전성**: `takeUnretainedValue()`는 의도된 패턴. `stop()`에서 `removeAXObserver()`가 항상 먼저 호출되어 해제 후 접근 불가
- **closeAllSessions 데드락**: `nonisolated`이고 GRDB `dbQueue.write`가 자체 직렬화를 수행하므로 데드락 불가
- **bundle ID "unknown" 폴백**: bundle ID 없는 앱은 극히 드물고, 있더라도 추적하는 것이 합리적
- **Logger DateFormatter thread-safety**: `formatter.string(from:)` 호출이 `lock.lock()` 이후에 위치하므로 이미 thread-safe함. DateFormatter가 static이라도 모든 접근이 lock 범위 내에서 발생
- **ConfigWatcher atomic save 시 fd 누수**: `waitForFile()`에서 `source?.cancel()` 후 `start()`를 호출할 때 fd 누수가 발생한다는 분석은 오류. `setCancelHandler { close(fd) }`가 설정되어 있어 `cancel()` 호출 시 cancelHandler가 실행되어 기존 fd가 닫힘. 새 `start()`는 새 fd를 열지만 이전 fd는 이미 정리된 상태

### 접근성 권한 시작 시 1회 체크

`AppMonitor`는 시작 시점에만 접근성 권한을 확인하고, 이후 권한 변경을 감지하지 않습니다.

**이유**: 실사용에서 권한을 도중에 취소하는 경우가 극히 드묾.
권한이 없으면 창 제목 추적만 비활성화되고 앱 전환 추적은 정상 동작하므로,
주기적 재확인의 복잡도 대비 실익이 적습니다.

### 종료 타임아웃 시 DB 명시적 정리 미수행

데몬 종료 시 5초 타임아웃 후 `exit(1)`로 강제 종료하는데, 이 시점에서 DB 연결을 명시적으로 닫지 않습니다.

**이유**: 타임아웃이 발생했다는 것은 이미 비정상 상태(정상 종료 루틴이 5초 내에 완료되지 않음)이므로,
그 시점에서 DB 정리를 시도해도 의미가 없습니다. 정상 종료 시에는 `closeAllSessions()`가 완료된 후
RunLoop이 종료되므로 타임아웃에 도달하지 않습니다. SQLite의 WAL 모드가 비정상 종료 복구를 처리합니다.
