# focus - macOS 스크린 타임 추적 도구 설계 문서

## 개요

macOS에서 Frontmost App과 창 제목을 추적하여 활동 시간을 기록하는 개발자 친화적인 CLI 도구.

| 항목 | 선택 |
|------|------|
| 언어 | Swift |
| DB | SQLite |
| 데몬 관리 | launchd |
| 데이터 수집 | 이벤트 기반 (앱 전환 + 창 제목 변경) |

## 아키텍처

```
┌─────────────────────────────────────────────────────────┐
│                      focus CLI                          │
│  ┌─────────┐  ┌─────────┐  ┌──────────┐  ┌──────────┐  │
│  │ start   │  │  stop   │  │ timeline │  │  search  │  │
│  └─────────┘  └─────────┘  └──────────┘  └──────────┘  │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                    focusd (데몬)                         │
│  ┌──────────────────┐    ┌──────────────────────────┐  │
│  │ AppMonitor       │───▶│ SessionRecorder          │  │
│  │ - NSWorkspace    │    │ - SQLite에 세션 기록       │  │
│  │ - AXObserver     │    └──────────────────────────┘  │
│  └──────────────────┘                                   │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
                    ┌──────────────┐
                    │   SQLite DB  │
                    │ ~/.focus/    │
                    │  focus.db    │
                    └──────────────┘
```

## 데이터 모델

### sessions 테이블

```sql
CREATE TABLE sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    app_bundle_id TEXT NOT NULL,      -- com.apple.Safari
    app_name TEXT NOT NULL,            -- Safari
    window_title TEXT,                 -- 현재 탭/문서 제목
    started_at INTEGER NOT NULL,       -- Unix timestamp (ms)
    ended_at INTEGER,                  -- NULL = 현재 진행 중
    duration_ms INTEGER                -- 캐시된 duration
);

CREATE INDEX idx_sessions_started_at ON sessions(started_at);
CREATE INDEX idx_sessions_app_bundle_id ON sessions(app_bundle_id);
```

### 세션 기록 정책

새 세션이 생성되는 경우:
1. 앱 전환 시 (다른 앱이 Frontmost가 됨)
2. 같은 앱 내 창 제목 변경 시

### 비정상 종료 복구

focusd 시작 시 ended_at IS NULL인 고아 세션 삭제.

## CLI 명령어

| 명령어 | 설명 |
|--------|------|
| focus start | 데몬 시작 |
| focus stop | 데몬 중지 |
| focus status | 데몬 상태 확인 |
| focus timeline [--from DATE] [--to DATE] | 시간순 세션 + 요약 |
| focus today | timeline의 alias (오늘) |
| focus search <query> [--from DATE] | 제목/앱 검색 |
| focus log [--limit N] | 원시 세션 로그 |

### 출력 예시 (focus today)

```
╭─────────────────────────────────────────────────────────────────╮
│ Timeline: 2024-01-15                                            │
├─────────────────────────────────────────────────────────────────┤
│ 09:00 - 09:45 │  45m │ VS Code      │ focus/Sources/main.swift  │
│ 09:45 - 09:52 │   7m │ Safari       │ Swift NSWorkspace docs    │
│ 09:52 - 10:30 │  38m │ VS Code      │ focus/Sources/monitor.sw… │
├─────────────────────────────────────────────────────────────────┤
│ Summary (3h 00m total)                                          │
│   VS Code    2h 43m (91%)  ████████████████████░                │
│   Safari        7m  (4%)   █░                                   │
╰─────────────────────────────────────────────────────────────────╯
```

## 프로젝트 구조

```
focus/
├── Package.swift
├── Sources/
│   ├── focus/                    # CLI 도구
│   │   ├── main.swift
│   │   └── Commands/
│   │       ├── StartCommand.swift
│   │       ├── StopCommand.swift
│   │       ├── StatusCommand.swift
│   │       ├── TimelineCommand.swift
│   │       └── SearchCommand.swift
│   ├── focusd/                   # 데몬
│   │   ├── main.swift
│   │   ├── AppMonitor.swift
│   │   └── SessionRecorder.swift
│   └── FocusCore/                # 공유 라이브러리
│       ├── Database.swift
│       ├── Models.swift
│       └── Config.swift
├── Resources/
│   └── com.focus.daemon.plist
└── Tests/
```

## 핵심 구현

### AppMonitor - 앱 전환 감지

```swift
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification,
    object: nil, queue: .main
) { notification in
    // 앱 전환 처리
}
```

### AppMonitor - 창 제목 변경 감지

- AXObserver + kAXTitleChangedNotification
- 접근성 권한 필요 (System Preferences > Privacy > Accessibility)

## 의존성

- swift-argument-parser - CLI 인자 파싱
- GRDB.swift - SQLite ORM

## 구현 순서

### 1단계: 프로젝트 기반 설정
- Swift Package 초기화
- 의존성 추가
- FocusCore/Config.swift

### 2단계: 데이터 레이어
- FocusCore/Database.swift (SQLite 연결, 마이그레이션)
- FocusCore/Models.swift (Session, AppInfo)

### 3단계: 데몬 핵심 기능
- focusd/AppMonitor.swift (앱 전환 + 창 제목 변경)
- focusd/SessionRecorder.swift
- focusd/main.swift
- 비정상 종료 복구

### 4단계: CLI 구현
- StartCommand, StopCommand, StatusCommand
- TimelineCommand, SearchCommand

### 5단계: launchd 통합
- com.focus.daemon.plist 작성
- 설치/제거 스크립트

## 파일 경로

| 용도 | 경로 |
|------|------|
| DB | ~/.focus/focus.db |
| 로그 | ~/.focus/focusd.log |
| launchd plist | ~/Library/LaunchAgents/com.focus.daemon.plist |

## 검증 방법

1. focusd 직접 실행 → 앱 전환 → DB 확인
2. CLI 테스트: start/stop/timeline/search
3. launchd 등록 → 재부팅 → 자동 시작 확인
