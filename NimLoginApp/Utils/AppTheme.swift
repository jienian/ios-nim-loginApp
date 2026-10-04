import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Keys.theme)
        }
    }

    private enum Keys {
        static let theme = "app.theme"
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: Keys.theme)
        var initial = AppTheme(rawValue: saved ?? "") ?? .system

        // Screenshot job: SCREENSHOT=login-dark / home-dark renders dark, others light.
        if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("SCREENSHOT=") }) {
            initial = arg.hasSuffix("-dark") ? .dark : .light
        }
        theme = initial
    }
}

/// Segmented theme picker shown on login and home screens.
struct ThemePicker: View {
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("外观")
                .font(.subheadline.weight(.medium))
            Picker("外观", selection: $themeManager.theme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}
