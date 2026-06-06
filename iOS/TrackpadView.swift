import SwiftUI
import UIKit

/// Direction of a multi-finger swipe.
enum SwipeDirection { case left, right, up, down }

/// SwiftUI bridge to the UIKit touch surface.
struct TrackpadView: UIViewRepresentable {
    let model: AppModel

    func makeUIView(context: Context) -> TrackpadInputView {
        let view = TrackpadInputView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        bind(view)
        return view
    }

    func updateUIView(_ view: TrackpadInputView, context: Context) {
        view.sensitivity = CGFloat(model.sensitivity)
        view.naturalScroll = model.naturalScroll
        view.hapticsEnabled = model.hapticsEnabled
    }

    private func bind(_ view: TrackpadInputView) {
        view.onMove = { dx, dy in
            model.send(ControlMessage(kind: .move, dx: Double(dx), dy: Double(dy)))
        }
        view.onScroll = { dx, dy in
            let sign = model.naturalScroll ? 1.0 : -1.0
            model.send(ControlMessage(kind: .scroll, dx: Double(dx) * sign, dy: Double(dy) * sign))
        }
        view.onLeftClick = { model.send(ControlMessage(kind: .leftClick)) }
        view.onRightClick = { model.send(ControlMessage(kind: .rightClick)) }
        view.onLeftDown = { model.send(ControlMessage(kind: .leftDown)) }
        view.onLeftUp = { model.send(ControlMessage(kind: .leftUp)) }
        view.onZoom = { delta in model.send(ControlMessage(kind: .zoom, amount: Double(delta))) }
        view.onSwipe = { direction, _ in
            // Mirror a real Mac trackpad:
            //  • swipe left  → next space   (Control + →)
            //  • swipe right → previous space (Control + ←)
            //  • swipe up    → Mission Control
            //  • swipe down  → App Exposé   (Control + ↓)
            let media: String
            switch direction {
            case .left:  media = "spaceNext"
            case .right: media = "spacePrev"
            case .up:    media = "missionControl"
            case .down:  media = "appExpose"
            }
            model.send(ControlMessage(kind: .media, media: media))
        }
    }
}

/// Touch surface that interprets multi-touch gestures as trackpad actions.
final class TrackpadInputView: UIView {
    var onMove: ((CGFloat, CGFloat) -> Void)?
    var onScroll: ((CGFloat, CGFloat) -> Void)?
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onLeftDown: (() -> Void)?
    var onLeftUp: (() -> Void)?
    var onZoom: ((CGFloat) -> Void)?
    var onSwipe: ((SwipeDirection, Int) -> Void)?

    var sensitivity: CGFloat = 1.8
    var naturalScroll = true
    var hapticsEnabled = true

    // Gesture thresholds
    private let tapMaxDuration: TimeInterval = 0.28
    private let tapMaxMovement: CGFloat = 14
    private let dragInitiationWindow: TimeInterval = 0.32
    private let scrollSensitivity: CGFloat = 1.0
    /// A two-finger tap counts as a right-click only if the second finger landed within
    /// this window of the first — filters out a resting thumb / accidental graze.
    private let twoFingerTapWindow: TimeInterval = 0.20
    /// Centroid travel (points) that triggers a 3+ finger swipe.
    private let swipeThreshold: CGFloat = 55

    // State of the in-progress gesture
    private var gestureStart = Date()
    private var activeCount = 0
    private var peakCount = 0
    private var accumulatedMovement: CGFloat = 0
    private var lastSinglePoint: CGPoint = .zero
    private var lastCentroid: CGPoint = .zero
    private var lastDistance: CGFloat = 0
    private var twoFingerMode: TwoFingerMode = .undecided
    private var accumPan: CGFloat = 0
    private var accumPinch: CGFloat = 0
    private var reachedTwoAt: Date?
    private var swipeFired = false
    private var swipeAccum: CGPoint = .zero

    private var dragging = false
    private var lastTapEnd: Date = .distantPast

    private enum TwoFingerMode { case undecided, scroll, zoom }

    private let haptic = UIImpactFeedbackGenerator(style: .light)

    // MARK: - Touch lifecycle

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let touchesNow = activeTouches(event)
        if activeCount == 0 {
            // Start of a new gesture
            gestureStart = Date()
            accumulatedMovement = 0
            twoFingerMode = .undecided
            peakCount = 0
            accumPan = 0
            accumPinch = 0
            reachedTwoAt = nil
            swipeFired = false
            swipeAccum = .zero
        }
        activeCount = touchesNow.count
        peakCount = max(peakCount, activeCount)
        if activeCount >= 2 && reachedTwoAt == nil { reachedTwoAt = Date() }

