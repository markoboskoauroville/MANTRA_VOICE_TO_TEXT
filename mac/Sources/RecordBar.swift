// THE RECORDING BAR, TTT Mini's on the Mac (Marko, 18.10.2026: "please check my app TTT Mini and its vu meter ... I want
// the same user interface here for dictation"). From TTT_MINI dictate/ui/MaRecordMeter.kt and audio/AudioLevelSmoother.kt:
//
//   🗑 throw away · ● the lamp, red while capturing, dark while paused (it does not pulse: "nothing in this app breathes")
//   · the clock, the one number always wanted · the size on disk · 🌐 the language · ⏸ pause / ▶ go on
//
// No ➤ send since request 16 (19.10.2026: "this send button on the UI is not necessary because F1 does the thing"),
// and a pipe between the parts as on the rest of the stripe.
//
// and a hairline meter along the bottom of the whole stripe: the level in its state colour, a peak marker falling back
// slowly so a transient stays readable; while the take is being written down and styled there is no microphone, so the
// line spreads out from the centre both ways, "decoration rather than data, and honest about it".
import AppKit

final class Meter: NSView {
    enum Mode { case off, level, sending }
    var mode: Mode = .off { didSet { needsDisplay = true } }
    var levelDB: Float = -60 { didSet { needsDisplay = true } }
    var peakDB: Float = -60
    var sweep: CGFloat = 0
    private var rising = true
    static let floor: Float = -50                       // below this the line is empty

    func norm(_ db: Float) -> CGFloat { CGFloat(min(max((db - Meter.floor) / -Meter.floor, 0), 1)) }

    // the colour is the state: green speech, amber loud, red at the top
    func colour(_ db: Float) -> NSColor { db > -3 ? Ink.red : db > -10 ? Ink.amber : Ink.green }

    // A new reading: quick to rise, slower to fall (the smoother's attack and release), the peak falling 0.6 dB a step.
    func feed(_ db: Float?) {
        guard let db else { levelDB = Meter.floor; return }
        let rate: Float = db > levelDB ? 0.55 : 0.20
        levelDB += (db - levelDB) * rate
        peakDB = db > peakDB ? db : max(peakDB - 0.6, Meter.floor)
    }

    func step() {
        sweep = min(max(sweep + (rising ? 0.06 : -0.06), 0), 1)
        if sweep >= 1 { rising = false }
        if sweep <= 0 { rising = true }
        needsDisplay = true
    }

    override func draw(_ r: NSRect) {
        guard mode != .off else { return }
        let h = bounds.height, w = bounds.width
        func bar(_ x: CGFloat, _ width: CGFloat, _ c: NSColor) {
            c.setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: width, height: h), xRadius: h / 2, yRadius: h / 2).fill()
        }
        bar(0, w, Ink.text.withAlphaComponent(0.12))
        if mode == .sending {
            let reach = w / 2 * sweep
            bar(w / 2 - reach, reach * 2, Ink.amber.withAlphaComponent(0.85))
        } else {
            bar(0, w * norm(levelDB), colour(levelDB))
            bar(min(w * norm(peakDB), w - 2), 2, colour(peakDB).withAlphaComponent(0.9))
        }
    }
}

final class RecordBar: NSStackView {
    let trash = RecordBar.button("trash", "Throw this take away (Esc)")
    let lamp = Dot()
    let clock = NSTextField(labelWithString: "0:00")
    let size = NSTextField(labelWithString: "0.0 MB")
    let lang = RecordBar.button("globe", "The language of this take: Croatian or English")
    let pause = RecordBar.button("pause.fill", "Pause; press again to go on")

    static func button(_ symbol: String, _ tip: String) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage(), target: nil, action: nil)
        b.isBordered = false
        b.title = ""                                    // NSButton(image:) carries the word "Button" otherwise
        b.toolTip = tip
        b.contentTintColor = Ink.text
        b.imagePosition = .imageLeading
        b.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        b.setContentHuggingPriority(.required, for: .horizontal)
        return b
    }

    init() {
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 5
        lamp.translatesAutoresizingMaskIntoConstraints = false
        lamp.widthAnchor.constraint(equalToConstant: 11).isActive = true
        lamp.heightAnchor.constraint(equalToConstant: 11).isActive = true
        lamp.color = Ink.red
        clock.font = .monospacedDigitSystemFont(ofSize: 14, weight: .bold)
        clock.textColor = Ink.text
        size.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        size.textColor = Ink.dim
        for l in [clock, size] { l.maximumNumberOfLines = 1; l.cell?.wraps = false; l.setContentHuggingPriority(.required, for: .horizontal) }
        clock.widthAnchor.constraint(equalToConstant: textWidth("88:88", clock.font!)).isActive = true
        size.widthAnchor.constraint(equalToConstant: textWidth("88.8 MB", size.font!)).isActive = true
        let lampAndClock = NSStackView(views: [lamp, clock, size])
        lampAndClock.spacing = 6
        lampAndClock.alignment = .centerY
        func pipe() -> NSTextField { let p = NSTextField(labelWithString: "|"); p.textColor = Ink.grey; p.font = .systemFont(ofSize: 12); return p }
        alignment = .centerY
        setViews([trash, pipe(), lampAndClock, pipe(), lang, pipe(), pause], in: .leading)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(elapsed: TimeInterval, megabytes: Double, paused: Bool, language: String) {
        let s = Int(elapsed)
        clock.stringValue = String(format: "%d:%02d", s / 60, s % 60)
        size.stringValue = String(format: "%.1f MB", megabytes)
        lamp.color = paused ? Ink.grey : Ink.red
        pause.image = NSImage(systemSymbolName: paused ? "play.fill" : "pause.fill", accessibilityDescription: nil)
        lang.title = language.uppercased()
    }
}
