import Foundation
import SwiftUI

/// Monitors claude.ai usage limits by reading the settings page from Chrome via AppleScript.
class UsageMonitor: NSObject, ObservableObject {
    static let shared = UsageMonitor()

    @Published var sessionUtilization: Double = 0  // 0.0–1.0
    @Published var weeklyUtilization: Double = 0
    @Published var sonnetUtilization: Double = 0
    @Published var sessionResetText: String = ""
    @Published var weeklyResetText: String = ""
    @Published var isLoggedIn: Bool = false
    @Published var lastUpdated: Date?

    private var refreshTimer: Timer?

    func startMonitoring(interval: TimeInterval = 120) {
        fetchUsageFromChrome()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.fetchUsageFromChrome()
        }
    }

    func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh() {
        fetchUsageFromChrome()
    }

    func openUsageInBrowser() {
        if let url = URL(string: "https://claude.ai/settings/usage") {
            NSWorkspace.shared.open(url)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.fetchUsageFromChrome()
        }
    }

    private func fetchUsageFromChrome() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            // First, reload the Chrome tab to get fresh data
            let reloadScript = """
            tell application "Google Chrome"
                repeat with w in windows
                    repeat with t in tabs of w
                        if URL of t contains "claude.ai/settings" then
                            tell t to reload
                            exit repeat
                        end if
                    end repeat
                end repeat
            end tell
            """
            let reloadAS = NSAppleScript(source: reloadScript)
            var reloadErr: NSDictionary?
            reloadAS?.executeAndReturnError(&reloadErr)

            // Wait for page to load
            Thread.sleep(forTimeInterval: 3.0)

            let script = """
            tell application "Google Chrome"
                set resultText to ""
                repeat with w in windows
                    repeat with t in tabs of w
                        if URL of t contains "claude.ai/settings" then
                            set resultText to execute t javascript "(function(){ var result = {loggedIn:false,session:0,weekly:0,sonnet:0,sessionReset:'',weeklyReset:''}; var allText = document.body ? document.body.innerText : ''; if (!allText.includes('% used')) return JSON.stringify(result); result.loggedIn = true; var sm = allText.match(/Current session[\\\\s\\\\S]*?(\\\\d+)%\\\\s*used/); if (sm) result.session = parseInt(sm[1]); var rm = allText.match(/Resets in ([^\\\\n]+)/); if (rm) result.sessionReset = rm[1].trim(); var wm = allText.match(/All models[\\\\s\\\\S]*?(\\\\d+)%\\\\s*used/); if (wm) result.weekly = parseInt(wm[1]); var wr = allText.match(/Resets (\\\\w+ \\\\d+:\\\\d+ [AP]M)/); if (wr) result.weeklyReset = wr[1].trim(); var sn = allText.match(/Sonnet only[\\\\s\\\\S]*?(\\\\d+)%\\\\s*used/); if (sn) result.sonnet = parseInt(sn[1]); return JSON.stringify(result); })()"
                            exit repeat
                        end if
                    end repeat
                    if resultText is not "" then exit repeat
                end repeat
                return resultText
            end tell
            """

            let appleScript = NSAppleScript(source: script)
            var error: NSDictionary?
            let output = appleScript?.executeAndReturnError(&error)

            guard let jsonStr = output?.stringValue,
                  !jsonStr.isEmpty,
                  let data = jsonStr.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoggedIn = parsed["loggedIn"] as? Bool ?? false
                if self.isLoggedIn {
                    self.sessionUtilization = Double(parsed["session"] as? Int ?? 0) / 100.0
                    self.weeklyUtilization = Double(parsed["weekly"] as? Int ?? 0) / 100.0
                    self.sonnetUtilization = Double(parsed["sonnet"] as? Int ?? 0) / 100.0
                    self.sessionResetText = parsed["sessionReset"] as? String ?? ""
                    self.weeklyResetText = parsed["weeklyReset"] as? String ?? ""
                    self.lastUpdated = Date()
                }
            }
        }
    }
}
