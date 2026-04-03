import Foundation
import Combine
import SwiftUI

/// Manages all Claude Code sessions
class SessionManager: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var activeSessionId: UUID?
    
    let settings = AppSettings.shared
    
    var activeSession: Session? {
        sessions.first { $0.id == activeSessionId }
    }
    
    init() {
        // Start with one default session
        createSession()
    }
    
    // MARK: - Session Lifecycle
    
    @discardableResult
    func createSession(name: String = "", workingDirectory: String? = nil) -> Session {
        let dir = workingDirectory ?? settings.defaultWorkingDirectory
        let session = Session(name: name, workingDirectory: dir)
        sessions.append(session)
        activeSessionId = session.id
        // No PTY launch needed — stream-json mode spawns per message
        session.status = .waitingForInput
        return session
    }
    
    func createSessionFromProfile(_ profile: LaunchProfile) -> Session {
        let session = createSession(name: profile.name, workingDirectory: profile.workingDirectory)
        // Profile flags will be applied when launching
        return session
    }
    
    func closeSession(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let session = sessions[index]
        
        // Terminate the process if running
        TerminalService.shared.terminate(session: session)
        
        sessions.remove(at: index)
        
        // Switch to another session if we closed the active one
        if activeSessionId == id {
            activeSessionId = sessions.last?.id
        }
        
        // Always keep at least one session
        if sessions.isEmpty {
            createSession()
        }
    }
    
    // MARK: - Message Queue
    
    /// Add a message to a session's queue
    func queueMessage(_ text: String, for session: Session) {
        let message = QueuedMessage(text: text)
        session.messageQueue.append(message)
        
        // Auto-process if the session is waiting for input
        if settings.autoProcessQueue && session.status == .waitingForInput {
            processNextInQueue(for: session)
        }
    }
    
    /// Send a message immediately, bypassing the queue
    func sendImmediately(_ text: String, to session: Session) {
        TerminalService.shared.send(text: text, to: session)
    }
    
    /// Process the next queued message for a session
    func processNextInQueue(for session: Session) {
        guard !session.messageQueue.isEmpty else {
            session.isProcessingQueue = false
            return
        }
        
        guard session.status == .waitingForInput || session.status == .idle else {
            // Not ready yet, will retry when status changes
            return
        }
        
        session.isProcessingQueue = true
        var message = session.messageQueue.removeFirst()
        message.status = .sending
        
        TerminalService.shared.send(text: message.text, to: session)
    }
    
    /// Remove a queued message before it's sent
    func dequeueMessage(_ messageId: UUID, from session: Session) {
        session.messageQueue.removeAll { $0.id == messageId }
    }
    
    /// Reorder queue
    func moveQueuedMessage(from source: IndexSet, to destination: Int, in session: Session) {
        session.messageQueue.move(fromOffsets: source, toOffset: destination)
    }
}
