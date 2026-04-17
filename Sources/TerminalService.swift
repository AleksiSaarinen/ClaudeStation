import Foundation
import Combine
import AppKit
import UserNotifications

/// Handles communication with Claude Code via stream-json API mode.
/// Each user message spawns: `claude -p --output-format stream-json --verbose --resume <session>`
/// and reads structured JSON events from stdout.
class TerminalService {
    static let shared = TerminalService()

    /// Track active summary processes per session so we can cancel stale ones
    private var activeSummaryProcesses: [UUID: Process] = [:]
    /// Debounce timers for context summary updates
    private var summaryDebounceTimers: [UUID: DispatchWorkItem] = [:]

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
            session.assistantState = .thinking(Self.randomSpinnerVerb())
            session.suggestedActions = []
        }

        let startTime = Date()

        // Build claude command
        let settings = AppSettings.shared
        var args = ["-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--model", "claude-opus-4-7"]

        // Plan mode takes precedence over bypass permissions
        if session.planMode {
            args += ["--permission-mode", "plan"]
        } else if settings.alwaysBypassPermissions {
            args.append("--dangerously-skip-permissions")
        }

        // Context mode: managed (build context ourselves) vs resume (send full history)
        if settings.managedContext {
            let contextPrompt = buildManagedPrompt(message: promptText, session: session)
            args.append(contextPrompt)
        } else {
            if let sessionId = session.claudeSessionId {
                args += ["--resume", sessionId]
            }
            args.append(promptText)
        }

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
        let actualPrompt = args.last ?? promptText
        let escapedText = actualPrompt.replacingOccurrences(of: "'", with: "'\\''")
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
        var resultInputTokens: Int?
        var resultOutputTokens: Int?

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
                                    session.lastToolName = name
                                    session.lastToolCommand = toolCommand
                                    // Detect sleep commands and set countdown
                                    if name == "Bash", let cmd = toolCommand {
                                        if let match = cmd.range(of: "sleep\\s+(\\d+)", options: .regularExpression) {
                                            let numRange = cmd[match].split(separator: " ").last.flatMap { Int($0) }
                                            if let secs = numRange {
                                                session.sleepEndTime = Date().addingTimeInterval(Double(secs))
                                            }
                                        } else {
                                            session.sleepEndTime = nil
                                        }
                                    } else {
                                        session.sleepEndTime = nil
                                    }
                                    if name == "AskUserQuestion" {
                                        let question = input["question"] as? String ?? "Waiting for your input..."
                                        session.assistantState = .thinking(question)
                                        session.status = .waitingForInput
                                    } else {
                                        session.assistantState = .thinking(label)
                                    }
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

                case "rate_limit_event":
                    if let info = json["rate_limit_info"] as? [String: Any] {
                        let resetsAt = info["resetsAt"] as? TimeInterval
                        let limitType = info["rateLimitType"] as? String
                        DispatchQueue.main.async {
                            if let ts = resetsAt { session.rateLimitResetsAt = Date(timeIntervalSince1970: ts) }
                            session.rateLimitType = limitType
                        }
                    }

                case "result":
                    resultDuration = json["duration_ms"] as? Int
                    resultCost = json["total_cost_usd"] as? Double
                    if let usage = json["usage"] as? [String: Any] {
                        resultInputTokens = usage["input_tokens"] as? Int
                        resultOutputTokens = usage["output_tokens"] as? Int
                    }
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
                if session.chatMessages[last].completionVerb == nil {
                    session.chatMessages[last].completionVerb = Self.randomCompletionVerb()
                }
                session.chatMessages[last].durationApiMs = resultDuration
                session.chatMessages[last].costUsd = resultCost
                if let cost = resultCost { session.totalCostUsd += cost }
                if let inp = resultInputTokens { session.totalInputTokens += inp }
                if let out = resultOutputTokens { session.totalOutputTokens += out }
            } else if process.terminationStatus != 0 && !stderrText.isEmpty {
                let err = ChatMessage(role: .assistant, content: "Error: \(stderrText)")
                session.chatMessages.append(err)
            }

            session.status = .waitingForInput
            session.assistantState = .idle
            if session.planMode { session.planResponseReceived = true }

            // Update context summary (Haiku) if managed context is on
            if AppSettings.shared.managedContext {
                self.updateContextSummary(for: session)
            }

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

    // MARK: - Spinner Verbs

    private static let spinnerVerbs = [
        "Accomplishing", "Actioning", "Actualizing", "Architecting",
        "Baking", "Beaming", "Beboppin'", "Befuddling", "Billowing", "Blanching",
        "Bloviating", "Boogieing", "Boondoggling", "Booping", "Bootstrapping",
        "Brewing", "Burrowing",
        "Calculating", "Canoodling", "Caramelizing", "Cascading", "Catapulting",
        "Cerebrating", "Channeling", "Choreographing", "Churning", "Clauding",
        "Coalescing", "Cogitating", "Combobulating", "Composing", "Computing",
        "Concocting", "Conjuring", "Considering", "Contemplating", "Cooking",
        "Crafting", "Creating", "Crunching", "Crystallizing", "Cultivating",
        "Deciphering", "Deliberating", "Determining", "Dilly-dallying",
        "Discombobulating", "Doodling", "Drizzling",
        "Ebbing", "Effecting", "Elucidating", "Embellishing", "Enchanting",
        "Envisioning", "Evaporating",
        "Fermenting", "Fiddle-faddling", "Finagling", "Flambeing",
        "Flibbertigibbeting", "Flowing", "Flummoxing", "Fluttering",
        "Forging", "Forming", "Frolicking", "Frosting",
        "Gallivanting", "Galloping", "Garnishing", "Generating", "Germinating",
        "Grooving", "Gusting",
        "Harmonizing", "Hashing", "Hatching", "Herding", "Hullaballooing",
        "Osmosing", "Perambulating", "Percolating", "Perusing", "Philosophising",
        "Photosynthesizing", "Pollinating", "Pondering", "Pontificating",
        "Precipitating", "Prestidigitating", "Processing", "Proofing",
        "Propagating", "Puttering", "Puzzling", "Quantumizing",
        "Razzle-dazzling", "Razzmatazzing", "Recombobulating", "Reticulating",
        "Roosting", "Ruminating",
        "Sauteing", "Scampering", "Schlepping", "Scurrying", "Seasoning",
        "Shenaniganing", "Shimmying", "Simmering", "Skedaddling", "Sketching",
        "Slithering", "Smooshing", "Sock-hopping", "Spelunking", "Spinning",
        "Sprouting", "Stewing", "Sublimating", "Swirling", "Swooping",
        "Symbioting", "Synthesizing",
        "Tempering", "Thinking", "Thundering", "Tinkering", "Tomfoolering",
        "Topsy-turvying", "Transfiguring", "Transmuting", "Twisting",
        "Undulating", "Unfurling", "Unravelling",
        "Vibing", "Waddling", "Wandering", "Warping", "Whatchamacalliting",
        "Whirlpooling", "Whirring", "Whisking", "Wibbling", "Working", "Wrangling",
        // ClaudeStation specials
        "Queueing", "Destacking", "Petting the buddy", "Feeding tokens",
        "Multiplexing", "Tab-juggling",
    ]

    private static let completionVerbs = [
        "Baked", "Brewed", "Churned", "Cooked", "Crafted", "Conjured",
        "Forged", "Hatched", "Simmered", "Synthesized", "Whipped up",
        "Concocted", "Crystallized", "Cultivated", "Garnished",
    ]

    static func randomSpinnerVerb() -> String {
        (spinnerVerbs.randomElement() ?? "Thinking") + "..."
    }

    static func randomCompletionVerb() -> String {
        completionVerbs.randomElement() ?? "Baked"
    }

    // MARK: - Managed Context

    /// Build a prompt that includes session context + recent exchanges instead of using --resume.
    /// This keeps token usage roughly constant regardless of conversation length.
    private func buildManagedPrompt(message: String, session: Session) -> String {
        let hasHistory = !session.chatMessages.isEmpty
        if !hasHistory && session.contextSummary.isEmpty {
            return message
        }

        var parts: [String] = []

        if !session.contextSummary.isEmpty {
            parts.append("<session-context>\n\(session.contextSummary)\n</session-context>")
        }

        // Include last 3 exchanges (up to 6 messages) for immediate detail
        let recentCount = min(session.chatMessages.count, 6)
        if recentCount > 0 {
            let recent = session.chatMessages.suffix(recentCount)
            var lines: [String] = []
            for msg in recent {
                if msg.role == .user {
                    lines.append("User: \(String(msg.content.prefix(500)))")
                } else if msg.role == .assistant {
                    var toolLines: [String] = []
                    var textContent = ""
                    for block in msg.blocks {
                        switch block.kind {
                        case .text(let t):
                            if textContent.isEmpty { textContent = t }
                        case .toolUse(let name, let inputJson):
                            if let data = inputJson.data(using: .utf8),
                               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                switch name {
                                case "Bash": toolLines.append("Ran: \(String((dict["command"] as? String ?? "").prefix(100)))")
                                case "Edit": toolLines.append("Edited \((dict["file_path"] as? String ?? "").components(separatedBy: "/").last ?? "")")
                                case "Write": toolLines.append("Wrote \((dict["file_path"] as? String ?? "").components(separatedBy: "/").last ?? "")")
                                case "Read": toolLines.append("Read \((dict["file_path"] as? String ?? "").components(separatedBy: "/").last ?? "")")
                                case "Grep", "Glob": toolLines.append("Searched: \(dict["pattern"] as? String ?? "")")
                                default: toolLines.append(name)
                                }
                            }
                        default: break
                        }
                    }
                    var summary = "Assistant: \(String(textContent.prefix(1500)))"
                    if !toolLines.isEmpty {
                        summary += "\n  [Actions: \(toolLines.joined(separator: "; "))]"
                    }
                    lines.append(summary)
                }
            }
            parts.append("<recent-exchange>\n\(lines.joined(separator: "\n"))\n</recent-exchange>")
        }

        parts.append(message)
        return parts.joined(separator: "\n\n")
    }

    /// Update the session's running context summary using Haiku (cheap & fast).
    /// Called after each exchange completes. Debounced to avoid spam when exchanges finish quickly.
    private func updateContextSummary(for session: Session) {
        let sessionId = session.id

        // Cancel any pending debounce for this session
        summaryDebounceTimers[sessionId]?.cancel()

        // Debounce: wait 2s before firing, in case another exchange finishes right after
        let work = DispatchWorkItem { [weak self] in
            self?.runContextSummaryUpdate(for: session)
        }
        summaryDebounceTimers[sessionId] = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    private func runContextSummaryUpdate(for session: Session) {
        let messages = session.chatMessages
        guard messages.count >= 2 else { return }

        let lastAssistant = messages.last { $0.role == .assistant }
        let lastUser = messages.last { $0.role == .user }
        guard let userMsg = lastUser, let assistantMsg = lastAssistant else { return }

        // Kill any still-running summary process for this session
        let sessionId = session.id
        if let existing = activeSummaryProcesses[sessionId], existing.isRunning {
            existing.terminate()
        }

        // Build concise tool summary
        var toolSummaries: [String] = []
        for block in assistantMsg.blocks {
            if case .toolUse(let name, let inputJson) = block.kind {
                if let data = inputJson.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    switch name {
                    case "Bash": toolSummaries.append("Ran: \(String((dict["command"] as? String ?? "").prefix(80)))")
                    case "Edit": toolSummaries.append("Edited \(dict["file_path"] as? String ?? "")")
                    case "Write": toolSummaries.append("Wrote \(dict["file_path"] as? String ?? "")")
                    case "Read": toolSummaries.append("Read \(dict["file_path"] as? String ?? "")")
                    case "Grep", "Glob": toolSummaries.append("Searched: \(dict["pattern"] as? String ?? "")")
                    default: toolSummaries.append(name)
                    }
                }
            }
        }

        let currentSummary = session.contextSummary.isEmpty ? "(beginning of session)" : session.contextSummary
        let toolStr = toolSummaries.isEmpty ? "" : "\nTools: \(toolSummaries.joined(separator: ", "))"
        let prompt = """
        Update this running summary of a coding session. Be concise (under 400 words). Include: files modified, decisions made, current task state, errors if any.

        Current summary:
        \(currentSummary)

        Latest exchange:
        User: \(String(userMsg.content.prefix(500)))
        Assistant: \(String(assistantMsg.content.prefix(1000)))\(toolStr)

        Return ONLY the updated summary.
        """

        let claudePath = resolvedClaudePath
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", "\(claudePath) -p --model haiku --output-format text '\(prompt.replacingOccurrences(of: "'", with: "'\\''"))'"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.environment = ProcessInfo.processInfo.environment

            self?.activeSummaryProcesses[sessionId] = process

            do {
                try process.run()
                process.waitUntilExit()

                // Clean up tracking
                DispatchQueue.main.async { self?.activeSummaryProcesses.removeValue(forKey: sessionId) }

                // Ignore results if process was terminated (cancelled)
                guard process.terminationReason == .exit, process.terminationStatus == 0 else { return }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else { return }
                DispatchQueue.main.async {
                    session.contextSummary = text
                    NotificationCenter.default.post(name: .init("ClaudeStationSave"), object: nil)
                }
            } catch {
                DispatchQueue.main.async { self?.activeSummaryProcesses.removeValue(forKey: sessionId) }
            }
        }
    }

    /// Generate an initial context summary from existing chat history (for sessions that predate managed context).
    func bootstrapContextSummary(for session: Session) {
        let messages = session.chatMessages
        guard messages.count >= 2 else { return }

        // Build a condensed view of the conversation
        var exchangeLines: [String] = []
        for msg in messages.suffix(20) { // last 20 messages max
            if msg.role == .user {
                exchangeLines.append("User: \(String(msg.content.prefix(200)))")
            } else if msg.role == .assistant {
                var toolNames: [String] = []
                for block in msg.blocks {
                    if case .toolUse(let name, _) = block.kind { toolNames.append(name) }
                }
                let tools = toolNames.isEmpty ? "" : " [Tools: \(toolNames.joined(separator: ", "))]"
                exchangeLines.append("Assistant: \(String(msg.content.prefix(300)))\(tools)")
            }
        }

        let prompt = """
        Summarize this coding session conversation. Be concise (under 400 words). Include: files modified, decisions made, current task state, key context.

        \(exchangeLines.joined(separator: "\n"))

        Return ONLY the summary.
        """

        let claudePath = resolvedClaudePath
        DispatchQueue.global(qos: .utility).async {
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
                guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else { return }
                DispatchQueue.main.async {
                    session.contextSummary = text
                    NotificationCenter.default.post(name: .init("ClaudeStationSave"), object: nil)
                }
            } catch {}
        }
    }

    // MARK: - Smart Suggestions

    func generateSuggestions(for session: Session) {
        // Collect context from last exchange — include tool details
        // Only use the last assistant message + the user message before it
        let lastMessages = session.chatMessages.suffix(2)
        var context = ""
        for msg in lastMessages {
            let role = msg.role == .user ? "User" : "Assistant"
            var toolDetails: [String] = []
            for block in msg.blocks {
                switch block.kind {
                case .toolUse(let name, let inputJson):
                    if let data = inputJson.data(using: .utf8),
                       let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let summary: String
                        switch name {
                        case "Bash": summary = "Ran: \(dict["command"] as? String ?? "")"
                        case "Edit", "Write": summary = "Edited: \(dict["file_path"] as? String ?? "")"
                        case "Read": summary = "Read: \(dict["file_path"] as? String ?? "")"
                        case "Grep", "Glob": summary = "Searched: \(dict["pattern"] as? String ?? "")"
                        default: summary = "Used: \(name)"
                        }
                        toolDetails.append(String(summary.prefix(200)))
                    } else {
                        toolDetails.append("Used: \(name)")
                    }
                default: break
                }
            }
            let toolStr = toolDetails.isEmpty ? "" : "\n  Actions taken:\n  - \(toolDetails.joined(separator: "\n  - "))"
            let content = String(msg.content.prefix(600))
            context += "\(role): \(content)\(toolStr)\n\n"
        }

        // Detect what's already done from the content
        let lastContent = (session.chatMessages.last?.content ?? "").lowercased()
        var doneActions: [String] = []
        if lastContent.contains("pushed") || lastContent.contains("git push") { doneActions.append("push is DONE") }
        if lastContent.contains("committed") || lastContent.contains("git commit") { doneActions.append("commit is DONE") }
        if lastContent.contains("deployed") || lastContent.contains("deploy") { doneActions.append("deploy is DONE") }
        if lastContent.contains("merged") { doneActions.append("merge is DONE") }
        let doneStr = doneActions.isEmpty ? "" : "\n\nALREADY DONE: \(doneActions.joined(separator: ", ")). Do NOT suggest these."

        let prompt = """
        Suggest 2-3 things the user should do NEXT in this Claude Code session. Return ONLY a valid JSON array.

        Format: [{"icon": "SF Symbol name", "label": "2-4 words", "prompt": "message to send to Claude Code"}]\(doneStr)

        RULES:
        - NEVER suggest something already done (check the actions and response text carefully)
        - Suggest things Claude Code CAN do: run commands, edit/read files, search code, run tests, analyze logs
        - Claude Code CANNOT: open apps, click UI, visually test, browse websites
        - After a completed task (pushed/deployed/done): suggest what to work on NEXT or ask "what should we work on next?"
        - Keep prompts under 50 chars, specific and actionable

        SF Symbols: checkmark.circle, arrow.triangle.branch, play.fill, hammer, arrow.counterclockwise, doc.text, terminal, testtube.2, paperplane, eye, bolt, server.rack, globe, magnifyingglass, questionmark.circle, list.bullet

        Conversation:
        \(context)
        """

        let claudePath = resolvedClaudePath
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", "\(claudePath) -p --model sonnet --output-format text '\(prompt.replacingOccurrences(of: "'", with: "'\\''"))'"]
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
                    jsonStr = String(jsonStr[start.lowerBound..<end.upperBound])
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
        // Get the last text block from the message (skips tool use blocks)
        let lastTextBlock = session.chatMessages.last?.blocks.last(where: {
            if case .text = $0.kind { return true }
            return false
        })
        let text: String
        if case .text(let t) = lastTextBlock?.kind {
            text = t
        } else {
            text = session.chatMessages.last?.content ?? ""
        }
        // Take first 150 chars of the final text block
        content.body = String(text.prefix(150))
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
