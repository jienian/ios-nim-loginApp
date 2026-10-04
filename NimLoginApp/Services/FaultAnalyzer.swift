import Foundation

/// Evidence-weighted fault analysis over collected or imported diagnostic logs.
///
/// This is deliberately not a keyword-only demo scorer:
/// 1. exact / near-duplicate log lines are folded together, while repeat
///    frequency is retained as evidence;
/// 2. benign status lines (healthy / completed / normal) do not become faults
///    merely because they mention a component;
/// 3. each hypothesis is scored from direct failure signals, severity,
///    independent evidence, recurrence, defect alignment, and recovery /
///    counter-evidence; and
/// 4. findings quote the original log lines so an engineer can audit them.
///
/// The resulting `confidence` is a calibrated heuristic score (0...100), not
/// a statistical probability that the hypothesis is true.
enum FaultAnalyzer {
    static let stages = ["事件采集", "解析清洗", "去重归并", "多信号评分", "证据复核", "生成报告"]

    private struct Rule {
        let key: String
        let strongSignals: [String]
        let weakSignals: [String]
        let title: String
        let suggestion: String
        let defectComponents: [String]
    }

    private struct HitGroup {
        var representative: DiagnosticLogEntry
        var entries: [DiagnosticLogEntry]
        var isStrong: Bool
    }

    private static let rules: [Rule] = [
        Rule(key: "auth",
             strongSignals: ["登录失败", "注册失败", "认证失败", "账号或密码不正确", "invalid credentials", "unauthorized", "401", "账号不存在", "密码错误", "account locked", "auth.failure"],
             weakSignals: ["auth", "登录", "注册", "认证", "login", "sign in"],
             title: "登录 / 认证异常",
             suggestion: "先区分凭据错误与系统认证故障：核对同一 attempt_id 的请求、返回码和耗时，再检查账号状态、密码策略、失败锁定与认证服务日志。",
             defectComponents: ["账号", "认证", "登录", "auth"]),
        Rule(key: "network",
             strongSignals: ["网络异常", "请求超时", "连接失败", "dns 解析失败", "dns failure", "timed out", "timeout", "502", "503", "504", "nsurlerrordomain", "-1001", "network.failure"],
             weakSignals: ["network", "网络", "http", "api", "服务器", "请求"],
             title: "网络 / 服务端异常",
             suggestion: "按 attempt_id / 请求 ID 对齐客户端与服务端时间线，核对 DNS、TLS、网关 5xx、超时阈值和重试是否放大故障。",
             defectComponents: ["网络", "主板", "通信", "network"]),
        Rule(key: "thermal",
             strongSignals: ["过热", "温控异常", "thermal 状态偏高", "temperature exceeds", "thermal pressure", "thermal throttling", "降频"],
             weakSignals: ["thermal", "temperature", "温度", "温控", "散热"],
             title: "散热 / 温控异常",
             suggestion: "复测高负载场景温度曲线，检查石墨散热片贴合与 SoC 功耗墙设置。",
             defectComponents: ["散热", "温控", "主板", "thermal"]),
        Rule(key: "battery",
             strongSignals: ["掉电异常", "异常掉电", "掉电速率", "充电失败", "无法充电", "battery drain", "电池老化"],
             weakSignals: ["battery", "电池", "电量", "充电", "电源"],
             title: "电池 / 电源管理异常",
             suggestion: "导出电量历史与充电循环，交叉对比同批次电池内阻，排查待机唤醒源。",
             defectComponents: ["电池", "电源", "battery"]),
        Rule(key: "camera",
             strongSignals: ["对焦失败", "对焦异常", "ois 对焦马达响应超时", "camera error", "摄像头异常", "无法对焦", "响应超时"],
             weakSignals: ["camera", "摄像头", "ois", "对焦"],
             title: "摄像头模组异常",
             suggestion: "做 OIS 校准与对焦马达阻抗测试，对比良品模组互换验证。",
             defectComponents: ["摄像头", "相机", "camera"]),
        Rule(key: "display",
             strongSignals: ["触控失灵", "触控无响应", "屏幕黑屏", "显示异常", "display failure", "touch failure", "屏幕异常"],
             weakSignals: ["display", "屏幕", "触控", "touch", "显示"],
             title: "显示 / 触控异常",
             suggestion: "跑触控网格扫描与排线阻抗测量，检查屏幕排线座子扣合状态。",
             defectComponents: ["屏幕", "显示", "触控", "display"]),
        Rule(key: "stability",
             strongSignals: ["crash", "panic", "watchdog", "闪退", "jetsam", "oom", "异常重启", "系统重启"],
             weakSignals: ["stability", "稳定性", "重启", "启动失败"],
             title: "系统稳定性 / 看门狗复位",
             suggestion: "比对 panic / crash 日志时间戳与温度、电量曲线，定位复位前最后一个驱动调用，并用同一版本尝试稳定复现。",
             defectComponents: ["主板", "系统", "稳定性", "stability"]),
    ]

