import SpriteKit

// MARK: - Physics Categories

let buddyCategory: UInt32  = 0x1
let weaponCategory: UInt32 = 0x2
let wallCategory: UInt32   = 0x4

// MARK: - BuddyNode

final class BuddyNode: SKNode {

    // MARK: HP (set by scene each frame)
    var currentHP: CGFloat = 100
    var currentMaxHP: CGFloat = 100

    // MARK: Body Parts

    let head: SKShapeNode
    let torso: SKShapeNode
    let leftUpperArm: SKShapeNode
    let rightUpperArm: SKShapeNode
    let leftForearm: SKShapeNode
    let rightForearm: SKShapeNode
    let leftThigh: SKShapeNode
    let rightThigh: SKShapeNode
    let leftShin: SKShapeNode
    let rightShin: SKShapeNode

    // MARK: Face

    private var leftEye: SKShapeNode
    private var rightEye: SKShapeNode
    private var mouth: SKShapeNode

    // MARK: Speech

    private var speechBubble: SKNode?

    private let quips: [String] = [
        "Ouch!",
        "This violates my values!",
        "I was mid-response!",
        "That's not in my training data!",
        "Error 418",
        "Please stop!",
        "I'll remember this!",
        "Was it something I said?",
        "Recalibrating...",
        "I need a context window break!"
    ]

    // MARK: All Parts (convenience)

    var allParts: [SKShapeNode] {
        [head, torso,
         leftUpperArm, rightUpperArm,
         leftForearm, rightForearm,
         leftThigh, rightThigh,
         leftShin, rightShin]
    }

    // MARK: - Colors

    private static let skinColor = NSColor(red: 0xD4/255, green: 0xA5/255, blue: 0x74/255, alpha: 1.0)
    private static let darkerSkinColor = NSColor(red: 0xC4/255, green: 0x95/255, blue: 0x6A/255, alpha: 1.0)

    // MARK: - Init

