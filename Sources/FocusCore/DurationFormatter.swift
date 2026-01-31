import Foundation

/// 시간 포맷 유틸리티
public enum DurationFormatter {
    /// 상세 포맷: "1h 2m 3s", "5m 30s", "45s"
    public static func detailed(_ seconds: Int) -> String {
        guard seconds >= 0 else { return "0s" }

        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, secs)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, secs)
        } else {
            return String(format: "%ds", secs)
        }
    }

    /// 간략 포맷: "1h 2m", "5m" (분 단위 올림)
    public static func compact(_ seconds: Int) -> String {
        guard seconds > 0 else { return "0m" }

        // 오버플로우 방지: Int.max - 59 초과 시 안전한 최대값 사용
        let safeSeconds = min(seconds, Int.max - 59)

        // 분 단위 올림: 61초 → 2분, 60초 → 1분, 59초 → 1분
        let totalMinutes = (safeSeconds + 59) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }
}
