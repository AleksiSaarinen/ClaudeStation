import Foundation
import WebKit
import Combine
import UserNotifications

/// Handles communication between the Kick the Claude minigame (WKWebView) and ClaudeStation
class MinigameBridge: NSObject, ObservableObject, WKScriptMessageHandler {
    
    weak var webView: WKWebView?
    private var cancellables = Set<AnyCancellable>()
    
    @Published var lastNotification: GameNotification?
    
    struct GameNotification: Identifiable {
        let id = UUID()
        let title: String
        let body: String
    }
    
    // MARK: - Setup
    
    /// Configure the WKWebView with the message handler
    func configure(webView: WKWebView) {
        self.webView = webView
        webView.configuration.userContentController.add(self, name: "claudeStation")
    }
    
    // MARK: - Swift → JS (send events to the game)
    
    /// Notify the game that Claude finished a task
    func taskCompleted(durationSeconds: Int) {
        // More tokens for longer tasks (min 20, scales with duration)
        let tokens = min(200, max(20, durationSeconds * 2))
        evaluateJS("window.claudeEvent('taskComplete', { tokens: \(tokens), taskType: 'code' })")
    }
    
    /// Notify the game that Claude started working
    func taskStarted() {
        evaluateJS("window.claudeEvent('taskStarted', {})")
    }
    
    /// Notify the game of a milestone (git push, test pass, etc.)
    func milestone(type: String, bonus: Int) {
        evaluateJS("window.claudeEvent('milestone', { type: '\(type)', bonus: \(bonus) })")
    }
    
    /// Send session status to the game
    func sessionStatusChanged(_ status: String) {
        evaluateJS("window.claudeEvent('sessionStatus', { status: '\(status)' })")
    }
    
    /// Load saved game state
    func loadSavedState() {
        guard let data = UserDefaults.standard.string(forKey: "minigameState") else { return }
        // Escape the JSON string for JS
        let escaped = data
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        evaluateJS("window.loadState('\(escaped)')")
    }
    
    // MARK: - JS → Swift (receive messages from the game)
    
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        
        switch type {
        case "saveState":
            if let state = body["state"],
               let data = try? JSONSerialization.data(withJSONObject: state),
               let json = String(data: data, encoding: .utf8) {
                UserDefaults.standard.set(json, forKey: "minigameState")
            }
            
        case "notification":
            let title = body["title"] as? String ?? ""
            let bodyText = body["body"] as? String ?? ""
            DispatchQueue.main.async {
                self.lastNotification = GameNotification(title: title, body: bodyText)
            }
            // Also send a system notification if the app is in background
            sendSystemNotification(title: title, body: bodyText)
            
        case "achievement":
            let name = body["name"] as? String ?? "Unknown"
            DispatchQueue.main.async {
                self.lastNotification = GameNotification(title: "Achievement Unlocked!", body: name)
            }
            sendSystemNotification(title: "Achievement Unlocked!", body: name)
            
        default:
            break
        }
    }
    
    // MARK: - Helpers
    
    private func evaluateJS(_ js: String) {
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript(js) { _, error in
                if let error = error {
                    print("[MinigameBridge] JS error: \(error.localizedDescription)")
                }
            }
        }
    }
    
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
