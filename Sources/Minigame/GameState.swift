import Foundation
import Combine

// MARK: - WeaponType

enum WeaponType: String, CaseIterable, Codable, Hashable {
    case bareHands
    case bat
    case wreckingBall
    case bugSwarm
    case keyboard
    case coffee

    var cost: Int {
        switch self {
        case .bareHands:    return 0
        case .bat:          return 100
        case .bugSwarm:     return 200
        case .keyboard:     return 150
        case .coffee:       return 250
        case .wreckingBall: return 300
        }
    }

    var baseDamage: Int {
        switch self {
        case .bareHands:    return 5
        case .bat:          return 12
        case .wreckingBall: return 30
        case .bugSwarm:     return 18
        case .keyboard:     return 15
        case .coffee:       return 22
        }
    }

    var displayName: String {
        switch self {
        case .bareHands:    return "Bare Hands"
        case .bat:          return "Bat"
        case .wreckingBall: return "Wrecking Ball"
        case .bugSwarm:     return "Bug Swarm"
        case .keyboard:     return "Keyboard"
        case .coffee:       return "Coffee"
        }
    }

    var iconName: String {
        switch self {
        case .bareHands:    return "hand.raised.fill"
        case .bat:          return "figure.cricket"
        case .wreckingBall: return "circle.circle.fill"
        case .bugSwarm:     return "ladybug.fill"
        case .keyboard:     return "keyboard.fill"
        case .coffee:       return "cup.and.saucer.fill"
        }
    }
}

// MARK: - Rank

enum Rank: String, CaseIterable, Codable, Comparable {
    case intern
    case junior
    case mid
    case senior
    case staff
    case principal
    case distinguished
    case fellow
    case ctoOfViolence

    var displayName: String {
        switch self {
        case .intern:        return "Intern"
        case .junior:        return "Junior"
        case .mid:           return "Mid"
        case .senior:        return "Senior"
        case .staff:         return "Staff"
        case .principal:     return "Principal"
        case .distinguished: return "Distinguished"
        case .fellow:        return "Fellow"
        case .ctoOfViolence: return "CTO of Violence"
        }
    }

    var xpRequired: Int {
        switch self {
        case .intern:        return 0
        case .junior:        return 100
        case .mid:           return 300
        case .senior:        return 700
        case .staff:         return 1500
        case .principal:     return 3000
        case .distinguished: return 6000
        case .fellow:        return 12000
        case .ctoOfViolence: return 25000
        }
    }

    static func < (lhs: Rank, rhs: Rank) -> Bool {
        lhs.xpRequired < rhs.xpRequired
    }
}

// MARK: - UpgradeType

enum UpgradeType: String, CaseIterable, Codable, Hashable {
    case critChance
    case comboDuration
    case autoDamage
    case maxHP

    var cost: Int {
        switch self {
        case .critChance:    return 150
        case .comboDuration: return 120
        case .autoDamage:    return 200
        case .maxHP:         return 180
        }
    }

    var maxLevel: Int {
        switch self {
        case .critChance:    return 10
        case .comboDuration: return 8
        case .autoDamage:    return 5
        case .maxHP:         return 10
        }
    }

    var displayName: String {
        switch self {
        case .critChance:    return "Critical Chance"
        case .comboDuration: return "Combo Duration"
        case .autoDamage:    return "Auto Damage"
        case .maxHP:         return "Max HP"
        }
    }

    var description: String {
        switch self {
        case .critChance:    return "+5% critical hit chance per level"
        case .comboDuration: return "+0.5s combo window per level"
        case .autoDamage:    return "+2 passive damage per second per level"
        case .maxHP:         return "+20 max HP per level"
        }
    }
}

// MARK: - GameState

final class GameState: ObservableObject, Codable {

    private static let storageKey = "kickTheClaudeState"

    // MARK: Published Properties

    @Published var hp: Int = 100
    @Published var maxHP: Int = 100
    @Published var tokens: Int = 0
    @Published var level: Int = 1
    @Published var xp: Int = 0
    @Published var totalDamageDealt: Int = 0
    @Published var totalKOs: Int = 0
    @Published var totalHits: Int = 0
    @Published var unlockedWeapons: Set<WeaponType> = [.bareHands]
    @Published var selectedWeapon: WeaponType = .bareHands
    @Published var upgradeLevels: [UpgradeType: Int] = [:]
    @Published var comboCount: Int = 0
    @Published var lastHitTime: Date? = nil

    // MARK: Computed Properties

    var currentRank: Rank {
        var best = Rank.intern
        for rank in Rank.allCases {
            if xp >= rank.xpRequired {
                best = rank
            }
        }
        return best
    }

    var xpForNextRank: Int? {
        let ranks = Rank.allCases
        guard let currentIndex = ranks.firstIndex(of: currentRank),
              currentIndex + 1 < ranks.count else {
            return nil
        }
        return ranks[currentIndex + 1].xpRequired
    }

    var critChancePercent: Int {
        let level = upgradeLevels[.critChance] ?? 0
        return 5 + (level * 5)
    }

    var comboDurationSeconds: Double {
        let level = upgradeLevels[.comboDuration] ?? 0
        return 2.0 + (Double(level) * 0.5)
    }

    var autoDamagePerSecond: Int {
        let level = upgradeLevels[.autoDamage] ?? 0
        return level * 2
    }

