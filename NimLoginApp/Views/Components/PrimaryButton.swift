import SwiftUI

struct PrimaryButton: View {
    let title: String
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                }
                Text(isLoading ? "请稍候…" : title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(isEnabled ? Color.accentColor : Color.secondary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .disabled(!isEnabled || isLoading)
    }
}