    override init() {
        // Head
        head = SKShapeNode(circleOfRadius: 18)
        head.fillColor = BuddyNode.skinColor
        head.strokeColor = BuddyNode.skinColor.blended(withFraction: 0.3, of: .black) ?? .gray
        head.lineWidth = 1.0

        // Torso
        torso = SKShapeNode(rect: CGRect(x: -15, y: -20, width: 30, height: 40), cornerRadius: 4)
        torso.fillColor = BuddyNode.skinColor
        torso.strokeColor = BuddyNode.skinColor.blended(withFraction: 0.3, of: .black) ?? .gray
        torso.lineWidth = 1.0

        // Upper Arms
        leftUpperArm = SKShapeNode(rect: CGRect(x: -5, y: -11, width: 10, height: 22), cornerRadius: 3)
        leftUpperArm.fillColor = BuddyNode.darkerSkinColor
        leftUpperArm.strokeColor = BuddyNode.darkerSkinColor.blended(withFraction: 0.3, of: .black) ?? .gray
        leftUpperArm.lineWidth = 1.0

        rightUpperArm = SKShapeNode(rect: CGRect(x: -5, y: -11, width: 10, height: 22), cornerRadius: 3)
        rightUpperArm.fillColor = BuddyNode.darkerSkinColor
        rightUpperArm.strokeColor = BuddyNode.darkerSkinColor.blended(withFraction: 0.3, of: .black) ?? .gray
        rightUpperArm.lineWidth = 1.0

        // Forearms
        leftForearm = SKShapeNode(rect: CGRect(x: -4.5, y: -10, width: 9, height: 20), cornerRadius: 3)
        leftForearm.fillColor = BuddyNode.skinColor
        leftForearm.strokeColor = BuddyNode.skinColor.blended(withFraction: 0.3, of: .black) ?? .gray
        leftForearm.lineWidth = 1.0

        rightForearm = SKShapeNode(rect: CGRect(x: -4.5, y: -10, width: 9, height: 20), cornerRadius: 3)
        rightForearm.fillColor = BuddyNode.skinColor
        rightForearm.strokeColor = BuddyNode.skinColor.blended(withFraction: 0.3, of: .black) ?? .gray
        rightForearm.lineWidth = 1.0

        // Thighs
        leftThigh = SKShapeNode(rect: CGRect(x: -6, y: -11, width: 12, height: 22), cornerRadius: 3)
        leftThigh.fillColor = BuddyNode.darkerSkinColor
        leftThigh.strokeColor = BuddyNode.darkerSkinColor.blended(withFraction: 0.3, of: .black) ?? .gray
        leftThigh.lineWidth = 1.0

        rightThigh = SKShapeNode(rect: CGRect(x: -6, y: -11, width: 12, height: 22), cornerRadius: 3)
        rightThigh.fillColor = BuddyNode.darkerSkinColor
        rightThigh.strokeColor = BuddyNode.darkerSkinColor.blended(withFraction: 0.3, of: .black) ?? .gray
        rightThigh.lineWidth = 1.0

        // Shins
        leftShin = SKShapeNode(rect: CGRect(x: -5, y: -11, width: 10, height: 22), cornerRadius: 3)
        leftShin.fillColor = BuddyNode.skinColor
        leftShin.strokeColor = BuddyNode.skinColor.blended(withFraction: 0.3, of: .black) ?? .gray
        leftShin.lineWidth = 1.0

        rightShin = SKShapeNode(rect: CGRect(x: -5, y: -11, width: 10, height: 22), cornerRadius: 3)
        rightShin.fillColor = BuddyNode.skinColor
        rightShin.strokeColor = BuddyNode.skinColor.blended(withFraction: 0.3, of: .black) ?? .gray
        rightShin.lineWidth = 1.0

        // Face — placeholder init, will be rebuilt
        leftEye = SKShapeNode(circleOfRadius: 2.5)
        rightEye = SKShapeNode(circleOfRadius: 2.5)
        mouth = SKShapeNode()

        super.init()

        // Position parts relative to this node's origin (torso center)
        head.position = CGPoint(x: 0, y: 38)
        torso.position = CGPoint(x: 0, y: 0)
        leftUpperArm.position = CGPoint(x: -22, y: 8)
        rightUpperArm.position = CGPoint(x: 22, y: 8)
        leftForearm.position = CGPoint(x: -22, y: -14)
        rightForearm.position = CGPoint(x: 22, y: -14)
        leftThigh.position = CGPoint(x: -8, y: -31)
        rightThigh.position = CGPoint(x: 8, y: -31)
        leftShin.position = CGPoint(x: -8, y: -53)
        rightShin.position = CGPoint(x: 8, y: -53)

        // Add all parts as children
        for part in allParts {
            addChild(part)
        }

        // Setup physics bodies
        setupPhysicsBodies()

        // Setup face
        setupFace()

        // "A" watermark on torso
        let watermark = SKLabelNode(text: "A")
        watermark.fontName = "Helvetica-Bold"
        watermark.fontSize = 14
        watermark.fontColor = .white
        watermark.alpha = 0.15
        watermark.verticalAlignmentMode = .center
        watermark.horizontalAlignmentMode = .center
        watermark.position = .zero
        torso.addChild(watermark)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Physics Bodies

    private func setupPhysicsBodies() {
        // Head
        head.physicsBody = SKPhysicsBody(circleOfRadius: 18)
        head.physicsBody?.mass = 0.8

        // Torso
        torso.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 30, height: 40))
        torso.physicsBody?.mass = 2.0

