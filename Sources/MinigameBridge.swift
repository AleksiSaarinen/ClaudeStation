import Foundation
import Combine
import SpriteKit
import UserNotifications

/// Native bridge between ClaudeStation sessions and the Kick the Claude SpriteKit game
class MinigameBridge: ObservableObject {
    @Published var gameState: GameState
    @Published var lastNotification: GameNotification?

    lazy var scene: KickTheClaudeScene = {
        let s = KickTheClaudeScene(size: CGSize(width: 600, height: 400))
        s.scaleMode = .resizeFill
        s.gameState = gameState
        return s
    }()

    struct GameNotification: Identifiable {
        let id = UUID()
        let title: String
        let body: String
    }

    private var cancellables = Set<AnyCancellable>()

    init() {
        self.gameState = GameState.load()

        // Auto-save on token/level/xp/KO changes (debounced)
        gameState.$tokens
            .merge(with: gameState.$level)
            .merge(with: gameState.$xp)
            .merge(with: gameState.$totalKOs)
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.gameState.save() }
            .store(in: &cancellables)
    }

    // MARK: - Session Events

    func taskCompleted(durationSeconds: Int) {
        let tokens = min(200, max(20, durationSeconds * 2))
        gameState.awardTokens(tokens)
        let note = GameNotification(title: "Task Complete!", body: "+\(tokens) tokens")
        lastNotification = note
    }

    func taskStarted() {
        // Could trigger buddy animation in future
    }

    func milestone(type: String, bonus: Int) {
        gameState.awardTokens(bonus)
        let note = GameNotification(title: "Milestone: \(type)", body: "+\(bonus) bonus tokens!")
        lastNotification = note
        sendSystemNotification(title: note.title, body: note.body)
    }

    func sessionStatusChanged(_ status: String) {
        // Could make buddy react to session state
    }

    // MARK: - Helpers

    private func sendSystemNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
