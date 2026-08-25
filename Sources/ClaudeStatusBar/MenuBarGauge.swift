import AppKit

/// The menu bar view: a ring that fills up with the current utilization.
/// The fill eases toward new values instead of snapping, and breathes
/// (slow alpha pulse) once usage is critical.
final class MenuBarGauge: NSView {
    var onClick: ((NSEvent) -> Void)?

    private var target: Double = 0
    private var displayed: Double = 0
    private var pulsePhase: Double = 0
    private var animation: Timer?
    private var level: UsageLevel = .comfortable
    private var isStale = false

    private static let frameDuration = 1.0 / 30.0
    private static let ringWidth: CGFloat = 2.6

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 46, height: NSStatusBar.system.thickness))
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Preferences.showTextInMenuBar ? 62 : 30, height: NSStatusBar.system.thickness)
    }

    func update(fraction: Double, level: UsageLevel, stale: Bool) {
        target = min(max(fraction, 0), 1)
        self.level = level
        isStale = stale
        setFrameSize(intrinsicContentSize)
        startAnimating()
    }

    private func startAnimating() {
        guard animation == nil else { return }
        animation = Timer.scheduledTimer(withTimeInterval: Self.frameDuration, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.step(timer)
        }
        RunLoop.main.add(animation!, forMode: .common)
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
        needsDisplay = true
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

    override func draw(_ dirtyRect: NSRect) {
        let pulse = pulsePhase > 0 ? 0.55 + 0.45 * (0.5 + 0.5 * sin(pulsePhase * 4)) : 1.0
        let diameter = min(bounds.height - 6, 16)
        let ringRect = NSRect(x: 5, y: (bounds.height - diameter) / 2, width: diameter, height: diameter)
        let center = NSPoint(x: ringRect.midX, y: ringRect.midY)
        let radius = diameter / 2 - Self.ringWidth / 2

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
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: ringRect.maxX + 5, y: (bounds.height - size.height) / 2),
                  withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) { onClick?(event) }
    override func rightMouseDown(with event: NSEvent) { onClick?(event) }
}
