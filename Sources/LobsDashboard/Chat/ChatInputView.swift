import SwiftUI

/// Text input bar for sending chat messages
struct ChatInputView: View {
    @Binding var text: String
    let isConnected: Bool
    let onSend: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Text editor
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Type a message...")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                }
                
                TextEditor(text: $text)
                    .focused($isFocused)
                    .frame(minHeight: 36, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .font(.body)
                    .onSubmit {
                        if !shiftKeyPressed {
                            sendMessage()
                        }
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(18)
            .disabled(!isConnected)
            .opacity(isConnected ? 1.0 : 0.5)
            
            // Send button
            Button(action: sendMessage) {
                Image(systemName: "paperplane.fill")
                    .font(.body)
                    .foregroundColor(canSend ? .blue : .gray)
                    .frame(width: 36, height: 36)
                    .background(canSend ? Color.blue.opacity(0.1) : Color.clear)
                    .cornerRadius(18)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            isFocused = true
        }
    }
    
    // MARK: - Computed Properties
    
    private var canSend: Bool {
        isConnected && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var shiftKeyPressed: Bool {
        NSEvent.modifierFlags.contains(.shift)
    }
    
    // MARK: - Actions
    
    private func sendMessage() {
        guard canSend else { return }
        onSend()
        text = ""
        isFocused = true
    }
}
