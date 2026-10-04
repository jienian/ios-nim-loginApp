import SwiftUI

/// Engineer diagnostics centre: hardware defect tracking, one-tap diagnostic
/// log collection, and a guided fault-analysis pipeline.
struct DiagnosticsView: View {
    @StateObject private var vm = DiagnosticsViewModel()
    @State private var showAddDefect = false
    var account: String? = nil

    var body: some View {
        ScrollViewReader { proxy in
            List {
                defectSection
                logSection
                    .id("logs")
                analysisSection
                    .id("analysis")
            }
            .onChange(of: vm.logs.count) { _, _ in
                withAnimation { proxy.scrollTo("logs", anchor: .top) }
            }
            .onChange(of: vm.isAnalyzing) { _, analyzing in
                if analyzing { withAnimation { proxy.scrollTo("analysis", anchor: .top) } }
            }
            .onChange(of: vm.analysis?.summary) { _, summary in
                if summary != nil {
                    withAnimation { proxy.scrollTo("analysis-summary", anchor: .top) }
                }
            }
        }
        .navigationTitle("工程师诊断中心")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddDefect = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("新建缺陷")
            }
        }
        .sheet(isPresented: $showAddDefect) { AddDefectView(vm: vm) }
        .task {
            await vm.runAutoFlow(account: account)
        }
    }

    // MARK: Defects

    private var defectSection: some View {
        Section {
            Picker("状态筛选", selection: $vm.statusFilter) {
                Text("全部").tag(HardwareDefect.Status?.none)
                ForEach(HardwareDefect.Status.allCases) { s in
                    Text(s.rawValue).tag(HardwareDefect.Status?.some(s))
                }
            }
            .pickerStyle(.segmented)

            if vm.filteredDefects.isEmpty {
                Text("暂无缺陷记录，点右上角 + 新建").foregroundStyle(.secondary)
            }
            ForEach(vm.filteredDefects) { defect in
                Button {
                    vm.selectedDefectID = defect.id
                    vm.advanceStatus(defect)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(defect.title).font(.headline).foregroundStyle(.primary)
                            Spacer()
                            Text(defect.severity.rawValue)
                                .font(.caption.bold())
                                .foregroundStyle(defect.severity == .p0 || defect.severity == .p1 ? .red : .orange)
                        }
                        Text("\(defect.id) · \(defect.component) · \(defect.deviceModel)")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(defect.symptom).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        HStack(spacing: 6) {
                            Text(defect.status.rawValue)
                                .font(.caption.bold())
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.15))
                                .clipShape(Capsule())
                            if vm.selectedDefectID == defect.id {
                                Text("已选为分析对象").font(.caption).foregroundStyle(.green)
                            } else {
                                Text("点按选为分析对象并推进状态").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { vm.deleteDefect(at: $0) }
        } header: {
            Text("硬件缺陷追踪（\(vm.filteredDefects.count)）")
        }
    }

    // MARK: Logs

    private var logSection: some View {
        Section {
            if vm.isCollecting {
                ProgressView(value: vm.collectionProgress) { Text("正在收集诊断日志…") }
            }
            Button {
                Task { await vm.collectLogs(account: account) }
            } label: {
                Label(vm.isCollecting ? "收集…" : "一键收集诊断日志", systemImage: "doc.text.magnifyingglass")
            }
            .disabled(vm.isCollecting)

            if !vm.logs.isEmpty {
                ForEach(vm.logs) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("[\(entry.level.rawValue)] \(entry.category)")
                            .font(.caption.bold())
                            .foregroundStyle(entry.level == .error ? .red : (entry.level == .warn ? .orange : .secondary))
                        Text(entry.message).font(.caption)
                    }
                }
                ShareLink(item: vm.logBundleText) {
                    Label("导出日志包", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) { vm.clearLogs() } label: {
                    Label("清空日志", systemImage: "trash")
                }
            }
        } header: {
            Text("诊断日志收集（\(vm.logs.count) 条）")
        }
    }

    // MARK: Analysis

    private var analysisSection: some View {
        Section {
            if vm.isAnalyzing {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(FaultAnalyzer.stages.enumerated()), id: \.offset) { i, stage in
                        HStack {
                            Image(systemName: i < vm.analysisStageIndex ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(i < vm.analysisStageIndex ? .green : .secondary)
                            Text(stage).font(.subheadline)
                        }
                    }
                }
            }
            Button {
                Task { await vm.runAnalysis() }
            } label: {
                Label("开始故障分析", systemImage: "waveform.path.ecg")
            }
            .disabled(vm.isAnalyzing || (vm.logs.isEmpty && vm.selectedDefect == nil))

            if let a = vm.analysis {
                Text(a.summary).font(.subheadline)
                    .id("analysis-summary")
                ForEach(a.findings) { f in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(f.title).font(.headline)
                            Spacer()
                            Text("置信度 \(f.confidence)%").font(.caption.bold()).foregroundStyle(.blue)
                        }
                        ProgressView(value: Double(f.confidence), total: 100)
                        Text(f.evidence).font(.caption).foregroundStyle(.secondary)
                        Text("建议：\(f.suggestion)").font(.caption)
                    }
                }
            }
        } header: {
            Text("故障分析")
        } footer: {
            Text("流程：收集 → 清洗去重 → 按部件分类 → 根因排序 → 生成建议。选中缺陷后再分析，结论会关联到缺陷单。")
        }
    }
}

struct AddDefectView: View {
    @ObservedObject var vm: DiagnosticsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var component = "摄像头"
    @State private var severity: HardwareDefect.Severity = .p2
    @State private var deviceModel = "iPhone 15 Pro"
    @State private var symptom = ""

    private let components = ["摄像头", "屏幕", "电池", "主板", "扬声器", "按键", "其他"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("缺陷标题", text: $title)
                Picker("部件", selection: $component) {
                    ForEach(components, id: \.self) { Text($0) }
                }
                Picker("严重程度", selection: $severity) {
                    ForEach(HardwareDefect.Severity.allCases) { Text($0.title).tag($0) }
                }
                TextField("设备型号", text: $deviceModel)
                TextField("故障现象", text: $symptom, axis: .vertical).lineLimit(3...6)
            }
            .navigationTitle("新建缺陷")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        vm.addDefect(title: title, component: component, severity: severity,
                                     deviceModel: deviceModel, symptom: symptom)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
