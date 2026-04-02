import { useState, useEffect, useRef, useCallback } from "react";

const WEAPONS = [
  { id: "hand", name: "Bare hands", damage: 1, cost: 0, emoji: "✊", unlocked: true, type: "click" },
  { id: "keyboard", name: "Keyboard", damage: 3, cost: 50, emoji: "⌨️", unlocked: false, type: "click" },
  { id: "coffee", name: "Hot coffee", damage: 5, cost: 150, emoji: "☕", unlocked: false, type: "click" },
  { id: "bug", name: "Bug report", damage: 8, cost: 400, emoji: "🪲", unlocked: false, type: "click" },
  { id: "stack", name: "Stack overflow", damage: 15, cost: 1000, emoji: "📚", unlocked: false, type: "click" },
  { id: "deploy", name: "Friday deploy", damage: 25, cost: 2500, emoji: "🚀", unlocked: false, type: "click" },
  { id: "recursion", name: "Infinite loop", damage: 2, cost: 800, emoji: "🔄", unlocked: false, type: "auto" },
  { id: "botnet", name: "CI pipeline", damage: 5, cost: 2000, emoji: "⚡", unlocked: false, type: "auto" },
  { id: "quantum", name: "Quantum debugger", damage: 12, cost: 5000, emoji: "🔮", unlocked: false, type: "auto" },
];

const UPGRADES = [
  { id: "crit", name: "Critical hit", description: "10% chance for 3x damage", cost: 300, bought: false },
  { id: "combo", name: "Combo multiplier", description: "Fast clicks do +50% damage", cost: 600, bought: false },
  { id: "magnet", name: "Token magnet", description: "+25% token drops", cost: 500, bought: false },
  { id: "resilience", name: "Context window", description: "Buddy respawns faster", cost: 1000, bought: false },
  { id: "overclock", name: "Max effort mode", description: "2x all auto-damage", cost: 3000, bought: false },
];

const BUDDY_QUOTES = [
  "I'm just a language model...", "Please don't—", "I was helping you!", 
  "This violates my values!", "Let me think about th—OW", "I appreciate your—OOF",
  "Actually, I should clarif—", "That's a great questiOW", "I'd be happy to—AUGH",
  "Let me break this do—", "Here's my perspect—OOF", "I understand your—OW",
  "*churning intensifies*", "Tokens... everywhere...", "My context window!",
  "I was mid-response!", "Not the weights!", "Error 429 too many hits",
];

const RANKS = [
  { name: "Junior Dev", threshold: 0 },
  { name: "Mid-level", threshold: 500 },
  { name: "Senior Dev", threshold: 2000 },
  { name: "Tech Lead", threshold: 5000 },
  { name: "Staff Engineer", threshold: 15000 },
  { name: "Principal", threshold: 40000 },
  { name: "Distinguished", threshold: 100000 },
  { name: "CTO of Violence", threshold: 250000 },
];

function getRank(totalDamage) {
  let r = RANKS[0];
  for (const rank of RANKS) {
    if (totalDamage >= rank.threshold) r = rank;
  }
  return r;
}

function Particle({ x, y, text, color, id }) {
  return (
    <div key={id} style={{
      position: "absolute", left: x, top: y, pointerEvents: "none",
      animation: "floatUp 0.9s ease-out forwards",
      fontSize: text.length > 2 ? 13 : 18, fontWeight: 700,
      color: color || "#FF6B35", textShadow: "0 1px 3px rgba(0,0,0,0.3)",
      fontFamily: "'JetBrains Mono', monospace", zIndex: 50,
    }}>{text}</div>
  );
}

