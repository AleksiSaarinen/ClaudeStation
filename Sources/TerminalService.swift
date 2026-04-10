import Foundation
import Combine
import AppKit
import UserNotifications

/// Handles communication with Claude Code via stream-json API mode.
/// Each user message spawns: `claude -p --output-format stream-json --verbose --resume <session>`
/// and reads structured JSON events from stdout.
class TerminalService {
    static let shared = TerminalService()

    /// Resolved full path to the claude binary (cached after first lookup)
    private lazy var resolvedClaudePath: String = {
        let configured = AppSettings.shared.claudeCodePath
        // Already a full path
        if configured.contains("/") {
            if FileManager.default.isExecutableFile(atPath: configured) { return configured }
            let expanded = (configured as NSString).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) { return expanded }
        }
        // Try `which` in a login shell to find it on PATH
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-l", "-c", "which \(configured)"]
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let found = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !found.isEmpty, task.terminationStatus == 0 {
            return found
        }
        // Try common locations
        let home = NSHomeDirectory()
        for candidate in ["\(home)/.local/bin/\(configured)", "/usr/local/bin/\(configured)", "/opt/homebrew/bin/\(configured)"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return configured
    }()

    // MARK: - Send Message

    func send(text: String, to session: Session, force: Bool = false) {
        guard !text.isEmpty else { return }

        // Prevent concurrent processes — queue if busy
        if session.activeProcess != nil {
            if force {
                // Force: insert at front of queue so it sends next
                session.messageQueue.insert(QueuedMessage(text: text), at: 0)
            } else {
                session.messageQueue.append(QueuedMessage(text: text))
            }
            return
        }

        // Extract image attachment and rewrite as a prompt Claude can act on.
        // The [Image: path] marker is stripped and replaced with an instruction
        // to use the Read tool on the file, since `claude -p` has no --image flag.
        var promptText = text

        // Extract all [Image: path] tags → instruct Claude to Read each image
        var imagePaths: [String] = []
        while let pathRange = promptText.range(of: "(?<=\\[Image: )[^\\]]+", options: .regularExpression),
              let fullRange = promptText.range(of: "\\[Image: [^\\]]+\\]", options: .regularExpression) {
            imagePaths.append(String(promptText[pathRange]))
            promptText = promptText.replacingCharacters(in: fullRange, with: "")
        }
        promptText = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !imagePaths.isEmpty {
            let imageInstructions = imagePaths.map { "Read and look at the image file at \($0)" }.joined(separator: ". ")
            if promptText.isEmpty {
                promptText = imageInstructions + " and describe what you see."
            } else {
                promptText = imageInstructions + ". " + promptText
            }
        }

        // Extract [File: path] → instruct Claude to Read the file/folder
        while let range = promptText.range(of: "\\[File: [^\\]]+\\]", options: .regularExpression),
              let pathRange = promptText.range(of: "(?<=\\[File: )[^\\]]+", options: .regularExpression) {
            let filePath = String(promptText[pathRange])
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: filePath, isDirectory: &isDir)
            let instruction = isDir.boolValue
                ? "The user dragged in the folder at \(filePath). Use it as context."
                : "The user dragged in the file at \(filePath). Read it and use it as context."
            promptText = promptText.replacingCharacters(in: range, with: instruction)
        }

        // Record user message (original text so [Image:] shows in chat)
        let userMsg = ChatMessage(role: .user, content: text)
        DispatchQueue.main.async {
            session.chatMessages.append(userMsg)
            session.status = .running
            session.assistantState = .thinking("Thinking...")
            session.suggestedActions = []
        }

        let startTime = Date()

        // Build claude command
        let settings = AppSettings.shared
        var args = ["-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--model", "claude-opus-4-6"]

        // Plan mode takes precedence over bypass permissions
        if session.planMode {
            args += ["--permission-mode", "plan"]
        } else if settings.alwaysBypassPermissions {
            args.append("--dangerously-skip-permissions")
        }

