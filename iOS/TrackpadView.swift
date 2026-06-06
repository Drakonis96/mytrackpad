import SwiftUI
import UIKit

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

    var sensitivity: CGFloat = 1.8
    var naturalScroll = true
    var hapticsEnabled = true

    // Gesture thresholds
    private let tapMaxDuration: TimeInterval = 0.28
    private let tapMaxMovement: CGFloat = 14
    private let dragInitiationWindow: TimeInterval = 0.32
    private let scrollSensitivity: CGFloat = 1.0

    // State of the in-progress gesture
    private var gestureStart = Date()
    private var activeCount = 0
    private var peakCount = 0
    private var accumulatedMovement: CGFloat = 0
    private var lastSinglePoint: CGPoint = .zero
    private var lastCentroid: CGPoint = .zero
    private var lastDistance: CGFloat = 0
    private var twoFingerMode: TwoFingerMode = .undecided

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
        }
        activeCount = touchesNow.count
        peakCount = max(peakCount, activeCount)

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
            twoFingerMode = .undecided
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let touchesNow = activeTouches(event)

        if touchesNow.count == 1, let p = touchesNow.first?.location(in: self) {
            let dx = p.x - lastSinglePoint.x
            let dy = p.y - lastSinglePoint.y
            lastSinglePoint = p
            accumulatedMovement += hypot(dx, dy)
            onMove?(dx * sensitivity, dy * sensitivity)
        } else if touchesNow.count >= 2 {
            let c = centroid(touchesNow)
            let dx = c.x - lastCentroid.x
            let dy = c.y - lastCentroid.y
            lastCentroid = c

            let d = spread(touchesNow)
            let dd = d - lastDistance
            lastDistance = d

            let pan = hypot(dx, dy)
            if twoFingerMode == .undecided {
                if abs(dd) > 6 && abs(dd) > pan {
                    twoFingerMode = .zoom
                } else if pan > 2 {
                    twoFingerMode = .scroll
                }
            }

            accumulatedMovement += max(pan, abs(dd))
            switch twoFingerMode {
            case .scroll:
                onScroll?(dx * scrollSensitivity, dy * scrollSensitivity)
            case .zoom:
                onZoom?(dd)
            case .undecided:
                break
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let remaining = activeTouches(event).filter { $0.phase != .ended && $0.phase != .cancelled }
        finishGesture(remaining: remaining)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        let remaining = activeTouches(event).filter { $0.phase != .ended && $0.phase != .cancelled }
        if dragging { onLeftUp?(); dragging = false }
        if remaining.isEmpty { resetGesture() } else { activeCount = remaining.count }
    }

    private func finishGesture(remaining: [UITouch]) {
        if remaining.isEmpty {
            let duration = Date().timeIntervalSince(gestureStart)
            if dragging {
                onLeftUp?()
                dragging = false
            } else if accumulatedMovement < tapMaxMovement && duration < tapMaxDuration {
                if peakCount >= 2 {
                    onRightClick?()
                    fireHaptic()
                } else {
                    onLeftClick?()
                    lastTapEnd = Date()
                    fireHaptic()
                }
            }
            resetGesture()
        } else {
            // One finger lifted but at least one remains: recalibrate to avoid jumps.
            activeCount = remaining.count
            if remaining.count == 1, let p = remaining.first?.location(in: self) {
                lastSinglePoint = p
            } else {
                lastCentroid = centroid(remaining)
                lastDistance = spread(remaining)
            }
        }
    }

    private func resetGesture() {
        activeCount = 0
        peakCount = 0
        accumulatedMovement = 0
        twoFingerMode = .undecided
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
