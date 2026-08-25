import AppKit

/// Draws the menu bar gauge — a ring that fills up with the current
/// utilization — into an image, one frame at a time.
///
/// Rendering to `NSStatusBarButton.image` instead of hosting a custom view
/// keeps the button's own geometry intact, which is what AppKit uses to
/// anchor the popover right under the menu bar.
@MainActor
final class MenuBarGauge {
    /// Called with a freshly rendered frame; assign it to the button's image.
    var onFrame: ((NSImage) -> Void)?

    private var target: Double = 0
    private var displayed: Double = 0
    private var pulsePhase: Double = 0
    private var animation: Timer?
    private var level: UsageLevel = .comfortable
    private var isStale = false

    private static let frameDuration = 1.0 / 30.0
    private static let ringWidth: CGFloat = 2.6
    private static let diameter: CGFloat = 16
    private static let height: CGFloat = 18

    var width: CGFloat {
        Preferences.showTextInMenuBar ? Self.diameter + 34 : Self.diameter + 4
    }

    func update(fraction: Double, level: UsageLevel, stale: Bool) {
        target = min(max(fraction, 0), 1)
        self.level = level
        isStale = stale
        startAnimating()
        render()
    }

    private func startAnimating() {
        guard animation == nil else { return }
        let timer = Timer(timeInterval: Self.frameDuration, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated { self?.step(timer) }
        }
        RunLoop.main.add(timer, forMode: .common)
        animation = timer
    }

    private func step(_ timer: Timer) {
        // Exponential ease toward the target; settles in roughly half a second.
        let delta = target - displayed
        displayed += delta * 0.18
        let settled = abs(delta) < 0.002
        if settled { displayed = target }

        let shouldPulse = level == .critical && !isStale
        pulsePhase = shouldPulse ? pulsePhase + Self.frameDuration : 0

        if settled && !shouldPulse {
            timer.invalidate()
            animation = nil
        }
        render()
    }

    private var tint: NSColor {
        if isStale { return .disabledControlTextColor }
        switch level {
        case .comfortable: return .systemGreen
        case .watch: return .systemYellow
        case .tight: return .systemOrange
        case .critical: return .systemRed
        }
    }

    private func render() {
        let size = NSSize(width: width, height: Self.height)
        let image = NSImage(size: size, flipped: false) { [self] _ in
            draw(in: size)
            return true
        }
        // Not a template image: the fill color is the whole point.
        image.isTemplate = false
        onFrame?(image)
    }

    private func draw(in size: NSSize) {
        let pulse = pulsePhase > 0 ? 0.55 + 0.45 * (0.5 + 0.5 * sin(pulsePhase * 4)) : 1.0
        let ringRect = NSRect(x: 2,
                              y: (size.height - Self.diameter) / 2,
                              width: Self.diameter,
                              height: Self.diameter)
        let center = NSPoint(x: ringRect.midX, y: ringRect.midY)
        let radius = Self.diameter / 2 - Self.ringWidth / 2

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = Self.ringWidth
        NSColor.tertiaryLabelColor.setStroke()
        track.stroke()

        if displayed > 0.001 {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center,
                          radius: radius,
                          startAngle: 90,
                          endAngle: 90 - 360 * displayed,
                          clockwise: true)
            arc.lineWidth = Self.ringWidth
            arc.lineCapStyle = .round
            tint.withAlphaComponent(pulse).setStroke()
            arc.stroke()
        }

        guard Preferences.showTextInMenuBar else { return }
        let text = "\(Int((displayed * 100).rounded()))%"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(pulse),
        ]
        let textSize = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: ringRect.maxX + 4, y: (size.height - textSize.height) / 2),
                  withAttributes: attributes)
    }
}
