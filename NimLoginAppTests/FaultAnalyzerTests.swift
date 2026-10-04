import XCTest
@testable import NimLoginApp

final class FaultAnalyzerTests: XCTestCase {
    private func entry(_ level: DiagnosticLogEntry.Level, _ category: String, _ msg: String) -> DiagnosticLogEntry {
        DiagnosticLogEntry(timestamp: Date(), level: level, category: category, message: msg)
    }

    func testEmptyLogs() {
        let r = FaultAnalyzer.analyze(logs: [])
        XCTAssertTrue(r.findings.isEmpty)
        XCTAssertEqual(r.errorCount, 0)
        XCTAssertEqual(r.stages.count, 5)
    }

    func testCameraRuleRanked() {
        let logs = [
            entry(.error, "camera", "camera OIS timeout"),
            entry(.warn, "camera", "camera focus retry"),
            entry(.info, "system", "ok"),
        ]
        let r = FaultAnalyzer.analyze(logs: logs)
        XCTAssertEqual(r.findings.first?.title, "摄像头模组异常")
        XCTAssertEqual(r.errorCount, 1)
        XCTAssertEqual(r.warningCount, 1)
        XCTAssertGreaterThan(r.findings.first?.confidence ?? 0, 50)
    }

    func testDefectFallback() {
        let d = HardwareDefect.samples[0]
        let r = FaultAnalyzer.analyze(logs: [], defect: d)
        XCTAssertEqual(r.findings.count, 1)
        XCTAssertTrue(r.summary.contains("先收集日志") || r.summary.contains("尚无"))
    }

    func testLoginFailureIsCaptured() {
        // A real login-flow failure, as recorded by AppEventLog.
        let logs = [
            entry(.info, "auth", "发起登录请求 · 账号 demo@nim.app"),
            entry(.error, "auth", "登录失败：账号或密码不正确 · 账号 demo@nim.app"),
            entry(.info, "auth", "登录成功 · 账号 demo@nim.app · 耗时 1203ms"),
            entry(.error, "camera", "camera OIS 对焦马达响应超时（120ms）"),
        ]
        let r = FaultAnalyzer.analyze(logs: logs)
        XCTAssertEqual(r.findings.first?.title, "登录 / 认证异常")
        XCTAssertTrue(r.summary.contains("登录 / 认证异常"))
    }

    func testAppEventLogRoundTrip() {
        let defaults = UserDefaults(suiteName: "eventlog-test-\(UUID().uuidString)")!
        let log = AppEventLog(defaults: defaults)
        XCTAssertTrue(log.entries().isEmpty)
        log.record(level: .error, category: "auth", message: "登录失败：账号或密码不正确")
        log.record(level: .info, category: "auth", message: "登录成功")
        XCTAssertEqual(log.entries().count, 2)
        XCTAssertEqual(log.entries().first?.level, .error)
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
}
