import Foundation

// MARK: - Models

/// 제외할 앱 설정
public struct ExcludedApp: Codable, Equatable, Sendable {
    public let bundleId: String
    public let comment: String?

    public init(bundleId: String, comment: String? = nil) {
        self.bundleId = bundleId
        self.comment = comment
    }
}

/// 제외할 윈도우 설정
public struct ExcludedWindow: Codable, Equatable, Sendable {
    public let bundleId: String
    public let titlePattern: String
    public let caseSensitive: Bool
    public let comment: String?

    public init(bundleId: String, titlePattern: String, caseSensitive: Bool = true, comment: String? = nil) {
        self.bundleId = bundleId
        self.titlePattern = titlePattern
        self.caseSensitive = caseSensitive
        self.comment = comment
    }

    enum CodingKeys: String, CodingKey {
        case bundleId, titlePattern, caseSensitive, comment
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleId = try container.decode(String.self, forKey: .bundleId)
        titlePattern = try container.decode(String.self, forKey: .titlePattern)
        caseSensitive = try container.decodeIfPresent(Bool.self, forKey: .caseSensitive) ?? true
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
    }
}

// MARK: - ExclusionConfig

/// 제외 설정 관리
public struct ExclusionConfig: Equatable, Sendable {
    public let excludedApps: [ExcludedApp]
    public let excludedWindows: [ExcludedWindow]

    /// 앱 제외 검사용 캐시 (O(1) 검색)
    private let excludedAppBundleIds: Set<String>

    public init(excludedApps: [ExcludedApp] = [], excludedWindows: [ExcludedWindow] = []) {
        self.excludedApps = excludedApps
        self.excludedWindows = excludedWindows
        self.excludedAppBundleIds = Set(excludedApps.map(\.bundleId))
    }

    /// 기본 설정 (loginwindow만 제외)
    public static let `default` = ExclusionConfig(
        excludedApps: [
            ExcludedApp(bundleId: "com.apple.loginwindow", comment: "System login"),
        ],
        excludedWindows: []
    )

    /// 설정 파일에서 로드 (없으면 기본값 반환)
    public static func load(from path: URL) -> ExclusionConfig {
        guard FileManager.default.fileExists(atPath: path.path) else {
            return .default
        }

        do {
            let data = try Data(contentsOf: path)
            let config = try JSONDecoder().decode(ExclusionConfig.self, from: data)
            return config
        } catch {
            Logger.error("ExclusionConfig", "Failed to parse config file: \(error.localizedDescription)")
            return .default
        }
    }

    /// 앱을 제외해야 하는지 확인 (O(1) Set 검색)
    public func shouldExcludeApp(bundleId: String) -> Bool {
        excludedAppBundleIds.contains(bundleId)
    }

    /// 윈도우를 제외해야 하는지 확인
    public func shouldExcludeWindow(bundleId: String, title: String) -> Bool {
        for window in excludedWindows {
            // bundleId 매칭 ("*"는 모든 앱)
            let bundleMatches = window.bundleId == "*" || window.bundleId == bundleId

            guard bundleMatches else { continue }

            // glob 패턴 매칭
            if matchesGlobPattern(title, pattern: window.titlePattern, caseSensitive: window.caseSensitive) {
                return true
            }
        }
        return false
    }
}

// MARK: - Codable

extension ExclusionConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case excludedApps, excludedWindows
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let apps = try container.decodeIfPresent([ExcludedApp].self, forKey: .excludedApps) ?? []
        let windows = try container.decodeIfPresent([ExcludedWindow].self, forKey: .excludedWindows) ?? []
        self.init(excludedApps: apps, excludedWindows: windows)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(excludedApps, forKey: .excludedApps)
        try container.encode(excludedWindows, forKey: .excludedWindows)
    }
}

// MARK: - Glob Pattern Matching

/// 컴파일된 정규식 캐시 (패턴 + 대소문자 옵션 기준)
/// NSCache는 스레드 안전하며 메모리 압박 시 자동 해제
///
/// 캐시 키 포맷: "{s|i}:{pattern}"
/// - "s:" 접두사: 대소문자 구분 (caseSensitive = true)
/// - "i:" 접두사: 대소문자 무시 (caseSensitive = false)
/// - 예: "s:*.txt", "i:*password*"
private let globRegexCache: NSCache<NSString, NSRegularExpression> = {
    let cache = NSCache<NSString, NSRegularExpression>()
    cache.countLimit = 100
    return cache
}()

/// glob 패턴을 정규식으로 변환
private func compileGlobPattern(_ pattern: String, caseSensitive: Bool) -> NSRegularExpression? {
    var regexPattern = "^"
    for char in pattern {
        switch char {
        case "*":
            regexPattern += ".*"
        case "?":
            regexPattern += "."
        case ".", "+", "^", "$", "{", "}", "[", "]", "|", "(", ")", "\\":
            regexPattern += "\\\(char)"
        default:
            regexPattern += String(char)
        }
    }
    regexPattern += "$"

    var options: NSRegularExpression.Options = []
    if !caseSensitive {
        options.insert(.caseInsensitive)
    }

    do {
        return try NSRegularExpression(pattern: regexPattern, options: options)
    } catch {
        Logger.warning("ExclusionConfig", "Invalid glob pattern '\(pattern)': \(error.localizedDescription)")
        return nil
    }
}

/// glob 패턴을 정규식으로 변환하여 매칭
/// 지원 패턴: * (0개 이상 문자), ? (단일 문자)
func matchesGlobPattern(_ string: String, pattern: String, caseSensitive: Bool) -> Bool {
    let cacheKey = "\(caseSensitive ? "s" : "i"):\(pattern)"

    let nsKey = cacheKey as NSString
    let regex: NSRegularExpression? = {
        if let cached = globRegexCache.object(forKey: nsKey) {
            return cached
        }

        guard let compiled = compileGlobPattern(pattern, caseSensitive: caseSensitive) else {
            return nil
        }

        globRegexCache.setObject(compiled, forKey: nsKey)
        return compiled
    }()

    guard let regex else { return false }
    let range = NSRange(string.startIndex..., in: string)
    return regex.firstMatch(in: string, options: [], range: range) != nil
}
