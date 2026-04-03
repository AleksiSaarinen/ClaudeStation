import SwiftUI

struct ChatView: View {
    @ObservedObject var session: Session

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if session.chatMessages.isEmpty && session.status != .idle {
                        WelcomeCard(session: session)
                            .padding(.top, 20)
                    }

                    ForEach(session.chatMessages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    // Thinking indicator
                    if case .thinking(let text) = session.assistantState {
                        ThinkingIndicator(text: text)
                            .id("thinking")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .onChange(of: session.chatMessages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    if let last = session.chatMessages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: session.assistantState) { _, newState in
                if case .thinking = newState {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("thinking", anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Welcome Card

struct WelcomeCard: View {
    @ObservedObject var session: Session

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            Text("Claude Code")
                .font(.title3.bold())
                .foregroundStyle(.primary)

            Text(session.workingDirectory)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontDesign(.monospaced)

            if session.status == .running || session.status == .waitingForInput {
                Text("Ready. Type a message below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Starting Claude...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Role label
                HStack(spacing: 4) {
                    if message.role == .assistant {
                        Image(systemName: "sparkle")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                    }
                    Text(message.role == .user ? "You" : "Claude")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }

                // Content
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.role == .user
                            ? Color.blue.opacity(0.15)
                            : Color(nsColor: .controlBackgroundColor)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                message.role == .user
                                    ? Color.blue.opacity(0.2)
                                    : Color.primary.opacity(0.08),
                                lineWidth: 1
                            )
                    )
            }

            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Thinking Indicator

struct ThinkingIndicator: View {
    let text: String
    @State private var dots = ""

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle")
                .font(.caption)
                .foregroundStyle(.purple)
                .symbolEffect(.pulse)

            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .italic()
        }
        .padding(.leading, 4)
    }
}

// MARK: - Make AssistantState equatable for onChange
extension AssistantState: Equatable {
    static func == (lhs: AssistantState, rhs: AssistantState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.thinking(let a), .thinking(let b)): return a == b
        case (.responding, .responding): return true
        case (.done, .done): return true
        default: return false
        }
    }
}
