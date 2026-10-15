// WaterBuddy: a desktop buddy that walks in every couple of hours to remind you to drink water.
import AppKit
import ServiceManagement

// MARK: - Settings

enum Settings {
    private static let d = UserDefaults.standard

    static var intervalMinutes: Int {
        get { d.object(forKey: "intervalMinutes") as? Int ?? 120 }
        set { d.set(newValue, forKey: "intervalMinutes") }
    }
    static var snoozeMinutes: Int {
        get { d.object(forKey: "snoozeMinutes") as? Int ?? 15 }
        set { d.set(newValue, forKey: "snoozeMinutes") }
    }
    static var soundOn: Bool {
        get { d.object(forKey: "soundOn") as? Bool ?? true }
        set { d.set(newValue, forKey: "soundOn") }
    }

    private static var today: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
    static var glassesToday: Int {
        d.string(forKey: "countDate") == today ? d.integer(forKey: "count") : 0
    }
    static func addGlass() {
        let n = glassesToday + 1
        d.set(today, forKey: "countDate")
        d.set(n, forKey: "count")
    }
    static func resetGlasses() {
        d.set(today, forKey: "countDate")
        d.set(0, forKey: "count")
    }
}

// MARK: - Sprites

@MainActor
enum Sprites {
    /// Loads sprites/<prefix>_0.png, _1.png, ... from the app bundle. Images are @2x.
    static func load(_ prefix: String, mirrored: Bool = false) -> [NSImage] {
        var frames: [NSImage] = []
        var i = 0
        while let url = Bundle.main.url(forResource: "\(prefix)_\(i)", withExtension: "png", subdirectory: "sprites"),
              let img = NSImage(contentsOf: url),
              let rep = img.representations.first {
            img.size = NSSize(width: CGFloat(rep.pixelsWide) / 2, height: CGFloat(rep.pixelsHigh) / 2)
            frames.append(mirrored ? mirror(img) : img)
            i += 1
        }
        if frames.isEmpty { NSLog("WaterBuddy: missing sprites for \(prefix)") }
        return frames
    }

    private static func mirror(_ img: NSImage) -> NSImage {
        NSImage(size: img.size, flipped: false) { rect in
            let t = NSAffineTransform()
            t.translateX(by: rect.width, yBy: 0)
            t.scaleX(by: -1, yBy: 1)
            t.concat()
            img.draw(in: rect)
            return true
        }
    }

    static let walkRight = load("walk")
    static let walkLeft = load("walk", mirrored: true)
    static let wave = load("wave")
    static let jump = load("jump")
    static let sad = load("sad")
}

// MARK: - Stage (plays an animation and moves the character along the ground)

final class Stage: NSView {
    private let imageView = NSImageView()
    private var timer: Timer?
    private var frames: [NSImage] = []
    private var fps = 10.0
    private var loops = true
    private var startTime = 0.0
    private var lastTick = 0.0
    private var speed: CGFloat = 0
    private var targetX: CGFloat?
    private var completion: (() -> Void)?

    var centerX: CGFloat = 0
    let groundY: CGFloat = 4

    override init(frame: NSRect) {
        super.init(frame: frame)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Plays `frames`. With `speed` and `targetX`, walks there and then calls `then`.
    /// Without a target, a non-looping animation calls `then` after its last frame.
    func play(_ frames: [NSImage], fps: Double, loops: Bool = true,
              speed: CGFloat = 0, to targetX: CGFloat? = nil, then: (() -> Void)? = nil) {
        self.frames = frames
        self.fps = fps
        self.loops = loops
        self.speed = speed
        self.targetX = targetX
        self.completion = then
        startTime = CACurrentMediaTime()
        lastTick = startTime
        if timer == nil {
            let t = Timer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(tick),
                          userInfo: nil, repeats: true)
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        completion = nil
    }

    private func finish() {
        let done = completion
        completion = nil
        speed = 0
        targetX = nil
        done?()
    }

    @objc private func tick() {
        guard !frames.isEmpty else { return }
        let now = CACurrentMediaTime()
        let dt = now - lastTick
        lastTick = now

        if speed != 0 {
            centerX += speed * CGFloat(dt)
            if let t = targetX, speed > 0 ? centerX >= t : centerX <= t {
                centerX = t
                show(frames[0])
                finish()
                return
            }
        }

        var idx = Int((now - startTime) * fps)
        if loops {
            idx %= frames.count
        } else if idx >= frames.count {
            idx = frames.count - 1
            if targetX == nil && completion != nil {
                show(frames[idx])
                finish()
                return
            }
        }
        show(frames[idx])
    }

    private func show(_ img: NSImage) {
        imageView.image = img
        let s = img.size
        imageView.frame = NSRect(x: centerX - s.width / 2, y: groundY, width: s.width, height: s.height)
    }
}

// MARK: - Speech bubble

final class Bubble: NSView {
    let label = NSTextField(wrappingLabelWithString: "")
    let drankButton = NSButton(title: "I drank 💧", target: nil, action: nil)
    let snoozeButton = NSButton(title: "Snooze", target: nil, action: nil)
    private let tail: CGFloat = 14

