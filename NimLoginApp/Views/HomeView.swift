import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: AuthViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)

                Text("登录成功")
                    .font(.title.bold())

                if let session = viewModel.session {
                    VStack(spacing: 6) {
                        Text(session.user.nickname)
                            .font(.headline)
                        Text(session.user.account)
                            .foregroundStyle(.secondary)
                        Text("登录时间：\(session.loginDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button(role: .destructive) {
                    viewModel.logout()
                } label: {
                    Text("退出登录")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.red.opacity(0.4), lineWidth: 1)
                        )
                }
                .padding(.horizontal, 24)
            }
            .padding(24)
            .navigationTitle("主页")
        }
    }
}
