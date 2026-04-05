import SwiftUI

/// Inline queue strip shown above the input bar when messages are queued.
struct InlineQueueStrip: View {
    @ObservedObject var session: Session
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.theme) var theme
    @State private var expanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()

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

                let messages = expanded ? session.messageQueue : Array(session.messageQueue.prefix(3))
                ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                    QueuePill(
                        message: message, index: index, isNext: index == 0,
                        onSendNow: {
                            sessionManager.dequeueMessage(message.id, from: session)
                            sessionManager.sendImmediately(message.text, to: session)
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
            .background(theme.chromeBar.opacity(0.9))
        }
        .animation(.easeInOut(duration: 0.15), value: session.messageQueue.count)
    }
}

struct QueuePill: View {
    let message: QueuedMessage
    let index: Int
    let isNext: Bool
    var onSendNow: () -> Void
    var onDelete: () -> Void
    @Environment(\.theme) var theme
    @State private var hovering = false

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

            Text(message.text)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(theme.assistantText)

            Spacer(minLength: 4)

            // Always visible — send now and delete
            Button(action: onSendNow) {
                Text("Send")
                    .font(.caption2.bold())
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.accent.opacity(0.12))
                    .clipShape(Capsule())
            }
            .buttonStyle(.borderless)

            Button(action: onDelete) {
                Image(systemName: "xmark").font(.caption2)
                    .foregroundStyle(theme.mutedText)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: max(theme.borderRadius - 6, 4))
                .fill(isNext ? theme.accent.opacity(0.08) : theme.toolCardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: max(theme.borderRadius - 6, 4))
                .strokeBorder(isNext ? theme.accent.opacity(0.2) : theme.toolCardBorder, lineWidth: 1)
        )
    }
}