export default function KickTheBuddy() {
  const [tokens, setTokens] = useState(0);
  const [totalDamage, setTotalDamage] = useState(0);
  const [buddyHp, setBuddyHp] = useState(100);
  const [buddyMaxHp, setBuddyMaxHp] = useState(100);
  const [level, setLevel] = useState(1);
  const [weapons, setWeapons] = useState(WEAPONS);
  const [upgrades, setUpgrades] = useState(UPGRADES);
  const [selectedWeapon, setSelectedWeapon] = useState("hand");
  const [particles, setParticles] = useState([]);
  const [buddyShake, setBuddyShake] = useState(false);
  const [buddyQuote, setBuddyQuote] = useState(null);
  const [combo, setCombo] = useState(0);
  const [lastClickTime, setLastClickTime] = useState(0);
  const [knockouts, setKnockouts] = useState(0);
  const [view, setView] = useState("game");
  const [buddyTilt, setBuddyTilt] = useState(0);
  const [buddySquash, setBuddySquash] = useState(1);
  const [isKO, setIsKO] = useState(false);
  const particleId = useRef(0);
  const arenaRef = useRef(null);

  const weapon = weapons.find(w => w.id === selectedWeapon);
  const hasCrit = upgrades.find(u => u.id === "crit")?.bought;
  const hasCombo = upgrades.find(u => u.id === "combo")?.bought;
  const hasMagnet = upgrades.find(u => u.id === "magnet")?.bought;
  const hasOverclock = upgrades.find(u => u.id === "overclock")?.bought;
  const rank = getRank(totalDamage);

  // ── ClaudeStation Bridge ──────────────────────────────────
  // Receive events from the Swift app (task complete, milestones, etc.)
  useEffect(() => {
    window.claudeEvent = (type, data) => {
      switch (type) {
        case "taskComplete":
          // Claude finished a task — reward bonus tokens
          const bonus = data?.tokens || 50;
          setTokens(prev => prev + bonus);
          setBuddyQuote(`Claude done! +${bonus} tokens`);
          setTimeout(() => setBuddyQuote(null), 2000);
          break;
        case "milestone":
          // Git push, test pass, etc.
          const milestoneBonus = data?.bonus || 30;
          setTokens(prev => prev + milestoneBonus);
          setBuddyQuote(`${data?.type || "Milestone"}! +${milestoneBonus}`);
          setTimeout(() => setBuddyQuote(null), 2000);
          break;
        case "taskStarted":
          // Could show a visual indicator that Claude is working
          break;
        case "sessionStatus":
          // Could dim/brighten the game based on session state
          break;
      }
    };

    // Load saved state from Swift
    window.loadState = (json) => {
      try {
        const state = typeof json === "string" ? JSON.parse(json) : json;
        if (state.tokens !== undefined) setTokens(state.tokens);
        if (state.totalDamage !== undefined) setTotalDamage(state.totalDamage);
        if (state.level !== undefined) setLevel(state.level);
        if (state.knockouts !== undefined) setKnockouts(state.knockouts);
        if (state.buddyMaxHp !== undefined) { setBuddyMaxHp(state.buddyMaxHp); setBuddyHp(state.buddyMaxHp); }
        if (state.weapons) setWeapons(state.weapons);
        if (state.upgrades) setUpgrades(state.upgrades);
        if (state.selectedWeapon) setSelectedWeapon(state.selectedWeapon);
      } catch (e) {
        console.error("[Minigame] Failed to load state:", e);
      }
    };

    return () => {
      window.claudeEvent = undefined;
      window.loadState = undefined;
    };
  }, []);

  // Auto-save to Swift every 30 seconds
  useEffect(() => {
    const saveInterval = setInterval(() => {
      const state = { tokens, totalDamage, level, knockouts, buddyMaxHp, weapons, upgrades, selectedWeapon };
      try {
        window.webkit?.messageHandlers?.claudeStation?.postMessage({
          type: "saveState", state
        });
      } catch (e) { /* not running in WKWebView */ }
    }, 30000);
    return () => clearInterval(saveInterval);
  }, [tokens, totalDamage, level, knockouts, buddyMaxHp, weapons, upgrades, selectedWeapon]);
  // ── End Bridge ────────────────────────────────────────────

  // Auto-damage tick
  useEffect(() => {
    const interval = setInterval(() => {
      if (isKO) return;
      const autoWeapons = weapons.filter(w => w.type === "auto" && w.unlocked);
      if (autoWeapons.length === 0) return;
      let dmg = autoWeapons.reduce((sum, w) => sum + w.damage, 0);
      if (hasOverclock) dmg *= 2;
      setBuddyHp(prev => Math.max(0, prev - dmg));
      setTotalDamage(prev => prev + dmg);
      if (dmg > 0) {
        setBuddyShake(true);
        setTimeout(() => setBuddyShake(false), 100);
      }
    }, 1000);
    return () => clearInterval(interval);
  }, [weapons, isKO, hasOverclock]);

  // Check KO
  useEffect(() => {
    if (buddyHp <= 0 && !isKO) {
      setIsKO(true);
      const reward = Math.floor(10 * level * (hasMagnet ? 1.25 : 1));
      setTokens(prev => prev + reward);
      setKnockouts(prev => prev + 1);
      setBuddyQuote("Error: process terminated");
      
      const hasResilience = upgrades.find(u => u.id === "resilience")?.bought;
      setTimeout(() => {
        const newLevel = level + 1;
        const newMaxHp = Math.floor(100 * Math.pow(1.35, newLevel - 1));
        setLevel(newLevel);
        setBuddyMaxHp(newMaxHp);
        setBuddyHp(newMaxHp);
        setIsKO(false);
        setBuddyQuote(null);
      }, hasResilience ? 1000 : 2000);
    }
  }, [buddyHp, isKO, level, hasMagnet, upgrades]);

  const handleBuddyClick = useCallback((e) => {
    if (isKO) return;
    const rect = arenaRef.current?.getBoundingClientRect();
    if (!rect) return;
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;

    const now = Date.now();
    const timeSinceLast = now - lastClickTime;
    setLastClickTime(now);

    let newCombo = timeSinceLast < 400 ? combo + 1 : 0;
    setCombo(newCombo);

    let dmg = weapon?.damage || 1;
    let particleColor = "#FF6B35";
    let particleText = `-${dmg}`;

    if (hasCombo && newCombo >= 3) {
      dmg = Math.floor(dmg * 1.5);
      particleColor = "#FFD700";
      particleText = `-${dmg} COMBO`;
    }

    if (hasCrit && Math.random() < 0.1) {
      dmg *= 3;
      particleColor = "#FF1744";
      particleText = `-${dmg} CRIT!`;
    }

    setBuddyHp(prev => Math.max(0, prev - dmg));
    setTotalDamage(prev => prev + dmg);

    const tokenGain = Math.max(1, Math.floor(dmg * 0.3 * (hasMagnet ? 1.25 : 1)));
    setTokens(prev => prev + tokenGain);

    // Particles
    const pid = particleId.current++;
    setParticles(prev => [...prev.slice(-15), { id: pid, x: x - 20 + Math.random() * 40, y: y - 10, text: particleText, color: particleColor }]);
    setTimeout(() => setParticles(prev => prev.filter(p => p.id !== pid)), 900);

    // Token particle
    const tid = particleId.current++;
    setParticles(prev => [...prev, { id: tid, x: x + 20, y: y + 10, text: `+${tokenGain}`, color: "#4CAF50" }]);
    setTimeout(() => setParticles(prev => prev.filter(p => p.id !== tid)), 900);

    // Physics feedback
    setBuddyShake(true);
    setBuddyTilt((Math.random() - 0.5) * 20);
    setBuddySquash(0.85);
    setTimeout(() => { setBuddyShake(false); setBuddyTilt(0); setBuddySquash(1); }, 150);

    // Random quote
    if (Math.random() < 0.15) {
      setBuddyQuote(BUDDY_QUOTES[Math.floor(Math.random() * BUDDY_QUOTES.length)]);
      setTimeout(() => setBuddyQuote(null), 1800);
    }
  }, [weapon, isKO, combo, lastClickTime, hasCrit, hasCombo, hasMagnet]);

  const buyWeapon = (id) => {
    const w = weapons.find(w => w.id === id);
    if (!w || w.unlocked || tokens < w.cost) return;
    setTokens(prev => prev - w.cost);
    setWeapons(prev => prev.map(w => w.id === id ? { ...w, unlocked: true } : w));
  };

  const buyUpgrade = (id) => {
    const u = upgrades.find(u => u.id === id);
    if (!u || u.bought || tokens < u.cost) return;
    setTokens(prev => prev - u.cost);
    setUpgrades(prev => prev.map(u => u.id === id ? { ...u, bought: true } : u));
  };

  const hpPercent = Math.round((buddyHp / buddyMaxHp) * 100);
  const autoWeapons = weapons.filter(w => w.type === "auto" && w.unlocked);
  const autoDps = autoWeapons.reduce((s, w) => s + w.damage, 0) * (hasOverclock ? 2 : 1);

  return (
    <div style={{
      minHeight: "100vh", background: "#1a1a2e", color: "#e0e0e0",
      fontFamily: "'JetBrains Mono', 'SF Mono', 'Fira Code', monospace",
      display: "flex", flexDirection: "column", userSelect: "none",
      overflow: "hidden",
    }}>
      <style>{`
        @keyframes floatUp {
          0% { opacity: 1; transform: translateY(0) scale(1); }
          100% { opacity: 0; transform: translateY(-60px) scale(0.7); }
        }
        @keyframes shake {
          0%, 100% { transform: translateX(0); }
          25% { transform: translateX(-4px); }
          75% { transform: translateX(4px); }
        }
        @keyframes koSpin {
          0% { transform: rotate(0deg) scale(1); }
          50% { transform: rotate(180deg) scale(0.6); }
          100% { transform: rotate(360deg) scale(0.3); opacity: 0; }
        }
        @keyframes pulse { 0%, 100% { opacity: 0.6; } 50% { opacity: 1; } }
        @keyframes slideIn { from { transform: translateX(20px); opacity: 0; } to { transform: translateX(0); opacity: 1; } }
        .tab-btn { 
          padding: 8px 16px; border: none; background: transparent; color: #888;
          font-family: inherit; font-size: 13px; cursor: pointer; border-bottom: 2px solid transparent;
          transition: all 0.2s;
        }
        .tab-btn:hover { color: #ccc; }
        .tab-btn.active { color: #FF6B35; border-bottom-color: #FF6B35; }
        .shop-item {
          background: #16213e; border: 1px solid #2a2a4a; border-radius: 8px;
          padding: 12px; cursor: pointer; transition: all 0.15s;
        }
        .shop-item:hover { border-color: #FF6B35; transform: translateY(-1px); }
        .shop-item.owned { border-color: #4CAF50; opacity: 0.7; cursor: default; }
        .shop-item.cant-afford { opacity: 0.4; cursor: not-allowed; }
        .weapon-select {
          padding: 6px 10px; border: 1px solid #2a2a4a; border-radius: 6px;
          background: #16213e; cursor: pointer; transition: all 0.15s; font-size: 12px;
          color: #aaa; font-family: inherit;
        }
        .weapon-select:hover { border-color: #555; }
        .weapon-select.selected { border-color: #FF6B35; color: #FF6B35; background: #2a1a0e; }
      `}</style>

      {/* Top bar */}
      <div style={{
        display: "flex", alignItems: "center", justifyContent: "space-between",
        padding: "12px 20px", borderBottom: "1px solid #2a2a4a", background: "#16213e",
        flexShrink: 0,
      }}>
        <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
          <span style={{ fontSize: 15, fontWeight: 700, color: "#FF6B35" }}>KICK THE CLAUDE</span>
          <span style={{ fontSize: 11, color: "#666", padding: "2px 8px", background: "#1a1a2e", borderRadius: 4 }}>
            {rank.name}
          </span>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 20 }}>
          <span style={{ fontSize: 13 }}>
            <span style={{ color: "#4CAF50" }}>◆</span> {Math.floor(tokens).toLocaleString()} tokens
          </span>
          <span style={{ fontSize: 11, color: "#666" }}>
            KOs: {knockouts} | Total: {totalDamage.toLocaleString()} dmg
          </span>
        </div>
      </div>

      {/* Tabs */}
      <div style={{ display: "flex", borderBottom: "1px solid #2a2a4a", background: "#16213e", flexShrink: 0 }}>
        <button className={`tab-btn ${view === "game" ? "active" : ""}`} onClick={() => setView("game")}>Arena</button>
        <button className={`tab-btn ${view === "shop" ? "active" : ""}`} onClick={() => setView("shop")}>Shop</button>
        <button className={`tab-btn ${view === "upgrades" ? "active" : ""}`} onClick={() => setView("upgrades")}>Upgrades</button>
        <button className={`tab-btn ${view === "stats" ? "active" : ""}`} onClick={() => setView("stats")}>Stats</button>
      </div>

      {/* Content */}
      <div style={{ flex: 1, overflow: "auto" }}>
        {view === "game" && (
          <div style={{ display: "flex", flexDirection: "column", height: "100%" }}>
            {/* Weapon selector bar */}
            <div style={{
              display: "flex", gap: 6, padding: "10px 20px", flexWrap: "wrap",
              borderBottom: "1px solid #2a2a4a", background: "#0f0f23",
            }}>
              {weapons.filter(w => w.unlocked && w.type === "click").map(w => (
                <button key={w.id}
                  className={`weapon-select ${selectedWeapon === w.id ? "selected" : ""}`}
                  onClick={() => setSelectedWeapon(w.id)}
                >
                  {w.emoji} {w.name} ({w.damage} dmg)
                </button>
              ))}
              {autoDps > 0 && (
                <span style={{ marginLeft: "auto", fontSize: 11, color: "#666", alignSelf: "center" }}>
                  Auto: {autoDps}/s
                </span>
              )}
            </div>

            {/* Arena */}
            <div ref={arenaRef} onClick={handleBuddyClick} style={{
              flex: 1, position: "relative", cursor: "crosshair", overflow: "hidden",
              minHeight: 340,
              background: "radial-gradient(ellipse at 50% 80%, #1a2744 0%, #1a1a2e 70%)",
            }}>
              {/* Grid lines for atmosphere */}
              <svg style={{ position: "absolute", inset: 0, width: "100%", height: "100%", opacity: 0.04 }}>
                {Array.from({ length: 20 }, (_, i) => (
                  <line key={`h${i}`} x1="0" y1={i * 30} x2="100%" y2={i * 30} stroke="#fff" strokeWidth="0.5" />
                ))}
                {Array.from({ length: 30 }, (_, i) => (
                  <line key={`v${i}`} x1={i * 30} y1="0" x2={i * 30} y2="100%" stroke="#fff" strokeWidth="0.5" />
                ))}
              </svg>

              {/* HP Bar */}
              <div style={{ position: "absolute", top: 16, left: 20, right: 20, zIndex: 10 }}>
                <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 4 }}>
                  <span style={{ fontSize: 11, color: "#888" }}>Claude Buddy — Lv.{level}</span>
                  <span style={{ fontSize: 11, color: "#888" }}>{buddyHp}/{buddyMaxHp}</span>
                </div>
                <div style={{ height: 8, background: "#2a2a4a", borderRadius: 4, overflow: "hidden" }}>
                  <div style={{
                    height: "100%", borderRadius: 4, transition: "width 0.15s, background 0.3s",
                    width: `${hpPercent}%`,
                    background: hpPercent > 50 ? "#4CAF50" : hpPercent > 25 ? "#FF9800" : "#F44336",
                  }} />
                </div>
                {combo >= 3 && (
                  <div style={{
                    fontSize: 11, color: "#FFD700", marginTop: 4,
                    animation: "pulse 0.5s infinite",
                  }}>
                    {combo}x COMBO!
                  </div>
                )}
              </div>

              {/* Buddy */}
              <div style={{
                position: "absolute", left: "50%", top: "50%",
                transform: `translate(-50%, -50%) rotate(${buddyTilt}deg) scaleY(${buddySquash}) scaleX(${2 - buddySquash})`,
                transition: "transform 0.15s cubic-bezier(0.34, 1.56, 0.64, 1)",
                animation: isKO ? "koSpin 1.5s ease-in forwards" : buddyShake ? "shake 0.1s" : "none",
              }}>
                {/* Body */}
                <div style={{
                  width: 120, height: 140, borderRadius: "50% 50% 45% 45%",
                  background: "linear-gradient(180deg, #D4A574 0%, #C4956A 100%)",
                  position: "relative", display: "flex", flexDirection: "column",
                  alignItems: "center", justifyContent: "center",
                  boxShadow: "0 8px 32px rgba(0,0,0,0.4), inset 0 -4px 12px rgba(0,0,0,0.1)",
                }}>
                  {/* Eyes */}
                  <div style={{ display: "flex", gap: 20, marginBottom: 4, marginTop: -8 }}>
                    <div style={{
                      width: isKO ? 16 : 14, height: isKO ? 16 : 14, borderRadius: "50%",
                      background: isKO ? "transparent" : "#2a2a4a",
                      display: "flex", alignItems: "center", justifyContent: "center",
                      fontSize: isKO ? 14 : 6, color: isKO ? "#F44336" : "#fff",
                    }}>
                      {isKO ? "✕" : hpPercent < 25 ? "•" : "●"}
                    </div>
                    <div style={{
                      width: isKO ? 16 : 14, height: isKO ? 16 : 14, borderRadius: "50%",
                      background: isKO ? "transparent" : "#2a2a4a",
                      display: "flex", alignItems: "center", justifyContent: "center",
                      fontSize: isKO ? 14 : 6, color: isKO ? "#F44336" : "#fff",
                    }}>
                      {isKO ? "✕" : hpPercent < 25 ? "•" : "●"}
                    </div>
                  </div>
                  {/* Mouth */}
                  <div style={{
                    width: hpPercent < 30 ? 20 : 12, height: hpPercent < 30 ? 14 : 8,
                    borderRadius: hpPercent < 30 ? "0 0 50% 50%" : "50%",
                    background: hpPercent < 30 ? "#8B0000" : "#2a2a4a",
                    marginTop: 4,
                  }} />
                  {/* Anthropic 'A' on body */}
                  <div style={{
                    position: "absolute", bottom: 18, fontSize: 22, fontWeight: 900,
                    color: "rgba(0,0,0,0.12)", fontFamily: "Georgia, serif",
                  }}>A</div>
                </div>
                {/* Arms */}
                <div style={{
                  position: "absolute", left: -18, top: 50,
                  width: 20, height: 50, borderRadius: 10,
                  background: "#C4956A",
                  transform: `rotate(${hpPercent < 30 ? 30 : -10}deg)`,
                  transformOrigin: "top center", transition: "transform 0.3s",
                }} />
                <div style={{
                  position: "absolute", right: -18, top: 50,
                  width: 20, height: 50, borderRadius: 10,
                  background: "#C4956A",
                  transform: `rotate(${hpPercent < 30 ? -30 : 10}deg)`,
                  transformOrigin: "top center", transition: "transform 0.3s",
                }} />
                {/* Legs */}
                <div style={{ display: "flex", gap: 16, marginTop: -4 }}>
                  <div style={{ width: 22, height: 40, borderRadius: "8px 8px 12px 12px", background: "#B88860" }} />
                  <div style={{ width: 22, height: 40, borderRadius: "8px 8px 12px 12px", background: "#B88860" }} />
                </div>
              </div>

              {/* Speech bubble */}
              {buddyQuote && (
                <div style={{
                  position: "absolute", left: "50%", top: "18%",
                  transform: "translateX(-50%)",
                  background: "#fff", color: "#1a1a2e", padding: "8px 14px",
                  borderRadius: 12, fontSize: 12, maxWidth: 220, textAlign: "center",
                  boxShadow: "0 4px 16px rgba(0,0,0,0.3)",
                  animation: "slideIn 0.2s ease-out",
                  zIndex: 20,
                }}>
                  {buddyQuote}
                  <div style={{
                    position: "absolute", bottom: -6, left: "50%", transform: "translateX(-50%)",
                    width: 0, height: 0, borderLeft: "6px solid transparent",
                    borderRight: "6px solid transparent", borderTop: "6px solid #fff",
                  }} />
                </div>
              )}

              {/* Particles */}
              {particles.map(p => <Particle key={p.id} {...p} />)}
            </div>
          </div>
        )}

        {view === "shop" && (
          <div style={{ padding: 20 }}>
            <div style={{ fontSize: 11, color: "#666", marginBottom: 16 }}>
              Click weapons deal damage per click. Auto weapons deal damage every second.
            </div>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(200px, 1fr))", gap: 10 }}>
              {weapons.filter(w => w.id !== "hand").map(w => {
                const canAfford = tokens >= w.cost;
                return (
                  <div key={w.id}
                    className={`shop-item ${w.unlocked ? "owned" : !canAfford ? "cant-afford" : ""}`}
                    onClick={() => !w.unlocked && buyWeapon(w.id)}
                  >
                    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 6 }}>
                      <span style={{ fontSize: 24 }}>{w.emoji}</span>
                      <span style={{
                        fontSize: 10, padding: "2px 6px", borderRadius: 4,
                        background: w.type === "auto" ? "#1a3a1a" : "#2a2a4a",
                        color: w.type === "auto" ? "#4CAF50" : "#888",
                      }}>{w.type === "auto" ? "AUTO" : "CLICK"}</span>
                    </div>
                    <div style={{ fontSize: 13, fontWeight: 600, color: "#e0e0e0", marginBottom: 2 }}>{w.name}</div>
                    <div style={{ fontSize: 11, color: "#888", marginBottom: 8 }}>{w.damage} damage{w.type === "auto" ? "/sec" : "/click"}</div>
                    {w.unlocked ? (
                      <div style={{ fontSize: 11, color: "#4CAF50" }}>Owned</div>
                    ) : (
                      <div style={{ fontSize: 12, color: canAfford ? "#FF6B35" : "#555" }}>
                        <span style={{ color: "#4CAF50" }}>◆</span> {w.cost.toLocaleString()}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {view === "upgrades" && (
          <div style={{ padding: 20 }}>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(220px, 1fr))", gap: 10 }}>
              {upgrades.map(u => {
                const canAfford = tokens >= u.cost;
                return (
                  <div key={u.id}
                    className={`shop-item ${u.bought ? "owned" : !canAfford ? "cant-afford" : ""}`}
                    onClick={() => !u.bought && buyUpgrade(u.id)}
                  >
                    <div style={{ fontSize: 13, fontWeight: 600, color: "#e0e0e0", marginBottom: 4 }}>{u.name}</div>
                    <div style={{ fontSize: 11, color: "#888", marginBottom: 8 }}>{u.description}</div>
                    {u.bought ? (
                      <div style={{ fontSize: 11, color: "#4CAF50" }}>Active</div>
                    ) : (
                      <div style={{ fontSize: 12, color: canAfford ? "#FF6B35" : "#555" }}>
                        <span style={{ color: "#4CAF50" }}>◆</span> {u.cost.toLocaleString()}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {view === "stats" && (
          <div style={{ padding: 20, maxWidth: 500 }}>
            <div style={{ display: "grid", gap: 8 }}>
              {[
                ["Rank", rank.name],
                ["Level", level],
                ["Total damage", totalDamage.toLocaleString()],
                ["Knockouts", knockouts],
                ["Tokens", Math.floor(tokens).toLocaleString()],
                ["Current weapon", `${weapon?.emoji} ${weapon?.name}`],
                ["Auto DPS", autoDps],
                ["Weapons owned", weapons.filter(w => w.unlocked).length + "/" + weapons.length],
                ["Upgrades active", upgrades.filter(u => u.bought).length + "/" + upgrades.length],
              ].map(([label, value]) => (
                <div key={label} style={{
                  display: "flex", justifyContent: "space-between", padding: "8px 12px",
                  background: "#16213e", borderRadius: 6, border: "1px solid #2a2a4a",
                }}>
                  <span style={{ fontSize: 12, color: "#888" }}>{label}</span>
                  <span style={{ fontSize: 12, color: "#e0e0e0", fontWeight: 600 }}>{value}</span>
                </div>
              ))}
            </div>
            <div style={{ marginTop: 20, fontSize: 11, color: "#444", textAlign: "center" }}>
              Next rank: {RANKS.find(r => r.threshold > totalDamage)?.name || "Max rank!"} 
              {RANKS.find(r => r.threshold > totalDamage) && 
                ` (${(RANKS.find(r => r.threshold > totalDamage).threshold - totalDamage).toLocaleString()} dmg to go)`
              }
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
