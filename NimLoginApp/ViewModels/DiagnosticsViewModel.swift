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
    @Published var importMessage: String?
    /// True when launched with SCREENSHOT=diagnostics-flow (used for video recording):
    /// the view auto-collects logs and then auto-runs fault analysis.
    let shouldAutoFlow: Bool

    private let defaults: UserDefaults
    private let eventLog: AppEventLog
    private enum Keys { static let defects = "diagnostics.defects" }

    init(defaults: UserDefaults = .standard, loadSamplesIfEmpty: Bool = true,
         eventLog: AppEventLog = .shared) {
        self.defaults = defaults
        self.eventLog = eventLog
        shouldAutoFlow = ProcessInfo.processInfo.arguments.contains("SCREENSHOT=diagnostics-flow")
        if shouldAutoFlow {
            // Slower, video-friendly pacing.
            selectedDefectID = HardwareDefect.samples.first?.id
        }
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

    /// Collects the evidence this app can legitimately observe:
    /// persisted structured app events plus a live device/app snapshot.
    /// External hardware or server logs enter through `importLogs(_:)`; the
    /// app does not fabricate component probe errors.
    func collectLogs(account: String?) async {
        guard !isCollecting else { return }
        isCollecting = true
        collectionProgress = 0
        logs = []
        analysis = nil
        importMessage = nil

        var entries: [DiagnosticLogEntry] = [
            .init(timestamp: Date(), level: .info, category: "system",
                  message: "开始收集诊断日志 · \(UIDevice.current.model) · \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
                  source: "diagnostic-collector"),
        ]
        entries.append(contentsOf: eventLog.entries().sorted { $0.timestamp < $1.timestamp })
        entries.append(contentsOf: deviceSnapshotEntries(account: account))

        let stepDelay: UInt64 = shouldAutoFlow ? 1_100_000_000 : 260_000_000
        for (i, entry) in entries.enumerated() {
            try? await Task.sleep(nanoseconds: stepDelay)
            logs.append(entry)
            collectionProgress = Double(i + 1) / Double(entries.count)
        }
        isCollecting = false
    }

    private func deviceSnapshotEntries(account: String?) -> [DiagnosticLogEntry] {
        let now = Date()
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true

        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let thermalState = ProcessInfo.processInfo.thermalState
        let thermal: String
        switch thermalState {
        case .nominal: thermal = "nominal"
        case .fair: thermal = "fair"
        case .serious: thermal = "serious"
        case .critical: thermal = "critical"
        @unknown default: thermal = "unknown"
        }
        let thermalIsHigh = thermalState == .serious || thermalState == .critical
        let thermalEntry = DiagnosticLogEntry(
            timestamp: now,
            level: thermalIsHigh ? .warn : .info,
            category: "thermal",
            message: thermalIsHigh
                ? "thermal 状态偏高：\(thermal)（设备即时热状态快照，需结合负载复核）"
                : "thermal 当前状态：\(thermal)（设备即时状态快照，不是单独的故障结论）",
            source: "device-snapshot"
        )

        let batteryText: String
        if device.batteryLevel >= 0 {
            let percent = Int((device.batteryLevel * 100).rounded())
            let state: String
            switch device.batteryState {
            case .charging: state = "charging"
            case .full: state = "full"
            case .unplugged: state = "unplugged"
            case .unknown: state = "unknown"
            @unknown default: state = "unknown"
            }
            batteryText = "battery 电量 \(percent)% · 状态 \(state) · 低电量模式 \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "开启" : "关闭")"
        } else {
            batteryText = "battery 电量不可用（模拟器或系统未提供读数，不作为故障证据）"
        }

        let uptimeHours = ProcessInfo.processInfo.systemUptime / 3600
        var entries: [DiagnosticLogEntry] = [
            .init(timestamp: now, level: .info, category: "system",
                  message: "App 版本 \(shortVersion) (\(build)) · 登录账号 \(account.map { _ in "已登录（账号已脱敏）" } ?? "未登录")",
                  source: "app-bundle"),
            thermalEntry,
            .init(timestamp: now, level: .info, category: "battery",
                  message: batteryText, source: "device-snapshot"),
            .init(timestamp: now, level: .info, category: "system",
                  message: String(format: "system 系统运行时间 %.1f 小时 · 时区 %@", uptimeHours, TimeZone.current.identifier),
                  source: "device-snapshot"),
        ]

        if let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let free = attributes[.systemFreeSize] as? NSNumber {
            let gb = free.doubleValue / 1_000_000_000
            entries.append(.init(timestamp: now, level: .info, category: "system",
                                 message: String(format: "storage 可用空间 %.1f GB（仅用于判断日志/缓存空间不足）", gb),
                                 source: "device-snapshot"))
        }
        return entries
    }

    /// Imports engineer-supplied log text (for example an exported service log
    /// or a text excerpt from a device report) into the current bundle.
    @discardableResult
    func importLogs(_ text: String) -> Int {
        let parsed = DiagnosticLogParser.parse(text)
        guard !parsed.isEmpty else {
            importMessage = "没有解析到日志行，请检查文本格式。"
            return 0
        }
        logs.append(contentsOf: parsed)
        logs.sort { $0.timestamp < $1.timestamp }
        analysis = nil
        importMessage = "已导入 \(parsed.count) 条外部日志，可继续开始故障分析。"
        return parsed.count
    }

    func importLogsFromClipboard() {
        guard let text = UIPasteboard.general.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            importMessage = "剪贴板里没有可用日志文本。"
            return
        }
        _ = importLogs(text)
    }

    /// Video/demo flow: wait a beat, collect logs slowly, pause, then analyse.
    func runAutoFlow(account: String?) async {
        guard shouldAutoFlow, logs.isEmpty, analysis == nil else { return }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        await collectLogs(account: account)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await runAnalysis()
    }

    func clearLogs() {
        logs = []
        analysis = nil
        importMessage = nil
    }

    var logBundleText: String {
        let f = ISO8601DateFormatter()
        return logs.map { entry in
            var line = "[\(entry.level.rawValue)] \(f.string(from: entry.timestamp)) \(entry.category): \(entry.message)"
            var metadata: [String] = []
            if let event = entry.event { metadata.append("event=\(event)") }
            if let source = entry.source { metadata.append("source=\(source)") }
            if let attributes = entry.attributes, !attributes.isEmpty {
                metadata.append(attributes.keys.sorted().map { "\($0)=\(attributes[$0] ?? "")" }.joined(separator: ","))
            }
            if !metadata.isEmpty { line += " {" + metadata.joined(separator: ", ") + "}" }
            return line
        }
        .joined(separator: "\n")
    }

    var incidentReportText: String {
        guard let analysis else { return "尚无故障分析结果。请先收集或导入日志并开始分析。" }
        return FaultIncidentReport.markdown(analysis: analysis, logs: logs, defect: selectedDefect)
    }

    // MARK: - Fault analysis

    func runAnalysis() async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        analysis = nil
        analysisStageIndex = 0
        let stageDelay: UInt64 = shouldAutoFlow ? 1_200_000_000 : 300_000_000
        for i in FaultAnalyzer.stages.indices {
            try? await Task.sleep(nanoseconds: stageDelay)
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
