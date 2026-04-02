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
        // Initial size — SwiftTerm will update this via sizeChanged when it knows its actual size
        var winSize = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)

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

            // Feed raw data to the SwiftTerm terminal view
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

                // Status detection on main thread
                DispatchQueue.main.async {
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

        // Strip ANSI for pattern matching
        let clean = text.replacingOccurrences(
            of: "\u{1B}\\[[0-9;?]*[a-zA-Z]|\u{1B}\\][^\u{07}]*(\u{07}|\u{1B}\\\\)|\u{1B}[^\\[\\]].",
            with: "",
            options: .regularExpression
        )

        if clean.contains("❯") {
            session.status = .waitingForInput
            if !session.messageQueue.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.processQueueIfNeeded(session: session)
                }
            }
        } else if text.contains("⠋") || text.contains("⠙") || text.contains("⠹") || text.contains("⠸") {
            session.status = .running
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
