import SpriteKit

// MARK: - WeaponController Protocol

protocol WeaponController: AnyObject {
    func activate(in scene: SKScene)
    func deactivate(from scene: SKScene)
    func mouseDown(at point: CGPoint, in scene: SKScene)
    func mouseDragged(to point: CGPoint, in scene: SKScene)
    func mouseUp(at point: CGPoint, in scene: SKScene) -> CGVector?
    var nodes: [SKNode] { get }
}

// MARK: - Factory

enum WeaponFactory {
    static func controller(for type: WeaponType) -> WeaponController {
        switch type {
        case .bareHands:
            return BareHandsController()
        case .bat, .keyboard:
            return BatController()
        case .wreckingBall:
            return WreckingBallController()
        case .bugSwarm, .coffee:
            return BugSwarmController()
        }
    }
}

// MARK: - BareHandsController

final class BareHandsController: WeaponController {
    private var startPoint: CGPoint = .zero
    private(set) var nodes: [SKNode] = []

    func activate(in scene: SKScene) {}

    func deactivate(from scene: SKScene) {
        nodes.forEach { $0.removeFromParent() }
        nodes.removeAll()
    }

    func mouseDown(at point: CGPoint, in scene: SKScene) {
        startPoint = point
        showRing(at: point, in: scene)
    }

    func mouseDragged(to point: CGPoint, in scene: SKScene) {}

    func mouseUp(at point: CGPoint, in scene: SKScene) -> CGVector? {
        let dx = (startPoint.x - point.x) * 3.0
        let dy = (startPoint.y - point.y) * 3.0
        var impulse = CGVector(dx: dx, dy: dy)

        let magnitude = sqrt(impulse.dx * impulse.dx + impulse.dy * impulse.dy)
        if magnitude > 800 {
            let scale = 800 / magnitude
            impulse.dx *= scale
            impulse.dy *= scale
        }

        return impulse
    }

    private func showRing(at point: CGPoint, in scene: SKScene) {
        let ring = SKShapeNode(circleOfRadius: 15)
        ring.position = point
        ring.strokeColor = .white
        ring.lineWidth = 2
        ring.fillColor = .clear
        ring.setScale(0.3)
        ring.alpha = 0.8
        scene.addChild(ring)
        nodes.append(ring)

        let expand = SKAction.scale(to: 2.0, duration: 0.3)
        let fade = SKAction.fadeAlpha(to: 0, duration: 0.3)
        let group = SKAction.group([expand, fade])
        ring.run(group) { [weak self] in
            ring.removeFromParent()
            self?.nodes.removeAll { $0 === ring }
        }
    }
}

// MARK: - BatController

final class BatController: WeaponController {
    private var bat: SKShapeNode?
    private var lastDragPoint: CGPoint = .zero
    private var lastDragTime: TimeInterval = 0
    private var dragVelocity: CGVector = .zero
    private(set) var nodes: [SKNode] = []

    func activate(in scene: SKScene) {}

    func deactivate(from scene: SKScene) {
        nodes.forEach { $0.removeFromParent() }
        nodes.removeAll()
        bat = nil
    }

    func mouseDown(at point: CGPoint, in scene: SKScene) {
        let batNode = SKShapeNode(rectOf: CGSize(width: 12, height: 80), cornerRadius: 3)
        batNode.fillColor = NSColor(red: 0x8B / 255.0, green: 0x45 / 255.0, blue: 0x13 / 255.0, alpha: 1)
        batNode.strokeColor = NSColor(red: 0x6B / 255.0, green: 0x35 / 255.0, blue: 0x10 / 255.0, alpha: 1)
        batNode.lineWidth = 1
        batNode.position = point

        let body = SKPhysicsBody(rectangleOf: CGSize(width: 12, height: 80))
        body.categoryBitMask = 0x2       // weaponCategory
        body.contactTestBitMask = 0x1    // buddyCategory
        body.collisionBitMask = 0x1
        body.affectedByGravity = false
        body.allowsRotation = true
        body.mass = 2.0
        batNode.physicsBody = body

        scene.addChild(batNode)
        nodes.append(batNode)
        bat = batNode
        lastDragPoint = point
        lastDragTime = CACurrentMediaTime()
        dragVelocity = .zero
    }

    func mouseDragged(to point: CGPoint, in scene: SKScene) {
        guard let bat = bat else { return }

        let now = CACurrentMediaTime()
        let dt = now - lastDragTime
        if dt > 0 {
            dragVelocity = CGVector(
                dx: (point.x - lastDragPoint.x) / dt,
                dy: (point.y - lastDragPoint.y) / dt
            )
        }

        bat.position = point
        bat.physicsBody?.velocity = .zero
        lastDragPoint = point
        lastDragTime = now
    }

