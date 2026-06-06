import AppKit
import CoreGraphics

/// Turns control messages into real mouse and keyboard events on the Mac.
/// Requires the Accessibility permission for the events to take effect.
final class EventInjector {
    private let source = CGEventSource(stateID: .combinedSessionState)
    private var dragging = false
    private var cachedBounds: CGRect = .zero

    // "Virtual" cursor position that we maintain ourselves. Accumulating the deltas
    // here —instead of re-reading the real position on every event— avoids the stutter:
    // during a fast movement the WindowServer hasn't updated the real position yet,
    // so re-reading it would give stale values.
    private var virtualPoint: CGPoint = .zero
    private var hasVirtualPoint = false
    private var lastMoveTime: TimeInterval = 0
    /// After this pause with no movement, the real cursor has "settled" and we
    /// re-sync (in case the physical mouse moved or there was a click elsewhere).
    private let resyncInterval: TimeInterval = 0.2

    /// Serial queue that owns the key-repeat timer state, so `keyDown`/`keyUp`
    /// coming from the network queue never race on the timer.
    private let repeatQueue = DispatchQueue(label: "com.drakonis96.mytrackpad.keyrepeat")
    private var repeatTimer: DispatchSourceTimer?

    init() {
        cachedBounds = displayBounds()
        let scrollSpeed: CGFloat = 1.6
        self.scrollSpeed = scrollSpeed
    }

    private var scrollSpeed: CGFloat = 1.6

    // MARK: - Mouse

