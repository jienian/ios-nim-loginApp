import XCTest
@testable import NimLoginApp

final class FaultAnalyzerTests: XCTestCase {
    private func entry(_ level: DiagnosticLogEntry.Level,
                       _ category: String,
                       _ message: String,
                       event: String? = nil,
                       attributes: [String: String]? = nil) -> DiagnosticLogEntry {
        DiagnosticLogEntry(timestamp: Date(), level: level, category: category, message: message,
                           event: event, source: "test", attributes: attributes)
    }

    func testEmptyLogs() {
        let r = FaultAnalyzer.analyze(logs: [])
        XCTAssertTrue(r.findings.isEmpty)
        XCTAssertEqual(r.errorCount, 0)
        XCTAssertEqual(r.stages.count, 6)
    }

    func testCameraRuleRanked() {
        let logs = [
            entry(.error, "camera", "camera OIS timeout"),
            entry(.warn, "camera", "camera focus retry"),
            entry(.info, "system", "ok"),
        ]
        let r = FaultAnalyzer.analyze(logs: logs)
        XCTAssertEqual(r.findings.first?.title, "摄像头模组异常")
        XCTAssertFalse(r.findings.contains { $0.title == "网络 / 服务端异常" })
        XCTAssertEqual(r.errorCount, 1)
        XCTAssertEqual(r.warningCount, 1)
        XCTAssertGreaterThan(r.findings.first?.confidence ?? 0, 50)
    }

    func testDefectFallback() {
        let d = HardwareDefect.samples[0]
        let r = FaultAnalyzer.analyze(logs: [], defect: d)
        XCTAssertEqual(r.findings.count, 1)
        XCTAssertTrue(r.summary.contains("先收集") || r.summary.contains("尚无"))
    }

    func testLoginFailureIsCaptured() {
        // A real login-flow failure, as recorded by AppEventLog.
        let logs = [
            entry(.info, "auth", "发起登录请求 · 账号 de***@nim.app", event: "auth.attempt"),
            entry(.error, "auth", "登录失败：账号或密码不正确 · 账号 de***@nim.app",
                  event: "auth.failure", attributes: ["error_code": "invalid_credentials"]),
            entry(.info, "auth", "登录成功 · 账号 de***@nim.app · 耗时 1203ms", event: "auth.success"),
        ]
        let r = FaultAnalyzer.analyze(logs: logs)
        XCTAssertEqual(r.findings.first?.title, "登录 / 认证异常")
        XCTAssertTrue(r.summary.contains("登录 / 认证异常"))
        XCTAssertTrue(r.findings.first?.supportingEvidence.contains { $0.contains("账号或密码不正确") } == true)
        XCTAssertTrue(r.findings.first?.counterEvidence.contains { $0.contains("登录成功") } == true)
    }

    func testBenignComponentStatusDoesNotCreateFinding() {
        let logs = [
            entry(.info, "battery", "battery 电量 80%，健康度良好"),
            entry(.info, "camera", "camera initialization completed successfully"),
            entry(.info, "display", "display 触控网格扫描完成，右上区域采样点待复测"),
        ]
        let r = FaultAnalyzer.analyze(logs: logs)
        XCTAssertTrue(r.findings.isEmpty, "Healthy/completed status lines must not become faults: \(r.findings)")
    }

    func testDuplicateFailuresAreFoldedButIncreaseScore() {
        let one = FaultAnalyzer.analyze(logs: [
            entry(.error, "auth", "登录失败：账号或密码不正确", event: "auth.failure"),
        ])
        let repeated = FaultAnalyzer.analyze(logs: [
            entry(.error, "auth", "登录失败：账号或密码不正确", event: "auth.failure"),
            entry(.error, "auth", "登录失败：账号或密码不正确", event: "auth.failure"),
            entry(.error, "auth", "登录失败：账号或密码不正确", event: "auth.failure"),
        ])
        let finding = repeated.findings.first
        XCTAssertEqual(finding?.uniqueHitCount, 1)
        XCTAssertEqual(finding?.occurrenceCount, 3)
        XCTAssertTrue(finding?.evidence.contains("共出现 3 次") == true)
        XCTAssertGreaterThan(finding?.confidence ?? 0, one.findings.first?.confidence ?? 0)
    }

    func testMixedFaultsKeepIndependentHypotheses() {
        let logs = [
            entry(.error, "auth", "登录失败：账号或密码不正确", event: "auth.failure"),
            entry(.info, "auth", "登录成功", event: "auth.success"),
            entry(.error, "camera", "camera OIS 对焦马达响应超时（120ms），近距离对焦失败"),
            entry(.warn, "camera", "camera focus retry failed"),
        ]
        let r = FaultAnalyzer.analyze(logs: logs)
        XCTAssertTrue(r.findings.contains { $0.title == "登录 / 认证异常" })
        XCTAssertTrue(r.findings.contains { $0.title == "摄像头模组异常" })
    }

    func testNetworkFailureFromImportedServiceLog() {
        let logs = [
            entry(.info, "network", "POST /login started"),
            entry(.error, "network", "POST /login timeout after 3000ms, status 503"),
        ]
        let r = FaultAnalyzer.analyze(logs: logs)
        XCTAssertEqual(r.findings.first?.title, "网络 / 服务端异常")
        XCTAssertFalse(r.findings.contains { $0.title == "登录 / 认证异常" })
    }

