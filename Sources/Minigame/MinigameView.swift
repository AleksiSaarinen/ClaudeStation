import SwiftUI
import SpriteKit

// MARK: - SpriteKit View Wrapper

struct SpriteKitView: NSViewRepresentable {
    let scene: KickTheClaudeScene

    func makeNSView(context: Context) -> SKView {
        let view = SKView()
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        view.presentScene(scene)
        return view
    }

    func updateNSView(_ nsView: SKView, context: Context) {}
}

// MARK: - Minigame View (replaces old WKWebView version)

struct MinigameView: View {
    @ObservedObject var bridge: MinigameBridge
    @State private var showShop = false
    @State private var showEquipBar = true

    var gameState: GameState { bridge.gameState }
    var scene: KickTheClaudeScene { bridge.scene }

    var body: some View {
        ZStack {
            // Game canvas
            SpriteKitView(scene: scene)
                .ignoresSafeArea()

            // HUD overlay
            VStack(spacing: 0) {
                // Top bar: HP + tokens + level
                HStack(spacing: 12) {
                    // HP bar
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.black.opacity(0.3))
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(hpColor)
                                    .frame(width: geo.size.width * hpPercent)
                            }
                        }
                        .frame(width: 100, height: 8)
                        Text("\(gameState.hp)/\(gameState.effectiveMaxHP)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    // Combo
                    if gameState.comboCount > 1 {
                        Text("\(gameState.comboCount)x COMBO")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundStyle(.orange)
                    }

                    Spacer()

                    // Tokens
                    HStack(spacing: 4) {
                        Image(systemName: "bitcoinsign.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                        Text("\(gameState.tokens)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.4))
                .contentShape(Rectangle())

                // XP bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.black.opacity(0.2))
                        Rectangle()
                            .fill(.purple.opacity(0.6))
                            .frame(width: geo.size.width * xpPercent)
                    }
                }
                .frame(height: 3)

                // Rank label + equip bar toggle
                HStack {
                    Text("Lv.\(gameState.level) \(gameState.currentRank.displayName)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.leading, 12)
                        .padding(.top, 2)
                    Spacer()
                }

                // Weapon bar (top)
                VStack(spacing: 0) {
                    if showEquipBar {
                        HStack(spacing: 8) {
                            ForEach(Array(gameState.unlockedWeapons.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { weapon in
                                VStack(spacing: 2) {
                                    Image(systemName: weapon.iconName)
                                        .font(.system(size: 16))
                                    Text(weapon.displayName)
                                        .font(.system(size: 8))
                                }
                                .frame(width: 50, height: 40)
                                .foregroundStyle(gameState.selectedWeapon == weapon ? .white : .white.opacity(0.5))
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(gameState.selectedWeapon == weapon ? .white.opacity(0.2) : .clear)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    gameState.selectedWeapon = weapon
                                    scene.switchWeapon(to: weapon)
                                }
                            }

                            Spacer()

                            VStack(spacing: 2) {
                                Image(systemName: "cart.fill")
                                    .font(.system(size: 16))
                                Text("Shop")
                                    .font(.system(size: 8))
                            }
                            .frame(width: 50, height: 40)
                            .foregroundStyle(.yellow)
                            .contentShape(Rectangle())
                            .onTapGesture { showShop = true }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.4))
                        .contentShape(Rectangle())
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Toggle handle
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { showEquipBar.toggle() }
                    } label: {
                        Image(systemName: showEquipBar ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 40, height: 16)
                            .background(.black.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }

                Spacer()
            }
        }
        .sheet(isPresented: $showShop) {
            ShopView(gameState: gameState)
        }
    }

    private var hpPercent: CGFloat {
        CGFloat(max(0, gameState.hp)) / CGFloat(max(1, gameState.effectiveMaxHP))
    }

    private var hpColor: Color {
        if hpPercent > 0.5 { return .green }
        if hpPercent > 0.2 { return .orange }
        return .red
    }

    private var xpPercent: CGFloat {
        guard let needed = gameState.xpForNextRank, needed > 0 else { return 1.0 }
        let current = gameState.xp - gameState.currentRank.xpRequired
        return CGFloat(max(0, current)) / CGFloat(needed)
    }
}

// MARK: - Shop View

struct ShopView: View {
    @ObservedObject var gameState: GameState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Shop")
                    .font(.title3.bold())
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "bitcoinsign.circle.fill")
                        .foregroundStyle(.yellow)
                    Text("\(gameState.tokens)")
                        .font(.headline.monospaced())
                }
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Weapons
                    Text("Weapons")
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach(WeaponType.allCases, id: \.self) { weapon in
                        if weapon != .bareHands {
                            HStack {
                                Image(systemName: weapon.iconName)
                                    .font(.title3)
                                    .frame(width: 30)
                                VStack(alignment: .leading) {
                                    Text(weapon.displayName)
                                        .font(.subheadline.bold())
                                    Text("Damage: \(weapon.baseDamage)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if gameState.unlockedWeapons.contains(weapon) {
                                    Text("Owned")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                } else {
                                    Button("\(weapon.cost) tokens") {
                                        if gameState.purchaseWeapon(weapon) {
                                            gameState.selectedWeapon = weapon
                                        }
                                    }
                                    .disabled(gameState.tokens < weapon.cost)
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    Divider()

                    // Upgrades
                    Text("Upgrades")
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach(UpgradeType.allCases, id: \.self) { upgrade in
                        let level = gameState.upgradeLevels[upgrade] ?? 0
                        HStack {
                            VStack(alignment: .leading) {
                                Text(upgrade.displayName)
                                    .font(.subheadline.bold())
                                Text(upgrade.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Level \(level)/\(upgrade.maxLevel)")
                                    .font(.caption2)
                                    .foregroundStyle(.purple)
                            }
                            Spacer()
                            if level >= upgrade.maxLevel {
                                Text("MAX")
                                    .font(.caption.bold())
                                    .foregroundStyle(.orange)
                            } else {
                                let cost = upgrade.cost * (level + 1)
                                Button("\(cost) tokens") {
                                    _ = gameState.purchaseUpgrade(upgrade)
                                }
                                .disabled(gameState.tokens < cost)
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
        }
        .frame(width: 350, height: 450)
    }
}