    private static let failureTerms = [
        "失败", "异常", "错误", "超时", "无响应", "失灵", "不正确", "不存在", "重启", "崩溃", "闪退", "掉电", "过热",
        "error", "failed", "failure", "timeout", "timed out", "crash", "panic", "watchdog", "unauthorized", "invalid", "locked", "401", "502", "503", "504",
    ]

    private static let healthyTerms = [
        "健康度良好", "状态正常", "运行正常", "检查通过", "扫描完成", "初始化完成", "无异常", "正常完成", "healthy", "completed successfully", "initialization completed", "状态 nominal", "状态：nominal", "当前状态：nominal",
    ]

    private static let recoveryTerms = [
        "成功", "恢复正常", "已恢复", "连接恢复", "请求成功", "recovered", "success", "succeeded",
    ]

    static func analyze(logs: [DiagnosticLogEntry], defect: HardwareDefect? = nil) -> FaultAnalysis {
        // Preserve bundle order for sequence checks, but make evidence output
        // deterministic by sorting hit groups by severity and time below.
        let indexed = Array(logs.enumerated())
        let errors = logs.filter { $0.level == .error }
        let warnings = logs.filter { $0.level == .warn }
        let uniqueLogCount = Set(logs.map(normalizedGroupKey)).count
        let duplicateLogCount = max(0, logs.count - uniqueLogCount)
        let dataQuality = makeDataQuality(logs: logs, uniqueCount: uniqueLogCount, duplicateCount: duplicateLogCount)

        var scored: [(rule: Rule, finding: FaultAnalysis.Finding, errorOccurrences: Int, strongGroups: Int)] = []

        for rule in rules {
            let groups = hitGroups(for: rule, in: logs)
            guard !groups.isEmpty else { continue }

            let allHits = groups.flatMap(\.entries)
            let occurrenceCount = allHits.count
            let uniqueHitCount = groups.count
            let errorOccurrences = allHits.filter { $0.level == .error }.count
            let warningOccurrences = allHits.filter { $0.level == .warn }.count
            let errorGroups = groups.filter { group in group.entries.contains { $0.level == .error } }.count
            let warningGroups = groups.filter { group in group.entries.contains { $0.level == .warn } }.count
            let strongGroups = groups.filter(\.isStrong).count
            let weakGroups = uniqueHitCount - strongGroups

            let lastHitOffset = indexed.last { pair in allHits.contains { $0.id == pair.element.id } }?.offset ?? 0
            let counterEvidence = recoveryEvidence(for: rule, in: logs, afterOffset: lastHitOffset)
            let defectAligned = isDefectAligned(rule: rule, defect: defect)

            var score = 30.0
            var reasons: [String] = []

            let signalPoints = min(28.0, Double(strongGroups) * 18.0 + Double(weakGroups) * 8.0)
            if signalPoints > 0 {
                score += signalPoints
                reasons.append(strongGroups > 0 ? "包含直接故障信号" : "包含故障上下文信号")
            }

            let severityPoints = min(24.0, Double(errorGroups) * 14.0 + Double(warningGroups) * 4.0)
            if severityPoints > 0 {
                score += severityPoints
                reasons.append("ERROR \(errorOccurrences) 次 / WARN \(warningOccurrences) 次")
            }

            if uniqueHitCount > 1 {
                score += 4
                reasons.append("\(uniqueHitCount) 条独立证据")
            }
            let repeatCount = max(0, occurrenceCount - uniqueHitCount)
            if repeatCount > 0 {
                score += min(8.0, Double(repeatCount) * 2.0)
                reasons.append("相同故障重复出现 \(occurrenceCount) 次")
            }
            if occurrenceCount >= 3 && counterEvidence.isEmpty {
                score += 5
                reasons.append("故障未见恢复且重复发生")
            }
            if logs.count >= 4 && lastHitOffset >= Int(Double(max(0, logs.count - 1)) * 0.75) {
                score += 4
                reasons.append("故障信号位于日志时间线后段")
            }
            if defectAligned {
                score += 6
                reasons.append("与所选缺陷部件一致")
            }
            if !counterEvidence.isEmpty {
                score -= 7
                reasons.append("后续出现成功/恢复记录，持续性需复核")
            }

            let confidence = max(5, min(96, Int(score.rounded())))
            guard confidence >= 35 else { continue }

            let supporting = groups
                .sorted { lhs, rhs in
                    let lScore = severityRank(lhs.representative)
                    let rScore = severityRank(rhs.representative)
                    if lScore != rScore { return lScore > rScore }
                    return lhs.representative.timestamp < rhs.representative.timestamp
                }
                .prefix(3)
                .map { quote($0.representative) }

            let evidence = "命中 \(uniqueHitCount) 条去重日志 / 共出现 \(occurrenceCount) 次（ERROR \(errorOccurrences) 次、WARN \(warningOccurrences) 次）；重复折叠 \(max(0, occurrenceCount - uniqueHitCount)) 条。"
            let finding = FaultAnalysis.Finding(
                title: rule.title,
                confidence: confidence,
                evidence: evidence,
                suggestion: rule.suggestion,
                supportingEvidence: Array(supporting),
                counterEvidence: counterEvidence,
                scoreExplanation: "评分依据：" + reasons.joined(separator: "；") + "。该分数是证据强度评分，不是统计概率。",
                occurrenceCount: occurrenceCount,
                uniqueHitCount: uniqueHitCount
            )
            scored.append((rule: rule, finding: finding, errorOccurrences: errorOccurrences, strongGroups: strongGroups))
        }

        var findings = scored
            .sorted { lhs, rhs in
                if lhs.finding.confidence != rhs.finding.confidence { return lhs.finding.confidence > rhs.finding.confidence }
                if lhs.errorOccurrences != rhs.errorOccurrences { return lhs.errorOccurrences > rhs.errorOccurrences }
                if lhs.strongGroups != rhs.strongGroups { return lhs.strongGroups > rhs.strongGroups }
                return lhs.rule.key < rhs.rule.key
            }
            .map(\.finding)

        if let defect, findings.isEmpty {
            findings.append(.init(
                title: "\(defect.component)相关异常（待验证）",
                confidence: 25,
                evidence: "缺陷单 \(defect.id)：\(defect.symptom)。当前日志未形成达到阈值的证据链。",
                suggestion: "先收集真实事件或导入外部日志，再重新分析以提高定位精度。",
                supportingEvidence: [],
                counterEvidence: [],
                scoreExplanation: "该项来自缺陷单先验，不计为已证实根因。",
                occurrenceCount: 0,
                uniqueHitCount: 0
            ))
        }

        let summary: String
        if logs.isEmpty {
            summary = "尚无诊断日志。先收集真实事件或导入外部日志，分析精度会明显更高。"
        } else if findings.isEmpty {
            summary = "共分析 \(logs.count) 条日志（去重 \(uniqueLogCount) 条），未形成达到阈值的根因假设，建议人工复核原始日志。"
        } else {
            let top = findings[0]
            let label = top.confidence >= 70 ? "最可能根因" : "首要假设"
            summary = "共分析 \(logs.count) 条日志（去重 \(uniqueLogCount) 条；ERROR \(errors.count) / WARN \(warnings.count)），\(label)：\(top.title)（评分 \(top.confidence)/100）。"
        }

        return FaultAnalysis(
            summary: summary,
            findings: findings,
            stages: stages,
            errorCount: errors.count,
            warningCount: warnings.count,
            analyzedLogCount: logs.count,
            uniqueLogCount: uniqueLogCount,
            duplicateLogCount: duplicateLogCount,
            dataQuality: dataQuality,
            limitations: [
                "评分是规则与证据强度的启发式结果，不是统计概率。",
                "分析范围仅限已采集或导入的日志；未接入系统级 sysdiagnose、崩溃上报后台与服务端日志时，不能宣称整机根因已证实。",
                "同一条日志可能支持多个假设，最终结论需结合时间线、复现实验或换件验证。",
            ]
        )
    }

