import SwiftUI

/// Main chat interface container
struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    
    @State private var inputText: String = ""
    @State private var showCreateSession: Bool = false
    @State private var shouldScrollToBottom: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Session picker
            ChatSessionPicker(
                sessions: viewModel.sessions,
                currentSessionKey: viewModel.currentSessionKey,
                onSelectSession: { sessionKey in
                    Task {
                        await viewModel.switchSession(to: sessionKey)
                    }
                },
                onCreateSession: {
                    showCreateSession = true
                }
            )
            
            Divider()
            
            // Connection status bar
            ConnectionStatusBar(
                connectionState: viewModel.connectionState
            )
            
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.messages) { message in
                            ChatMessageView(message: message)
                                .id(message.id)
                        }
                        
                        // Typing indicator
                        if viewModel.isAgentTyping {
                            TypingIndicator()
                                .id("typing-indicator")
                        }
                        
                        // Invisible anchor for auto-scroll
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: viewModel.messages.count) { _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: viewModel.isAgentTyping) { _ in
                    scrollToBottom(proxy: proxy)
                }
                .onAppear {
                    scrollToBottom(proxy: proxy)
                }
            }
            
            Divider()
            
            // Input bar
            ChatInputView(
                text: $inputText,
                isConnected: viewModel.connectionState.isConnected,
                onSend: {
                    viewModel.sendMessage(inputText)
                    inputText = ""
                }
            )
        }
        .background(Color(NSColor.textBackgroundColor))
        .sheet(isPresented: $showCreateSession) {
            CreateSessionAlert(
                isPresented: $showCreateSession,
                onCreate: { label in
                    viewModel.createSession(label: label)
                }
            )
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.2)) {
                if viewModel.isAgentTyping {
                    proxy.scrollTo("typing-indicator", anchor: .bottom)
                } else {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - Connection Status Bar

private struct ConnectionStatusBar: View {
    let connectionState: ChatConnectionState
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    private var statusColor: Color {
        switch connectionState {
        case .connected:
            return .green
        case .connecting, .reconnecting:
            return .yellow
        case .disconnected, .error:
            return .red
        }
    }
    
    private var statusText: String {
        switch connectionState {
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

// MARK: - Typing Indicator

private struct TypingIndicator: View {
    @State private var animationPhase: Int = 0
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.title3)
                .foregroundColor(.purple)
                .frame(width: 24, height: 24)
            
            HStack(spacing: 4) {
                Text("Lobs is thinking")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 2) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 4, height: 4)
                            .opacity(animationPhase == index ? 1.0 : 0.3)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.15))
            .cornerRadius(16)
            
            Spacer(minLength: 50)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                animationPhase = (animationPhase + 1) % 3
            }
        }
    }
}
