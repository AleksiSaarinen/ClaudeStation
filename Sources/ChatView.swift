import SwiftUI

struct ChatView: View {
    @ObservedObject var session: Session

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if session.chatMessages.isEmpty && session.status != .idle {
                        WelcomeCard(session: session)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            .padding(.top, 20)
                    }

                    ForEach(session.chatMessages) { message in
                        if message.role == .user {
                            UserMessageRow(message: message)
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        } else {
                            AssistantMessageRow(message: message)
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                    }

                    if case .thinking(let text) = session.assistantState {
                        ThinkingIndicator(text: text)
                            .id("thinking")
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: session.chatMessages.count)
                .animation(.easeInOut(duration: 0.25), value: session.assistantState)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .onChange(of: session.chatMessages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    if let last = session.chatMessages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: session.assistantState) { _, newState in
                if case .thinking = newState {
                    withAnimation(.easeOut(duration: 0.3)) {
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
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
                .scaleEffect(appeared ? 1.0 : 0.5)
                .opacity(appeared ? 1.0 : 0.0)
            Text("Claude Code")
                .font(.title3.bold())
                .opacity(appeared ? 1.0 : 0.0)
            Text(session.workingDirectory)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontDesign(.monospaced)
                .opacity(appeared ? 1.0 : 0.0)
            Text(session.status == .waitingForInput ? "Ready. Type a message below." : "Starting Claude...")
                .font(.caption)
                .foregroundStyle(.secondary)
                .opacity(appeared ? 1.0 : 0.0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
    }
}

// MARK: - User Message

struct UserMessageRow: View {
    let message: ChatMessage
    @State private var appeared = false

    var body: some View {
        HStack {
            Spacer(minLength: 80)
            Text(message.content)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.15), lineWidth: 1)
                )
                .scaleEffect(appeared ? 1.0 : 0.92)
                .opacity(appeared ? 1.0 : 0.0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { appeared = true }
        }
    }
}

// MARK: - Assistant Message

struct AssistantMessageRow: View {
    let message: ChatMessage
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 5) {
                Circle().fill(Color.purple).frame(width: 6, height: 6)
                Text("Claude").font(.caption2.bold()).foregroundStyle(.secondary)
                if let secs = message.durationSeconds {
                    Text("·").foregroundStyle(.quaternary)
                    Image(systemName: "clock").font(.caption2).foregroundStyle(.tertiary)
                    Text(formatDuration(secs)).font(.caption2).foregroundStyle(.tertiary)
                }
                if let cost = message.costUsd, cost > 0 {
                    Text("·").foregroundStyle(.quaternary)
                    Text(String(format: "$%.3f", cost)).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            // Content blocks
            VStack(alignment: .leading, spacing: 6) {
                if message.blocks.isEmpty {
                    Text(message.content)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                } else {
                    ForEach(Array(message.blocks.enumerated()), id: \.element.id) { index, block in
                        Group {
                            switch block {
                            case .text(let text):
                                MarkdownText(text: text)
                            case .toolUse(_, let name, let input):
                                ToolUseCard(name: name, input: input)
                            case .toolResult(_, let content):
                                ToolResultCard(content: content)
                            }
                        }
                        .padding(.horizontal, 12)
                        .opacity(appeared ? 1.0 : 0.0)
                        .offset(y: appeared ? 0 : 6)
                        .animation(
                            .easeOut(duration: 0.3).delay(Double(index) * 0.06),
                            value: appeared
                        )
                    }
                }
            }
            .padding(.bottom, 10)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .padding(.trailing, 24)
        .onAppear {
            withAnimation { appeared = true }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 { return String(format: "%.0fs", seconds) }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins)m \(secs)s"
    }
}

// MARK: - Tool Use Card

struct ToolUseCard: View {
    let name: String
    let input: [String: Any]

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: toolIcon)
                .font(.caption)
                .foregroundStyle(toolColor)
                .frame(width: 16)

            Text(name)
                .font(.system(.caption, design: .monospaced).bold())
                .foregroundStyle(toolColor)

            Text(toolSummary)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(toolColor.opacity(0.15), lineWidth: 1)
        )
    }

    private var toolSummary: String {
        if let path = input["file_path"] as? String {
            return (path as NSString).lastPathComponent
        }
        if let cmd = input["command"] as? String {
            return String(cmd.prefix(60))
        }
        if let pattern = input["pattern"] as? String {
            return pattern
        }
        if let desc = input["description"] as? String {
            return String(desc.prefix(50))
        }
        return ""
    }

    var toolIcon: String {
        switch name {
        case "Read": return "doc.text"
        case "Write": return "doc.badge.plus"
        case "Edit": return "pencil.line"
        case "Bash": return "terminal"
        case "Glob": return "magnifyingglass"
        case "Grep": return "text.magnifyingglass"
        case "Agent": return "person.2"
        case "WebFetch", "WebSearch": return "globe"
        default: return "wrench"
        }
    }

    var toolColor: Color {
        switch name {
        case "Read": return .blue
        case "Write": return .green
        case "Edit": return .orange
        case "Bash": return .purple
        case "Glob", "Grep": return .cyan
        case "Agent": return .indigo
        default: return .gray
        }
    }
}

// MARK: - Markdown Text

struct MarkdownText: View {
    let text: String

    var body: some View {
        // SwiftUI Text supports markdown via LocalizedStringKey on macOS 13+
        Text(try! AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            .font(.body)
            .textSelection(.enabled)
    }
}

// MARK: - Tool Result Card

struct ToolResultCard: View {
    let content: String
    @State private var expanded = false

    var body: some View {
        if !content.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        expanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                        Text("\(content.components(separatedBy: "\n").count) lines output")
                            .font(.caption2)
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expanded {
                    Text(String(content.prefix(2000)))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 6)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(Color.primary.opacity(0.02))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }
}

// MARK: - Thinking Indicator

struct ThinkingIndicator: View {
    let text: String
    @State private var dotCount = 0

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 5, height: 5)
                        .scaleEffect(dotCount % 3 == i ? 1.3 : 0.7)
                        .opacity(dotCount % 3 == i ? 1.0 : 0.3)
                        .animation(.easeInOut(duration: 0.4), value: dotCount)
                }
            }
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.purple.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.purple.opacity(0.1), lineWidth: 1)
        )
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                dotCount += 1
            }
        }
    }
}
