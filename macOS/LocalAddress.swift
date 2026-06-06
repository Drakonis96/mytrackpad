import Foundation

/// Discovers the Mac's local IPv4 address so it can be displayed and used to
/// connect manually from the iPhone when Bonjour doesn't work.
enum LocalAddress {
    /// IPv4 of the active network interface, prioritizing Wi-Fi (`en0`).
    /// Returns `nil` if there's no interface with IPv4 (no network).
    static func wifiIPv4() -> String? {
        var preferred: String?   // en0 = Wi-Fi on Mac
        var fallback: String?    // Ethernet / Thunderbolt / other enX

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            let interface = p.pointee

            // IPv4 only.
            guard let sa = interface.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }

            // Active interface and not loopback.
            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP == IFF_UP, flags & IFF_LOOPBACK == 0 else { continue }

            // Ethernet/Wi-Fi interfaces only (enX); discard utun, awdl, bridge…
            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("en") else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(sa, socklen_t(sa.pointee.sa_len),
                        &hostname, socklen_t(hostname.count),
                        nil, 0, NI_NUMERICHOST)
            let ip = String(cString: hostname)

            if name == "en0" {
                preferred = ip
            } else if fallback == nil {
                fallback = ip
            }
        }
        return preferred ?? fallback
    }
}
