import Foundation

/// Transport protocol shared between iOS and macOS.
/// Each message is sent as: [length UInt32 big-endian][JSON payload].
enum Framing {
    /// Bonjour service type used to advertise and discover the Mac.
    static let serviceType = "_mytrackpad._tcp"

    /// Fixed TCP port of the server. Enables manual connection by IP
    /// (typing the IP on the iPhone) in addition to Bonjour discovery.
    /// Useful when mDNS does not work: networks with client isolation,
    /// VPN, or sandboxed apps like LiveContainer.
    static let port: UInt16 = 52525

    /// Reasonable maximum size for a message; guards against corrupt data.
    static let maxMessageBytes = 1 << 20  // 1 MB

    static func encode(_ message: ControlMessage) -> Data {
        let payload = (try? JSONEncoder().encode(message)) ?? Data()
        let len = UInt32(payload.count)
        var data = Data(capacity: payload.count + 4)
        data.append(UInt8((len >> 24) & 0xFF))
        data.append(UInt8((len >> 16) & 0xFF))
        data.append(UInt8((len >> 8) & 0xFF))
        data.append(UInt8(len & 0xFF))
        data.append(payload)
        return data
    }
}

/// Accumulates incoming bytes and extracts complete messages (Mac side).
///
/// Uses a `[UInt8]` buffer with indices always base-0; this avoids the
/// `Data.subdata(in:)` bug when `startIndex` is no longer 0 after `removeFirst`.
final class FrameDecoder {
    private var buffer: [UInt8] = []

    func append(_ data: Data) -> [ControlMessage] {
        buffer.append(contentsOf: data)
        var out: [ControlMessage] = []
        var offset = 0

        while buffer.count - offset >= 4 {
            let len = (UInt32(buffer[offset]) << 24)
                    | (UInt32(buffer[offset + 1]) << 16)
                    | (UInt32(buffer[offset + 2]) << 8)
                    |  UInt32(buffer[offset + 3])

            // Impossible message → corrupt stream: discard everything and resync.
            if Int(len) > Framing.maxMessageBytes {
                buffer.removeAll(keepingCapacity: false)
                return out
            }

            let total = 4 + Int(len)
            if buffer.count - offset < total { break }

            let payload = Data(buffer[(offset + 4)..<(offset + total)])
            offset += total

            if let message = try? JSONDecoder().decode(ControlMessage.self, from: payload) {
                out.append(message)
            }
        }

        if offset > 0 {
            buffer.removeFirst(offset)
        }
        return out
    }
}