    override init(frame: NSRect) {
        super.init(frame: frame)
        appearance = NSAppearance(named: .aqua)
        wantsLayer = true
        shadow = {
            let s = NSShadow()
            s.shadowBlurRadius = 8
            s.shadowOffset = NSSize(width: 0, height: -2)
            s.shadowColor = NSColor.black.withAlphaComponent(0.35)
            return s
        }()

        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .black
        label.alignment = .center
        label.frame = NSRect(x: 12, y: 46, width: frame.width - tail - 24, height: frame.height - 56)
        addSubview(label)

        let bw = (frame.width - tail - 30) / 2
        drankButton.bezelStyle = .rounded
        drankButton.keyEquivalent = "\r"
        drankButton.frame = NSRect(x: 10, y: 10, width: bw, height: 30)
        snoozeButton.bezelStyle = .rounded
        snoozeButton.frame = NSRect(x: 20 + bw, y: 10, width: bw, height: 30)
        addSubview(drankButton)
        addSubview(snoozeButton)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let body = NSRect(x: 2, y: 2, width: bounds.width - tail - 4, height: bounds.height - 4)
        let path = NSBezierPath(roundedRect: body, xRadius: 16, yRadius: 16)
        // Tail pointing right, toward the character.
        let ty = body.midY + 4
        path.move(to: NSPoint(x: body.maxX - 1, y: ty + 10))
        path.line(to: NSPoint(x: bounds.maxX - 1, y: ty - 4))
        path.line(to: NSPoint(x: body.maxX - 1, y: ty - 6))
        path.close()
        NSColor.white.setFill()
        path.fill()
    }
}

// MARK: - Floating panel

final class BuddyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let size = NSSize(width: 420, height: 260)
    private var panel: BuddyPanel!
    private var stage: Stage!
    private var bubble: Bubble!
    private var statusItem: NSStatusItem!
    private var nextLine: NSMenuItem!
    private var countLine: NSMenuItem!
    private var pauseItem: NSMenuItem!

    private var nextDue = Date()
    private var isShowing = false
    private var paused = false
    private var restX: CGFloat { size.width - 85 }

    private let messages = [
        "Hey! Time for a glass of water 💧",
        "Saar, vellam kudikku! 💧",
        "2 hours gone. Hydrate, my friend!",
        "One glass of water. Now. 😄",
        "Water break! Your body will thank you.",
    ]

    func applicationDidFinishLaunching(_ note: Notification) {
        buildPanel()
        buildMenu()
        scheduleNext(minutes: Settings.intervalMinutes)

        let check = Timer(timeInterval: 15, target: self, selector: #selector(checkDue),
                          userInfo: nil, repeats: true)
        RunLoop.main.add(check, forMode: .common)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(checkDue), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(placePanel), name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // Say hello once on first launch so you can see it works.
        if !UserDefaults.standard.bool(forKey: "launchedBefore") {
            UserDefaults.standard.set(true, forKey: "launchedBefore")
            showReminder()
        }
    }

    // MARK: UI construction

    private func buildPanel() {
        panel = BuddyPanel(contentRect: NSRect(origin: .zero, size: size),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let root = NSView(frame: NSRect(origin: .zero, size: size))
        stage = Stage(frame: root.bounds)
        root.addSubview(stage)

        bubble = Bubble(frame: NSRect(x: 8, y: 120, width: 260, height: 120))
        bubble.drankButton.target = self
        bubble.drankButton.action = #selector(drank)
        bubble.snoozeButton.target = self
        bubble.snoozeButton.action = #selector(snooze)
        bubble.isHidden = true
        root.addSubview(bubble)

        panel.contentView = root
        placePanel()
    }

    @objc private func placePanel() {
        guard let screen = NSScreen.main else { return }
        let v = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: v.maxX - size.width - 10, y: v.minY))
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "💧"

