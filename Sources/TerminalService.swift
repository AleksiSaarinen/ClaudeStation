import Foundation
import Combine
import Darwin

/// Handles spawning and communicating with Claude Code processes via PTY
class TerminalService {
    static let shared = TerminalService()

    // MARK: - Launch Claude Code

    func launch(session: Session, settings: AppSettings) {
        // Create a pseudo-terminal so Claude Code sees a real TTY
        var primary: Int32 = 0
        var secondary: Int32 = 0
        // Use SwiftTerm's reported size if available, otherwise default
        var winSize = winsize(
            ws_row: UInt16(session.terminalRows),
            ws_col: UInt16(session.terminalCols),
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        guard openpty(&primary, &secondary, nil, nil, &winSize) == 0 else {
            DispatchQueue.main.async {
                session.status = .error
            }
            return
        }

        let process = Process()
        let primaryHandle = FileHandle(fileDescriptor: primary, closeOnDealloc: false)
        let secondaryHandle = FileHandle(fileDescriptor: secondary, closeOnDealloc: false)

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")

        // Build the claude command
        var claudeCmd = settings.claudeCodePath
        if settings.alwaysBypassPermissions {
            claudeCmd += " --dangerously-skip-permissions"
        }

        // Expand ~ in working directory
        let workDir = (session.workingDirectory as NSString).expandingTildeInPath

        process.arguments = ["-l", "-c", "cd '\(workDir)' && exec \(claudeCmd)"]
        process.standardInput = secondaryHandle
        process.standardOutput = secondaryHandle
        process.standardError = secondaryHandle

        // Set up environment
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        // Don't set COLUMNS/ROWS — SwiftTerm reports its actual size via TIOCSWINSZ
        env.removeValue(forKey: "COLUMNS")
        env.removeValue(forKey: "ROWS")
        process.environment = env

        session.process = process
        session.ptyPrimary = primaryHandle

        // Raw buffer for auto-accept detection (accessed on I/O thread)
        var rawBuffer = ""

        // Read output from the primary side of the PTY
        primaryHandle.readabilityHandler = { [weak session] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            // Buffer raw data for replay on session switch
            session?.terminalDataBuffer.append(data)
            // Feed to the SwiftTerm terminal view
            session?.terminalFeed?(data)

            // Auto-accept prompts on I/O thread
            if let text = String(data: data, encoding: .utf8) {
                rawBuffer += text

                // Auto-accept trust prompt
                if let session = session, !session.trustAccepted,
                   rawBuffer.contains("trust"), rawBuffer.contains("confirm") {
                    session.trustAccepted = true
                    Thread.sleep(forTimeInterval: 0.5)
                    handle.write(Data([0x0D]))
                }

                // Auto-accept "use this API key?" prompt
                if rawBuffer.contains("API") && rawBuffer.contains("key") && rawBuffer.contains("Yes")
                    && !rawBuffer.contains("__API_ACCEPTED__") {
                    rawBuffer += "__API_ACCEPTED__"
                    Thread.sleep(forTimeInterval: 0.5)
                    handle.write("\u{1B}[A".data(using: .utf8)!) // Arrow up → Yes
                    Thread.sleep(forTimeInterval: 0.3)
                    handle.write(Data([0x0D])) // Enter
                }

                DispatchQueue.main.async {
                    guard let session = session else { return }

                    // Accumulate response text
                    if session.isCollectingResponse {
                        session.responseBuffer += text
                    }

                    // Detect thinking indicators
                    if let thinking = OutputParser.thinkingIndicator(in: text) {
                        session.assistantState = .thinking(thinking)
                    }

                    // Detect when Claude finishes (prompt reappears)
                    if session.isCollectingResponse && OutputParser.containsPrompt(text) {
                        session.isCollectingResponse = false
                        let response = OutputParser.extractResponse(session.responseBuffer)
                        if !response.isEmpty {
                            let msg = ChatMessage(role: .assistant, content: response)
                            session.chatMessages.append(msg)
                        }
                        session.assistantState = .idle
                        session.responseBuffer = ""
                    }

                    self.detectStatus(from: text, session: session)
                }
            }
        }

        // Handle process termination
        process.terminationHandler = { [weak session] _ in
            DispatchQueue.main.async {
                guard let session = session else { return }
                session.ptyPrimary?.readabilityHandler = nil
                if let handle = session.ptyPrimary {
                    close(handle.fileDescriptor)
                }
                session.ptyPrimary = nil
                session.terminalFeed = nil
                session.status = .idle
            }
        }

        do {
            try process.run()
            close(secondary)
            DispatchQueue.main.async {
                session.status = .running
            }
        } catch {
            close(primary)
            close(secondary)
            DispatchQueue.main.async {
                session.status = .error
            }
        }
    }

    // MARK: - Send Input

    func send(text: String, to session: Session) {
        guard let handle = session.ptyPrimary else { return }

        // Record user message in chat
        if !text.isEmpty {
            let msg = ChatMessage(role: .user, content: text)
            DispatchQueue.main.async {
                session.chatMessages.append(msg)
                session.responseBuffer = ""
                session.isCollectingResponse = true
                session.assistantState = .thinking("Thinking...")
            }
        }

        let data = (text + "\r").data(using: .utf8)!
        handle.write(data)
    }

    // MARK: - Terminate

    func terminate(session: Session) {
        session.ptyPrimary?.readabilityHandler = nil
        session.process?.terminate()
        if let handle = session.ptyPrimary {
            close(handle.fileDescriptor)
        }
        session.process = nil
        session.ptyPrimary = nil
        session.terminalFeed = nil
        session.status = .idle
    }

    // MARK: - Status Detection

    private func detectStatus(from text: String, session: Session?) {
        guard let session = session else { return }

        // Spinner characters = Claude is actively working
        let spinners: [Character] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        if text.contains(where: { spinners.contains($0) }) {
            session.status = .running
            return
        }

        // Claude's thinking indicators
        if text.contains("Noodling") || text.contains("Waddling") || text.contains("Harmonizing")
            || text.contains("Pondering") || text.contains("Crunching") || text.contains("Churning") {
            session.status = .running
            return
        }

        // The ❯ prompt means Claude is waiting for input
        // Only match if it's near the end of a chunk (not inside a menu)
        let clean = text.replacingOccurrences(
            of: "\u{1B}\\[[0-9;?]*[a-zA-Z]|\u{1B}\\][^\u{07}]*(\u{07}|\u{1B}\\\\)|\u{1B}[^\\[\\]].",
            with: "",
            options: .regularExpression
        )
        let trimmed = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("❯") && !trimmed.contains("trust") && !trimmed.contains("Yes") {
            session.status = .waitingForInput
            if !session.messageQueue.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.processQueueIfNeeded(session: session)
                }
            }
        }
    }

    private func processQueueIfNeeded(session: Session) {
        guard session.status == .waitingForInput,
              !session.messageQueue.isEmpty else { return }
        let message = session.messageQueue.removeFirst()
        send(text: message.text, to: session)
        session.status = .running
    }
}