    private func currentLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    func move(dx: Double, dy: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        // If we're coming out of a pause (or it's the first movement), we start from
        // the real position. During a continuous movement we accumulate on the virtual one.
        if !hasVirtualPoint || now - lastMoveTime > resyncInterval {
            virtualPoint = currentLocation()
            hasVirtualPoint = true
        }
        lastMoveTime = now

        virtualPoint.x += dx
        virtualPoint.y += dy
        virtualPoint = clamp(virtualPoint)

        let type: CGEventType = dragging ? .leftMouseDragged : .mouseMoved
        let event = CGEvent(mouseEventSource: source, mouseType: type,
                            mouseCursorPosition: virtualPoint, mouseButton: .left)
        // Carry the relative delta as well as the absolute position. Without the delta
        // fields the WindowServer derives its own delta from the (possibly stale) previous
        // position, which makes the cursor feel choppy; providing it gives a smooth stroke.
        event?.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx.rounded()))
        event?.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy.rounded()))
        event?.post(tap: .cghidEventTap)
    }

    func leftClick() {
        let p = syncPointer()
        postMouse(.leftMouseDown, p, .left)
        postMouse(.leftMouseUp, p, .left)
    }

    func rightClick() {
        let p = syncPointer()
        postMouse(.rightMouseDown, p, .right)
        postMouse(.rightMouseUp, p, .right)
    }

    func leftDown() {
        dragging = true
        postMouse(.leftMouseDown, pointerPoint(), .left)
    }

    func leftUp() {
        postMouse(.leftMouseUp, pointerPoint(), .left)
        dragging = false
    }

    /// Current pointer position based on our virtual state (or the real one if we
    /// don't have it yet). Keeps continuity with the last movement.
    private func pointerPoint() -> CGPoint {
        hasVirtualPoint ? virtualPoint : currentLocation()
    }

    /// For discrete actions (clicks): takes the real, already-settled position and
    /// re-syncs the virtual state with it.
    @discardableResult
    private func syncPointer() -> CGPoint {
        let p = currentLocation()
        virtualPoint = p
        hasVirtualPoint = true
        lastMoveTime = ProcessInfo.processInfo.systemUptime
        return p
    }

    func scroll(dx: Double, dy: Double) {
        let vertical = Int32((dy * Double(scrollSpeed)).rounded())
        let horizontal = Int32((dx * Double(scrollSpeed)).rounded())
        let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel,
                            wheelCount: 2, wheel1: vertical, wheel2: horizontal, wheel3: 0)
        event?.post(tap: .cghidEventTap)
    }

    /// Pinch → zoom. Cmd+scroll is not honored by every app, so we accumulate the
    /// pinch distance and emit ⌘+ / ⌘− keystrokes, which zoom reliably in browsers,
    /// Preview, Maps, Finder, Photos, etc.
    private var zoomAccumulator: Double = 0
    func zoom(amount: Double) {
        zoomAccumulator += amount
        let step: Double = 22  // points of finger-spread change per zoom keystroke
        while zoomAccumulator >= step {
            zoomAccumulator -= step
            pressShortcut("=", modifiers: ["command"])    // zoom in (⌘+)
        }
        while zoomAccumulator <= -step {
            zoomAccumulator += step
            pressShortcut("-", modifiers: ["command"])    // zoom out (⌘−)
        }
    }

    private func postMouse(_ type: CGEventType, _ point: CGPoint, _ button: CGMouseButton) {
        CGEvent(mouseEventSource: source, mouseType: type,
                mouseCursorPosition: point, mouseButton: button)?.post(tap: .cghidEventTap)
    }

    // MARK: - Keyboard

    func typeText(_ text: String) {
        let utf16 = Array(text.utf16)
        guard !utf16.isEmpty else { return }
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        utf16.withUnsafeBufferPointer { buffer in
            down?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            up?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
        }
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// One-shot key press (down + up).
    func pressKey(_ name: String, modifiers: [String]) {
        pressShortcut(name, modifiers: modifiers)
    }

    /// Press and hold a key. The Mac generates the auto-repeat (initial delay then
    /// steady repeats) until `keyUp` arrives — this is what makes "hold an arrow" work.
    func keyDown(_ name: String, modifiers: [String]) {
        guard let code = keyCode(for: name) else { return }
        let flags = modifierFlags(modifiers)
        let mods = modifierKeyCodes(modifiers)
        pressModifiers(mods, down: true)
        postKey(code, down: true, flags: flags, autorepeat: false)

        repeatQueue.async { [weak self] in
            guard let self else { return }
            self.repeatTimer?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: self.repeatQueue)
            timer.schedule(deadline: .now() + 0.40, repeating: 0.045)
            var fired = 0
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                fired += 1
                // Safety net: if a `keyUp` is ever lost, stop after a few seconds so a
                // key can't get stuck repeating forever.
                if fired > 220 {
                    timer.cancel()
                    self.repeatTimer = nil
                    self.postKey(code, down: false, flags: flags, autorepeat: false)
                    self.pressModifiers(mods, down: false)
                    return
                }
                self.postKey(code, down: true, flags: flags, autorepeat: true)
            }
            self.repeatTimer = timer
            timer.resume()
        }
    }

    func keyUp(_ name: String, modifiers: [String]) {
        guard let code = keyCode(for: name) else { return }
        let flags = modifierFlags(modifiers)
        let mods = modifierKeyCodes(modifiers)
        // Cancel the repeat AND post the release on the same serial queue, so a
        // pending repeat tick can never fire after the key-up (which would stick the key).
        repeatQueue.async { [weak self] in
            guard let self else { return }
            self.repeatTimer?.cancel()
            self.repeatTimer = nil
            self.postKey(code, down: false, flags: flags, autorepeat: false)
            self.pressModifiers(mods, down: false)
        }
    }

    /// Posts a key combination by establishing real modifier-key state first (a plain
    /// `flags` field is sometimes ignored by system shortcuts like Spaces / App Exposé).
    private func pressShortcut(_ name: String, modifiers: [String]) {
        guard let code = keyCode(for: name) else { return }
        let flags = modifierFlags(modifiers)
        let mods = modifierKeyCodes(modifiers)
        pressModifiers(mods, down: true)
        postKey(code, down: true, flags: flags, autorepeat: false)
        postKey(code, down: false, flags: flags, autorepeat: false)
        pressModifiers(mods, down: false)
    }

    private func postKey(_ code: CGKeyCode, down: Bool, flags: CGEventFlags, autorepeat: Bool) {
        let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
        event?.flags = flags
        if autorepeat { event?.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        event?.post(tap: .cghidEventTap)
    }

    /// Posts the modifier keys themselves (Control, Command…) so the WindowServer sees
    /// a genuine flag state. Needed for system-wide shortcuts to trigger.
    private func pressModifiers(_ codes: [CGKeyCode], down: Bool) {
        guard !codes.isEmpty else { return }
        let ordered = down ? codes : codes.reversed()
        var accumulated: CGEventFlags = down ? [] : flags(for: codes)
        for code in ordered {
            if down { accumulated.insert(flag(for: code)) } else { accumulated.remove(flag(for: code)) }
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            event?.flags = accumulated
            event?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Media / quick functions / gestures

    func media(_ name: String) {
        switch name {
        case "volUp":          postNXKey(NXKey.soundUp)
        case "volDown":        postNXKey(NXKey.soundDown)
        case "mute":           postNXKey(NXKey.mute)
        case "brightUp":       postNXKey(NXKey.brightnessUp)
        case "brightDown":     postNXKey(NXKey.brightnessDown)
        case "playPause":      postNXKey(NXKey.play)
        case "next":           postNXKey(NXKey.next)
        case "prev":           postNXKey(NXKey.previous)
        case "missionControl": launchMissionControl()
        case "appExpose":      pressShortcut("down", modifiers: ["control"])
        case "spacePrev":      pressShortcut("left", modifiers: ["control"])
        case "spaceNext":      pressShortcut("right", modifiers: ["control"])
        case "spotlight":      pressShortcut("space", modifiers: ["command"])
        case "zoomIn":         pressShortcut("=", modifiers: ["command"])
        case "zoomOut":        pressShortcut("-", modifiers: ["command"])
        case "dictation":      pressShortcut("f5", modifiers: [])
        default: break
        }
    }

    /// Most reliable, shortcut-config-independent way to toggle Mission Control.
    private func launchMissionControl() {
        DispatchQueue.main.async {
            let url = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
            NSWorkspace.shared.open(url)
        }
    }

    private enum NXKey {
        static let soundUp: Int32 = 0
        static let soundDown: Int32 = 1
        static let brightnessUp: Int32 = 2
        static let brightnessDown: Int32 = 3
        static let mute: Int32 = 7
        static let play: Int32 = 16
        static let next: Int32 = 17
        static let previous: Int32 = 18
    }

    private func postNXKey(_ key: Int32) {
        func send(keyDown: Bool) {
            let flagsRaw = keyDown ? 0xA00 : 0xB00
            let data1 = Int((key << 16) | Int32((keyDown ? 0xA : 0xB) << 8))
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flagsRaw)),
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
        send(keyDown: true)
        send(keyDown: false)
    }

    // MARK: - Key maps

    private func keyCode(for name: String) -> CGKeyCode? {
        switch name.lowercased() {
        case "left": return 0x7B
        case "right": return 0x7C
        case "down": return 0x7D
        case "up": return 0x7E
        case "return", "enter": return 0x24
        case "tab": return 0x30
        case "space": return 0x31
        case "delete", "backspace": return 0x33
        case "forwarddelete": return 0x75
        case "escape", "esc": return 0x35
        case "home": return 0x73
        case "end": return 0x77
        case "pageup": return 0x74
        case "pagedown": return 0x79
        case "f5": return 0x60
        case "8": return 0x1C
        case "=", "plus": return 0x18
        case "-", "minus": return 0x1B
        default: return nil
        }
    }

    private func modifierFlags(_ modifiers: [String]) -> CGEventFlags {
        var flags: CGEventFlags = []
        for modifier in modifiers {
            switch modifier.lowercased() {
            case "command", "cmd": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "option", "alt": flags.insert(.maskAlternate)
            case "control", "ctrl": flags.insert(.maskControl)
            case "fn": flags.insert(.maskSecondaryFn)
            default: break
            }
        }
        return flags
    }

    /// Virtual key codes for the modifier keys (left-hand variants).
    private func modifierKeyCodes(_ modifiers: [String]) -> [CGKeyCode] {
        modifiers.compactMap { modifier in
            switch modifier.lowercased() {
            case "command", "cmd": return 0x37
            case "shift": return 0x38
            case "option", "alt": return 0x3A
            case "control", "ctrl": return 0x3B
            default: return nil   // fn has no postable key code; handled via flags only
            }
        }
    }

    private func flag(for keyCode: CGKeyCode) -> CGEventFlags {
        switch keyCode {
        case 0x37: return .maskCommand
        case 0x38: return .maskShift
        case 0x3A: return .maskAlternate
        case 0x3B: return .maskControl
        default: return []
        }
    }

    private func flags(for keyCodes: [CGKeyCode]) -> CGEventFlags {
        var f: CGEventFlags = []
        for code in keyCodes { f.insert(flag(for: code)) }
        return f
    }

    // MARK: - Screen bounds

    private func displayBounds() -> CGRect {
        var rect = CGDisplayBounds(CGMainDisplayID())
        var count: UInt32 = 0
        if CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 {
            var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
            if CGGetActiveDisplayList(count, &ids, &count) == .success {
                for id in ids { rect = rect.union(CGDisplayBounds(id)) }
            }
        }
        return rect
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        if cachedBounds.isEmpty { cachedBounds = displayBounds() }
        let x = min(max(point.x, cachedBounds.minX), cachedBounds.maxX - 1)
        let y = min(max(point.y, cachedBounds.minY), cachedBounds.maxY - 1)
        return CGPoint(x: x, y: y)
    }
}