        let menu = NSMenu()
        menu.delegate = self
        nextLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        countLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        menu.addItem(nextLine)
        menu.addItem(countLine)
        menu.addItem(.separator())
        menu.addItem(item("Remind Me Now", #selector(remindNow), key: "r"))
        menu.addItem(item("I Drank a Glass", #selector(logGlass), key: "d"))
        menu.addItem(item("Reset Today's Count", #selector(resetCount)))
        pauseItem = item("Pause Reminders", #selector(togglePause), key: "p")
        menu.addItem(pauseItem)
        menu.addItem(.separator())
        menu.addItem(submenu("Remind Every", options: [(30, "30 minutes"), (60, "1 hour"), (90, "1.5 hours"),
                                                      (120, "2 hours"), (180, "3 hours")],
                             current: { Settings.intervalMinutes }, action: #selector(setInterval)))
        menu.addItem(submenu("Snooze For", options: [(5, "5 minutes"), (10, "10 minutes"), (15, "15 minutes"),
                                                    (30, "30 minutes"), (60, "1 hour")],
                             current: { Settings.snoozeMinutes }, action: #selector(setSnooze)))
        menu.addItem(item("Sound", #selector(toggleSound)))
        menu.addItem(item("Open at Login", #selector(toggleLogin)))
        menu.addItem(.separator())
        menu.addItem(item("Quit WaterBuddy", #selector(NSApplication.terminate(_:)), key: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = action == #selector(NSApplication.terminate(_:)) ? NSApp : self
        return i
    }

    private var submenuCurrent: [String: () -> Int] = [:]

    private func submenu(_ title: String, options: [(Int, String)], current: @escaping () -> Int,
                         action: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu(title: title)
        sub.delegate = self
        for (minutes, label) in options {
            let i = NSMenuItem(title: label, action: action, keyEquivalent: "")
            i.target = self
            i.tag = minutes
            sub.addItem(i)
        }
        submenuCurrent[title] = current
        parent.submenu = sub
        return parent
    }

    func menuWillOpen(_ menu: NSMenu) {
        if let current = submenuCurrent[menu.title] {
            for i in menu.items { i.state = i.tag == current() ? .on : .off }
            return
        }
        if paused {
            nextLine.title = "Reminders paused"
        } else if isShowing {
            nextLine.title = "Reminder showing now"
        } else {
            let mins = max(0, Int(ceil(nextDue.timeIntervalSinceNow / 60)))
            nextLine.title = "Next reminder in " + (mins >= 60 ? "\(mins / 60)h \(mins % 60)m" : "\(mins)m")
        }
        let n = Settings.glassesToday
        countLine.title = "Glasses today: \(n) " + String(repeating: "💧", count: min(n, 10))
        pauseItem.title = paused ? "Resume Reminders" : "Pause Reminders"
        for i in menu.items {
            if i.action == #selector(toggleSound) { i.state = Settings.soundOn ? .on : .off }
            if i.action == #selector(toggleLogin) { i.state = SMAppService.mainApp.status == .enabled ? .on : .off }
        }
    }

    // MARK: Scheduling

    private func scheduleNext(minutes: Int) {
        nextDue = Date().addingTimeInterval(TimeInterval(minutes * 60))
    }

    @objc private func checkDue() {
        if !paused && !isShowing && Date() >= nextDue { showReminder() }
    }

    // MARK: Choreography

    private func showReminder() {
        guard !isShowing else { return }
        isShowing = true
        placePanel()
        bubble.isHidden = true
        bubble.label.stringValue = messages.randomElement()!
        bubble.snoozeButton.title = "Snooze \(Settings.snoozeMinutes)m"
        stage.centerX = size.width + 80
        panel.orderFrontRegardless()
        if Settings.soundOn { NSSound(named: "Glass")?.play() }

        // Walk in from the right edge, then wave.
        stage.play(Sprites.walkLeft, fps: 10, speed: -140, to: restX) { [weak self] in
            guard let self else { return }
            self.stage.play(Sprites.wave, fps: 6)
            self.bubble.alphaValue = 0
            self.bubble.isHidden = false
            NSAnimationContext.runAnimationGroup { $0.duration = 0.25; self.bubble.animator().alphaValue = 1 }
        }
    }

    @objc private func drank() {
        guard isShowing else { return }
        Settings.addGlass()
        scheduleNext(minutes: Settings.intervalMinutes)
        bubble.isHidden = true
        stage.play(Sprites.jump, fps: 10, loops: false) { [weak self] in self?.walkOff() }
    }

    @objc private func snooze() {
        guard isShowing else { return }
        scheduleNext(minutes: Settings.snoozeMinutes)
        bubble.isHidden = true
        stage.play(Sprites.sad, fps: 0.8, loops: false) { [weak self] in self?.walkOff() }
    }

    /// Snooze or done: he turns and walks off to the right.
    private func walkOff() {
        stage.play(Sprites.walkRight, fps: 10, speed: 140, to: size.width + 90) { [weak self] in
            guard let self else { return }
            self.stage.stop()
            self.panel.orderOut(nil)
            self.isShowing = false
        }
    }

    // MARK: Menu actions

    @objc private func remindNow() { showReminder() }

    @objc private func logGlass() {
        if isShowing { drank(); return }
        Settings.addGlass()
        scheduleNext(minutes: Settings.intervalMinutes)
    }

    @objc private func resetCount() { Settings.resetGlasses() }

    @objc private func togglePause() {
        paused.toggle()
        if !paused { scheduleNext(minutes: Settings.intervalMinutes) }
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        Settings.intervalMinutes = sender.tag
        scheduleNext(minutes: sender.tag)
    }

    @objc private func setSnooze(_ sender: NSMenuItem) { Settings.snoozeMinutes = sender.tag }

    @objc private func toggleSound() { Settings.soundOn.toggle() }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Open at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nMove WaterBuddy.app to /Applications and try again."
            alert.runModal()
        }
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
