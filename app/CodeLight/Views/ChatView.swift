import SwiftUI

/// Chat view for a single session — shows messages and allows sending.
struct ChatView: View {
    @EnvironmentObject var appState: AppState
    let sessionId: String

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = true
    @State private var selectedModel = "opus"
    @State private var selectedMode = "auto"

    private let models = ["opus", "sonnet", "haiku"]
    private let modes = ["auto", "default", "plan"]

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        }

                        ForEach(messages) { message in
                            MessageRow(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Model/Mode selector + Input
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Menu {
                        ForEach(models, id: \.self) { model in
                            Button(model.capitalized) {
                                selectedModel = model
                                appState.updateModelMode(sessionId: sessionId, model: model, mode: selectedMode)
                            }
                        }
                    } label: {
                        Label(selectedModel.capitalized, systemImage: "cpu")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                    }

                    Menu {
                        ForEach(modes, id: \.self) { mode in
                            Button(mode.capitalized) {
                                selectedMode = mode
                                appState.updateModelMode(sessionId: sessionId, model: selectedModel, mode: mode)
                            }
                        }
                    } label: {
                        Label(selectedMode.capitalized, systemImage: "shield")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                    }

                    Spacer()
                }

                HStack(spacing: 8) {
                    TextField("Message...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .lineLimit(1...5)

                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(inputText.isEmpty ? .gray : .blue)
                    }
                    .disabled(inputText.isEmpty)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .navigationTitle(sessionTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadMessages()
        }
        .refreshable {
            await loadMessages()
        }
        .onReceive(appState.newMessageSubject) { event in
            guard event.sessionId == sessionId else { return }
            // Avoid duplicates
            if !messages.contains(where: { $0.id == event.message.id }) {
                messages.append(event.message)
            }
        }
    }

    private var sessionTitle: String {
        appState.sessions.first { $0.id == sessionId }?.metadata?.title ?? "Session"
    }

    private func loadMessages() async {
        isLoading = true
        if let socket = appState.socket {
            messages = (try? await socket.fetchMessages(sessionId: sessionId)) ?? []
            print("[ChatView] Loaded \(messages.count) messages")
        }
        isLoading = false
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        appState.sendMessage(text, toSession: sessionId)

        let msg = ChatMessage(id: UUID().uuidString, seq: (messages.last?.seq ?? 0) + 1, content: text, localId: nil)
        messages.append(msg)
    }
}

// MARK: - Message Row

private struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        let parsed = parseContent(message.content)

        HStack(alignment: .top, spacing: 10) {
            // Role icon
            Image(systemName: roleIcon(parsed.type))
                .font(.caption)
                .foregroundStyle(roleColor(parsed.type))
                .frame(width: 16, height: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                // Role label
                Text(roleLabel(parsed.type))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(roleColor(parsed.type))
                    .textCase(.uppercase)

                // Content by type
                switch parsed.type {
                case "tool":
                    toolView(parsed)
                case "thinking":
                    thinkingView(parsed)
                case "interrupted":
                    Label("Interrupted by user", systemImage: "stop.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                default:
                    textContentView(parsed.text)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    // MARK: - Content Views

    private func textContentView(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Split by code blocks
            let parts = splitCodeBlocks(text)
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                if part.isCode {
                    // Code block
                    VStack(alignment: .leading, spacing: 0) {
                        if !part.language.isEmpty {
                            Text(part.language)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.top, 4)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(part.text)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(8)
                        }
                    }
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
                } else if !part.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(part.text)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func toolView(_ parsed: ParsedMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: toolIcon(parsed.toolName ?? ""))
                    .font(.caption)
                Text(parsed.toolName ?? "tool")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                if let status = parsed.toolStatus {
                    Text(status)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor(status).opacity(0.2), in: Capsule())
                        .foregroundStyle(statusColor(status))
                }
            }

            if !parsed.text.isEmpty {
                Text(parsed.text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            // Approval buttons for pending permissions
            if parsed.toolStatus == "pending" || parsed.toolStatus == "waiting" {
                HStack(spacing: 12) {
                    Button {
                        // Send deny via message (CodeIsland will handle)
                        // For now this is a placeholder
                    } label: {
                        Label("Deny", systemImage: "xmark.circle")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.red.opacity(0.2), in: Capsule())
                    }
                    .foregroundStyle(.red)

                    Button {
                        // Send approve via message
                    } label: {
                        Label("Allow", systemImage: "checkmark.circle")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.green.opacity(0.2), in: Capsule())
                    }
                    .foregroundStyle(.green)
                }
                .padding(.top, 4)
            }
        }
        .padding(8)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
    }

    private func thinkingView(_ parsed: ParsedMessage) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "brain")
                .font(.caption)
            Text(parsed.text.isEmpty ? "Thinking..." : parsed.text)
                .font(.caption)
                .italic()
                .lineLimit(2)
        }
        .foregroundStyle(.purple.opacity(0.8))
        .padding(6)
        .background(.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Code Block Parsing

    private struct TextPart {
        let text: String
        let isCode: Bool
        let language: String
    }

    private func splitCodeBlocks(_ text: String) -> [TextPart] {
        var parts: [TextPart] = []
        let pattern = "```(\\w*)\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [TextPart(text: text, isCode: false, language: "")]
        }

        let nsText = text as NSString
        var lastEnd = 0
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            let beforeRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
            if beforeRange.length > 0 {
                parts.append(TextPart(text: nsText.substring(with: beforeRange), isCode: false, language: ""))
            }

            let lang = match.numberOfRanges > 1 ? nsText.substring(with: match.range(at: 1)) : ""
            let code = match.numberOfRanges > 2 ? nsText.substring(with: match.range(at: 2)) : ""
            parts.append(TextPart(text: code, isCode: true, language: lang))

            lastEnd = match.range.location + match.range.length
        }

        if lastEnd < nsText.length {
            parts.append(TextPart(text: nsText.substring(from: lastEnd), isCode: false, language: ""))
        }

        return parts.isEmpty ? [TextPart(text: text, isCode: false, language: "")] : parts
    }

    // MARK: - Parse

    private struct ParsedMessage {
        let type: String
        let text: String
        let toolName: String?
        let toolStatus: String?
    }

    private func parseContent(_ content: String) -> ParsedMessage {
        if let data = content.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = dict["type"] as? String {
            let text = dict["text"] as? String ?? ""
            let toolName = dict["toolName"] as? String
            let toolStatus = dict["toolStatus"] as? String
            return ParsedMessage(type: type, text: text, toolName: toolName, toolStatus: toolStatus)
        }
        return ParsedMessage(type: "user", text: content, toolName: nil, toolStatus: nil)
    }

    // MARK: - Style Helpers

    private func roleColor(_ type: String) -> Color {
        switch type {
        case "user": return .blue
        case "assistant": return .green
        case "thinking": return .purple
        case "tool": return .cyan
        case "interrupted": return .red
        default: return .gray
        }
    }

    private func roleIcon(_ type: String) -> String {
        switch type {
        case "user": return "person.fill"
        case "assistant": return "sparkles"
        case "thinking": return "brain"
        case "tool": return "wrench.and.screwdriver.fill"
        case "interrupted": return "stop.circle.fill"
        default: return "circle"
        }
    }

    private func roleLabel(_ type: String) -> String {
        switch type {
        case "user": return "You"
        case "assistant": return "Claude"
        case "thinking": return "Thinking"
        case "tool": return "Tool"
        case "interrupted": return "Interrupted"
        default: return type
        }
    }

    private func toolIcon(_ name: String) -> String {
        switch name.lowercased() {
        case "bash": return "terminal"
        case "read": return "doc.text"
        case "write": return "doc.badge.plus"
        case "edit": return "pencil"
        case "glob": return "folder.badge.magnifyingglass"
        case "grep": return "magnifyingglass"
        case "agent": return "person.2"
        case "task": return "checklist"
        default: return "gearshape"
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "success", "completed": return .green
        case "error", "failed": return .red
        case "running", "pending": return .orange
        default: return .secondary
        }
    }
}
