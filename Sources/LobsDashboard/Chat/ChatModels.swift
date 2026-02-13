import Foundation

// MARK: - Chat Session

struct ChatSession: Identifiable, Codable, Equatable {
    let id: String
    let sessionKey: String
    var label: String?
    let createdAt: Date
    var isActive: Bool
    var lastMessageAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case sessionKey = "session_key"
        case label
        case createdAt = "created_at"
        case isActive = "is_active"
        case lastMessageAt = "last_message_at"
    }
    
    var displayLabel: String {
        label ?? sessionKey
    }
}

// MARK: - Chat Message

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: String
    let role: MessageRole
    let content: String
    let createdAt: Date
    let messageMetadata: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case createdAt = "created_at"
        case messageMetadata = "message_metadata"
    }
    
    enum MessageRole: String, Codable {
        case user
        case assistant
        case system
    }
    
    var isFromUser: Bool {
        role == .user
    }
}

// MARK: - WebSocket Events

enum ChatWebSocketEvent: Codable {
    case connected(sessionKey: String)
    case message(ChatMessage)
    case typingStart
    case typingStop
    case sessionList([ChatSession])
    case sessionCreated(ChatSession)
    case error(String)
    
    enum EventType: String, Codable {
        case connected
        case message
        case typingStart = "typing_start"
        case typingStop = "typing_stop"
        case sessionList = "session_list"
        case sessionCreated = "session_created"
        case error
    }
    
    enum CodingKeys: String, CodingKey {
        case type
        case sessionKey = "session_key"
        case data
        case message
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "connected":
            let sessionKey = try container.decode(String.self, forKey: .sessionKey)
            self = .connected(sessionKey: sessionKey)
            
        case "message":
            let messageData = try container.decode(ChatMessage.self, forKey: .data)
            self = .message(messageData)
            
        case "typing_start":
            self = .typingStart
            
        case "typing_stop":
            self = .typingStop
            
        case "session_list":
            let sessions = try container.decode([ChatSession].self, forKey: .data)
            self = .sessionList(sessions)
            
        case "session_created":
            let session = try container.decode(ChatSession.self, forKey: .data)
            self = .sessionCreated(session)
            
        case "error":
            let errorMessage = try container.decode(String.self, forKey: .message)
            self = .error(errorMessage)
            
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown event type: \(type)"
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .connected(let sessionKey):
            try container.encode("connected", forKey: .type)
            try container.encode(sessionKey, forKey: .sessionKey)
            
        case .message(let message):
            try container.encode("message", forKey: .type)
            try container.encode(message, forKey: .data)
            
        case .typingStart:
            try container.encode("typing_start", forKey: .type)
            
        case .typingStop:
            try container.encode("typing_stop", forKey: .type)
            
        case .sessionList(let sessions):
            try container.encode("session_list", forKey: .type)
            try container.encode(sessions, forKey: .data)
            
        case .sessionCreated(let session):
            try container.encode("session_created", forKey: .type)
            try container.encode(session, forKey: .data)
            
        case .error(let message):
            try container.encode("error", forKey: .type)
            try container.encode(message, forKey: .message)
        }
    }
}

// MARK: - Outgoing Events

enum ChatOutgoingEvent: Encodable {
    case sendMessage(content: String, sessionKey: String?)
    case createSession(label: String, sessionKey: String?)
    case listSessions
    case switchSession(sessionKey: String)
    
    var jsonData: Data? {
        try? JSONEncoder().encode(self)
    }
    
    enum CodingKeys: String, CodingKey {
        case type
        case content
        case sessionKey = "session_key"
        case label
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .sendMessage(let content, let sessionKey):
            try container.encode("send_message", forKey: .type)
            try container.encode(content, forKey: .content)
            if let sessionKey = sessionKey {
                try container.encode(sessionKey, forKey: .sessionKey)
            }
            
        case .createSession(let label, let sessionKey):
            try container.encode("create_session", forKey: .type)
            try container.encode(label, forKey: .label)
            if let sessionKey = sessionKey {
                try container.encode(sessionKey, forKey: .sessionKey)
            }
            
        case .listSessions:
            try container.encode("list_sessions", forKey: .type)
            
        case .switchSession(let sessionKey):
            try container.encode("switch_session", forKey: .type)
            try container.encode(sessionKey, forKey: .sessionKey)
        }
    }
}

// MARK: - Connection State

enum ChatConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(sessionKey: String)
    case reconnecting
    case error(String)
    
    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
    
    var statusText: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected(let sessionKey):
            return "Connected to \(sessionKey)"
        case .reconnecting:
            return "Reconnecting..."
        case .error(let message):
            return "Error: \(message)"
        }
    }
}
