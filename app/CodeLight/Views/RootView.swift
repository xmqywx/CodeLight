import SwiftUI

/// Root navigation — shows pairing if no servers, server list if multiple, session list if one.
struct RootView: View {
    @EnvironmentObject var appState: AppState
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            if appState.servers.isEmpty {
                PairingView()
            } else if appState.servers.count > 1 {
                ServerListView()
            } else if appState.isConnected {
                SessionListView(server: appState.currentServer ?? appState.servers[0])
            } else {
                connectingView
                    .task {
                        if let server = appState.currentServer ?? appState.servers.first {
                            await appState.connectTo(server)
                            if !appState.isConnected {
                                errorMessage = String(localized: "could_not_connect")
                                showError = true
                            }
                        }
                    }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var connectingView: some View {
        VStack(spacing: 24) {
            Spacer()

            if showError {
                // Error state
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                VStack(spacing: 8) {
                    Text(String(localized: "connection_failed"))
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    Button {
                        showError = false
                        Task {
                            if let server = appState.currentServer ?? appState.servers.first {
                                await appState.connectTo(server)
                                if !appState.isConnected {
                                    showError = true
                                }
                            }
                        }
                    } label: {
                        Label(String(localized: "try_again"), systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .destructive) {
                        appState.servers.removeAll()
                        UserDefaults.standard.removeObject(forKey: "servers")
                        appState.disconnect()
                    } label: {
                        Text(String(localized: "reset_connection"))
                    }
                }
                .padding(.horizontal, 40)
            } else {
                // Loading state
                ProgressView()
                    .scaleEffect(1.2)

                Text(String(localized: "connecting_to_server"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
    }
}