    func mouseUp(at point: CGPoint, in scene: SKScene) -> CGVector? {
        guard let bat = bat else { return nil }

        bat.physicsBody?.affectedByGravity = true
        bat.physicsBody?.velocity = dragVelocity

        let batRef = bat
        self.bat = nil

        let wait = SKAction.wait(forDuration: 1.0)
        let fade = SKAction.fadeAlpha(to: 0, duration: 0.2)
        let remove = SKAction.removeFromParent()
        batRef.run(SKAction.sequence([wait, fade, remove])) { [weak self] in
            self?.nodes.removeAll { $0 === batRef }
        }

        return nil
    }
}

// MARK: - WreckingBallController

final class WreckingBallController: WeaponController {
    private var anchor: SKNode?
    private var chainLinks: [SKShapeNode] = []
    private var ball: SKShapeNode?
    private(set) var nodes: [SKNode] = []

    private let linkCount = 8
    private let linkRadius: CGFloat = 3
    private let linkSpacing: CGFloat = 10
    private let ballRadius: CGFloat = 20

    func activate(in scene: SKScene) {}

    func deactivate(from scene: SKScene) {
        nodes.forEach { $0.removeFromParent() }
        nodes.removeAll()
        anchor = nil
        chainLinks.removeAll()
        ball = nil
    }

    func mouseDown(at point: CGPoint, in scene: SKScene) {
        // Remove any existing chain
        deactivate(from: scene)

        // Anchor — invisible, kinematic
        let anchorNode = SKNode()
        anchorNode.position = point
        let anchorBody = SKPhysicsBody(circleOfRadius: 1)
        anchorBody.isDynamic = false
        anchorBody.categoryBitMask = 0
        anchorBody.collisionBitMask = 0
        anchorNode.physicsBody = anchorBody
        scene.addChild(anchorNode)
        nodes.append(anchorNode)
        anchor = anchorNode

        // Chain links
        var previousNode: SKNode = anchorNode
        for i in 0..<linkCount {
            let link = SKShapeNode(circleOfRadius: linkRadius)
            link.fillColor = .gray
            link.strokeColor = .darkGray
            link.lineWidth = 0.5
            link.position = CGPoint(x: point.x, y: point.y - CGFloat(i + 1) * linkSpacing)

            let body = SKPhysicsBody(circleOfRadius: linkRadius)
            body.categoryBitMask = 0
            body.collisionBitMask = wallCategory
            body.mass = 0.1
            body.linearDamping = 0.3
            link.physicsBody = body

            scene.addChild(link)
            nodes.append(link)
            chainLinks.append(link)

            let joint = SKPhysicsJointPin.joint(
                withBodyA: previousNode.physicsBody!,
                bodyB: body,
                anchor: CGPoint(
                    x: (previousNode.position.x + link.position.x) / 2,
                    y: (previousNode.position.y + link.position.y) / 2
                )
            )
            scene.physicsWorld.add(joint)

            previousNode = link
        }

        // Wrecking ball
        let ballNode = SKShapeNode(circleOfRadius: ballRadius)
        ballNode.fillColor = NSColor(white: 0.2, alpha: 1)
        ballNode.strokeColor = NSColor(white: 0.1, alpha: 1)
        ballNode.lineWidth = 1.5
        let lastLinkPos = chainLinks.last?.position ?? point
        ballNode.position = CGPoint(x: lastLinkPos.x, y: lastLinkPos.y - linkSpacing)

        let ballBody = SKPhysicsBody(circleOfRadius: ballRadius)
        ballBody.categoryBitMask = 0x2       // weaponCategory
        ballBody.contactTestBitMask = 0x1    // buddyCategory
        ballBody.collisionBitMask = 0x1 | wallCategory
        ballBody.mass = 5.0
        ballBody.restitution = 0.3
        ballBody.linearDamping = 0.1
        ballNode.physicsBody = ballBody

        scene.addChild(ballNode)
        nodes.append(ballNode)
        ball = ballNode

        // Joint between last chain link and ball
        if let lastLink = chainLinks.last {
            let ballJoint = SKPhysicsJointPin.joint(
                withBodyA: lastLink.physicsBody!,
                bodyB: ballBody,
                anchor: CGPoint(
                    x: (lastLink.position.x + ballNode.position.x) / 2,
                    y: (lastLink.position.y + ballNode.position.y) / 2
                )
            )
            scene.physicsWorld.add(ballJoint)
        }
    }

    func mouseDragged(to point: CGPoint, in scene: SKScene) {
        anchor?.position = point
    }