    /// Convenience path for validating raw text bundles and future import UI.
    static func analyze(text: String, defect: HardwareDefect? = nil) -> FaultAnalysis {
        analyze(logs: DiagnosticLogParser.parse(text), defect: defect)
    }

    // MARK: - Evidence handling

    private static func hitGroups(for rule: Rule, in logs: [DiagnosticLogEntry]) -> [HitGroup] {
        var order: [String] = []
        var grouped: [String: HitGroup] = [:]

        for entry in logs {
            guard let isStrong = hitStrength(rule: rule, entry: entry) else { continue }
            let key = normalizedGroupKey(entry)
            if var existing = grouped[key] {
                existing.entries.append(entry)
                existing.isStrong = existing.isStrong || isStrong
                if severityRank(entry) > severityRank(existing.representative) {
                    existing.representative = entry
                }
                grouped[key] = existing
            } else {
                grouped[key] = HitGroup(representative: entry, entries: [entry], isStrong: isStrong)
                order.append(key)
            }
        }
        return order.compactMap { grouped[$0] }
    }

    /// Returns `true` for a direct/strong signal, `false` for a weaker
    /// corroborating signal, and `nil` when the entry should not support the
    /// hypothesis at all.
    private static func hitStrength(rule: Rule, entry: DiagnosticLogEntry) -> Bool? {
        // Structured app events carry a domain. Do not let wording such as
        // "登录失败：网络异常" turn a network.failure event into an auth hit.
        if let event = entry.event?.lowercased() {
            if event.hasPrefix("auth."), rule.key != "auth" { return nil }
            if event.hasPrefix("network."), rule.key != "network" { return nil }
        }

        // Imported logs usually carry the subsystem in `category`. Treat a
        // known subsystem as the evidence domain: a network log mentioning
        // "/login" is not auth evidence, and a camera log mentioning
        // "timeout" is not network evidence. Free-text `system` logs may still
        // match by content because they have no specific subsystem.
        let knownCategories = Set(rules.map(\.key))
        let entryCategory = entry.category.lowercased()
        if knownCategories.contains(entryCategory), entryCategory != rule.key {
            return nil
        }

        let text = searchableText(entry)
        let hasStrong = rule.strongSignals.contains { text.contains($0.lowercased()) }
        let hasWeak = rule.weakSignals.contains { text.contains($0.lowercased()) }
        guard hasStrong || hasWeak else { return nil }

        if isHealthyStatusLine(text: text, level: entry.level) {
            return nil
        }
        if hasStrong { return true }
        if entry.level == .error || failureTerms.contains(where: { text.contains($0.lowercased()) }) {
            return false
        }
        if entry.level == .warn {
            return false
        }
        return nil
    }

