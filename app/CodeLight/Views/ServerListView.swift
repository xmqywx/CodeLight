import SwiftUI

/// List of paired servers — shown when multiple servers exist.
struct ServerListView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAddServer = false

    var body: some View {
        Group {
            if appState.servers.isEmpty {
                emptyState
            } else {
                serverList
            }
        }
        .navigationTitle(String(localized: "servers"))
        .navigationDestination(for: ServerConfig.self) { server in
            SessionListView(server: server)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddServer = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddServer) {
            NavigationStack {
                PairingView()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))

            VStack(spacing: 8) {
                Text(String(localized: "no_servers"))
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(String(localized: "add_server_instruction"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Server List

    private var serverList: some View {
        List {
            ForEach(appState.servers) { server in
                NavigationLink(value: server) {
                    ServerRow(server: server, isActive: appState.currentServer?.id == server.id, isConnected: appState.currentServer?.id == server.id && appState.isConnected)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        appState.removeServer(server)
                    } label: {
                        Label(String(localized: "delete"), systemImage: "trash")
                    }
                }
            }
        }
    }
}

/// A single server row with connection status indicator.
private struct ServerRow: View {
    let server: ServerConfig
    let isActive: Bool
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Connection status dot
            Circle()
                .fill(isConnected ? .green : .red)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                    .font(.headline)
                Text(URL(string: server.url)?.host ?? server.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }
}
