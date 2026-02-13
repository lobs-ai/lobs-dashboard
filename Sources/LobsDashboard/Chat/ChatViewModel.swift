import Foundation
import Combine

/// ViewModel for chat interface - coordinates ChatService (WebSocket) and APIService (REST)
@MainActor
final class ChatViewModel: ObservableObject {
    
    // MARK: - Published State
    
    @Published var messages: [ChatMessage] = []
    @Published var sessions: [ChatSession] = []
    @Published var currentSessionKey: String = "main"
    @Published var isAgentTyping: Bool = false
    @Published var connectionState: ChatConnectionState = .disconnected
    @Published var errorMessage: String?
    
    // MARK: - Dependencies
    
    private let chatService: ChatService
    private let apiService: APIService
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(chatService: ChatService, apiService: APIService) {
        self.chatService = chatService
        self.apiService = apiService
        
        setupSubscriptions()
    }
    
    // MARK: - Public API
    
    func connect(serverURL: String) {
        chatService.connect(serverURL: serverURL, sessionKey: currentSessionKey)
        loadSessions()
    }
    
    func disconnect() {
        chatService.disconnect()
    }
    
    func sendMessage(_ content: String) {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        chatService.sendMessage(content: content, sessionKey: currentSessionKey)
    }
    
    func createSession(label: String) {
        Task {
            do {
                let newSession = try await apiService.createChatSession(label: label)
                sessions.append(newSession)
                // Switch to the new session
                await switchSession(to: newSession.sessionKey)
            } catch {
                errorMessage = "Failed to create session: \(error.localizedDescription)"
            }
        }
    }
    
    func switchSession(to sessionKey: String) async {
        guard sessionKey != currentSessionKey else { return }
        
        // Clear current messages
        messages = []
        currentSessionKey = sessionKey
        
        // Load history for new session
        await loadHistory()
        
        // Switch WebSocket connection
        chatService.switchSession(to: sessionKey)
    }
    
    func loadSessions() {
        Task {
            do {
                sessions = try await apiService.fetchChatSessions()
            } catch {
                errorMessage = "Failed to load sessions: \(error.localizedDescription)"
            }
        }
    }
    
    func loadHistory() async {
        do {
            let history = try await apiService.fetchChatHistory(
                sessionKey: currentSessionKey,
                limit: 100,
                before: nil
            )
            messages = history.sorted { $0.createdAt < $1.createdAt }
        } catch {
            errorMessage = "Failed to load history: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Private Methods
    
    private func setupSubscriptions() {
        // Connection state
        chatService.$connectionState
            .receive(on: DispatchQueue.main)
            .assign(to: &$connectionState)
        
        // WebSocket events
        chatService.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleWebSocketEvent(event)
            }
            .store(in: &cancellables)
    }
    
    private func handleWebSocketEvent(_ event: ChatWebSocketEvent) {
        switch event {
        case .connected(let sessionKey):
            print("Connected to session: \(sessionKey)")
            // Request session list on connect
            chatService.listSessions()
            
        case .message(let message):
            handleNewMessage(message)
            
        case .typingStart:
            isAgentTyping = true
            
        case .typingStop:
            isAgentTyping = false
            
        case .sessionList(let sessionList):
            sessions = sessionList.sorted { $0.createdAt > $1.createdAt }
            
        case .sessionCreated(let session):
            if !sessions.contains(where: { $0.id == session.id }) {
                sessions.insert(session, at: 0)
            }
            
        case .error(let message):
            errorMessage = message
        }
    }
    
    private func handleNewMessage(_ message: ChatMessage) {
        // Add if not already present
        if !messages.contains(where: { $0.id == message.id }) {
            messages.append(message)
        }
        
        // Stop typing indicator when agent message arrives
        if message.role == .assistant {
            isAgentTyping = false
        }
    }
}