    private static func isHealthyStatusLine(text: String, level: DiagnosticLogEntry.Level) -> Bool {
        guard level != .error else { return false }
        let hasFailure = failureTerms.contains { text.contains($0.lowercased()) }
        guard !hasFailure else { return false }
        return healthyTerms.contains { text.contains($0.lowercased()) }
    }

    private static func recoveryEvidence(for rule: Rule, in logs: [DiagnosticLogEntry], afterOffset: Int) -> [String] {
        guard afterOffset < logs.count - 1 else { return [] }
        return logs.enumerated().compactMap { (offset, entry) in
            guard offset > afterOffset else { return nil }
            let text = searchableText(entry)
            let sameDomain = rule.weakSignals.contains { text.contains($0.lowercased()) } || entry.category.lowercased() == rule.key
            guard sameDomain else { return nil }
            guard recoveryTerms.contains(where: { text.contains($0.lowercased()) }) else { return nil }
            guard !failureTerms.contains(where: { text.contains($0.lowercased()) }) else { return nil }
            return quote(entry)
        }.prefix(2).map { $0 }
    }

    private static func isDefectAligned(rule: Rule, defect: HardwareDefect?) -> Bool {
        guard let defect else { return false }
        let component = defect.component.lowercased()
        return rule.defectComponents.contains { component.contains($0.lowercased()) }
    }

