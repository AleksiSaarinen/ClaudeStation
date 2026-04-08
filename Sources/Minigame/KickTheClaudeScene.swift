import SpriteKit

final class KickTheClaudeScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Properties

    var buddy: BuddyNode!
    var gameState: GameState!
    var weaponController: WeaponController?

    var grabbedBody: SKNode?
    var grabJoint: SKPhysicsJointPin?
    var dragStart: CGPoint = .zero
    var dragStartTime: TimeInterval = 0
    var lastDragPoint: CGPoint = .zero
    var lastDragTime: TimeInterval = 0
    var dragVelocity: CGVector = .zero
    var recentPositions: [(point: CGPoint, time: TimeInterval)] = []

    var autoDamageTimer: TimeInterval = 0
    var isKO: Bool = false

    // Invisible anchor node used as the fixed end of the grab joint.
    private var grabAnchorNode: SKNode?

    // MARK: - Scene Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = .clear

        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
        physicsWorld.contactDelegate = self

        setupEdgeLoop()

        // Create buddy centred horizontally, sitting on the lower third.
        buddy = BuddyNode()
        buddy.position = CGPoint(x: size.width / 2, y: size.height * 0.3)
        addChild(buddy)
        buddy.setupJoints(in: self)

        // Activate the weapon that is currently selected in GameState.
        if let state = gameState {
            switchWeapon(to: state.selectedWeapon)
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        setupEdgeLoop()

        // Keep buddy inside the new bounds.
        if let buddy = buddy {
            let pos = buddy.position
            let clamped = CGPoint(
                x: min(max(pos.x, 40), size.width - 40),
                y: min(max(pos.y, 40), size.height - 40)
            )
            if pos != clamped {
                buddy.position = clamped
            }
        }
    }

    // MARK: - Edge Loop

    private func setupEdgeLoop() {
        // Thick boundary with inset so buddy bounces well before the edge
        let inset = CGRect(x: 5, y: 5, width: frame.width - 10, height: frame.height - 10)
        physicsBody = SKPhysicsBody(edgeLoopFrom: inset)
        physicsBody?.categoryBitMask = wallCategory
        physicsBody?.collisionBitMask = buddyCategory | weaponCategory
        physicsBody?.friction = 0.5
        physicsBody?.restitution = 0.5
    }

    // MARK: - Weapon Switching

    func switchWeapon(to type: WeaponType) {
        weaponController?.deactivate(from: self)
        weaponController = WeaponFactory.controller(for: type)
        weaponController?.activate(in: self)
    }

    // MARK: - Mouse Handling (macOS)

    override func mouseDown(with event: NSEvent) {
        guard !isKO else { return }

        let point = event.location(in: self)
        let now = CACurrentMediaTime()
        dragStart = point
        dragStartTime = now
        lastDragPoint = point
        lastDragTime = now
        dragVelocity = .zero
        recentPositions = [(point, now)]

        // Check if the click lands on a buddy body part.
        if let part = buddy.bodyPart(at: point), let partBody = part.physicsBody {
            grabbedBody = part

            // Create a small invisible anchor to pin against.
            let anchor = SKNode()
            anchor.position = point
            anchor.physicsBody = SKPhysicsBody(circleOfRadius: 1)
            anchor.physicsBody?.isDynamic = false
            addChild(anchor)
            grabAnchorNode = anchor

            let joint = SKPhysicsJointPin.joint(
                withBodyA: anchor.physicsBody!,
                bodyB: partBody,
                anchor: point
            )
            joint.frictionTorque = 0.1
            joint.shouldEnableLimits = false
            physicsWorld.add(joint)
            grabJoint = joint
        } else {
            weaponController?.mouseDown(at: point, in: self)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = event.location(in: self)
        let now = CACurrentMediaTime()

        if grabbedBody != nil, let anchor = grabAnchorNode {
            // Move the anchor so the joint drags the body part along.
            anchor.position = point
        } else {
            weaponController?.mouseDragged(to: point, in: self)
        }

        // Store recent positions (keep last 0.1 seconds worth)
        recentPositions.append((point, now))
        recentPositions = recentPositions.filter { now - $0.time < 0.1 }

        lastDragPoint = point
        lastDragTime = now
    }

    override func mouseUp(with event: NSEvent) {
        let point = event.location(in: self)

        if let grabbed = grabbedBody {
            // Remove the joint and anchor.
            if let joint = grabJoint {
                physicsWorld.remove(joint)
                grabJoint = nil
            }
            grabAnchorNode?.removeFromParent()
            grabAnchorNode = nil

            // Calculate fling velocity from recent position history
            var flingVelocity = CGVector.zero
            if let first = recentPositions.first, let last = recentPositions.last, recentPositions.count >= 2 {
                let dt = last.time - first.time
                if dt > 0.001 {
                    flingVelocity = CGVector(
                        dx: (last.point.x - first.point.x) / dt,
                        dy: (last.point.y - first.point.y) / dt
                    )
                }
            }
            let clampedVelocity = clampVector(flingVelocity, maxMagnitude: 1500)

            // Set velocity on every buddy body part for a full-body fling
            for part in buddy.allParts {
                part.physicsBody?.velocity = clampedVelocity
            }
            // Extra impulse on the grabbed part for spin
            grabbed.physicsBody?.applyImpulse(CGVector(dx: clampedVelocity.dx * 0.2, dy: clampedVelocity.dy * 0.2))

            // Dragging the buddy counts as a hit when the fling is forceful enough.
            let speed = hypot(clampedVelocity.dx, clampedVelocity.dy)
            if speed > 200 {
                let baseDamage = Int(min(50, max(1, speed / 50)))
                let actual = gameState.dealDamage(amount: baseDamage)
                buddy.takeDamage()
                spawnImpactParticles(at: point)
                shakeScreen()

                if Bool.random(probability: 0.2) {
                    buddy.showSpeechBubble(text: buddy.randomQuip())
                }

                if gameState.hp <= 0 {
                    triggerKO()
                }

                _ = actual // suppress unused-variable warning
            }

            grabbedBody = nil
        } else {
            if let impulse = weaponController?.mouseUp(at: point, in: self) {
                // Apply the weapon's returned impulse to the nearest buddy part.
                if let part = buddy.bodyPart(at: point) {
                    buddy.applyImpulse(impulse, to: part)
                }
            }
        }

        dragVelocity = .zero
    }

    // MARK: - Physics Contact

    func didBegin(_ contact: SKPhysicsContact) {
        let (bodyA, bodyB) = (contact.bodyA, contact.bodyB)

        // Determine which is weapon and which is buddy.
        let isAWeapon = bodyA.categoryBitMask & weaponCategory != 0
        let isBWeapon = bodyB.categoryBitMask & weaponCategory != 0
        let isABuddy = bodyA.categoryBitMask & buddyCategory != 0
        let isBBuddy = bodyB.categoryBitMask & buddyCategory != 0

        guard (isAWeapon && isBBuddy) || (isBWeapon && isABuddy) else { return }
        guard !isKO else { return }

        // Calculate impact speed from relative velocity.
        let relVelocity = CGVector(
            dx: bodyA.velocity.dx - bodyB.velocity.dx,
            dy: bodyA.velocity.dy - bodyB.velocity.dy
        )
        let speed = hypot(relVelocity.dx, relVelocity.dy)
        let baseDamage = Int(min(50, max(1, speed / 50)))

        let actual = gameState.dealDamage(amount: baseDamage)
        buddy.takeDamage()

        // Randomly show a speech bubble.
        if Bool.random(probability: 0.2) {
            buddy.showSpeechBubble(text: buddy.randomQuip())
        }

        // Screen shake.
        shakeScreen()

        // Impact particles at the contact point.
        spawnImpactParticles(at: contact.contactPoint)

        // Check for KO.
        if gameState.hp <= 0 {
            triggerKO()
        }

        _ = actual
    }

    // MARK: - KO Sequence

    private func triggerKO() {
        guard !isKO else { return }
        isKO = true

        buddy.knockout()
        // gameState.knockout() is already called inside dealDamage when hp <= 0,
        // but in case it was reached through a different path:
        if gameState.hp <= 0 {
            gameState.knockout()
        }
        gameState.save()

        // Big "KO!" label.
        let koLabel = SKLabelNode(text: "KO!")
        koLabel.fontName = "AvenirNext-Heavy"
        koLabel.fontSize = 96
        koLabel.fontColor = .red
        koLabel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        koLabel.zPosition = 100
        koLabel.setScale(0.1)
        addChild(koLabel)

        let popIn = SKAction.scale(to: 1.2, duration: 0.2)
        let settle = SKAction.scale(to: 1.0, duration: 0.1)
        let hold = SKAction.wait(forDuration: 1.2)
        let fadeOut = SKAction.fadeOut(withDuration: 0.5)
        let cleanup = SKAction.removeFromParent()
        koLabel.run(SKAction.sequence([popIn, settle, hold, fadeOut, cleanup]))

        // Reset after a delay.
        run(SKAction.sequence([
            SKAction.wait(forDuration: 2.0),
            SKAction.run { [weak self] in
                guard let self = self else { return }
                self.buddy.resetPosition(in: self.size)
                self.isKO = false
            }
        ]))
    }

    // MARK: - Update Loop

    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)

        // Auto-damage tick (once per second).
        let autoDPS = gameState.autoDamagePerSecond
        if autoDPS > 0 && !isKO {
            if autoDamageTimer == 0 {
                autoDamageTimer = currentTime
            }
            if currentTime - autoDamageTimer >= 1.0 {
                autoDamageTimer = currentTime
                gameState.dealDamage(amount: autoDPS)
                buddy.takeDamage()
                if gameState.hp <= 0 {
                    triggerKO()
                }
            }
        }

        // Sync HP to buddy for face expressions
        if let buddy = buddy, let gs = gameState {
            buddy.currentHP = CGFloat(gs.hp)
            buddy.currentMaxHP = CGFloat(gs.effectiveMaxHP)
            buddy.updateFace(hp: buddy.currentHP, maxHP: buddy.currentMaxHP, isHit: false)
        }

        // Clamp buddy body part velocities and positions
        if let buddy = buddy {
            let maxSpeed: CGFloat = 1500
            for part in buddy.allParts {
                guard let body = part.physicsBody else { continue }
                // Cap velocity
                let speed = hypot(body.velocity.dx, body.velocity.dy)
                if speed > maxSpeed {
                    let scale = maxSpeed / speed
                    body.velocity = CGVector(dx: body.velocity.dx * scale, dy: body.velocity.dy * scale)
                }
            }
            // If torso is way off screen, reset everything
            let pos = buddy.position
            let margin: CGFloat = 80
            if pos.x < -margin || pos.x > size.width + margin ||
               pos.y < -margin || pos.y > size.height + margin {
                buddy.resetPosition(in: size)
            }
        }
    }

    // MARK: - Impact Particles

    func spawnImpactParticles(at point: CGPoint) {
        let count = Int.random(in: 5...8)
        for _ in 0..<count {
            let particle = SKShapeNode(circleOfRadius: CGFloat.random(in: 2...5))
            particle.fillColor = [.orange, .yellow, .white, .red].randomElement()!
            particle.strokeColor = .clear
            particle.position = point
            particle.zPosition = 50
            addChild(particle)

            let angle = CGFloat.random(in: 0...(2 * .pi))
            let distance = CGFloat.random(in: 30...80)
            let dest = CGPoint(
                x: point.x + cos(angle) * distance,
                y: point.y + sin(angle) * distance
            )

            let move = SKAction.move(to: dest, duration: TimeInterval(CGFloat.random(in: 0.2...0.4)))
            move.timingMode = .easeOut
            let fade = SKAction.fadeOut(withDuration: 0.3)
            let shrink = SKAction.scale(to: 0.1, duration: 0.35)
            let group = SKAction.group([move, fade, shrink])
            let cleanup = SKAction.removeFromParent()
            particle.run(SKAction.sequence([group, cleanup]))
        }
    }

    // MARK: - Screen Shake

    func shakeScreen() {
        guard self.action(forKey: "shake") == nil else { return }

        let originalPos = position
        var actions: [SKAction] = []
        var amplitude: CGFloat = 6.0
        let steps = 6

        for _ in 0..<steps {
            let dx = CGFloat.random(in: -amplitude...amplitude)
            let dy = CGFloat.random(in: -amplitude...amplitude)
            let shiftAction = SKAction.moveBy(x: dx, y: dy, duration: 0.03)
            actions.append(shiftAction)
            amplitude *= 0.7
        }
        actions.append(SKAction.move(to: originalPos, duration: 0.03))
        run(SKAction.sequence(actions), withKey: "shake")
    }

    // MARK: - Helpers

    private func clampVector(_ v: CGVector, maxMagnitude: CGFloat) -> CGVector {
        let mag = hypot(v.dx, v.dy)
        guard mag > maxMagnitude else { return v }
        let scale = maxMagnitude / mag
        return CGVector(dx: v.dx * scale, dy: v.dy * scale)
    }
}

// MARK: - Bool Random Utility

private extension Bool {
    /// Returns `true` with the given probability (0...1).
    static func random(probability: Double) -> Bool {
        Double.random(in: 0..<1) < probability
    }
}
