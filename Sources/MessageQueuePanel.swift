import SwiftUI

/// Inline queue strip shown above the input bar when messages are queued.
struct InlineQueueStrip: View {
    @ObservedObject var session: Session
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.theme) var theme
    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "tray.full")
                    .font(.caption2)
                    .foregroundStyle(theme.accent)

                Text("\(session.messageQueue.count) queued")
                    .font(.caption.bold())
                    .foregroundStyle(theme.accent)

                Spacer()

                if session.messageQueue.count > 1 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                    } label: {
                        Image(systemName: expanded ? "chevron.down" : "chevron.up")
                            .font(.caption2.bold())
                            .foregroundStyle(theme.mutedText)
                    }
                    .buttonStyle(.borderless)
                }

                Button { session.messageQueue.removeAll() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(theme.mutedText)
                }
                .buttonStyle(.borderless)
            }

            let count = expanded ? session.messageQueue.count : min(3, session.messageQueue.count)
            ForEach(Array(session.messageQueue.prefix(count).enumerated()), id: \.element.id) { index, message in
                QueuePill(
                    message: $session.messageQueue[index], index: index, isNext: index == 0,
                    onSendNow: {
                        let text = session.messageQueue[index].text
                        sessionManager.dequeueMessage(message.id, from: session)
                        sessionManager.sendImmediately(text, to: session)
                    },
                    onDelete: { sessionManager.dequeueMessage(message.id, from: session) }
                )
            }

            if !expanded && session.messageQueue.count > 3 {
                Text("+\(session.messageQueue.count - 3) more")
                    .font(.caption2)
                    .foregroundStyle(theme.mutedText)
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(theme.assistantBubble.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .modifier(LiquidGlassChrome(cornerRadius: 16))
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .animation(.easeInOut(duration: 0.15), value: session.messageQueue.count)
    }
}

struct QueuePill: View {
    @Binding var message: QueuedMessage
    let index: Int
    let isNext: Bool
    var onSendNow: () -> Void
    var onDelete: () -> Void
    @Environment(\.theme) var theme
    @State private var isEditing = false

    var body: some View {
        HStack(spacing: 6) {
            if isNext {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(theme.accent)
            } else {
                Text("#\(index + 1)")
                    .font(.system(.caption2, design: .monospaced).bold())
                    .foregroundStyle(theme.mutedText)
                    .frame(width: 16)
            }

            if isEditing {
                TextField("Edit message", text: $message.text, onCommit: {
                    isEditing = false
                })
                .textFieldStyle(.plain)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(theme.assistantText)
                .onExitCommand { isEditing = false }
            } else {
                Text(message.text)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(theme.assistantText)
                    .onTapGesture { isEditing = true }
            }

            Spacer(minLength: 4)

            // Always visible — send now and delete
            Button(action: onSendNow) {
                Text("Send")
                    .font(.caption2.bold())
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.accent.opacity(0.12))
                    .clipShape(Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "xmark").font(.caption2)
                    .foregroundStyle(theme.mutedText)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isNext ? theme.accent.opacity(0.12) : theme.assistantBubble.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isNext ? theme.accent.opacity(0.3) : theme.assistantBubbleBorder.opacity(0.3), lineWidth: 0.5)
        )
    }
}
