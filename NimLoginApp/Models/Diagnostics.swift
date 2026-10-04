import Foundation

/// A tracked hardware defect reported by an engineer.
struct HardwareDefect: Identifiable, Codable, Equatable {
    enum Severity: String, CaseIterable, Codable, Identifiable {
        case p0 = "P0"
        case p1 = "P1"
        case p2 = "P2"
        case p3 = "P3"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .p0: return "P0 · 致命"
            case .p1: return "P1 · 严重"
            case .p2: return "P2 · 一般"
            case .p3: return "P3 · 轻微"
            }
        }
    }

    enum Status: String, CaseIterable, Codable, Identifiable {
        case open = "待处理"
        case analyzing = "分析中"
        case located = "已定位"
        case fixed = "已修复"
        var id: String { rawValue }
    }

    var id: String
    var title: String
    var component: String          // e.g. 摄像头 / 屏幕 / 电池 / 主板
    var severity: Severity
    var status: Status
    var deviceModel: String
    var symptom: String
    var createdAt: Date
    var updatedAt: Date

    static func newID(now: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return "HW-\(f.string(from: now))"
    }

    static let samples: [HardwareDefect] = [
        HardwareDefect(id: "HW-20261001-001", title: "后置摄像头对焦异响", component: "摄像头",
                       severity: .p1, status: .analyzing, deviceModel: "iPhone 15 Pro",
                       symptom: "打开相机后持续嗡嗡声，近距离对焦失败。", createdAt: Date(timeIntervalSinceNow: -86_400 * 3), updatedAt: Date(timeIntervalSinceNow: -3_600)),
        HardwareDefect(id: "HW-20261002-002", title: "待机掉电异常", component: "电池",
                       severity: .p2, status: .open, deviceModel: "iPhone 14",
                       symptom: "夜间待机 8 小时掉电 18%，无后台高耗电应用。", createdAt: Date(timeIntervalSinceNow: -86_400 * 2), updatedAt: Date(timeIntervalSinceNow: -86_400)),
        HardwareDefect(id: "HW-20261003-003", title: "屏幕边缘触控失灵", component: "屏幕",
                       severity: .p2, status: .located, deviceModel: "iPhone 15",
                       symptom: "右上角约 5mm 区域触控无响应，重启后短暂恢复。", createdAt: Date(timeIntervalSinceNow: -86_400), updatedAt: Date(timeIntervalSinceNow: -1_800)),
    ]
}

/// One line of a collected diagnostic log bundle.
/// `event`, `source`, and `attributes` are optional so event records written
/// by earlier builds remain decodable.
struct DiagnosticLogEntry: Identifiable, Codable, Equatable {
    enum Level: String, Codable {
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
    }
    var id: UUID = UUID()
    var timestamp: Date
    var level: Level
    var category: String   // thermal / battery / camera / display / system
    var message: String
    var event: String? = nil
    var source: String? = nil
    var attributes: [String: String]? = nil
}

/// A ranked, evidence-backed fault hypothesis. `confidence` is a calibrated
/// heuristic score, not a statistical probability.
struct FaultAnalysis: Equatable {
    struct Finding: Equatable, Identifiable {
        var id: String { title }
        var title: String
        var confidence: Int        // 0...100
        var evidence: String
        var suggestion: String
        var supportingEvidence: [String] = []
        var counterEvidence: [String] = []
        var scoreExplanation: String = ""
        var occurrenceCount: Int = 0
        var uniqueHitCount: Int = 0
    }
    var summary: String
    var findings: [Finding]
    var stages: [String]           // pipeline stages that were run
    var errorCount: Int
    var warningCount: Int
    var analyzedLogCount: Int = 0
    var uniqueLogCount: Int = 0
    var duplicateLogCount: Int = 0
    var dataQuality: String = ""
    var limitations: [String] = []
}
