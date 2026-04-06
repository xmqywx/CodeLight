import SwiftUI

struct SessionDetailView: View {
    @EnvironmentObject var appState: AppState
    let sessionId: String

    private var session: SessionInfo? {
        appState.sessions.first { $0.id == sessionId }
    }

    var body: some View {
        List {
            if let session {
                Section {
                    HStack {
                        Label(String(localized: "status"), systemImage: "circle.fill")
                            .foregroundStyle(session.active ? .green : .gray)
                        Spacer()
                        Text(session.active ? String(localized: "active_status") : String(localized: "inactive_status"))
                            .foregroundStyle(.secondary)
                    }

                    if let path = session.metadata?.path {
                        HStack {
                            Label(String(localized: "path"), systemImage: "folder")
                            Spacer()
                            Text(path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                    }

                    if let model = session.metadata?.model {
                        HStack {
                            Label(String(localized: "model"), systemImage: "cpu")
                            Spacer()
                            Text(model.capitalized)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let mode = session.metadata?.mode {
                        HStack {
                            Label(String(localized: "mode"), systemImage: "shield")
                            Spacer()
                            Text(mode.capitalized)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Label(String(localized: "last_active"), systemImage: "clock")
                        Spacer()
                        Text(session.lastActiveAt, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(String(localized: "session_info"))
                }

                Section {
                    NavigationLink(value: sessionId) {
                        Label(String(localized: "open_chat"), systemImage: "bubble.left.and.bubble.right")
                    }
                }
            } else {
                ContentUnavailableView(String(localized: "session_not_found"), systemImage: "exclamationmark.triangle")
            }
        }
        .navigationTitle(session?.metadata?.title ?? String(localized: "session"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
