import SwiftUI
import CodeLightCrypto

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("tokenExpiryDays") private var tokenExpiryDays: Int = 30

    private let expiryOptions = [7, 14, 30, 90, 180, 365]

    var body: some View {
        List {
            // Connection
            Section {
                if let server = appState.currentServer {
                    HStack {
                        Label(String(localized: "server"), systemImage: "server.rack")
                        Spacer()
                        Text(URL(string: server.url)?.host ?? server.url)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }

                    HStack {
                        Label(String(localized: "status"), systemImage: "circle.fill")
                            .foregroundStyle(appState.isConnected ? .green : .red)
                        Spacer()
                        Text(appState.isConnected ? String(localized: "connected") : String(localized: "disconnected"))
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label(String(localized: "device_name"), systemImage: "iphone")
                        Spacer()
                        Text(server.name)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label(String(localized: "paired"), systemImage: "calendar")
                        Spacer()
                        Text(server.pairedAt, style: .date)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(String(localized: "connection"))
            }

            // Security
            Section {
                Picker(selection: $tokenExpiryDays) {
                    ForEach(expiryOptions, id: \.self) { days in
                        Text(expiryLabel(days)).tag(days)
                    }
                } label: {
                    Label(String(localized: "token_expiry"), systemImage: "clock.badge.checkmark")
                }
            } header: {
                Text(String(localized: "security"))
            } footer: {
                Text(String(localized: "token_expiry_footer"))
            }

            // Actions
            Section {
                Button {
                    Task {
                        if let server = appState.currentServer {
                            await appState.connectTo(server)
                        }
                    }
                } label: {
                    Label(String(localized: "reconnect"), systemImage: "arrow.clockwise")
                }

                Button {
                    appState.disconnect()
                    appState.servers.removeAll()
                    UserDefaults.standard.removeObject(forKey: "servers")
                    dismiss()
                } label: {
                    Label(String(localized: "scan_new_qr_code"), systemImage: "qrcode.viewfinder")
                }

                Button(role: .destructive) {
                    if let server = appState.currentServer {
                        appState.removeServer(server)
                    }
                    dismiss()
                } label: {
                    Label(String(localized: "disconnect_remove"), systemImage: "wifi.slash")
                }
            } header: {
                Text(String(localized: "actions"))
            }

            // Notifications
            Section {
                HStack {
                    Label(String(localized: "push_notifications"), systemImage: "bell.badge")
                    Spacer()
                    Text(PushManager.shared.isRegistered ? String(localized: "enabled") : String(localized: "disabled"))
                        .foregroundStyle(.secondary)
                }

                if !PushManager.shared.isRegistered {
                    Button {
                        Task { await PushManager.shared.requestPermission() }
                    } label: {
                        Text(String(localized: "enable_notifications"))
                    }
                }
            } header: {
                Text(String(localized: "notifications"))
            }

            // About
            Section {
                HStack {
                    Label(String(localized: "version"), systemImage: "info.circle")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                        .foregroundStyle(.secondary)
                }

                Link(destination: URL(string: "https://github.com/xmqywx/CodeLight")!) {
                    Label(String(localized: "github"), systemImage: "link")
                }

                Link(destination: URL(string: "https://github.com/xmqywx/CodeIsland")!) {
                    Label(String(localized: "codeisland_mac_companion"), systemImage: "desktopcomputer")
                }

                Link(destination: URL(string: "https://github.com/xmqywx/CodeLight/blob/main/PRIVACY.md")!) {
                    Label(String(localized: "privacy_policy"), systemImage: "hand.raised")
                }
            } header: {
                Text(String(localized: "about"))
            } footer: {
                Text(String(localized: "about_footer"))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
        }
        .navigationTitle(String(localized: "settings"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func expiryLabel(_ days: Int) -> String {
        switch days {
        case 7: return String(localized: "7_days")
        case 14: return String(localized: "14_days")
        case 30: return String(localized: "30_days")
        case 90: return String(localized: "90_days")
        case 180: return String(localized: "180_days")
        case 365: return String(localized: "1_year")
        default: return "\(days)d"
        }
    }
}
