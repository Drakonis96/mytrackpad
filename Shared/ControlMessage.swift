import Foundation

/// Control message that travels from the iPhone to the Mac.
/// It is serialized as JSON and framed with a length prefix (see `Framing`).
struct ControlMessage: Codable {
    enum Kind: String, Codable {
        case hello        // initial handshake (includes the device name)
        case move         // relative cursor movement (dx, dy in points)
        case scroll       // two-finger scrolling (dx, dy)
        case leftClick    // left click
        case rightClick   // right click (two fingers)
        case leftDown     // press and hold the left button (start of a drag)
        case leftUp       // release the left button (end of a drag)
        case zoom         // pinch to zoom (amount = distance delta)
        case text         // literal text to type
        case key          // special key (arrows, return, delete, esc...)
        case media        // media button / quick function
    }

    var kind: Kind
    var dx: Double?
    var dy: Double?
    var amount: Double?
    var text: String?
    var key: String?
    var modifiers: [String]?
    var media: String?
    var name: String?

    init(kind: Kind,
         dx: Double? = nil,
         dy: Double? = nil,
         amount: Double? = nil,
         text: String? = nil,
         key: String? = nil,
         modifiers: [String]? = nil,
         media: String? = nil,
         name: String? = nil) {
        self.kind = kind
        self.dx = dx
        self.dy = dy
        self.amount = amount
        self.text = text
        self.key = key
        self.modifiers = modifiers
        self.media = media
        self.name = name
    }
}
