import SwiftUI

/// Shows connection status at the top of session list.
/// When connected: shows latency badge. When disconnected: shows reconnecting spinner.
struct ConnectionStatusBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if !appState.isConnected {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(Theme.warning)
                Text(String(localized: "reconnecting"))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button(String(localized: "retry")) {
                    Task { await appState.connect() }
                }
                .font(.caption)
                .foregroundStyle(Theme.brand)
                .buttonStyle(.bordered)
                .tint(Theme.brand)
                .controlSize(.mini)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.warning.opacity(0.10))
            .overlay(
                Rectangle()
                    .fill(Theme.warning.opacity(0.4))
                    .frame(height: 0.5),
                alignment: .bottom
            )
        } else if let ms = appState.latencyMs {
            HStack(spacing: 6) {
                Circle()
                    .fill(latencyColor(ms))
                    .frame(width: 6, height: 6)
                Text(latencyText(ms))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(Theme.bgSurface.opacity(0.6))
            .overlay(
                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 0.5),
                alignment: .bottom
            )
        }
    }

    private func latencyColor(_ ms: Int) -> Color {
        if ms < 100 { return .green }
        if ms < 300 { return .yellow }
        return .red
    }

    private func latencyText(_ ms: Int) -> String {
        if ms < 1000 {
            return "\(ms) ms"
        } else {
            let sec = Double(ms) / 1000.0
            return String(format: "%.1f s", sec)
        }
    }
}
