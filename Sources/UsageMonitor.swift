import Foundation
import SwiftUI

enum PlanType: String, Codable, CaseIterable {
    case team
    case max
    case unknown

    var displayName: String {
        switch self {
        case .team: return "Team"
        case .max: return "Max"
        case .unknown: return "?"
        }
    }

    var shortLabel: String {
        switch self {
        case .team: return "T"
        case .max: return "M"
        case .unknown: return "?"
        }
    }
}

struct PlanUsage: Codable, Equatable {
    var plan: PlanType
    var session: Double = 0
    var weekly: Double = 0
    var sonnet: Double = 0
    var sessionReset: String = ""
    var weeklyReset: String = ""
    var lastUpdated: Date = Date()
}

/// Monitors claude.ai usage limits by reading the settings page from Chrome via AppleScript.
/// Tracks both Team and Max plans independently — switches between them based on which
/// account is logged in to the active Chrome settings tab.
class UsageMonitor: NSObject, ObservableObject {
    static let shared = UsageMonitor()

    @Published var teamUsage: PlanUsage?
    @Published var maxUsage: PlanUsage?
    @Published var currentPlan: PlanType = .unknown
    @Published var isLoggedIn: Bool = false
    @Published var lastUpdated: Date?

    // Backwards-compat accessors mirroring whichever plan is currently logged in.
    // Existing callers in TerminalService / ChatView keep working unchanged.
    var sessionUtilization: Double { currentSnapshot?.session ?? 0 }
    var weeklyUtilization: Double { currentSnapshot?.weekly ?? 0 }
    var sonnetUtilization: Double { currentSnapshot?.sonnet ?? 0 }
    var sessionResetText: String { currentSnapshot?.sessionReset ?? "" }
    var weeklyResetText: String { currentSnapshot?.weeklyReset ?? "" }

    private var currentSnapshot: PlanUsage? {
        switch currentPlan {
        case .team: return teamUsage
        case .max: return maxUsage
        case .unknown: return teamUsage ?? maxUsage
        }
    }

    private let storageKey = "UsageMonitor.PlanSnapshots.v1"
    private let currentPlanKey = "UsageMonitor.CurrentPlan.v1"
    private var refreshTimer: Timer?

    override init() {
        super.init()
        loadSnapshots()
    }

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

    private func loadSnapshots() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let snapshots = try? JSONDecoder().decode([String: PlanUsage].self, from: data) {
            teamUsage = snapshots[PlanType.team.rawValue]
            maxUsage = snapshots[PlanType.max.rawValue]
        }
        if let raw = UserDefaults.standard.string(forKey: currentPlanKey),
           let plan = PlanType(rawValue: raw) {
            currentPlan = plan
        }
    }

    private func saveSnapshots() {
        var snapshots: [String: PlanUsage] = [:]
        if let t = teamUsage { snapshots[PlanType.team.rawValue] = t }
        if let m = maxUsage { snapshots[PlanType.max.rawValue] = m }
        if let data = try? JSONEncoder().encode(snapshots) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        UserDefaults.standard.set(currentPlan.rawValue, forKey: currentPlanKey)
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
                            set resultText to execute t javascript "(function(){ var result = {loggedIn:false,plan:'unknown',planName:'',session:0,weekly:0,sonnet:0,sessionReset:'',weeklyReset:''}; var allText = document.body ? document.body.innerText : ''; if (!allText.includes('% used')) return JSON.stringify(result); result.loggedIn = true; var pm = allText.match(/Your usage limits\\\\s+(Team|Max\\\\s*\\\\d*x?|Pro|Enterprise)/i); if (pm) { result.planName = pm[1].trim(); var p = pm[1].toLowerCase(); if (p.indexOf('team') !== -1 || p.indexOf('enterprise') !== -1) { result.plan = 'team'; } else if (p.indexOf('max') !== -1) { result.plan = 'max'; } } var sm = allText.match(/Current session[\\\\s\\\\S]*?(\\\\d+)%\\\\s*used/); if (sm) result.session = parseInt(sm[1]); var rm = allText.match(/Resets in ([^\\\\n]+)/); if (rm) result.sessionReset = rm[1].trim(); var wm = allText.match(/All models[\\\\s\\\\S]*?(\\\\d+)%\\\\s*used/); if (wm) result.weekly = parseInt(wm[1]); var wr = allText.match(/Resets (\\\\w+ \\\\d+:\\\\d+ [AP]M)/); if (wr) result.weeklyReset = wr[1].trim(); var sn = allText.match(/Sonnet only[\\\\s\\\\S]*?(\\\\d+)%\\\\s*used/); if (sn) result.sonnet = parseInt(sn[1]); return JSON.stringify(result); })()"
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
                let loggedIn = parsed["loggedIn"] as? Bool ?? false
                self.isLoggedIn = loggedIn
                guard loggedIn else { return }

                let planRaw = parsed["plan"] as? String ?? "unknown"
                let detectedPlan = PlanType(rawValue: planRaw) ?? .unknown

                let snapshot = PlanUsage(
                    plan: detectedPlan,
                    session: Double(parsed["session"] as? Int ?? 0) / 100.0,
                    weekly: Double(parsed["weekly"] as? Int ?? 0) / 100.0,
                    sonnet: Double(parsed["sonnet"] as? Int ?? 0) / 100.0,
                    sessionReset: parsed["sessionReset"] as? String ?? "",
                    weeklyReset: parsed["weeklyReset"] as? String ?? "",
                    lastUpdated: Date()
                )

                switch detectedPlan {
                case .team:
                    self.teamUsage = snapshot
                    self.currentPlan = .team
                case .max:
                    self.maxUsage = snapshot
                    self.currentPlan = .max
                case .unknown:
                    // Detection failed — write into whichever was last current to avoid
                    // losing freshly-fetched numbers, but don't change currentPlan.
                    if self.currentPlan == .team {
                        var s = snapshot; s.plan = .team
                        self.teamUsage = s
                    } else if self.currentPlan == .max {
                        var s = snapshot; s.plan = .max
                        self.maxUsage = s
                    }
                }

                self.lastUpdated = Date()
                self.saveSnapshots()
            }
        }
    }
}
