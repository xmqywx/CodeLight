import Combine
import Foundation
import CodeLightCrypto
import CodeLightProtocol

/// Global app state — manages server connections and sessions.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var servers: [ServerConfig] = []
    @Published var currentServer: ServerConfig?
    @Published var sessions: [SessionInfo] = []
    @Published var isConnected = false

    /// New message events — ChatView subscribes to this
    let newMessageSubject = PassthroughSubject<(sessionId: String, message: ChatMessage), Never>()

    private let keyManager = KeyManager(serviceName: "com.codelight.app")
    private(set) var socket: SocketClient?

    private init() {
        loadServers()
    }

    // MARK: - Server Management

    func addServer(_ config: ServerConfig) {
        servers.append(config)
        saveServers()
    }

    func removeServer(_ config: ServerConfig) {
        servers.removeAll { $0.id == config.id }
        if currentServer?.id == config.id {
            currentServer = nil
            disconnect()
        }
        saveServers()
    }

    func connectTo(_ server: ServerConfig) async {
        disconnect()
        currentServer = server

        let client = SocketClient(serverUrl: server.url, keyManager: keyManager)
        self.socket = client

        do {
            try await client.authenticate()
            client.connect()
            client.onSessionsUpdate = { [weak self] sessions in
                self?.sessions = sessions
            }
            client.onNewMessage = { [weak self] sessionId, msg in
                let chatMsg = ChatMessage(id: msg.id, seq: msg.seq, content: msg.content, localId: msg.localId)
                self?.newMessageSubject.send((sessionId: sessionId, message: chatMsg))

                // Trigger Dynamic Island based on message type
                self?.updateLiveActivity(sessionId: sessionId, content: msg.content, serverName: server.name)
            }
            client.onEphemeral = { [weak self] sessionId, active in
                if !active {
                    LiveActivityManager.shared.end(sessionId: sessionId)
                }
            }
            isConnected = true
            print("[AppState] Connected to \(server.url)")

            // Auto-fetch sessions (Live Activities are started when user opens a chat)
            do {
                let fetched = try await client.fetchSessions()
                self.sessions = fetched
            } catch {
                print("[AppState] Failed to fetch sessions: \(error)")
            }
        } catch {
            isConnected = false
            print("[AppState] Connection failed: \(error)")
        }
    }

    func disconnect() {
        socket?.disconnect()
        socket = nil
        sessions = []
        isConnected = false
    }

    // MARK: - Messaging

    func sendMessage(_ text: String, toSession sessionId: String) {
        guard let socket else { return }
        let localId = UUID().uuidString
        socket.sendMessage(sessionId: sessionId, content: text, localId: localId)
    }

    /// Send a model/mode change via session metadata update
    func updateModelMode(sessionId: String, model: String, mode: String) {
        guard let socket else { return }
        let metadata: [String: Any] = ["model": model, "mode": mode]
        if let data = try? JSONSerialization.data(withJSONObject: metadata),
           let str = String(data: data, encoding: .utf8) {
            socket.sendMessage(sessionId: sessionId, content: "{\"type\":\"config\",\"model\":\"\(model)\",\"mode\":\"\(mode)\"}", localId: "config-\(UUID().uuidString)")
        }
    }

    // MARK: - Dynamic Island

    /// Start Live Activity for the MOST RECENTLY ACTIVE session only (single-mode)
    func startLiveActivitiesForActiveSessions() {
        let serverName = currentServer?.name ?? "Server"
        guard let socket = self.socket else { return }

        // Pick only the most recently active session (sessions are already sorted by updatedAt desc)
        guard let session = sessions.first(where: { $0.active }) else { return }

        Task { [weak self] in
            let (phase, toolName, userMsg, assistantMsg) = await self?.fetchLatestPhaseState(sessionId: session.id, socket: socket) ?? ("idle", nil, nil, nil)

            await MainActor.run {
                LiveActivityManager.shared.update(
                    sessionId: session.id,
                    phase: phase,
                    toolName: toolName,
                    projectName: session.metadata?.title ?? "Session",
                    serverName: serverName,
                    lastUserMessage: userMsg,
                    lastAssistantSummary: assistantMsg
                )
                if let u = userMsg { self?.lastUserMessageBySession[session.id] = u }
                if let a = assistantMsg { self?.lastAssistantMessageBySession[session.id] = a }
            }
        }
    }

    /// Fetch latest messages for a session and extract the most recent phase state.
    private func fetchLatestPhaseState(sessionId: String, socket: SocketClient) async -> (phase: String, toolName: String?, userMsg: String?, assistantMsg: String?) {
        do {
            let result = try await socket.fetchMessages(sessionId: sessionId)
            var phase = "idle"
            var toolName: String? = nil
            var userMsg: String? = nil
            var assistantMsg: String? = nil

            // Iterate most recent first
            for msg in result.messages.reversed() {
                guard let data = msg.content.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = dict["type"] as? String else { continue }

                // Latest phase message wins
                if type == "phase", phase == "idle", toolName == nil {
                    phase = dict["phase"] as? String ?? "idle"
                    toolName = dict["toolName"] as? String
                }
                // Latest user message
                if userMsg == nil, type == "user", let text = dict["text"] as? String {
                    userMsg = String(text.prefix(120))
                }
                // Latest assistant message
                if assistantMsg == nil, type == "assistant", let text = dict["text"] as? String, !text.isEmpty {
                    assistantMsg = String(text.prefix(200))
                }

                if userMsg != nil && assistantMsg != nil && phase != "idle" { break }
            }

            return (phase, toolName, userMsg, assistantMsg)
        } catch {
            return ("idle", nil, nil, nil)
        }
    }

    private var idleTimers: [String: Timer] = [:]

    /// Track last user/assistant message per session for Dynamic Island display
    private var lastUserMessageBySession: [String: String] = [:]
    private var lastAssistantMessageBySession: [String: String] = [:]

    private func updateLiveActivity(sessionId: String, content: String, serverName: String) {
        guard let data = content.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = dict["type"] as? String else { return }

        let projectName = sessions.first(where: { $0.id == sessionId })?.metadata?.title ?? "Session"

        // Track user/assistant messages (truncated to fit ActivityKit 4KB limit)
        if type == "user", let text = dict["text"] as? String {
            lastUserMessageBySession[sessionId] = String(text.prefix(120))
        } else if type == "assistant", let text = dict["text"] as? String, !text.isEmpty {
            lastAssistantMessageBySession[sessionId] = String(text.prefix(200))
        }

        // Phase messages from CodeIsland — authoritative session state
        if type == "phase" {
            let phase = dict["phase"] as? String ?? "idle"
            let toolName = dict["toolName"] as? String

            // Phase messages from CodeIsland include latest user/assistant messages
            if let userMsg = dict["lastUserMessage"] as? String {
                lastUserMessageBySession[sessionId] = userMsg
            }
            if let assistantMsg = dict["lastAssistantSummary"] as? String {
                lastAssistantMessageBySession[sessionId] = assistantMsg
            }

            LiveActivityManager.shared.update(
                sessionId: sessionId,
                phase: phase,
                toolName: toolName,
                projectName: projectName,
                serverName: serverName,
                lastUserMessage: lastUserMessageBySession[sessionId],
                lastAssistantSummary: lastAssistantMessageBySession[sessionId]
            )
        } else if type == "user" || type == "assistant" {
            // Update existing activity's messages without changing phase (passing nil)
            LiveActivityManager.shared.update(
                sessionId: sessionId,
                phase: nil,
                toolName: nil,
                projectName: projectName,
                serverName: serverName,
                lastUserMessage: lastUserMessageBySession[sessionId],
                lastAssistantSummary: lastAssistantMessageBySession[sessionId]
            )
        }
    }

    private func scheduleIdle(sessionId: String, projectName: String, serverName: String, after seconds: Double) {
        idleTimers[sessionId]?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                LiveActivityManager.shared.update(
                    sessionId: sessionId,
                    phase: "idle",
                    toolName: nil,
                    projectName: projectName,
                    serverName: serverName
                )
                self?.idleTimers[sessionId] = nil
            }
        }
        idleTimers[sessionId] = timer
    }

    // MARK: - Persistence

    private func loadServers() {
        guard let data = UserDefaults.standard.data(forKey: "servers"),
              let saved = try? JSONDecoder().decode([ServerConfig].self, from: data) else { return }
        servers = saved
    }

    private func saveServers() {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        UserDefaults.standard.set(data, forKey: "servers")
    }
}

/// Server configuration — persisted.
struct ServerConfig: Codable, Identifiable, Hashable {
    let id: String
    let url: String
    let name: String
    let pairedAt: Date

    init(url: String, name: String) {
        self.id = UUID().uuidString
        self.url = url
        self.name = name
        self.pairedAt = Date()
    }
}

/// Session info from server.
struct SessionInfo: Identifiable {
    let id: String
    let tag: String
    let metadata: SessionMetadata?
    let active: Bool
    let lastActiveAt: Date
}