    var effectiveMaxHP: Int {
        let level = upgradeLevels[.maxHP] ?? 0
        return 100 + (level * 20)
    }

    // MARK: Init

    init() {}

    // MARK: Methods

    /// Deal damage with the selected weapon. Returns actual damage dealt (includes crit and combo multipliers).
    @discardableResult
    func dealDamage(amount: Int? = nil) -> Int {
        let base = amount ?? selectedWeapon.baseDamage

        // Crit check
        let isCrit = Int.random(in: 1...100) <= critChancePercent
        let afterCrit = isCrit ? base * 2 : base

        // Combo multiplier
        let comboMultiplier = 1.0 + (Double(comboCount) * 0.1)
        let finalDamage = max(1, Int(Double(afterCrit) * comboMultiplier))

        hp = max(0, hp - finalDamage)
        totalDamageDealt += finalDamage

        registerHit()

        // Award XP proportional to damage
        let xpGain = max(1, finalDamage / 2)
        xp += xpGain

        // Level up every 100 XP
        let newLevel = (xp / 100) + 1
        if newLevel > level {
            level = newLevel
        }

        // Check for knockout
        if hp <= 0 {
            knockout()
        }

        return finalDamage
    }

    /// Update combo counter based on timing window.
    func registerHit() {
        let now = Date()
        if let last = lastHitTime, now.timeIntervalSince(last) <= comboDurationSeconds {
            comboCount += 1
        } else {
            comboCount = 1
        }
        lastHitTime = now
        totalHits += 1
    }

    /// Handle a knockout: award tokens and XP, reset HP, increment KO counter.
    func knockout() {
        let tokenReward = 50 + (level * 10)
        awardTokens(tokenReward)
        xp += 25
        totalKOs += 1
        hp = effectiveMaxHP
        maxHP = effectiveMaxHP
        comboCount = 0
        lastHitTime = nil
    }

    /// Attempt to purchase a weapon. Returns true if successful.
    @discardableResult
    func purchaseWeapon(_ weapon: WeaponType) -> Bool {
        guard !unlockedWeapons.contains(weapon) else { return false }
        guard tokens >= weapon.cost else { return false }
        tokens -= weapon.cost
        unlockedWeapons.insert(weapon)
        return true
    }

    /// Attempt to purchase an upgrade level. Returns true if successful.
    @discardableResult
    func purchaseUpgrade(_ upgrade: UpgradeType) -> Bool {
        let currentLevel = upgradeLevels[upgrade] ?? 0
        guard currentLevel < upgrade.maxLevel else { return false }
        guard tokens >= upgrade.cost else { return false }
        tokens -= upgrade.cost
        upgradeLevels[upgrade] = currentLevel + 1

        // If max HP was upgraded, update current and max HP
        if upgrade == .maxHP {
            let newMax = effectiveMaxHP
            hp += 20
            maxHP = newMax
            hp = min(hp, maxHP)
        }

        return true
    }

    /// Award tokens to the player.
    func awardTokens(_ amount: Int) {
        tokens += amount
    }

    // MARK: Persistence

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    static func load() -> GameState {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let state = try? JSONDecoder().decode(GameState.self, from: data) else {
            return GameState()
        }
        return state
    }

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case hp, maxHP, tokens, level, xp
        case totalDamageDealt, totalKOs, totalHits
        case unlockedWeapons, selectedWeapon
        case upgradeLevels
        case comboCount, lastHitTime
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hp = try container.decode(Int.self, forKey: .hp)
        maxHP = try container.decode(Int.self, forKey: .maxHP)
        tokens = try container.decode(Int.self, forKey: .tokens)
        level = try container.decode(Int.self, forKey: .level)
        xp = try container.decode(Int.self, forKey: .xp)
        totalDamageDealt = try container.decode(Int.self, forKey: .totalDamageDealt)
        totalKOs = try container.decode(Int.self, forKey: .totalKOs)
        totalHits = try container.decode(Int.self, forKey: .totalHits)
        unlockedWeapons = try container.decode(Set<WeaponType>.self, forKey: .unlockedWeapons)
        selectedWeapon = try container.decode(WeaponType.self, forKey: .selectedWeapon)
        upgradeLevels = try container.decode([UpgradeType: Int].self, forKey: .upgradeLevels)
        comboCount = try container.decode(Int.self, forKey: .comboCount)
        lastHitTime = try container.decodeIfPresent(Date.self, forKey: .lastHitTime)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hp, forKey: .hp)
        try container.encode(maxHP, forKey: .maxHP)
        try container.encode(tokens, forKey: .tokens)
        try container.encode(level, forKey: .level)
        try container.encode(xp, forKey: .xp)
        try container.encode(totalDamageDealt, forKey: .totalDamageDealt)
        try container.encode(totalKOs, forKey: .totalKOs)
        try container.encode(totalHits, forKey: .totalHits)
        try container.encode(unlockedWeapons, forKey: .unlockedWeapons)
        try container.encode(selectedWeapon, forKey: .selectedWeapon)
        try container.encode(upgradeLevels, forKey: .upgradeLevels)
        try container.encode(comboCount, forKey: .comboCount)
        try container.encodeIfPresent(lastHitTime, forKey: .lastHitTime)
    }
}
