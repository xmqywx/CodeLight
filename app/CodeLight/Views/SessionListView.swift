import SwiftUI

/// Sessions belonging to a single paired Mac. Shown after the user picks a Mac
/// from `LinkedMacsListView`. Filters `appState.sessions` by `ownerDeviceId`.
struct MacSessionListView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var prefs = SessionPreferences.shared
    let mac: LinkedMac
    @State private var isLoading = true
    @State private var showLaunchSheet = false
    @State private var renameTarget: SessionInfo? = nil
    @State private var renameDraft = ""
    @State private var selectedTab: Tab = .active

    enum Tab: String, CaseIterable, Identifiable {
        case active, recent, archived
        var id: String { rawValue }
        var labelKey: String {
            switch self {
            case .active:   return "tab_active"
            case .recent:   return "tab_recent"
            case .archived: return "tab_archived"
            }
        }
    }

    /// Sessions belonging to this Mac, sorted by id (cuid → createdAt order),
    /// stable across phase updates. The tabs filter further from this base.
    private var allMacSessions: [SessionInfo] {
        appState.sessions
            .filter { $0.ownerDeviceId == mac.deviceId }
            .sorted { $0.id > $1.id }
    }

    private var activeSessions: [SessionInfo] {
        allMacSessions.filter { $0.active && !prefs.isArchived($0.id) }
    }

    private var recentSessions: [SessionInfo] {
        allMacSessions.filter { !$0.active && !prefs.isArchived($0.id) }
    }

    private var archivedSessions: [SessionInfo] {
        allMacSessions.filter { prefs.isArchived($0.id) }
    }

    private var sessionsForTab: [SessionInfo] {
        switch selectedTab {
        case .active:   return activeSessions
        case .recent:   return recentSessions
        case .archived: return archivedSessions
        }
    }

    private func count(for tab: Tab) -> Int {
        switch tab {
        case .active:   return activeSessions.count
        case .recent:   return recentSessions.count
        case .archived: return archivedSessions.count
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ConnectionStatusBar()

            tabBar

            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(String(localized: "loading_sessions"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if sessionsForTab.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
        }
        .navigationTitle(mac.name)
        .navigationDestination(for: String.self) { sessionId in
            ChatView(sessionId: sessionId)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    Button {
                        Haptics.light()
                        Task { await refreshSessions() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    Button {
                        Haptics.medium()
                        showLaunchSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
        }
        .sheet(isPresented: $showLaunchSheet, onDismiss: {
            Task { await appState.refreshSessions() }
        }) {
            NavigationStack {
                LaunchSessionSheet(mac: mac)
            }
        }
        .sheet(item: $renameTarget) { session in
            RenameSessionSheet(session: session, draft: $renameDraft)
        }
        .task {
            Haptics.light()
            // Make sure we're connected to this Mac's server before fetching sessions.
            if mac.serverUrl != appState.currentServerUrl || !appState.isConnected {
                await appState.switchServerIfNeeded(to: mac.serverUrl)
            }
            if let socket = appState.socket {
                do {
                    appState.sessions = try await socket.fetchSessions()
                } catch {
                    print("[MacSessionList] Fetch error: \(error)")
                }
            }
            isLoading = false
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))

            VStack(spacing: 8) {
                Text(String(localized: "no_sessions_yet"))
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(String(localized: "tap_plus_to_launch"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                Haptics.medium()
                showLaunchSheet = true
            } label: {
                Label(String(localized: "launch_session"), systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Theme.brand, in: Capsule())
                    .foregroundStyle(Theme.onBrand)
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding()
    }

    // MARK: - Tab Bar

    /// Three-tab segmented selector at the top of the list. Custom render
    /// instead of `Picker(.segmented)` so we can show per-tab counts and
    /// match the dark theme palette.
    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases) { tab in
                tabPill(tab)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func tabPill(_ tab: Tab) -> some View {
        let isSelected = selectedTab == tab
        let count = count(for: tab)
        Button {
            Haptics.light()
            withAnimation(.easeInOut(duration: 0.18)) { selectedTab = tab }
        } label: {
            HStack(spacing: 6) {
                Text(String(localized: String.LocalizationValue(tab.labelKey)))
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            (isSelected ? Theme.onBrand.opacity(0.2) : Theme.brandSoft),
                            in: Capsule()
                        )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                isSelected ? Theme.brand : Color.clear,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .foregroundStyle(isSelected ? Theme.onBrand : Theme.textSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isSelected ? Color.clear : Theme.divider, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Session List

    private var sessionList: some View {
        List {
            ForEach(sessionsForTab) { session in
                sessionRow(session)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.bgPrimary)
        .refreshable {
            await refreshSessions()
        }
    }

    /// One row with NavigationLink + swipe action + context menu rename.
    /// Swipe action shows "Unarchive" in the archived tab and "Archive"
    /// elsewhere — same gesture, opposite direction depending on context.
    @ViewBuilder
    private func sessionRow(_ session: SessionInfo) -> some View {
        let isArchived = prefs.isArchived(session.id)
        NavigationLink(value: session.id) {
            SessionRow(session: session)
                .environmentObject(prefs)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if isArchived {
                Button {
                    Haptics.medium()
                    prefs.unarchive(session.id)
                } label: {
                    Label(String(localized: "unarchive"), systemImage: "tray.and.arrow.up")
                }
                .tint(Theme.brand)
            } else {
                Button {
                    Haptics.medium()
                    prefs.archive(session.id)
                } label: {
                    Label(String(localized: "archive"), systemImage: "archivebox")
                }
                .tint(.gray)
            }

            Button {
                renameDraft = prefs.customName(for: session.id)
                    ?? session.metadata?.title
                    ?? session.metadata?.displayProjectName
                    ?? ""
                renameTarget = session
            } label: {
                Label(String(localized: "rename"), systemImage: "pencil")
            }
            .tint(Theme.brand)
        }
        .contextMenu {
            Button {
                renameDraft = prefs.customName(for: session.id)
                    ?? session.metadata?.title
                    ?? session.metadata?.displayProjectName
                    ?? ""
                renameTarget = session
            } label: {
                Label(String(localized: "rename"), systemImage: "pencil")
            }
            if isArchived {
                Button {
                    Haptics.medium()
                    prefs.unarchive(session.id)
                } label: {
                    Label(String(localized: "unarchive"), systemImage: "tray.and.arrow.up")
                }
            } else {
                Button {
                    Haptics.medium()
                    prefs.archive(session.id)
                } label: {
                    Label(String(localized: "archive"), systemImage: "archivebox")
                }
            }
        }
    }

    private func refreshSessions() async {
        if let socket = appState.socket {
            appState.sessions = (try? await socket.fetchSessions()) ?? []
        }
    }
}

/// Shorten a path by replacing home directory with ~
private func shortenPath(_ path: String) -> String {
    var p = path
    if let home = ProcessInfo.processInfo.environment["HOME"], p.hasPrefix(home) {
        p = "~" + p.dropFirst(home.count)
    }
    return p
}

private struct SessionRow: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var prefs: SessionPreferences
    let session: SessionInfo

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if session.active {
                    Circle()
                        .fill(Theme.brand.opacity(0.25))
                        .frame(width: 18, height: 18)
                }
                Circle()
                    .fill(session.active ? Theme.brand : Theme.textTertiary)
                    .frame(width: 8, height: 8)
            }
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                // Line 1: custom name → project name → tag
                Text(prefs.customName(for: session.id)
                     ?? session.metadata?.displayProjectName
                     ?? session.tag)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                // Line 2: latest message preview (real content) instead of the
                // auto-title which was often just the project name again.
                // Falls back to the smart title only if we haven't seen any
                // content for this session in this app launch.
                if let preview = appState.lastMessagePreviewBySession[session.id], !preview.isEmpty {
                    Text(preview)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                } else if let title = session.metadata?.title, !title.isEmpty,
                          title != session.metadata?.displayProjectName {
                    Text(title)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                if let path = session.metadata?.path {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 8))
                        Text(shortenPath(path))
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundStyle(Theme.textTertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let model = session.metadata?.model {
                    Text(model.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(0.5)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Theme.brandSoft, in: Capsule())
                        .overlay(Capsule().stroke(Theme.borderActive, lineWidth: 0.5))
                        .foregroundStyle(Theme.brand)
                }

                if let lastTime = appState.lastMessageTimeBySession[session.id] {
                    Text(lastTime, style: .relative)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(Theme.bgPrimary)
        .listRowSeparatorTint(Theme.divider)
    }
}

// MARK: - Rename Sheet

private struct RenameSessionSheet: View {
    let session: SessionInfo
    @Binding var draft: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var prefs = SessionPreferences.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "session_name_placeholder"), text: $draft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text(String(localized: "rename_session"))
                } footer: {
                    Text(String(localized: "rename_footer"))
                        .font(.caption)
                }

                if prefs.customName(for: session.id) != nil {
                    Section {
                        Button(role: .destructive) {
                            prefs.setCustomName(nil, for: session.id)
                            dismiss()
                        } label: {
                            Label(String(localized: "reset_to_default"), systemImage: "arrow.uturn.backward")
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "rename"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "save")) {
                        prefs.setCustomName(draft, for: session.id)
                        dismiss()
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Archived Sessions View

struct ArchivedSessionsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var prefs = SessionPreferences.shared
    let mac: LinkedMac

    private var archived: [SessionInfo] {
        appState.sessions
            .filter { $0.ownerDeviceId == mac.deviceId }
            .filter { prefs.isArchived($0.id) }
            .sorted { $0.id > $1.id }
    }

    var body: some View {
        Group {
            if archived.isEmpty {
                ContentUnavailableView(
                    String(localized: "no_archived_sessions"),
                    systemImage: "archivebox",
                    description: Text(String(localized: "archive_hint"))
                )
            } else {
                List {
                    ForEach(archived) { session in
                        NavigationLink(value: session.id) {
                            SessionRow(session: session)
                                .environmentObject(prefs)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                Haptics.medium()
                                prefs.unarchive(session.id)
                            } label: {
                                Label(String(localized: "unarchive"), systemImage: "tray.and.arrow.up")
                            }
                            .tint(Theme.brand)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.bgPrimary)
            }
        }
        .navigationTitle(String(localized: "archived"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
