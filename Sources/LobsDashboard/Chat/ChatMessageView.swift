import SwiftUI

/// Individual chat message bubble with role-based styling
struct ChatMessageView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 50)
            }
            
            if message.role != .user {
                roleIcon
                    .frame(width: 24, height: 24)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .system {
                    // System messages: centered and muted
                    Text(message.content)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(12)
                } else {
                    // User and assistant messages: bubbles
                    VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                        Text(message.content)
                            .font(.body)
                            .foregroundColor(textColor)
                            .textSelection(.enabled)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(bubbleColor)
                            .cornerRadius(16)
                        
                        Text(relativeTimestamp)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                    }
                }
            }
            
            if message.role == .user {
                roleIcon
                    .frame(width: 24, height: 24)
            } else if message.role != .system {
                Spacer(minLength: 50)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
    
    // MARK: - Computed Properties
    
    private var roleIcon: some View {
        Group {
            switch message.role {
            case .user:
                Image(systemName: "person.circle.fill")
                    .foregroundColor(.blue)
            case .assistant:
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.purple)
            case .system:
                EmptyView()
            }
        }
        .font(.title3)
    }
    
    private var bubbleColor: Color {
        switch message.role {
        case .user:
            return Color.blue.opacity(0.2)
        case .assistant:
            return Color.gray.opacity(0.15)
        case .system:
            return Color.clear
        }
    }
    
    private var textColor: Color {
        switch message.role {
        case .user:
            return .primary
        case .assistant:
            return .primary
        case .system:
            return .secondary
        }
    }
    
    private var relativeTimestamp: String {
        let now = Date()
        let interval = now.timeIntervalSince(message.createdAt)
        
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}
