import SwiftUI

struct ContentView: View {
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var themeManager = ThemeManager()

    var body: some View {
        Group {
            if authViewModel.session != nil {
                HomeView(viewModel: authViewModel)
            } else {
                LoginView(viewModel: authViewModel)
            }
        }
        .environmentObject(themeManager)
        .preferredColorScheme(themeManager.theme.colorScheme)
    }
}
