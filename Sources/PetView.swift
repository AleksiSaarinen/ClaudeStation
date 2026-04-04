import SwiftUI
import AppKit

// MARK: - Pet State

enum PetState: String {
    case idle, coding, thinking, reading, searching, testing, deploying, success, error, sleepy

    var frameCount: Int {
        switch self {
        case .idle, .thinking, .searching, .sleepy, .deploying: return 6
        case .coding, .testing: return 8
        case .reading, .success, .error: return 4
        }
    }

    var frameDuration: Double {
        switch self {
        case .idle, .sleepy: return 0.25    // 4fps
        case .reading: return 0.2
        case .thinking, .deploying: return 0.18
        case .searching: return 0.16
        case .success, .error: return 0.15
        case .coding, .testing: return 0.12  // 8fps
        }
    }

    var loops: Bool {
        switch self {
        case .success, .error: return false
        default: return true
        }
    }

    /// Map from session status + tool info to pet state
    static func from(sessionStatus: SessionStatus, lastToolName: String?) -> PetState {
        switch sessionStatus {
        case .running:
            guard let tool = lastToolName else { return .thinking }
            switch tool {
            case "Read": return .reading
            case "Grep", "Glob": return .searching
            case "Bash": return .coding  // Will be refined by command content
            case "Write", "Edit": return .coding
            case "Agent": return .thinking
            default: return .coding
            }
        case .waitingForInput: return .idle
        case .idle: return .idle
        case .error: return .error
        }
    }

    /// Refine Bash state by command content
    static func refineBash(command: String) -> PetState {
        let cmd = command.lowercased()
        if cmd.contains("test") || cmd.contains("jest") || cmd.contains("pytest") || cmd.contains("vitest") {
            return .testing
        }
        if cmd.contains("git push") || cmd.contains("git commit") || cmd.contains("git merge") ||
           cmd.contains("deploy") || cmd.contains("publish") {
            return .deploying
        }
        if cmd.contains("grep") || cmd.contains("find") || cmd.contains("search") || cmd.contains("rg ") {
            return .searching
        }
        return .coding
    }
}

// MARK: - Pet Frame Cache

/// Loads and caches pet sprite frames from the Resources/PetFrames directory
class PetFrameCache {
    static let shared = PetFrameCache()
    private var frames: [String: [NSImage]] = [:]

    func framesFor(state: PetState) -> [NSImage] {
        if let cached = frames[state.rawValue] { return cached }

        var loaded: [NSImage] = []
        for i in 0..<state.frameCount {
            let name = "\(state.rawValue)_\(i)"
            if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "PetFrames"),
               let image = NSImage(contentsOf: url) {
                loaded.append(image)
            }
        }

        // Fallback: try loading from Resources directory directly
        if loaded.isEmpty {
            let resourcePath = Bundle.main.resourcePath ?? ""
            for i in 0..<state.frameCount {
                let path = "\(resourcePath)/PetFrames/\(state.rawValue)_\(i).png"
                if let image = NSImage(contentsOfFile: path) {
                    loaded.append(image)
                }
            }
        }

        frames[state.rawValue] = loaded
        return loaded
    }
}

// MARK: - Pet View

struct PetView: View {
    @ObservedObject var session: Session
    @Environment(\.theme) var theme

    @State private var currentFrame = 0
    @State private var currentState: PetState = .idle
    @State private var timer: Timer?
    @State private var idleSince = Date()
    @State private var oneShotComplete = false

    private let size: CGFloat = 32

    var body: some View {
        let frames = PetFrameCache.shared.framesFor(state: currentState)
        let isActive = currentState != .idle && currentState != .sleepy

        Group {
            if !frames.isEmpty && currentFrame < frames.count {
                Image(nsImage: frames[currentFrame])
                    .interpolation(.none)  // Keep pixel art crisp
                    .resizable()
                    .frame(width: size, height: size)
            } else {
                // Fallback: simple colored circle
                Circle()
                    .fill(theme.accent)
                    .frame(width: size * 0.6, height: size * 0.6)
            }
        }
        .colorMultiply(isActive ? .white : theme.accent)
        .animation(.easeInOut(duration: 0.3), value: isActive)
        .onAppear { updateState(); startTimer() }
        .onDisappear { timer?.invalidate(); timer = nil }
        .onChange(of: session.status) { _, _ in updateState() }
        .onChange(of: session.assistantState) { _, _ in updateState() }
    }

    private func updateState() {
        let newState: PetState

        switch session.status {
        case .running:
            if let tool = session.lastToolName {
                if tool == "Read" {
                    newState = .reading
                } else if tool == "Grep" || tool == "Glob" {
                    newState = .searching
                } else if tool == "Bash", let cmd = session.lastToolCommand {
                    newState = PetState.refineBash(command: cmd)
                } else if tool == "Write" || tool == "Edit" {
                    newState = .coding
                } else if tool == "Agent" {
                    newState = .thinking
                } else {
                    newState = .coding
                }
            } else if case .responding = session.assistantState {
                newState = .thinking
            } else {
                newState = .thinking
            }
            idleSince = Date()

        case .waitingForInput:
            let idleTime = Date().timeIntervalSince(idleSince)
            newState = idleTime > 120 ? .sleepy : .idle

        case .error:
            newState = .error

        case .idle:
            newState = .idle
        }

        if newState != currentState {
            currentState = newState
            currentFrame = 0
            oneShotComplete = false
            startTimer()
        }
    }

    private func startTimer() {
        timer?.invalidate()
        let state = currentState
        timer = Timer.scheduledTimer(withTimeInterval: state.frameDuration, repeats: true) { _ in
            let frames = PetFrameCache.shared.framesFor(state: state)
            guard !frames.isEmpty else { return }

            if state.loops {
                currentFrame = (currentFrame + 1) % frames.count
            } else {
                if currentFrame < frames.count - 1 {
                    currentFrame += 1
                } else if !oneShotComplete {
                    oneShotComplete = true
                    // Transition to idle after one-shot animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if currentState == state {
                            currentState = .idle
                            currentFrame = 0
                            startTimer()
                        }
                    }
                }
            }

            // Check for sleepy transition while idle
            if currentState == .idle && session.status == .waitingForInput {
                let idleTime = Date().timeIntervalSince(idleSince)
                if idleTime > 120 && currentState != .sleepy {
                    currentState = .sleepy
                    currentFrame = 0
                    startTimer()
                }
            }
        }
    }
}
