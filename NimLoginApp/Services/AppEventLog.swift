import Foundation

/// Persistent in-app event log. Real user-flow events (login attempts,
/// failures, successes, logouts) are recorded here so the diagnostics
/// centre can collect and analyse what actually happened in the app —
/// not just simulated hardware probes.
struct AppEventLog {
    static let shared = AppEventLog()

    private let defaults: UserDefaults
    private let key = "app.eventLog"
    private let capacity = 100

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func record(level: DiagnosticLogEntry.Level, category: String, message: String) {
        record(level: level, event: nil, category: category, message: message,
               source: "app-event", attributes: nil)
    }

    func record(level: DiagnosticLogEntry.Level,
                event: String?,
                category: String,
                message: String,
                source: String = "app-event",
                attributes: [String: String]? = nil) {
        var all = entries()
        all.append(DiagnosticLogEntry(
            timestamp: Date(), level: level, category: category, message: message,
            event: event, source: source, attributes: attributes
        ))
        if all.count > capacity {
            all.removeFirst(all.count - capacity)
        }
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: key)
        }
    }

    func entries() -> [DiagnosticLogEntry] {
        guard let data = defaults.data(forKey: key),
              let saved = try? JSONDecoder().decode([DiagnosticLogEntry].self, from: data) else { return [] }
        return saved
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