    func testParserSupportsExportedAndPlainTextFormats() {
        let text = """
        [ERROR] 2026-10-05T00:01:02Z auth: 登录失败：账号或密码不正确
        2026-10-05 00:02:03 WARN [network] request timeout after 3000ms
        INFO system: app launched successfully
        """
        let logs = DiagnosticLogParser.parse(text)
        XCTAssertEqual(logs.count, 3)
        XCTAssertEqual(logs[0].level, .error)
        XCTAssertEqual(logs[0].category, "auth")
        XCTAssertTrue(logs[0].message.contains("账号或密码不正确"))
        XCTAssertEqual(logs[1].level, .warn)
        XCTAssertEqual(logs[1].category, "network")
        XCTAssertTrue(logs[1].message.contains("timeout"))
        XCTAssertEqual(logs[2].category, "system")
    }

    func testParserRestoresExportedMetadata() {
        let line = "[ERROR] 2026-10-05T00:01:02Z auth: 登录失败：账号或密码不正确 {event=auth.failure, source=app-event, attempt_id=123, error_code=invalid_credentials}"
        let logs = DiagnosticLogParser.parse(line)
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.event, "auth.failure")
        XCTAssertEqual(logs.first?.source, "app-event")
        XCTAssertEqual(logs.first?.attributes?["error_code"], "invalid_credentials")
        XCTAssertFalse(logs.first?.message.contains("{") == true)
    }

    func testAnalyzeRawText() {
        let r = FaultAnalyzer.analyze(text: "[ERROR] 2026-10-05T00:01:02Z auth: 登录失败：账号或密码不正确")
        XCTAssertEqual(r.findings.first?.title, "登录 / 认证异常")
    }

    func testIncidentReportQuotesEvidenceAndStatesLimits() {
        let logs = [
            entry(.error, "auth", "登录失败：账号或密码不正确", event: "auth.failure"),
        ]
        let analysis = FaultAnalyzer.analyze(logs: logs)
        let report = FaultIncidentReport.markdown(analysis: analysis, logs: logs)
        XCTAssertTrue(report.contains("登录失败：账号或密码不正确"))
        XCTAssertTrue(report.contains("不是统计概率"))
        XCTAssertTrue(report.contains("数据范围与限制"))
    }

    func testAppEventLogRoundTrip() {
        let defaults = UserDefaults(suiteName: "eventlog-test-\(UUID().uuidString)")!
        let log = AppEventLog(defaults: defaults)
        XCTAssertTrue(log.entries().isEmpty)
        log.record(level: .error, event: "auth.failure", category: "auth",
                   message: "登录失败：账号或密码不正确",
                   attributes: ["error_code": "invalid_credentials"])
        log.record(level: .info, event: "auth.success", category: "auth", message: "登录成功")
        XCTAssertEqual(log.entries().count, 2)
        XCTAssertEqual(log.entries().first?.level, .error)
        XCTAssertEqual(log.entries().first?.event, "auth.failure")
        XCTAssertEqual(log.entries().first?.attributes?["error_code"], "invalid_credentials")
        log.clear()
        XCTAssertTrue(log.entries().isEmpty)
    }
}

@MainActor
final class DiagnosticsViewModelTests: XCTestCase {
    func testAddAndAdvanceDefect() {
        let defaults = UserDefaults(suiteName: "diag-test-\(UUID().uuidString)")!
        let vm = DiagnosticsViewModel(defaults: defaults, loadSamplesIfEmpty: false)
        XCTAssertTrue(vm.defects.isEmpty)
        vm.addDefect(title: "测试缺陷", component: "电池", severity: .p1, deviceModel: "iPhone 15", symptom: "掉电")
        XCTAssertEqual(vm.defects.count, 1)
        XCTAssertEqual(vm.defects.first?.status, .open)
        vm.advanceStatus(vm.defects[0])
        XCTAssertEqual(vm.defects.first?.status, .analyzing)
    }

    func testImportLogsParsesAndAppends() {
        let defaults = UserDefaults(suiteName: "diag-import-test-\(UUID().uuidString)")!
        let vm = DiagnosticsViewModel(defaults: defaults, loadSamplesIfEmpty: false)
        let count = vm.importLogs("""
        [ERROR] 2026-10-05T00:01:02Z auth: 登录失败：账号或密码不正确
        2026-10-05 00:02:03 WARN [network] request timeout after 3000ms
        """)
        XCTAssertEqual(count, 2)
        XCTAssertEqual(vm.logs.count, 2)
        XCTAssertTrue(vm.importMessage?.contains("已导入 2 条") == true)
    }

    func testCollectLogsUsesRealEventsWithoutFabricatedProbes() async {
        let defaults = UserDefaults(suiteName: "diag-collect-test-\(UUID().uuidString)")!
        let eventLog = AppEventLog(defaults: defaults)
        eventLog.record(level: .error, event: "auth.failure", category: "auth",
                        message: "登录失败：账号或密码不正确",
                        attributes: ["error_code": "invalid_credentials"])
        let vm = DiagnosticsViewModel(defaults: defaults, loadSamplesIfEmpty: false, eventLog: eventLog)

        await vm.collectLogs(account: "demo@nim.app")

        XCTAssertTrue(vm.logs.contains { $0.event == "auth.failure" })
        XCTAssertTrue(vm.logs.contains { $0.source == "device-snapshot" })
        XCTAssertFalse(vm.logs.contains { $0.message.contains("OIS 对焦马达响应超时") })
    }
}
