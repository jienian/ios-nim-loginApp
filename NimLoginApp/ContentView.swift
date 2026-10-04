import SwiftUI

struct ContentView: View {
    @StateObject private var authViewModel = AuthViewModel()

    var body: some View {
        Group {
            if authViewModel.session != nil {
                HomeView(viewModel: authViewModel)
            } else {
                LoginView(viewModel: authViewModel)
            }
        }
        .preferredColorScheme(.light)
    }
}
