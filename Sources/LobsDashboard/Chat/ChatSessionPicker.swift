import SwiftUI

/// Horizontal session tabs with create button
struct ChatSessionPicker: View {
    let sessions: [ChatSession]
    let currentSessionKey: String
    let onSelectSession: (String) -> Void
    let onCreateSession: () -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sessions) { session in
                    SessionTab(
                        session: session,
                        isSelected: session.sessionKey == currentSessionKey,
                        onTap: { onSelectSession(session.sessionKey) }
                    )
                }
                
                // Create new session button
                Button(action: onCreateSession) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption.weight(.semibold))
                        Text("New")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Session Tab

private struct SessionTab: View {
    let session: ChatSession
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text(session.displayLabel)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                
                // Unread indicator (placeholder - would need to track unread count)
                // if session.hasUnread {
                //     Circle()
                //         .fill(Color.blue)
                //         .frame(width: 6, height: 6)
                // }
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color.gray.opacity(0.15))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Create Session Alert

struct CreateSessionAlert: View {
    @Binding var isPresented: Bool
    let onCreate: (String) -> Void
    
    @State private var sessionLabel: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Create New Session")
                .font(.headline)
            
            TextField("Session label (optional)", text: $sessionLabel)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    createSession()
                }
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                    sessionLabel = ""
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Create") {
                    createSession()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            isFocused = true
        }
    }
    
    private func createSession() {
        let label = sessionLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        onCreate(label.isEmpty ? "New Session" : label)
        isPresented = false
        sessionLabel = ""
    }
}