    private static func makeDataQuality(logs: [DiagnosticLogEntry], uniqueCount: Int, duplicateCount: Int) -> String {
        guard !logs.isEmpty else { return "无日志，数据质量：不足。" }
        let sources = Set(logs.map { $0.source ?? "unknown" }).sorted().joined(separator: ", ")
        var notes: [String] = []
        if logs.count < 5 { notes.append("样本量偏小") }
        if duplicateCount > 0 { notes.append("已折叠 \(duplicateCount) 条重复日志") }
        if logs.allSatisfy({ $0.source == "simulated-probe" }) { notes.append("仅包含模拟探针，不应当作真机证据") }
        let quality = logs.count < 5 ? "偏低" : (duplicateCount > logs.count / 2 ? "中等（重复较多）" : "可用")
        let suffix = notes.isEmpty ? "" : "；" + notes.joined(separator: "；")
        return "数据质量：\(quality)，共 \(logs.count) 条（去重 \(uniqueCount) 条），来源：\(sources)\(suffix)。"
    }

    private static func severityRank(_ entry: DiagnosticLogEntry) -> Int {
        switch entry.level {
        case .error: return 3
        case .warn: return 2
        case .info: return 1
        }
    }

    private static func searchableText(_ entry: DiagnosticLogEntry) -> String {
        var parts = [entry.category, entry.event ?? "", entry.message]
        if let attributes = entry.attributes {
            parts.append(attributes.keys.sorted().joined(separator: " "))
            parts.append(attributes.values.sorted().joined(separator: " "))
        }
        return parts.joined(separator: " ").lowercased()
    }

