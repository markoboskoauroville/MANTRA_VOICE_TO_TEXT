// v17 (Marko, 14.11.2026: "Make two columns. Radio buttons to select the actual engine for each language ... I want the same
// menu design as in TTT"). TTT's Voice transcription buttons screen (MaVoiceButtonsScreen.kt, ttt-design): the host colours
// (background #11151C, key #1C2129, lit #262C36, ink #E6EDF3, muted #8B949E, gold #E8B15C for numbers, ring red #E53935 for the
// chosen one), two columns, a header pill per column with the letter (H Croatian, E English) and the engine in use, one
// rounded card per engine with its radio, its name and accuracy in parentheses, and the free/minutes/key line under it.
import AppKit

enum Host {
    static let bg = NSColor(srgbRed: 0x11 / 255, green: 0x15 / 255, blue: 0x1C / 255, alpha: 1)
    static let key = NSColor(srgbRed: 0x1C / 255, green: 0x21 / 255, blue: 0x29 / 255, alpha: 1)
    static let lit = NSColor(srgbRed: 0x26 / 255, green: 0x2C / 255, blue: 0x36 / 255, alpha: 1)
    static let ink = NSColor(srgbRed: 0xE6 / 255, green: 0xED / 255, blue: 0xF3 / 255, alpha: 1)
    static let muted = NSColor(srgbRed: 0x8B / 255, green: 0x94 / 255, blue: 0x9E / 255, alpha: 1)
    static let gold = NSColor(srgbRed: 0xE8 / 255, green: 0xB1 / 255, blue: 0x5C / 255, alpha: 1)
    static let red = NSColor(srgbRed: 0xE5 / 255, green: 0x39 / 255, blue: 0x35 / 255, alpha: 1)
    static let darkRed = NSColor(srgbRed: 0x9B / 255, green: 0x3B / 255, blue: 0x33 / 255, alpha: 1)
    static let sand = NSColor(srgbRed: 0xF2 / 255, green: 0xDD / 255, blue: 0xB4 / 255, alpha: 1)
    static let green = NSColor(srgbRed: 0x6F / 255, green: 0xA8 / 255, blue: 0x5A / 255, alpha: 1)
}

/// one engine as a card: radio, name (accuracy in gold in parentheses), sub line; a click picks it
final class EngineCard: NSView {
    let id: String, lang: String
    var onPick: ((String, String) -> Void)?
    var chosen = false { didSet { needsDisplay = true } }
    var usable = true { didSet { needsDisplay = true; alphaValue = usable ? 1 : 0.45 } }
    var hovering = false { didSet { needsDisplay = true } }
    var name = "" { didSet { needsDisplay = true } }
    var pct = "" { didSet { needsDisplay = true } }
    var sub = "" { didSet { needsDisplay = true } }
    init(id: String, lang: String) {
        self.id = id; self.lang = lang
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 52))
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 52).isActive = true
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
        setAccessibilityRole(.radioButton); setAccessibilityIdentifier("engine-\(lang)-\(id)")
    }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 52) }
    override func mouseEntered(with e: NSEvent) { if usable { hovering = true } }
    override func mouseExited(with e: NSEvent) { hovering = false }
    override func mouseDown(with e: NSEvent) { if usable { onPick?(lang, id) } }
    override func accessibilityPerformPress() -> Bool { if usable { onPick?(lang, id) }; return usable }
    override func accessibilityValue() -> Any? { chosen ? 1 : 0 }
    override func accessibilityLabel() -> String? { name + " " + pct }
    override func draw(_ r: NSRect) {
        let box = bounds.insetBy(dx: 1, dy: 1)
        let p = NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12)
        (chosen ? Host.red.withAlphaComponent(0.12) : hovering ? Host.lit : Host.key).setFill(); p.fill()
        (chosen ? Host.red : NSColor(white: 1, alpha: 0.10)).setStroke(); p.lineWidth = chosen ? 2 : 1; p.stroke()
        let cy = bounds.midY
        let ring = NSBezierPath(ovalIn: NSRect(x: 14, y: cy - 9, width: 18, height: 18).insetBy(dx: 1, dy: 1))
        (chosen ? Host.red : Host.muted).setStroke(); ring.lineWidth = 2; ring.stroke()
        if chosen { Host.red.setFill(); NSBezierPath(ovalIn: NSRect(x: 19, y: cy - 4, width: 8, height: 8)).fill() }
        let title = NSMutableAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: Host.ink])
        if !pct.isEmpty { title.append(NSAttributedString(string: " " + pct, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold), .foregroundColor: Host.gold])) }
        let w = bounds.width - 46 - 10
        title.draw(with: NSRect(x: 44, y: cy + 1, width: w, height: 20), options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin], context: nil)
        NSAttributedString(string: sub, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: Host.muted])
            .draw(with: NSRect(x: 44, y: cy - 19, width: w, height: 16), options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin], context: nil)
    }
    override var isFlipped: Bool { false }
}

/// the pill that heads a column: the letter, the engine in use (TTT's H and E keys, red ring)
final class ColumnHead: NSView {
    var letter = "", engine = "", pct = ""
    var ringColour = Host.red
    override init(frame: NSRect) {
        super.init(frame: frame); translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 48).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ r: NSRect) {
        let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 24, yRadius: 24)
        Host.key.setFill(); p.fill(); ringColour.setStroke(); p.lineWidth = 2; p.stroke()
        let s = NSMutableAttributedString(string: letter + "  ", attributes: [.font: NSFont.systemFont(ofSize: 20, weight: .bold), .foregroundColor: Host.ink])
        s.append(NSAttributedString(string: engine, attributes: [.font: NSFont.systemFont(ofSize: 17), .foregroundColor: Host.sand]))
        if !pct.isEmpty { s.append(NSAttributedString(string: " " + pct, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 17, weight: .regular), .foregroundColor: Host.gold])) }
        let h = s.size().height
        s.draw(with: NSRect(x: 18, y: bounds.midY - h / 2, width: bounds.width - 30, height: h), options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin], context: nil)
    }
}
