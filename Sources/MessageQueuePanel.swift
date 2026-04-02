import SwiftUI

struct MessageQueuePanel: View {
    @ObservedObject var session: Session
    @EnvironmentObject var sessionManager: SessionManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Queue header
            HStack {
                Label("Message Queue", systemImage: "tray.full")
                    .font(.headline)
                
                Spacer()
                
                if !session.messageQueue.isEmpty {
                    Text("\(session.messageQueue.count)")
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.bar)
            
            Divider()
            
            if session.messageQueue.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Queue is empty")
                        .foregroundStyle(.secondary)
                    Text("Messages you queue will appear here\nand send automatically when Claude is ready.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(Array(session.messageQueue.enumerated()), id: \.element.id) { index, message in
                        QueuedMessageRow(
                            message: message,
                            index: index,
                            onSendNow: {
                                // Remove from queue and send immediately
                                sessionManager.dequeueMessage(message.id, from: session)
                                sessionManager.sendImmediately(message.text, to: session)
                            },
                            onDelete: {
                                sessionManager.dequeueMessage(message.id, from: session)
                            }
                        )
                    }
                    .onMove { source, destination in
                        sessionManager.moveQueuedMessage(from: source, to: destination, in: session)
                    }
                }
                .listStyle(.plain)
            }
            
            Divider()
            
            // Queue controls
            HStack {
                Button {
                    sessionManager.processNextInQueue(for: session)
                } label: {
                    Label("Send Next", systemImage: "arrow.up.circle")
                        .font(.caption)
                }
                .disabled(session.messageQueue.isEmpty)
                
                Spacer()
                
                Button(role: .destructive) {
                    session.messageQueue.removeAll()
                } label: {
                    Label("Clear All", systemImage: "trash")
                        .font(.caption)
                }
                .disabled(session.messageQueue.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}

struct QueuedMessageRow: View {
    let message: QueuedMessage
    let index: Int
    var onSendNow: () -> Void
    var onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text("#\(index + 1)")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                
                Text(message.text)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(3)
                
                Spacer()
            }
            
            HStack(spacing: 12) {
                Spacer()
                
                Button {
                    onSendNow()
                } label: {
                    Label("Send Now", systemImage: "paperplane")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)
                
                Button {
                    onDelete()
                } label: {
                    Label("Remove", systemImage: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }
}