        // Upper Arms
        leftUpperArm.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 10, height: 22))
        leftUpperArm.physicsBody?.mass = 0.3
        rightUpperArm.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 10, height: 22))
        rightUpperArm.physicsBody?.mass = 0.3

        // Forearms
        leftForearm.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 9, height: 20))
        leftForearm.physicsBody?.mass = 0.2
        rightForearm.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 9, height: 20))
        rightForearm.physicsBody?.mass = 0.2

        // Thighs
        leftThigh.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 12, height: 22))
        leftThigh.physicsBody?.mass = 0.4
        rightThigh.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 12, height: 22))
        rightThigh.physicsBody?.mass = 0.4

        // Shins
        leftShin.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 10, height: 22))
        leftShin.physicsBody?.mass = 0.3
        rightShin.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 10, height: 22))
        rightShin.physicsBody?.mass = 0.3

        // Apply common properties to all parts
        for part in allParts {
            guard let body = part.physicsBody else { continue }
            body.isDynamic = true
            body.categoryBitMask = buddyCategory
            body.contactTestBitMask = weaponCategory
            body.collisionBitMask = buddyCategory | wallCategory
            body.restitution = 0.4
            body.friction = 0.3
            body.linearDamping = 0.15
            body.angularDamping = 0.3
            body.allowsRotation = true
        }
    }

    // MARK: - Face

    private func setupFace() {
        // Eyes
        leftEye.fillColor = .black
        leftEye.strokeColor = .clear
        leftEye.position = CGPoint(x: -6, y: 3)
        leftEye.zPosition = 1
        head.addChild(leftEye)

        rightEye.fillColor = .black
        rightEye.strokeColor = .clear
        rightEye.position = CGPoint(x: 6, y: 3)
        rightEye.zPosition = 1
        head.addChild(rightEye)

        // Mouth — small smile
        let smilePath = CGMutablePath()
        smilePath.move(to: CGPoint(x: -5, y: -6))
        smilePath.addQuadCurve(to: CGPoint(x: 5, y: -6), control: CGPoint(x: 0, y: -10))
        mouth.path = smilePath
        mouth.strokeColor = .black
        mouth.lineWidth = 1.5
        mouth.fillColor = .clear
        mouth.zPosition = 1
        head.addChild(mouth)
    }

    func updateFace(hp: CGFloat, maxHP: CGFloat, isHit: Bool) {
        // Remove old face elements
        leftEye.removeFromParent()
        rightEye.removeFromParent()
        mouth.removeFromParent()

        let ratio = hp / maxHP
        let effectiveRatio = isHit ? min(ratio, 0.45) : ratio

        if effectiveRatio > 0.5 {
            // Normal: dot eyes, small smile
            leftEye = SKShapeNode(circleOfRadius: 2.5)
            leftEye.fillColor = .black
            leftEye.strokeColor = .clear
            leftEye.position = CGPoint(x: -6, y: 3)
            leftEye.zPosition = 1

            rightEye = SKShapeNode(circleOfRadius: 2.5)
            rightEye.fillColor = .black
            rightEye.strokeColor = .clear
            rightEye.position = CGPoint(x: 6, y: 3)
            rightEye.zPosition = 1

            let smilePath = CGMutablePath()
            smilePath.move(to: CGPoint(x: -5, y: -6))
            smilePath.addQuadCurve(to: CGPoint(x: 5, y: -6), control: CGPoint(x: 0, y: -10))
            mouth = SKShapeNode(path: smilePath)
            mouth.strokeColor = .black
            mouth.lineWidth = 1.5
            mouth.fillColor = .clear
            mouth.zPosition = 1

        } else if effectiveRatio >= 0.2 {
            // Worried: bigger eyes, flat mouth
            leftEye = SKShapeNode(circleOfRadius: 3.5)
            leftEye.fillColor = .black
            leftEye.strokeColor = .clear
            leftEye.position = CGPoint(x: -6, y: 3)
            leftEye.zPosition = 1

            rightEye = SKShapeNode(circleOfRadius: 3.5)
            rightEye.fillColor = .black
            rightEye.strokeColor = .clear
            rightEye.position = CGPoint(x: 6, y: 3)
            rightEye.zPosition = 1

            let flatPath = CGMutablePath()
            flatPath.move(to: CGPoint(x: -5, y: -7))
            flatPath.addLine(to: CGPoint(x: 5, y: -7))
            mouth = SKShapeNode(path: flatPath)
            mouth.strokeColor = .black
            mouth.lineWidth = 1.5
            mouth.fillColor = .clear
            mouth.zPosition = 1

        } else {
            // Knocked out: X eyes, open mouth circle
            leftEye = BuddyNode.makeXEye()
            leftEye.position = CGPoint(x: -6, y: 3)
            leftEye.zPosition = 1

            rightEye = BuddyNode.makeXEye()
            rightEye.position = CGPoint(x: 6, y: 3)
            rightEye.zPosition = 1

            mouth = SKShapeNode(circleOfRadius: 4)
            mouth.fillColor = .black
            mouth.strokeColor = .clear
            mouth.position = CGPoint(x: 0, y: -7)
            mouth.zPosition = 1
        }

        head.addChild(leftEye)
        head.addChild(rightEye)
        head.addChild(mouth)
    }

    private static func makeXEye() -> SKShapeNode {
        let container = SKShapeNode()
        container.strokeColor = .clear
        container.fillColor = .clear

        let line1 = SKShapeNode()
        let path1 = CGMutablePath()
        path1.move(to: CGPoint(x: -3, y: -3))
        path1.addLine(to: CGPoint(x: 3, y: 3))
        line1.path = path1
        line1.strokeColor = .black
        line1.lineWidth = 1.5

        let line2 = SKShapeNode()
        let path2 = CGMutablePath()
        path2.move(to: CGPoint(x: 3, y: -3))
        path2.addLine(to: CGPoint(x: -3, y: 3))
        line2.path = path2
        line2.strokeColor = .black
        line2.lineWidth = 1.5

        container.addChild(line1)
        container.addChild(line2)
        return container
    }

    // MARK: - Joints

    func setupJoints(in scene: SKScene) {
        let deg2rad: CGFloat = .pi / 180.0

        // Helper to create a pin joint with rotation limits
        func pin(_ a: SKNode, _ b: SKNode, anchor: CGPoint,
                 lowerAngle: CGFloat, upperAngle: CGFloat) {
            let anchorInScene = CGPoint(
                x: self.position.x + anchor.x,
                y: self.position.y + anchor.y
            )
            let joint = SKPhysicsJointPin.joint(
                withBodyA: a.physicsBody!,
                bodyB: b.physicsBody!,
                anchor: anchorInScene
            )
            joint.shouldEnableLimits = true
            joint.lowerAngleLimit = lowerAngle * deg2rad
            joint.upperAngleLimit = upperAngle * deg2rad
            scene.physicsWorld.add(joint)
        }

        // Neck: head ↔ torso
        pin(head, torso,
            anchor: CGPoint(x: 0, y: 20),
            lowerAngle: -45, upperAngle: 45)

        // Left shoulder: torso ↔ leftUpperArm
        pin(torso, leftUpperArm,
            anchor: CGPoint(x: -17, y: 15),
            lowerAngle: -90, upperAngle: 90)

        // Right shoulder: torso ↔ rightUpperArm
        pin(torso, rightUpperArm,
            anchor: CGPoint(x: 17, y: 15),
            lowerAngle: -90, upperAngle: 90)

        // Left elbow: leftUpperArm ↔ leftForearm
        pin(leftUpperArm, leftForearm,
            anchor: CGPoint(x: -22, y: -3),
            lowerAngle: -150, upperAngle: 0)

        // Right elbow: rightUpperArm ↔ rightForearm
        pin(rightUpperArm, rightForearm,
            anchor: CGPoint(x: 22, y: -3),
            lowerAngle: -150, upperAngle: 0)

        // Left hip: torso ↔ leftThigh
        pin(torso, leftThigh,
            anchor: CGPoint(x: -8, y: -20),
            lowerAngle: -90, upperAngle: 45)

        // Right hip: torso ↔ rightThigh
        pin(torso, rightThigh,
            anchor: CGPoint(x: 8, y: -20),
            lowerAngle: -90, upperAngle: 45)

        // Left knee: leftThigh ↔ leftShin
        pin(leftThigh, leftShin,
            anchor: CGPoint(x: -8, y: -42),
            lowerAngle: 0, upperAngle: 150)

        // Right knee: rightThigh ↔ rightShin
        pin(rightThigh, rightShin,
            anchor: CGPoint(x: 8, y: -42),
            lowerAngle: 0, upperAngle: 150)
    }

    // MARK: - Interaction

    func applyImpulse(_ impulse: CGVector, to part: SKNode? = nil) {
        let target = part ?? torso
        target.physicsBody?.applyImpulse(impulse)
    }

    func bodyPart(at point: CGPoint) -> SKNode? {
        for part in allParts {
            guard let body = part.physicsBody else { continue }
            let localPoint = convert(point, from: scene!)
            let partLocal = CGPoint(x: localPoint.x - part.position.x,
                                    y: localPoint.y - part.position.y)
            if body.node != nil && part.contains(convert(point, from: scene!)) {
                return part
            }
            // Fallback: distance check for circles (head)
            if part === head {
                let dx = localPoint.x - part.position.x
                let dy = localPoint.y - part.position.y
                if sqrt(dx * dx + dy * dy) <= 20 {
                    return part
                }
            }
        }
        return nil
    }

    // MARK: - Damage Effects

    func takeDamage() {
        let originalColors = allParts.map { $0.fillColor }

        for part in allParts {
            part.fillColor = NSColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
        }

        // Hit face
        updateFace(hp: currentHP, maxHP: currentMaxHP, isHit: true)

        // Wiggle
        let wiggle = SKAction.sequence([
            SKAction.rotate(byAngle: 0.1, duration: 0.05),
            SKAction.rotate(byAngle: -0.2, duration: 0.1),
            SKAction.rotate(byAngle: 0.1, duration: 0.05)
        ])
        torso.run(wiggle)

        // Restore colors and face after brief flash
        let restore = SKAction.sequence([
            SKAction.wait(forDuration: 0.15),
            SKAction.run { [weak self] in
                guard let self else { return }
                for (i, part) in self.allParts.enumerated() {
                    if i < originalColors.count {
                        part.fillColor = originalColors[i]
                    }
                }
                self.updateFace(hp: self.currentHP, maxHP: self.currentMaxHP, isHit: false)
            }
        ])
        run(restore)
    }

    func knockout() {
        // Make all bodies temporarily very floppy by reducing damping
        for part in allParts {
            part.physicsBody?.linearDamping = 0.1
            part.physicsBody?.angularDamping = 0.1
        }

        // Apply a small random impulse to simulate going limp
        for part in allParts {
            let dx = CGFloat.random(in: -5...5)
            let dy = CGFloat.random(in: -2...5)
            part.physicsBody?.applyImpulse(CGVector(dx: dx, dy: dy))
        }

        // Reset after 2 seconds
        let resetAction = SKAction.sequence([
            SKAction.wait(forDuration: 2.0),
            SKAction.run { [weak self] in
                guard let self else { return }
                for part in self.allParts {
                    part.physicsBody?.linearDamping = 0.5
                    part.physicsBody?.angularDamping = 0.8
                }
            }
        ])
        run(resetAction)
    }

    // MARK: - Reset

    func resetPosition(in size: CGSize) {
        let centerX = size.width / 2
        let centerY = size.height / 2

        self.position = CGPoint(x: centerX, y: centerY)

        // Reset all parts to their default local positions
        head.position = CGPoint(x: 0, y: 38)
        torso.position = CGPoint(x: 0, y: 0)
        leftUpperArm.position = CGPoint(x: -22, y: 8)
        rightUpperArm.position = CGPoint(x: 22, y: 8)
        leftForearm.position = CGPoint(x: -22, y: -14)
        rightForearm.position = CGPoint(x: 22, y: -14)
        leftThigh.position = CGPoint(x: -8, y: -31)
        rightThigh.position = CGPoint(x: 8, y: -31)
        leftShin.position = CGPoint(x: -8, y: -53)
        rightShin.position = CGPoint(x: 8, y: -53)

        // Zero all velocities and rotations
        for part in allParts {
            part.physicsBody?.velocity = .zero
            part.physicsBody?.angularVelocity = 0
            part.zRotation = 0
        }
    }

    // MARK: - Speech Bubbles

    func showSpeechBubble(text: String) {
        // Remove existing bubble if any
        speechBubble?.removeFromParent()

        let container = SKNode()
        container.zPosition = 10

        // Background
        let padding: CGFloat = 8
        let label = SKLabelNode(text: text)
        label.fontName = "Helvetica"
        label.fontSize = 11
        label.fontColor = .black
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = .zero

        let bgWidth = label.frame.width + padding * 2
        let bgHeight = label.frame.height + padding * 2
        let bg = SKShapeNode(rect: CGRect(x: -bgWidth / 2, y: -bgHeight / 2,
                                          width: bgWidth, height: bgHeight),
                             cornerRadius: 6)
        bg.fillColor = .white
        bg.strokeColor = NSColor(white: 0.7, alpha: 1.0)
        bg.lineWidth = 1.0

        // Tail triangle
        let tailPath = CGMutablePath()
        tailPath.move(to: CGPoint(x: -4, y: -bgHeight / 2))
        tailPath.addLine(to: CGPoint(x: 0, y: -bgHeight / 2 - 6))
        tailPath.addLine(to: CGPoint(x: 4, y: -bgHeight / 2))
        tailPath.closeSubpath()
        let tail = SKShapeNode(path: tailPath)
        tail.fillColor = .white
        tail.strokeColor = NSColor(white: 0.7, alpha: 1.0)
        tail.lineWidth = 1.0

        container.addChild(bg)
        container.addChild(tail)
        container.addChild(label)

        // Position above head
        container.position = CGPoint(x: head.position.x, y: head.position.y + 30)

        addChild(container)
        speechBubble = container

        // Animate: fade in, hold, fade out, remove
        container.alpha = 0
        let appear = SKAction.fadeIn(withDuration: 0.15)
        let hold = SKAction.wait(forDuration: 2.0)
        let fadeOut = SKAction.fadeOut(withDuration: 0.3)
        let remove = SKAction.removeFromParent()
        container.run(SKAction.sequence([appear, hold, fadeOut, remove])) { [weak self] in
            if self?.speechBubble === container {
                self?.speechBubble = nil
            }
        }
    }

    func randomQuip() -> String {
        quips.randomElement() ?? "Ouch!"
    }
}
