import Foundation

/// Rule-based fault analysis over collected diagnostic logs.
/// The pipeline mirrors an optimised engineer workflow:
/// collect -> clean/dedupe -> classify by component -> rank root causes -> suggest next steps.
enum FaultAnalyzer {
    static let stages = ["日志收集", "清洗去重", "按部件分类", "根因排序", "生成建议"]

    private struct Rule {
        let keywords: [String]
        let title: String
        let suggestion: String
    }

    private static let rules: [Rule] = [
        Rule(keywords: ["登录失败", "认证失败", "账号或密码不正确", "invalid credentials", "401", "账号不存在"],
             title: "登录 / 认证异常",
             suggestion: "核对账号密码与账号状态，确认密码策略与失败锁定策略，检查认证接口返回码分布。"),
        Rule(keywords: ["网络异常", "network", "请求超时", "timeout", "502", "503", "dns"],
             title: "网络 / 服务端异常",
             suggestion: "抓包核对 DNS / TLS 与网关 5xx 日志，检查接口超时与重试策略。"),
        Rule(keywords: ["thermal", "temperature", "过热", "温控"],
             title: "散热 / 温控异常",
             suggestion: "复测高负载场景温度曲线，检查石墨散热片贴合与 SoC 功耗墙设置。"),
        Rule(keywords: ["battery", "掉电", "充电", "电量"],
             title: "电池 / 电源管理异常",
             suggestion: "导出电量历史与充电循环，交叉对比同批次电池内阻，排查待机唤醒源。"),
        Rule(keywords: ["camera", "对焦", "摄像头", "ois"],
             title: "摄像头模组异常",
             suggestion: "做 OIS 校准与对焦马达阻抗测试，对比良品模组互换验证。"),
        Rule(keywords: ["display", "触控", "屏幕", "touch"],
             title: "显示 / 触控异常",
             suggestion: "跑触控网格扫描与排线阻抗测量，检查屏幕排线座子扣合状态。"),
        Rule(keywords: ["crash", "panic", "重启", "watchdog"],
             title: "系统稳定性 / 看门狗复位",
             suggestion: "比对 panic 日志时间戳与温度、电量曲线，定位复位前最后一个驱动调用。"),
    ]

    static func analyze(logs: [DiagnosticLogEntry], defect: HardwareDefect? = nil) -> FaultAnalysis {
        let errors = logs.filter { $0.level == .error }
        let warnings = logs.filter { $0.level == .warn }

        var findings: [FaultAnalysis.Finding] = []
        for rule in rules {
            let hits = logs.filter { entry in
                let text = (entry.category + " " + entry.message).lowercased()
                return rule.keywords.contains { text.contains($0.lowercased()) }
            }
            guard !hits.isEmpty else { continue }
            let errorHits = hits.filter { $0.level == .error }.count
            let confidence = min(95, 35 + hits.count * 12 + errorHits * 15)
            findings.append(.init(
                title: rule.title,
                confidence: confidence,
                evidence: "命中 \(hits.count) 条相关日志（其中 ERROR \(errorHits) 条）",
                suggestion: rule.suggestion
            ))
        }

        if let defect, findings.isEmpty {
            findings.append(.init(
                title: "\(defect.component)相关异常（待补充日志）",
                confidence: 40,
                evidence: "缺陷单 \(defect.id)：\(defect.symptom)",
                suggestion: "先一键收集诊断日志，再重新分析以提高定位精度。"
            ))
        }

        findings.sort { $0.confidence > $1.confidence }

        let summary: String
        if logs.isEmpty {
            summary = "尚无诊断日志。先收集日志，分析精度会明显更高。"
        } else if findings.isEmpty {
            summary = "共分析 \(logs.count) 条日志，未命中已知故障规则，建议人工复核原始日志。"
        } else {
            summary = "共分析 \(logs.count) 条日志（ERROR \(errors.count) / WARN \(warnings.count)），最可能根因：\(findings[0].title)（置信度 \(findings[0].confidence)%）。"
        }

        return FaultAnalysis(summary: summary, findings: findings, stages: stages,
                             errorCount: errors.count, warningCount: warnings.count)
    }
}