    func mouseUp(at point: CGPoint, in scene: SKScene) -> CGVector? {
        guard let anchor = anchor else { return nil }

        // Detach anchor by making it dynamic and removing from scene
        anchor.physicsBody?.isDynamic = true
        anchor.physicsBody?.affectedByGravity = false
        anchor.removeFromParent()
        nodes.removeAll { $0 === anchor }
        self.anchor = nil

        // Let everything fall, then clean up after 3 seconds
        let allNodes = nodes
        let wait = SKAction.wait(forDuration: 3.0)
        let fade = SKAction.fadeAlpha(to: 0, duration: 0.4)

        for node in allNodes {
            node.run(SKAction.sequence([wait, fade, SKAction.removeFromParent()])) { [weak self] in
                self?.nodes.removeAll { $0 === node }
            }
        }

        chainLinks.removeAll()
        ball = nil

        return nil
    }
}

// MARK: - BugSwarmController

final class BugSwarmController: WeaponController {
    private(set) var nodes: [SKNode] = []
    private var buddyProvider: (() -> CGPoint)?
    private var active = false
    private let bugCount = 12
    private let lifetime: TimeInterval = 5.0

    func activate(in scene: SKScene) {
        active = true
    }

    func deactivate(from scene: SKScene) {
        active = false
        nodes.forEach { $0.removeFromParent() }
        nodes.removeAll()
    }

    func mouseDown(at point: CGPoint, in scene: SKScene) {
        // Spawn swarm at click point
        spawnSwarm(at: point, in: scene)
    }

    func mouseDragged(to point: CGPoint, in scene: SKScene) {
        // Bugs follow their own AI, no drag interaction
    }

    func mouseUp(at point: CGPoint, in scene: SKScene) -> CGVector? {
        return nil
    }

    /// Call from the scene's update loop to steer bugs toward the buddy.
    func update(buddyPosition: CGPoint) {
        guard active else { return }
        for node in nodes {
            guard let body = node.physicsBody else { continue }
            let dx = buddyPosition.x - node.position.x
            let dy = buddyPosition.y - node.position.y
            let dist = max(sqrt(dx * dx + dy * dy), 1)
            let strength: CGFloat = 8.0
            body.applyImpulse(CGVector(dx: dx / dist * strength, dy: dy / dist * strength))

            // Clamp bug velocity
            let vx = body.velocity.dx
            let vy = body.velocity.dy
            let speed = sqrt(vx * vx + vy * vy)
            let maxSpeed: CGFloat = 300
            if speed > maxSpeed {
                body.velocity = CGVector(dx: vx / speed * maxSpeed, dy: vy / speed * maxSpeed)
            }
        }
    }

    private func spawnSwarm(at origin: CGPoint, in scene: SKScene) {
        // Remove any existing bugs first
        nodes.forEach { $0.removeFromParent() }
        nodes.removeAll()

        let bugColors: [NSColor] = [
            NSColor(red: 0.2, green: 0.6, blue: 0.2, alpha: 1),   // green
            NSColor(red: 0.4, green: 0.3, blue: 0.1, alpha: 1),   // brown
            NSColor(red: 0.1, green: 0.5, blue: 0.15, alpha: 1),  // dark green
            NSColor(red: 0.5, green: 0.35, blue: 0.15, alpha: 1), // tan
        ]

        for _ in 0..<bugCount {
            let radius = CGFloat.random(in: 2...3)
            let bug = SKShapeNode(circleOfRadius: radius)
            bug.fillColor = bugColors.randomElement()!
            bug.strokeColor = .black
            bug.lineWidth = 0.5

            // Scatter around origin
            let spread: CGFloat = 30
            bug.position = CGPoint(
                x: origin.x + CGFloat.random(in: -spread...spread),
                y: origin.y + CGFloat.random(in: -spread...spread)
            )

            let body = SKPhysicsBody(circleOfRadius: radius)
            body.categoryBitMask = 0x2       // weaponCategory
            body.contactTestBitMask = 0x1    // buddyCategory
            body.collisionBitMask = 0
            body.mass = 0.05
            body.linearDamping = 2.0
            body.allowsRotation = false
            bug.physicsBody = body

            scene.addChild(bug)
            nodes.append(bug)
        }

        // Fade out and remove after lifetime
        let allBugs = nodes
        let wait = SKAction.wait(forDuration: lifetime)
        let fade = SKAction.fadeAlpha(to: 0, duration: 0.6)
        let remove = SKAction.removeFromParent()
        let sequence = SKAction.sequence([wait, fade, remove])

        for bug in allBugs {
            bug.run(sequence) { [weak self] in
                self?.nodes.removeAll { $0 === bug }
                if self?.nodes.isEmpty == true {
                    self?.active = false
                }
            }
        }
    }
}
