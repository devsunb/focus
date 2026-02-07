# focus

macOS 스크린 타임 추적 도구. 앱 사용 시간과 창 제목을 자동으로 기록합니다.

## 설치

```bash
swift build -c release
cp .build/release/focus "$HOME/.local/bin/"
cp .build/release/focusd "$HOME/.local/bin/"
```

## 사용법

### 데몬 관리

```bash
# launchd 에이전트 설치 (로그인 시 자동 시작)
focus install

# launchd 에이전트 제거
focus uninstall
```

### 사용 요약 (기본 커맨드)

```bash
# 오늘 앱별 요약
focus
focus summary

# 특정 날짜
focus summary 2026-01-29

# 날짜 범위
focus summary --from 2026-01-27 --to 2026-01-29

# 창별 요약
focus summary --window

# JSON 출력
focus summary --json
```

### 세션 로그

```bash
# 최근 세션
focus log

# 검색 (앱 이름 또는 창 제목)
focus log "Safari"
focus log "GitHub"

# 앱 필터
focus log --app Safari

# 날짜 필터
focus log --date 2026-01-29
focus log --from 2026-01-27 --to 2026-01-29

# 결과 수 제한
focus log --limit 20

# 상세 출력
focus log --verbose

# JSON 출력
focus log --json
```

### 세션 삭제

```bash
# dry run (삭제 대상 미리보기)
focus delete --id 42
focus delete --app Safari
focus delete --date 2026-01-29
focus delete --from 2026-01-27 --to 2026-01-29
focus delete --all

# 실제 삭제 (-y 또는 --yes)
focus delete --id 42 -y
focus delete --app Safari --date 2026-01-29 -y
```

## 데이터 저장 위치

- 데이터베이스: `~/.local/share/focus/focus.db`
- PID 파일: `~/.local/share/focus/focusd.pid`
- 로그 파일: `~/.local/share/focus/focusd.log`
- 설정 파일: `~/.config/focus/config.json`

## 제외 설정

특정 앱이나 윈도우를 추적에서 제외할 수 있습니다. 설정 파일을 수정하면 데몬 재시작 없이 실시간 반영됩니다.

### 설정 파일 위치

`~/.config/focus/config.json`

### 기본값

설정 파일이 없으면 다음 기본값이 적용됩니다:
- **제외 앱**: `com.apple.loginwindow` (시스템 로그인 화면)
- **제외 윈도우**: 없음

### 설정 예시

```json
{
  "excludedApps": [
    { "bundleId": "com.apple.loginwindow", "comment": "System login" },
    { "bundleId": "com.1password.1password", "comment": "Password manager" }
  ],
  "excludedWindows": [
    {
      "bundleId": "com.apple.Safari",
      "titlePattern": "*Private*",
      "comment": "Safari private browsing"
    },
    {
      "bundleId": "*",
      "titlePattern": "*password*",
      "caseSensitive": false,
      "comment": "Any password window"
    }
  ]
}
```

### 필드 설명

**excludedApps**
- `bundleId`: 제외할 앱의 Bundle ID (필수)
- `comment`: 설명 (선택)

**excludedWindows**
- `bundleId`: 대상 앱의 Bundle ID, `*`는 모든 앱 (필수)
- `titlePattern`: 윈도우 제목 패턴 (필수)
    - `*`: 0개 이상의 문자
    - `?`: 단일 문자
- `caseSensitive`: 대소문자 구분 여부 (기본값: `true`)
- `comment`: 설명 (선택)

## 필요 권한

- **앱 전환 추적**: 권한 불필요
- **창 제목 추적**: 시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용 권한 필요

## 개발

```bash
# 빌드
swift build

# 테스트
swift test

# 릴리스 빌드
swift build -c release
```