        // Resume existing conversation or start new
        if let sessionId = session.claudeSessionId {
            args += ["--resume", sessionId]
        }

        args.append(promptText)

        let workDir = (session.workingDirectory as NSString).expandingTildeInPath

        // Validate working directory
        if !FileManager.default.fileExists(atPath: workDir) {
            DispatchQueue.main.async {
                let err = ChatMessage(role: .assistant, content: "Error: Working directory not found: \(workDir)")
                session.chatMessages.append(err)
                session.status = .waitingForInput
                session.assistantState = .idle
            }
            return
        }

        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()
        let escapedText = promptText.replacingOccurrences(of: "'", with: "'\\''")
        let claudeCmd = ([resolvedClaudePath] + args.dropLast()).joined(separator: " ")
        let fullCmd = "cd '\(workDir)' && \(claudeCmd) '\(escapedText)'"

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", fullCmd]
        process.standardOutput = pipe
        process.standardError = errorPipe

        // Environment — TERM=dumb prevents any terminal UI
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        process.environment = env

        session.activeProcess = process

        // Collect events on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runAndCollect(process: process, pipe: pipe, errorPipe: errorPipe, session: session, startTime: startTime)
        }
    }

    // MARK: - Run Process & Collect JSON Events

    private func runAndCollect(process: Process, pipe: Pipe, errorPipe: Pipe, session: Session, startTime: Date) {
        do {
            try process.run()
        } catch {
            DispatchQueue.main.async {
                let err = ChatMessage(role: .assistant, content: "Failed to launch claude: \(error.localizedDescription)")
                session.chatMessages.append(err)
                session.status = .error
                session.assistantState = .idle
            }
            return
        }

        let handle = pipe.fileHandleForReading
        var buffer = Data()
        var messageCreated = false    // Track on background thread
        var streamingText = ""        // Accumulate current text block
        var currentTextBlockId: String? // ID of the text block being streamed
        var allTextParts: [String] = [] // All text blocks for content field
        var resultDuration: Int?
        var resultCost: Double?

        // Read stdout line by line — stream blocks into live message
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)

            while let newlineRange = buffer.range(of: Data([0x0A])) {
                let lineData = buffer[buffer.startIndex..<newlineRange.lowerBound]
                buffer = Data(buffer[newlineRange.upperBound...])

                guard let line = String(data: lineData, encoding: .utf8),
                      !line.isEmpty,
                      let jsonData = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                      let type = json["type"] as? String
                else { continue }

                switch type {
                case "system":
                    if let sid = json["session_id"] as? String {
                        DispatchQueue.main.async { session.claudeSessionId = sid }
                    }

                case "assistant":
                    if let message = json["message"] as? [String: Any],
                       let content = message["content"] as? [[String: Any]] {
                        for block in content {
                            guard let blockType = block["type"] as? String else { continue }

                            switch blockType {
                            case "text":
                                // Skip — streaming deltas handle text content.
                                // With --include-partial-messages, assistant events fire
                                // with PARTIAL text that would overwrite the fuller streamed text.
                                break

                            case "tool_use":
                                let toolId = block["id"] as? String ?? UUID().uuidString
                                let name = block["name"] as? String ?? "Unknown"
                                let input = block["input"] as? [String: Any] ?? [:]
                                let created = messageCreated
                                messageCreated = true
                                let toolBlock = ContentBlock.toolUse(id: toolId, name: name, input: input)
                                DispatchQueue.main.async {
                                    if created, let last = session.chatMessages.indices.last,
                                       session.chatMessages[last].role == .assistant {
                                        session.chatMessages[last].blocks.append(toolBlock)
                                    } else {
                                        var msg = ChatMessage(role: .assistant, content: "", blocks: [toolBlock])
                                        msg.durationSeconds = 0
                                        session.chatMessages.append(msg)
                                    }
                                }
                                let label: String = {
                                    let file = (input["file_path"] as? String ?? "").components(separatedBy: "/").last ?? ""
                                    switch name {
                                    case "Read": return "Reading \(file)..."
                                    case "Write": return "Writing \(file)..."
                                    case "Edit": return "Editing \(file)..."
                                    case "Bash":
                                        let cmd = (input["command"] as? String ?? "").prefix(50)
                                        return "Running: \(cmd)"
                                    case "Glob": return "Searching: \(input["pattern"] as? String ?? "files")..."
                                    case "Grep": return "Searching: \(input["pattern"] as? String ?? "")..."
                                    case "Agent":
                                        let desc = input["description"] as? String ?? input["prompt"] as? String ?? "task"
                                        return "Agent: \(desc.prefix(40))..."
                                    case "WebSearch": return "Searching: \(input["query"] as? String ?? "")..."
                                    case "WebFetch": return "Fetching URL..."
                                    default: return "\(name)..."
                                    }
                                }()
                                let toolCommand = input["command"] as? String
                                DispatchQueue.main.async {
                                    session.assistantState = .thinking(label)
                                    session.lastToolName = name
                                    session.lastToolCommand = toolCommand
                                }

                            default: break
                            }
                        }
                    }

                case "tool_result":
                    let toolUseId = json["tool_use_id"] as? String ?? ""
                    var resultContent = ""
                    if let content = json["content"] as? String {
                        resultContent = content
                    } else if let content = json["content"] as? [[String: Any]] {
                        resultContent = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
                    }
                    if !resultContent.isEmpty {
                        let resultBlock = ContentBlock.toolResult(toolUseId: toolUseId, content: resultContent)
                        DispatchQueue.main.async {
                            if let last = session.chatMessages.indices.last,
                               session.chatMessages[last].role == .assistant {
                                session.chatMessages[last].blocks.append(resultBlock)
                            }
                        }
                    }

                case "stream_event":
                    if let event = json["event"] as? [String: Any],
                       let eventType = event["type"] as? String {

                        if eventType == "content_block_start" {
                            if let block = event["content_block"] as? [String: Any],
                               block["type"] as? String == "text" {
                                // Save previous text block if any
                                if !streamingText.isEmpty {
                                    allTextParts.append(streamingText)
                                }
                                streamingText = ""
                                // Create a new text block with unique ID
                                let blockId = "text-\(UUID().uuidString)"
                                currentTextBlockId = blockId
                                let created = messageCreated
                                messageCreated = true
                                DispatchQueue.main.async {
                                    if created, let last = session.chatMessages.indices.last,
                                       session.chatMessages[last].role == .assistant {
                                        session.chatMessages[last].blocks.append(
                                            ContentBlock(id: blockId, kind: .text(""))
                                        )
                                    } else {
                                        var msg = ChatMessage(role: .assistant, content: "",
                                                              blocks: [ContentBlock(id: blockId, kind: .text(""))])
                                        msg.durationSeconds = 0
                                        session.chatMessages.append(msg)
                                    }
                                }
                            }
                        }

                        if eventType == "content_block_delta",
                           let delta = event["delta"] as? [String: Any],
                           let deltaType = delta["type"] as? String,
                           deltaType == "text_delta",
                           let text = delta["text"] as? String {
                            streamingText += text
                            let snapshot = streamingText
                            let blockId = currentTextBlockId
                            DispatchQueue.main.async {
                                guard let last = session.chatMessages.indices.last,
                                      session.chatMessages[last].role == .assistant,
                                      let blockId else { return }
                                // Find and update the specific text block by ID
                                if let blkIdx = session.chatMessages[last].blocks.firstIndex(where: { $0.id == blockId }) {
                                    session.chatMessages[last].blocks[blkIdx] = ContentBlock(
                                        id: blockId, kind: .text(snapshot)
                                    )
                                }
                                // Update content with all text parts combined
                                let allText = session.chatMessages[last].blocks.compactMap { block -> String? in
                                    if case .text(let t) = block.kind, !t.isEmpty { return t }
                                    return nil
                                }.joined(separator: "\n\n")
                                session.chatMessages[last].content = allText
                                session.assistantState = .responding
                            }
                        }

                        if eventType == "content_block_stop" {
                            if !streamingText.isEmpty {
                                allTextParts.append(streamingText)
                            }
                            streamingText = ""
                            currentTextBlockId = nil
                        }
                    }

                case "result":
                    resultDuration = json["duration_ms"] as? Int
                    resultCost = json["total_cost_usd"] as? Double
                    if let sid = json["session_id"] as? String {
                        DispatchQueue.main.async { session.claudeSessionId = sid }
                    }

                default: break
                }
            }
        }

        // Process any remaining data in buffer (last line without trailing newline)
        if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8), !line.isEmpty,
           let jsonData = line.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let type = json["type"] as? String {
            if type == "result" {
                resultDuration = json["duration_ms"] as? Int
                resultCost = json["total_cost_usd"] as? Double
                if let sid = json["session_id"] as? String {
                    DispatchQueue.main.async { session.claudeSessionId = sid }
                }
            }
        }

        process.waitUntilExit()

        // Read any remaining stdout after process exits
        let remaining = handle.readDataToEndOfFile()
        if !remaining.isEmpty {
            let allRemaining = remaining
            if let lines = String(data: allRemaining, encoding: .utf8) {
                for line in lines.components(separatedBy: "\n") where !line.isEmpty {
                    guard let jsonData = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                          let type = json["type"] as? String else { continue }

                    if type == "stream_event",
                       let event = json["event"] as? [String: Any],
                       let eventType = event["type"] as? String,
                       eventType == "content_block_delta",
                       let delta = event["delta"] as? [String: Any],
                       delta["type"] as? String == "text_delta",
                       let text = delta["text"] as? String {
                        streamingText += text
                        let snapshot = streamingText
                        let blockId = currentTextBlockId
                        DispatchQueue.main.async {
                            guard let last = session.chatMessages.indices.last,
                                  session.chatMessages[last].role == .assistant,
                                  let blockId else { return }
                            if let blkIdx = session.chatMessages[last].blocks.firstIndex(where: { $0.id == blockId }) {
                                session.chatMessages[last].blocks[blkIdx] = ContentBlock(id: blockId, kind: .text(snapshot))
                            }
                            let allText = session.chatMessages[last].blocks.compactMap { block -> String? in
                                if case .text(let t) = block.kind, !t.isEmpty { return t }; return nil
                            }.joined(separator: "\n\n")
                            session.chatMessages[last].content = allText
                        }
                    }

                    if type == "result" {
                        resultDuration = json["duration_ms"] as? Int
                        resultCost = json["total_cost_usd"] as? Double
                        if let sid = json["session_id"] as? String {
                            DispatchQueue.main.async { session.claudeSessionId = sid }
                        }
                    }
                }
            }
        }

        // Read stderr
        let stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrText = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Finalize
        let duration = Date().timeIntervalSince(startTime)
        DispatchQueue.main.async {
            session.activeProcess = nil

            // Update duration/cost on the streamed message
            if let last = session.chatMessages.indices.last,
               session.chatMessages[last].role == .assistant {
                session.chatMessages[last].durationSeconds = duration
                session.chatMessages[last].durationApiMs = resultDuration
                session.chatMessages[last].costUsd = resultCost
            } else if process.terminationStatus != 0 && !stderrText.isEmpty {
                let err = ChatMessage(role: .assistant, content: "Error: \(stderrText)")
                session.chatMessages.append(err)
            }

            session.status = .waitingForInput
            session.assistantState = .idle

            // Generate smart suggestions for next action
            self.generateSuggestions(for: session)

            // Trigger save after response completes
            NotificationCenter.default.post(name: .init("ClaudeStationSave"), object: nil)

            // System notification if app is not focused
            if !NSApp.isActive {
                let center = UNUserNotificationCenter.current()
                center.getNotificationSettings { settings in
                    switch settings.authorizationStatus {
                    case .notDetermined:
                        // First time — request permission, then send
                        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                            if granted { self.sendNotification(session: session) }
                        }
                    case .authorized, .provisional:
                        self.sendNotification(session: session)
                    default:
                        break
                    }
                }
            }

            if !session.messageQueue.isEmpty {
                self.processNextInQueue(for: session)
            }
        }
    }

    // MARK: - Smart Suggestions

    func generateSuggestions(for session: Session) {
        // Collect context from last exchange
        let lastMessages = session.chatMessages.suffix(4)
        var context = ""
        for msg in lastMessages {
            let role = msg.role == .user ? "User" : "Assistant"
            // Include tool names used
            let tools = msg.blocks.compactMap { block -> String? in
                if case .toolUse(let name, _) = block.kind { return name }
                return nil
            }
            let toolStr = tools.isEmpty ? "" : " [Tools: \(tools.joined(separator: ", "))]"
            // Truncate content to keep prompt small
            let content = String(msg.content.prefix(300))
            context += "\(role)\(toolStr): \(content)\n\n"
        }

        let prompt = """
        Based on this Claude Code conversation, suggest 2-3 short follow-up actions the user might want to do next. Return ONLY a JSON array, no markdown, no explanation. Each item has "icon" (SF Symbol name), "label" (2-4 words), and "prompt" (the actual message to send to Claude).

        Conversation:
        \(context)

        Rules:
        - Be specific to what just happened, not generic
        - Use SF Symbol names like: checkmark.circle, arrow.triangle.branch, play.fill, hammer, arrow.counterclockwise, doc.text, ant, terminal, testtube.2, paperplane
        - Keep labels short (2-4 words max)
        - Keep prompts concise but actionable
        - If code was edited, suggest testing or committing
        - If tests passed, suggest committing
        - If there was an error, suggest fixing
        - Return valid JSON array only
        """

        let claudePath = resolvedClaudePath
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", "\(claudePath) -p --model haiku --output-format text '\(prompt.replacingOccurrences(of: "'", with: "'\\''"))'"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.environment = ProcessInfo.processInfo.environment

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return }

                // Extract JSON array from response (handle potential markdown wrapping)
                var jsonStr = text
                if let start = jsonStr.range(of: "["), let end = jsonStr.range(of: "]", options: .backwards) {
                    jsonStr = String(jsonStr[start.lowerBound...end.upperBound])
                }

                guard let jsonData = jsonStr.data(using: .utf8),
                      let arr = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: String]] else { return }

                let suggestions = arr.prefix(3).compactMap { item -> (icon: String, label: String, prompt: String)? in
                    guard let icon = item["icon"], let label = item["label"], let prompt = item["prompt"] else { return nil }
                    return (icon: icon, label: label, prompt: prompt)
                }

                DispatchQueue.main.async {
                    session.suggestedActions = suggestions
                }
            } catch {}
        }
    }

    private func sendNotification(session: Session) {
        let content = UNMutableNotificationContent()
        content.title = "\(session.displayName) — Claude finished"
        let preview = session.chatMessages.last?.content.prefix(100) ?? ""
        content.body = String(preview)
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Queue Processing

    func processNextInQueue(for session: Session) {
        guard session.status == .waitingForInput,
              !session.messageQueue.isEmpty else { return }
        let message = session.messageQueue.removeFirst()
        send(text: message.text, to: session)
    }

    // MARK: - Terminate

    func terminate(session: Session) {
        session.activeProcess?.terminate()
        session.activeProcess = nil
        // Also terminate legacy PTY if present
        session.ptyPrimary?.readabilityHandler = nil
        session.process?.terminate()
        if let handle = session.ptyPrimary {
            close(handle.fileDescriptor)
        }
        session.process = nil
        session.ptyPrimary = nil
        session.terminalFeed = nil
        session.status = .idle
        session.assistantState = .idle
    }
}
