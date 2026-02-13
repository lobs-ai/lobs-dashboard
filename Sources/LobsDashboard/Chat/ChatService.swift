import Foundation
import Combine

/// WebSocket client for real-time chat communication with lobs-server
final class ChatService: NSObject {
    
    // MARK: - Published State
    
    @Published private(set) var connectionState: ChatConnectionState = .disconnected
    @Published private(set) var lastError: String?
    
    // MARK: - Event Publishers
    
    let eventPublisher = PassthroughSubject<ChatWebSocketEvent, Never>()
    
    // MARK: - Private State
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var serverURL: String = ""
    private var currentSessionKey: String = "main"
    private var reconnectAttempts = 0
    private var maxReconnectDelay: TimeInterval = 30
    private var heartbeatTimer: Timer?
    private var reconnectTimer: Timer?
    private var isIntentionalDisconnect = false
    
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    // MARK: - Public API
    
    func connect(serverURL: String, sessionKey: String) {
        guard connectionState != .connected(sessionKey: sessionKey) else { return }
        
        self.serverURL = serverURL
        self.currentSessionKey = sessionKey
        self.isIntentionalDisconnect = false
        
        performConnect()
    }
    
    func disconnect() {
        isIntentionalDisconnect = true
        cleanupConnection()
        connectionState = .disconnected
    }
    
    func sendMessage(content: String, sessionKey: String? = nil) {
        let event = ChatOutgoingEvent.sendMessage(
            content: content,
            sessionKey: sessionKey ?? currentSessionKey
        )
        send(event: event)
    }
    
    func createSession(label: String, sessionKey: String? = nil) {
        let event = ChatOutgoingEvent.createSession(
            label: label,
            sessionKey: sessionKey
        )
        send(event: event)
    }
    
    func listSessions() {
        let event = ChatOutgoingEvent.listSessions
        send(event: event)
    }
    
    func switchSession(to sessionKey: String) {
        currentSessionKey = sessionKey
        let event = ChatOutgoingEvent.switchSession(sessionKey: sessionKey)
        send(event: event)
    }
    
    // MARK: - Private Methods
    
    private func performConnect() {
        cleanupConnection()
        
        // Build WebSocket URL
        var wsURLString = serverURL
            .replacingOccurrences(of: "http://", with: "ws://")
            .replacingOccurrences(of: "https://", with: "wss://")
        
        wsURLString += "/api/chat/ws?session_key=\(currentSessionKey)"
        
        guard let url = URL(string: wsURLString) else {
            connectionState = .error("Invalid WebSocket URL")
            return
        }
        
        connectionState = reconnectAttempts > 0 ? .reconnecting : .connecting
        
        webSocketTask = urlSession.webSocketTask(with: url)
        webSocketTask?.resume()
        
        // Start receiving messages
        receiveMessage()
        
        // Start heartbeat
        startHeartbeat()
    }
    
    private func cleanupConnection() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                
                // Continue receiving
                self.receiveMessage()
                
            case .failure(let error):
                print("WebSocket receive error: \(error)")
                self.handleDisconnect(error: error)
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let str = try container.decode(String.self)
                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = isoFormatter.date(from: str) { return date }
                isoFormatter.formatOptions = [.withInternetDateTime]
                if let date = isoFormatter.date(from: str) { return date }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(str)")
            }
            
            let event = try decoder.decode(ChatWebSocketEvent.self, from: data)
            
            DispatchQueue.main.async {
                // Update connection state on connected event
                if case .connected(let sessionKey) = event {
                    self.connectionState = .connected(sessionKey: sessionKey)
                    self.reconnectAttempts = 0
                }
                
                // Publish event
                self.eventPublisher.send(event)
            }
        } catch {
            print("Failed to decode WebSocket message: \(error)")
            print("Raw message: \(text)")
        }
    }
    
    private func send(event: ChatOutgoingEvent) {
        guard let data = event.jsonData,
              let jsonString = String(data: data, encoding: .utf8) else {
            print("Failed to encode outgoing event")
            return
        }
        
        let message = URLSessionWebSocketTask.Message.string(jsonString)
        webSocketTask?.send(message) { error in
            if let error = error {
                print("WebSocket send error: \(error)")
            }
        }
    }
    
    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.webSocketTask?.sendPing { error in
                if let error = error {
                    print("Heartbeat ping failed: \(error)")
                }
            }
        }
    }
    
    private func handleDisconnect(error: Error) {
        DispatchQueue.main.async {
            if !self.isIntentionalDisconnect {
                self.connectionState = .reconnecting
                self.scheduleReconnect()
            } else {
                self.connectionState = .disconnected
            }
        }
    }
    
    private func scheduleReconnect() {
        guard !isIntentionalDisconnect else { return }
        
        // Exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s (max)
        let delay = min(pow(2.0, Double(reconnectAttempts)), maxReconnectDelay)
        reconnectAttempts += 1
        
        print("Scheduling reconnect in \(delay)s (attempt \(reconnectAttempts))")
        
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            print("Attempting reconnect...")
            self.performConnect()
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension ChatService: URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        print("WebSocket connected")
    }
    
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        print("WebSocket closed with code: \(closeCode)")
        handleDisconnect(error: NSError(domain: "WebSocket", code: closeCode.rawValue))
    }
}