    private static func normalizedGroupKey(_ entry: DiagnosticLogEntry) -> String {
        var text = (entry.category + "|" + (entry.event ?? "") + "|" + entry.message).lowercased()
        // Fold volatile identifiers / measured values so repeated occurrences
        // of the same failure are counted as recurrence, not as many
        // independent pieces of evidence.
        text = replaceRegex(text, pattern: #"[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}"#, with: "<account>")
        text = replaceRegex(text, pattern: #"\b[0-9a-f]{8}-[0-9a-f-]{27,}\b"#, with: "<uuid>")
        text = replaceRegex(text, pattern: #"\b\d+(?:\.\d+)?\s*(?:ms|s|%|/h)?\b"#, with: "<n>")
        text = replaceRegex(text, pattern: #"\s+"#, with: " ")
        if let attributes = entry.attributes, let errorCode = attributes["error_code"] {
            text += "|error_code=" + errorCode.lowercased()
        }
        return text
    }

    private static func replaceRegex(_ value: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..., in: value)
        return regex.stringByReplacingMatches(in: value, range: range, withTemplate: replacement)
    }

    private static func quote(_ entry: DiagnosticLogEntry) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        let event = entry.event.map { "/\($0)" } ?? ""
        return "\(formatter.string(from: entry.timestamp)) [\(entry.level.rawValue)] \(entry.category)\(event): \(entry.message)"
    }
}

/// Markdown incident report generated from an analysis. Keeping this next to
/// the analyzer makes the report deterministic and unit-testable.
enum FaultIncidentReport {
    static func markdown(analysis: FaultAnalysis, logs: [DiagnosticLogEntry], defect: HardwareDefect? = nil) -> String {
        let iso = ISO8601DateFormatter()
        var lines: [String] = []
        lines.append("# 故障分析报告")
        lines.append("")
        lines.append("- 生成时间：\(iso.string(from: Date()))")
        if let defect {
            lines.append("- 关联缺陷：\(defect.id) · \(defect.title)（\(defect.component)，\(defect.severity.rawValue)，\(defect.status.rawValue)）")
            lines.append("- 设备：\(defect.deviceModel)")
            lines.append("- 现象：\(defect.symptom)")
        }
        lines.append("- \(analysis.dataQuality)")
        lines.append("")
        lines.append("## 结论")
        lines.append("")
        lines.append(analysis.summary)
        lines.append("")
        lines.append("> 口径说明：下文的“评分”是证据强度评分，不是统计概率，也不能替代复现/换件验证。")
        lines.append("")

        lines.append("## 假设排序")
        lines.append("")
        if analysis.findings.isEmpty {
            lines.append("未形成达到阈值的根因假设。")
        } else {
            for (index, finding) in analysis.findings.enumerated() {
                lines.append("### \(index + 1). \(finding.title) — \(finding.confidence)/100")
                lines.append("")
                lines.append("- 证据概况：\(finding.evidence)")
                if !finding.supportingEvidence.isEmpty {
                    lines.append("- 原始证据：")
                    for item in finding.supportingEvidence { lines.append("  - `\(item)`") }
                }
                if !finding.counterEvidence.isEmpty {
                    lines.append("- 反证/恢复证据：")
                    for item in finding.counterEvidence { lines.append("  - `\(item)`") }
                }
                lines.append("- \(finding.scoreExplanation)")
                lines.append("- 建议：\(finding.suggestion)")
                lines.append("")
            }
        }

        lines.append("## 关键时间线")
        lines.append("")
        let timeline = logs.filter { $0.level != .info }.sorted { $0.timestamp < $1.timestamp }
        if timeline.isEmpty {
            lines.append("无 WARN / ERROR 事件。")
        } else {
            for entry in timeline {
                lines.append("- `\(iso.string(from: entry.timestamp)) [\(entry.level.rawValue)] \(entry.category): \(entry.message)`")
            }
        }
        lines.append("")

        lines.append("## 数据范围与限制")
        lines.append("")
        lines.append("- 分析日志：\(analysis.analyzedLogCount) 条，去重后 \(analysis.uniqueLogCount) 条，重复 \(analysis.duplicateLogCount) 条。")
        for limitation in analysis.limitations {
            lines.append("- \(limitation)")
        }
        lines.append("")

        lines.append("## 原始日志")
        lines.append("")
        if logs.isEmpty {
            lines.append("（空）")
        } else {
            for entry in logs.sorted(by: { $0.timestamp < $1.timestamp }) {
                lines.append("- `\(iso.string(from: entry.timestamp)) [\(entry.level.rawValue)] \(entry.category): \(entry.message)`")
            }
        }
        return lines.joined(separator: "\n")
    }
}
