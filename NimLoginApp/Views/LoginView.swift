import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var showForgotPassword = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ThemePicker()
                header
                form
                if case .failure(let message) = viewModel.status {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                PrimaryButton(
                    title: viewModel.mode == .login ? "登录" : "注册并登录",
                    isLoading: viewModel.isLoading,
                    isEnabled: viewModel.canSubmit
                ) {
                    Task { await viewModel.submit() }
                }
                optionsRow
                faceIDButton
                switchModeButton
            }
            .padding(24)
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.mode == .login ? "欢迎回来" : "创建账号")
                .font(.largeTitle.bold())
            Text("演示账号：demo@nim.app / 123456")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 24)
    }

    private var form: some View {
        VStack(spacing: 16) {
            InputField(
                title: "账号",
                placeholder: "邮箱或手机号",
                text: $viewModel.account,
                error: viewModel.accountError,
                keyboardType: .emailAddress
            )

            InputField(
                title: "密码",
                placeholder: "至少 6 位",
                text: $viewModel.password,
                error: viewModel.passwordError,
                isSecure: true
            )

            if viewModel.mode == .register {
                InputField(
                    title: "确认密码",
                    placeholder: "再次输入密码",
                    text: $viewModel.confirmPassword,
                    error: viewModel.confirmPasswordError,
                    isSecure: true
                )
                Text("密码强度：\(viewModel.passwordStrength.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var optionsRow: some View {
        HStack {
            Toggle("记住我", isOn: $viewModel.rememberMe)
                .font(.subheadline)
                .fixedSize()
            Spacer()
            if viewModel.mode == .login {
                Button("忘记密码？") { showForgotPassword = true }
                    .font(.subheadline)
            }
        }
    }

    private var faceIDButton: some View {
        Button {
            // Placeholder for LocalAuthentication: wire LAContext here for a real build.
        } label: {
            Label("Face ID 登录", systemImage: "faceid")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var switchModeButton: some View {
        Button {
            viewModel.switchMode()
        } label: {
            Text(viewModel.mode == .login ? "没有账号？立即注册" : "已有账号？去登录")
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var error: String?
    @State private var sent = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                InputField(
                    title: "邮箱",
                    placeholder: "请输入注册邮箱",
                    text: $email,
                    error: error,
                    keyboardType: .emailAddress
                )
                if sent {
                    Text("重置链接已发送，请查看邮箱（演示提示）")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
                PrimaryButton(title: "发送重置链接", isLoading: false, isEnabled: !email.isEmpty) {
                    error = Validators.isValidEmail(email) ? nil : "邮箱格式不正确"
                    sent = error == nil
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle("忘记密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