        if activeCount == 1, let p = touchesNow.first?.location(in: self) {
            lastSinglePoint = p
            // Double-tap to drag? (quick tap followed by press and move)
            if Date().timeIntervalSince(lastTapEnd) < dragInitiationWindow {
                dragging = true
                onLeftDown?()
                fireHaptic()
            }
        } else if activeCount >= 2 {
            lastCentroid = centroid(touchesNow)
            lastDistance = spread(touchesNow)
            if activeCount == 2 { twoFingerMode = .undecided }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let touchesNow = activeTouches(event)
        let count = touchesNow.count

        if count == 1, let touch = touchesNow.first {
            // Use the coalesced samples so fast strokes stay smooth on ProMotion
            // displays instead of collapsing into a few large jumps.
            let samples = event?.coalescedTouches(for: touch) ?? [touch]
            var last = lastSinglePoint
            for sample in samples {
                let p = sample.location(in: self)
                let dx = p.x - last.x
                let dy = p.y - last.y
                last = p
                accumulatedMovement += hypot(dx, dy)
                onMove?(dx * sensitivity, dy * sensitivity)
            }
            lastSinglePoint = last
        } else if count == 2 {
            handleTwoFinger(touchesNow)
        } else if count >= 3 {
            handleSwipe(touchesNow)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let remaining = activeTouches(event).filter { $0.phase != .ended && $0.phase != .cancelled }
        finishGesture(remaining: remaining)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        let remaining = activeTouches(event).filter { $0.phase != .ended && $0.phase != .cancelled }
        if dragging { onLeftUp?(); dragging = false }
        if remaining.isEmpty { resetGesture() } else { recalibrate(remaining) }
    }

    // MARK: - Two-finger (scroll / zoom)

    private func handleTwoFinger(_ touchesNow: [UITouch]) {
        let c = centroid(touchesNow)
        let dx = c.x - lastCentroid.x
        let dy = c.y - lastCentroid.y
        lastCentroid = c

        let d = spread(touchesNow)
        let dd = d - lastDistance
        lastDistance = d

        let pan = hypot(dx, dy)
        if twoFingerMode == .undecided {
            accumPan += pan
            accumPinch += abs(dd)
            // A scroll keeps the finger spread roughly constant (low pinch); a pinch
            // changes it a lot. Bias toward zoom when the spread clearly dominates.
            if accumPinch > 14 && accumPinch > accumPan {
                twoFingerMode = .zoom
            } else if accumPan > 8 {
                twoFingerMode = .scroll
            }
        }

        accumulatedMovement += max(pan, abs(dd))
        switch twoFingerMode {
        case .scroll: onScroll?(dx * scrollSensitivity, dy * scrollSensitivity)
        case .zoom:   onZoom?(dd)
        case .undecided: break
        }
    }

    // MARK: - Three / four-finger swipe

    private func handleSwipe(_ touchesNow: [UITouch]) {
        let c = centroid(touchesNow)
        let dx = c.x - lastCentroid.x
        let dy = c.y - lastCentroid.y
        lastCentroid = c
        swipeAccum.x += dx
        swipeAccum.y += dy
        accumulatedMovement += hypot(dx, dy)

        guard !swipeFired else { return }
        if abs(swipeAccum.x) > swipeThreshold || abs(swipeAccum.y) > swipeThreshold {
            swipeFired = true
            let fingers = peakCount
            if abs(swipeAccum.x) > abs(swipeAccum.y) {
                onSwipe?(swipeAccum.x < 0 ? .left : .right, fingers)
            } else {
                onSwipe?(swipeAccum.y < 0 ? .up : .down, fingers)
            }
            fireHaptic()
        }
    }

    // MARK: - Gesture completion

    private func finishGesture(remaining: [UITouch]) {
        if remaining.isEmpty {
            let duration = Date().timeIntervalSince(gestureStart)
            if dragging {
                onLeftUp?()
                dragging = false
            } else if !swipeFired && accumulatedMovement < tapMaxMovement && duration < tapMaxDuration {
                classifyTap()
            }
            resetGesture()
        } else {
            // One finger lifted but at least one remains: recalibrate to avoid jumps.
            recalibrate(remaining)
        }
    }

    private func classifyTap() {
        if peakCount >= 3 {
            // Multi-finger tap: reserved for swipes; no click.
            return
        }
        if peakCount == 2 {
            // Right-click only for a deliberate, near-simultaneous two-finger tap.
            let concurrent = reachedTwoAt.map { $0.timeIntervalSince(gestureStart) < twoFingerTapWindow } ?? false
            if concurrent {
                onRightClick?()
                fireHaptic()
                return
            }
            // A late second touch is most likely an accidental graze → treat as left-click.
        }
        onLeftClick?()
        lastTapEnd = Date()
        fireHaptic()
    }

    private func recalibrate(_ remaining: [UITouch]) {
        activeCount = remaining.count
        if remaining.count == 1, let p = remaining.first?.location(in: self) {
            lastSinglePoint = p
        } else if remaining.count >= 2 {
            lastCentroid = centroid(remaining)
            lastDistance = spread(remaining)
        }
    }

    private func resetGesture() {
        activeCount = 0
        peakCount = 0
        accumulatedMovement = 0
        twoFingerMode = .undecided
        accumPan = 0
        accumPinch = 0
        reachedTwoAt = nil
        swipeFired = false
        swipeAccum = .zero
    }

    // MARK: - Helpers

    private func activeTouches(_ event: UIEvent?) -> [UITouch] {
        guard let all = event?.allTouches else { return [] }
        return all.filter { $0.phase == .began || $0.phase == .moved || $0.phase == .stationary }
            .sorted { $0.hash < $1.hash }
    }

    private func centroid(_ touches: [UITouch]) -> CGPoint {
        guard !touches.isEmpty else { return .zero }
        var x: CGFloat = 0, y: CGFloat = 0
        for t in touches {
            let p = t.location(in: self)
            x += p.x; y += p.y
        }
        return CGPoint(x: x / CGFloat(touches.count), y: y / CGFloat(touches.count))
    }

    private func spread(_ touches: [UITouch]) -> CGFloat {
        guard touches.count >= 2 else { return 0 }
        let a = touches[0].location(in: self)
        let b = touches[1].location(in: self)
        return hypot(a.x - b.x, a.y - b.y)
    }

    private func fireHaptic() {
        guard hapticsEnabled else { return }
        haptic.impactOccurred(intensity: 0.6)
    }
}
