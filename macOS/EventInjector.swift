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

    func zoom(amount: Double) {
        // Pinch → ⌘ + scroll (zoom in browsers, Preview, Maps, etc.)
        let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel,
                            wheelCount: 1, wheel1: Int32(amount.rounded()), wheel2: 0, wheel3: 0)
        event?.flags = .maskCommand
        event?.post(tap: .cghidEventTap)
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

    func pressKey(_ name: String, modifiers: [String]) {
        guard let code = keyCode(for: name) else { return }
        let flags = modifierFlags(modifiers)
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Media / quick functions

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
        case "missionControl": pressKey("up", modifiers: ["control"])
        case "spotlight":      pressKey("space", modifiers: ["command"])
        case "zoom":           pressKey("8", modifiers: ["command", "option"]) // Accessibility zoom
        case "dictation":      pressKey("f5", modifiers: [])
        default: break
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
