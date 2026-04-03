import SwiftUI

/// Inline queue strip shown above the input bar when messages are queued.
/// Compact pill-style items with send/remove actions.
struct InlineQueueStrip: View {
    @ObservedObject var session: Session
    @EnvironmentObject var sessionManager: SessionManager
    @State private var expanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            VStack(alignment: .leading, spacing: 6) {
                // Header row
                HStack(spacing: 6) {
                    Image(systemName: "tray.full")
                        .font(.caption2)
                        .foregroundStyle(.orange)

                    Text("\(session.messageQueue.count) queued")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)

                    Spacer()

                    if session.messageQueue.count > 1 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                expanded.toggle()
                            }
                        } label: {
                            Image(systemName: expanded ? "chevron.down" : "chevron.up")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help(expanded ? "Collapse queue" : "Show all")
                    }

                    Button {
                        session.messageQueue.removeAll()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Clear all queued messages")
                }

                // Message pills
                let messages = expanded ? session.messageQueue : Array(session.messageQueue.prefix(3))
                ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                    QueuePill(
                        message: message,
                        index: index,
                        isNext: index == 0,
                        onSendNow: {
                            sessionManager.dequeueMessage(message.id, from: session)
                            sessionManager.sendImmediately(message.text, to: session)
                        },
                        onDelete: {
                            sessionManager.dequeueMessage(message.id, from: session)
                        }
                    )
                }

                if !expanded && session.messageQueue.count > 3 {
                    Text("+\(session.messageQueue.count - 3) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .animation(.easeInOut(duration: 0.15), value: session.messageQueue.count)
    }
}

/// Compact pill showing a queued message with inline actions.
struct QueuePill: View {
    let message: QueuedMessage
    let index: Int
    let isNext: Bool
    var onSendNow: () -> Void
    var onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            // Position indicator
            if isNext {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
                Text("#\(index + 1)")
                    .font(.system(.caption2, design: .monospaced).bold())
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)
            }

            // Message text
            Text(message.text)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)

            Spacer(minLength: 4)

            // Actions (visible on hover)
            if hovering {
                Button(action: onSendNow) {
                    Image(systemName: "paperplane.fill")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)
                .help("Send now")

                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isNext ? Color.orange.opacity(0.08) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isNext ? Color.orange.opacity(0.2) : Color.primary.opacity(0.06), lineWidth: 1)
        )
        .onHover { hovering = $0 }
    }
}
