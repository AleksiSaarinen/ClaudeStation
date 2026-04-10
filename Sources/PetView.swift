import SwiftUI
import AppKit

// MARK: - Pet State

enum PetState: String, Equatable {
    case idle, coding, thinking, reading, searching, testing, deploying, success, error, sleepy

    var frameCount: Int {
        switch self {
        case .idle, .coding, .testing, .sleepy: return 10
        case .thinking, .success, .error, .searching, .reading, .deploying: return 8
        }
    }

    var frameDuration: Double {
        switch self {
        case .idle: return 0.18
        case .sleepy: return 0.25
        case .coding, .testing: return 0.10
        case .thinking, .deploying: return 0.16
        case .searching: return 0.15
        case .reading: return 0.22
        case .success: return 0.12
        case .error: return 0.10
        }
    }

    var loops: Bool {
        switch self {
        case .success, .error: return false
        default: return true
        }
    }

    static func refineBash(command: String) -> PetState {
        let cmd = command.lowercased()
        if cmd.contains("test") || cmd.contains("jest") || cmd.contains("pytest") || cmd.contains("vitest") { return .testing }
        if cmd.contains("git push") || cmd.contains("git commit") || cmd.contains("deploy") || cmd.contains("publish") { return .deploying }
        if cmd.contains("grep") || cmd.contains("find ") || cmd.contains("search") || cmd.contains("rg ") { return .searching }
        return .coding
    }
}

// MARK: - Pet Frame Cache

class PetFrameCache {
    static let shared = PetFrameCache()
    private var frames: [String: [NSImage]] = [:]

    func framesFor(state: PetState) -> [NSImage] {
        if let cached = frames[state.rawValue] { return cached }

        var loaded: [NSImage] = []
        let resourcePath = Bundle.main.resourcePath ?? ""
        for i in 0..<state.frameCount {
            let path = "\(resourcePath)/PetFrames/\(state.rawValue)_\(i).png"
            if let image = NSImage(contentsOfFile: path) {
                image.size = NSSize(width: 120, height: 120) // Ensure consistent size
                loaded.append(image)
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

    @State private var currentState: PetState = .idle
    @State private var previousStatus: SessionStatus = .idle
    @State private var currentFrame = 0
    @State private var timer: Timer?
    @State private var idleSince = Date()
    @State private var oneShotDone = false

    private let size: CGFloat = 36

    var body: some View {
        let frames = PetFrameCache.shared.framesFor(state: currentState)

        Group {
            if !frames.isEmpty && currentFrame < frames.count {
                Image(nsImage: frames[currentFrame])
                    .interpolation(.none)
                    .resizable()
                    .frame(width: size, height: size)
            } else {
                // Fallback
                RoundedRectangle(cornerRadius: 4)
                    .fill(theme.accent.opacity(0.3))
                    .frame(width: size, height: size)
            }
        }
        .onAppear { updateState(); startAnimation() }
        .onDisappear { timer?.invalidate(); timer = nil }
        .onChange(of: session.status) { _, _ in updateState() }
        .onChange(of: session.assistantState) { _, _ in updateState() }
        .onChange(of: session.lastToolName) { _, _ in updateState() }
    }

    private func updateState() {
        let newState: PetState

        switch session.status {
        case .running:
            if let tool = session.lastToolName {
                switch tool {
                case "Read": newState = .reading
                case "Grep", "Glob": newState = .searching
                case "Bash": newState = PetState.refineBash(command: session.lastToolCommand ?? "")
                case "Write", "Edit": newState = .coding
                case "Agent": newState = .thinking
                default: newState = .coding
                }
            } else if case .responding = session.assistantState {
                newState = .thinking
            } else {
                newState = .thinking
            }
            idleSince = Date()

        case .waitingForInput:
            // Play success animation when transitioning from running to waiting
            if previousStatus == .running && currentState != .success {
                newState = .success
            } else if currentState == .success {
                // Already playing success, let it finish
                return
            } else {
                newState = .idle
            }

        case .error: newState = .error
        case .idle: newState = .idle
        }

        previousStatus = session.status

        if newState != currentState {
            currentState = newState
            currentFrame = 0
            oneShotDone = false
            startAnimation()
        }
    }

    private func startAnimation() {
        timer?.invalidate()
        let state = currentState
        timer = Timer.scheduledTimer(withTimeInterval: state.frameDuration, repeats: true) { _ in
            let count = PetFrameCache.shared.framesFor(state: state).count
            guard count > 0 else { return }

            if state.loops {
                currentFrame = (currentFrame + 1) % count
            } else if currentFrame < count - 1 {
                currentFrame += 1
            } else if !oneShotDone {
                oneShotDone = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if currentState == state {
                        currentState = .idle
                        currentFrame = 0
                        startAnimation()
                    }
                }
            }

        }
    }
}
