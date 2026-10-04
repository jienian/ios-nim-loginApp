import Foundation
import UIKit

@MainActor
final class DiagnosticsViewModel: ObservableObject {
    @Published var defects: [HardwareDefect] = []
    @Published var statusFilter: HardwareDefect.Status?
    @Published var logs: [DiagnosticLogEntry] = []
    @Published var isCollecting = false
    @Published var collectionProgress: Double = 0
    @Published var analysis: FaultAnalysis?
    @Published var isAnalyzing = false
    @Published var analysisStageIndex = 0
    @Published var selectedDefectID: String?

    private let defaults: UserDefaults
    private enum Keys { static let defects = "diagnostics.defects" }

    init(defaults: UserDefaults = .standard, loadSamplesIfEmpty: Bool = true) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Keys.defects),
           let saved = try? JSONDecoder().decode([HardwareDefect].self, from: data), !saved.isEmpty {
            defects = saved
        } else if loadSamplesIfEmpty {
            defects = HardwareDefect.samples
        }
    }

    var filteredDefects: [HardwareDefect] {
        guard let statusFilter else { return defects }
        return defects.filter { $0.status == statusFilter }
    }

    var selectedDefect: HardwareDefect? {
        defects.first { $0.id == selectedDefectID }
    }

    // MARK: - Defect tracking

    func addDefect(title: String, component: String, severity: HardwareDefect.Severity,
                   deviceModel: String, symptom: String) {
        let now = Date()
        defects.insert(HardwareDefect(
            id: HardwareDefect.newID(now: now), title: title, component: component,
            severity: severity, status: .open, deviceModel: deviceModel,
            symptom: symptom, createdAt: now, updatedAt: now), at: 0)
        persist()
    }

    func advanceStatus(_ defect: HardwareDefect) {
        guard let idx = defects.firstIndex(of: defect) else { return }
        let all = HardwareDefect.Status.allCases
        if let cur = all.firstIndex(of: defect.status), cur + 1 < all.count {
            defects[idx].status = all[cur + 1]
            defects[idx].updatedAt = Date()
            persist()
        }
    }

    func deleteDefect(at offsets: IndexSet) {
        // offsets refer to filteredDefects; map back by id.
        let ids = offsets.map { filteredDefects[$0].id }
        defects.removeAll { ids.contains($0.id) }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(defects) {
            defaults.set(data, forKey: Keys.defects)
        }
    }

    // MARK: - Diagnostic log collection

    /// Simulates gathering a diagnostic bundle: device info, auth/theme state,
    /// and component health probes, streamed in as log entries.
    func collectLogs(account: String?) async {
        guard !isCollecting else { return }
        isCollecting = true
        collectionProgress = 0
        logs = []

        let device = UIDevice.current
        let entries: [DiagnosticLogEntry] = [
            .init(timestamp: Date(), level: .info, category: "system",
                  message: "开始收集诊断日志 · \(device.model) · \(device.systemName) \(device.systemVersion)"),
            .init(timestamp: Date(), level: .info, category: "system",
                  message: "App 版本 1.0 (1) · 登录账号 \(account ?? "未登录")"),
            .init(timestamp: Date(), level: .warn, category: "thermal",
                  message: "thermal 状态偏高：nominal→fair，SoC 温度曲线待复核"),
            .init(timestamp: Date(), level: .error, category: "camera",
                  message: "camera OIS 对焦马达响应超时（120ms），近距离对焦失败"),
            .init(timestamp: Date(), level: .warn, category: "battery",
                  message: "battery 待机掉电速率 2.3%/h，高于基线 0.8%/h"),
            .init(timestamp: Date(), level: .info, category: "display",
                  message: "display 触控网格扫描完成，右上区域采样点待复测"),
            .init(timestamp: Date(), level: .info, category: "system",
                  message: "诊断日志收集完成，共生成日志包 1 份"),
        ]

        for (i, entry) in entries.enumerated() {
            try? await Task.sleep(nanoseconds: 260_000_000)
            logs.append(entry)
            collectionProgress = Double(i + 1) / Double(entries.count)
        }
        isCollecting = false
    }

    func clearLogs() {
        logs = []
        analysis = nil
    }

    var logBundleText: String {
        let f = ISO8601DateFormatter()
        return logs.map { "[\($0.level.rawValue)] \(f.string(from: $0.timestamp)) \($0.category): \($0.message)" }
            .joined(separator: "\n")
    }

    // MARK: - Fault analysis

    func runAnalysis() async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        analysis = nil
        analysisStageIndex = 0
        for i in FaultAnalyzer.stages.indices {
            try? await Task.sleep(nanoseconds: 300_000_000)
            analysisStageIndex = i + 1
        }
        analysis = FaultAnalyzer.analyze(logs: logs, defect: selectedDefect)
        isAnalyzing = false
        // Analysis moves the selected defect forward automatically.
        if let defect = selectedDefect, defect.status == .open {
            advanceStatus(defect)
        }
    }
}
