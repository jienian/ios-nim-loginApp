import Foundation

/// Parser for diagnostic log text supplied by an engineer.
///
/// This intentionally accepts the formats this app exports plus common
/// plain-text service / device-log shapes. It does not claim to parse Apple's
/// private sysdiagnose archives; those still need to be reduced to text (or a
/// dedicated importer) before analysis.
enum DiagnosticLogParser {
    private static let knownCategories = [
        "auth", "network", "thermal", "battery", "camera", "display", "system", "stability",
    ]

    static func parse(_ text: String, fallbackDate: Date = Date()) -> [DiagnosticLogEntry] {
        text.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }

            let level = detectLevel(in: line)
            let timestamp = detectTimestamp(in: line) ?? fallbackDate
            let category = detectCategory(in: line)
            let message = extractMessage(from: line, category: category)
            return DiagnosticLogEntry(
                timestamp: timestamp,
                level: level,
                category: category,
                message: message.isEmpty ? line : message,
                event: nil,
                source: "imported-text",
                attributes: nil
            )
        }
    }

    private static func detectLevel(in line: String) -> DiagnosticLogEntry.Level {
        let upper = line.uppercased()
        if upper.contains("[ERROR]") || upper.contains(" ERROR ") || upper.hasPrefix("ERROR") || upper.contains(" FATAL ") {
            return .error
        }
        if upper.contains("[WARN]") || upper.contains(" WARN") || upper.contains("WARNING") {
            return .warn
        }
        return .info
    }

    private static func detectTimestamp(in line: String) -> Date? {
        // ISO-8601, e.g. 2026-10-05T00:01:02Z or with fractional seconds.
        if let range = line.range(of: #"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?"#, options: .regularExpression) {
            let value = String(line[range])
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: value) { return date }
        }
        // Local date-time, e.g. 2026-10-05 00:01:02.
        if let range = line.range(of: #"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}"#, options: .regularExpression) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return formatter.date(from: String(line[range]))
        }
        return nil
    }

    private static func detectCategory(in line: String) -> String {
        let lower = line.lowercased()

        // Bracketed subsystem that is not the level, e.g. [network].
        let bracketPattern = #"\[([a-z][a-z0-9_.-]{1,30})\]"#
        if let matches = try? NSRegularExpression(pattern: bracketPattern).matches(
            in: lower, range: NSRange(lower.startIndex..., in: lower)
        ) {
            for match in matches {
                guard let range = Range(match.range(at: 1), in: lower) else { continue }
                let value = String(lower[range])
                if !["info", "warn", "warning", "error", "fatal"].contains(value) {
                    return value
                }
            }
        }

        // Explicit `category:` prefix after optional timestamp/level tokens.
        let prefixPattern = #"(?:^|\s)([a-z][a-z0-9_.-]{1,30}):\s"#
        if let match = try? NSRegularExpression(pattern: prefixPattern).firstMatch(
            in: lower, range: NSRange(lower.startIndex..., in: lower)
        ), let range = Range(match.range(at: 1), in: lower) {
            let value = String(lower[range])
            if knownCategories.contains(value) { return value }
        }

        // Last resort: infer from the vocabulary used by the analysis rules.
        if lower.contains("login") || lower.contains("auth") || lower.contains("登录") || lower.contains("认证") { return "auth" }
        if lower.contains("network") || lower.contains("dns") || lower.contains("http") || lower.contains("网络") { return "network" }
        if lower.contains("thermal") || lower.contains("temperature") || lower.contains("温度") { return "thermal" }
        if lower.contains("battery") || lower.contains("电池") || lower.contains("电量") { return "battery" }
        if lower.contains("camera") || lower.contains("摄像头") || lower.contains("对焦") { return "camera" }
        if lower.contains("display") || lower.contains("touch") || lower.contains("屏幕") || lower.contains("触控") { return "display" }
        if lower.contains("crash") || lower.contains("panic") || lower.contains("watchdog") { return "stability" }
        return "system"
    }

    private static func extractMessage(from line: String, category: String) -> String {
        // Preferred shape: `... category: message`.
        if let range = line.range(of: "\(category):", options: [.caseInsensitive]) {
            return String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        // Bracketed subsystem shape: `... [category] message`.
        if let close = line.range(of: "]", options: [], range: line.startIndex..<line.endIndex) {
            let tail = String(line[close.upperBound...]).trimmingCharacters(in: .whitespaces)
            if tail.lowercased().contains(category) || tail.count > 8 { return tail }
        }
        return line
    }
}
