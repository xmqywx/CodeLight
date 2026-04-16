import SwiftUI

/// A single slash command / skill / MCP server item from the server.
struct CapabilityItem: Decodable, Identifiable, Hashable {
    let name: String
    let description: String
    let source: String

    var id: String { "\(source):\(name)" }
}

/// One choice in a slash command's sub-menu (e.g. `/model opus`).
struct SubOption: Identifiable, Hashable {
    let value: String   // text to append after the command
    let label: String   // display name
    let hint: String    // short description

    var id: String { value }
}

/// Second-level picker pushed when the user taps a slash command that takes
/// a fixed enum argument.
struct SubOptionPicker: View {
    let title: String
    let description: String
    let options: [SubOption]
    let onPick: (String) -> Void

    var body: some View {
        List {
            if !description.isEmpty {
                Section {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(options) { option in
                    Button {
                        onPick(option.value)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.label)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                if !option.hint.isEmpty {
                                    Text(option.hint)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(option.value)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The full snapshot uploaded by MioIsland.
struct CapabilitySnapshot: Decodable {
    let builtinCommands: [CapabilityItem]
    let userCommands: [CapabilityItem]
    let pluginCommands: [CapabilityItem]
    let projectCommands: [CapabilityItem]
    let userSkills: [CapabilityItem]
    let pluginSkills: [CapabilityItem]
    let projectSkills: [CapabilityItem]
    let mcpServers: [CapabilityItem]
    let projectPath: String?
    let scannedAt: TimeInterval
}

/// Bottom sheet that lets the user browse and pick a slash command, skill, or
/// MCP server to insert into the compose bar.
struct CapabilitySheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Called with the text to insert into the compose field.
    let onSelect: (String) -> Void

    @State private var snapshot: CapabilitySnapshot?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    ContentUnavailableView(
                        "Capabilities Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if let snapshot {
                    listView(snapshot)
                } else {
                    ContentUnavailableView("No Data", systemImage: "questionmark.circle")
                }
            }
            .navigationTitle("Commands & Skills")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    // MARK: - List

    @ViewBuilder
    private func listView(_ snap: CapabilitySnapshot) -> some View {
        List {
            sectionIfNotEmpty("Built-in Commands", items: filter(snap.builtinCommands))
            sectionIfNotEmpty("Your Commands", items: filter(snap.userCommands))
            sectionIfNotEmpty("Plugin Commands", items: filter(snap.pluginCommands))
            sectionIfNotEmpty("Project Commands", items: filter(snap.projectCommands))
            sectionIfNotEmpty("Your Skills", items: filter(snap.userSkills))
            sectionIfNotEmpty("Plugin Skills", items: filter(snap.pluginSkills))
            sectionIfNotEmpty("Project Skills", items: filter(snap.projectSkills))
            sectionIfNotEmpty("MCP Servers", items: filter(snap.mcpServers))
        }
    }

    @ViewBuilder
    private func sectionIfNotEmpty(_ title: String, items: [CapabilityItem]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { item in
                    if let subOptions = subOptions(for: item) {
                        // Slash commands with known sub-options (e.g. /model) push a
                        // second-level picker instead of inserting raw text.
                        NavigationLink {
                            SubOptionPicker(
                                title: item.name,
                                description: item.description,
                                options: subOptions
                            ) { choice in
                                onSelect("\(item.name) \(choice) ")
                                dismiss()
                            }
                        } label: {
                            commandLabel(item)
                        }
                    } else {
                        Button {
                            onSelect(insertText(for: item))
                            dismiss()
                        } label: {
                            commandLabel(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func commandLabel(_ item: CapabilityItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.name)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.primary)
            if !item.description.isEmpty {
                Text(item.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    /// Returns a list of sub-options for slash commands that take a fixed
    /// argument (like `/model opus`). nil → no sub-menu, behave normally.
    private func subOptions(for item: CapabilityItem) -> [SubOption]? {
        switch item.name {
        case "/model":
            return [
                SubOption(value: "opus",     label: "Opus",      hint: "Most capable"),
                SubOption(value: "opusplan", label: "Opus Plan", hint: "Opus with plan mode"),
                SubOption(value: "sonnet",   label: "Sonnet",    hint: "Balanced"),
                SubOption(value: "haiku",    label: "Haiku",     hint: "Fastest"),
                SubOption(value: "default",  label: "Default",   hint: "Reset to project default"),
            ]
        case "/output-style":
            return [
                SubOption(value: "default",     label: "Default",     hint: "Standard responses"),
                SubOption(value: "explanatory", label: "Explanatory", hint: "Verbose with reasoning"),
                SubOption(value: "learning",    label: "Learning",    hint: "Teaching-oriented"),
            ]
        default:
            return nil
        }
    }

    private func filter(_ items: [CapabilityItem]) -> [CapabilityItem] {
        guard !searchText.isEmpty else { return items }
        let q = searchText.lowercased()
        return items.filter {
            $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }

    /// Build the text to insert into the compose bar based on the item type.
    private func insertText(for item: CapabilityItem) -> String {
        if item.name.hasPrefix("/") {
            return "\(item.name) "
        }
        if item.source == "mcp" || item.source == "mcp:project" {
            return "@\(item.name) "
        }
        // Skill — reference by name so user can invoke naturally
        return "use \(item.name) to "
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        errorMessage = nil
        guard let socket = appState.socket else {
            errorMessage = "Not connected"
            isLoading = false
            return
        }
        do {
            let snap = try await socket.fetchCapabilities()
            await MainActor.run {
                self.snapshot = snap
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}
