import Foundation
import Network

/// A Mac discovered on the local / peer-to-peer network.
struct DiscoveredDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let endpoint: NWEndpoint
}

enum ConnectionState: Equatable {
    case idle
    case scanning
    case connecting(String)
    case connected(String)
    case failed(String)
}

/// Searches for Macs advertising the `_mytrackpad._tcp` service over Bonjour.
/// Enables `includePeerToPeer` to also discover over a direct link (AWDL/Bluetooth-assisted).
final class BonjourBrowser {
    var onChange: (([DiscoveredDevice]) -> Void)?
    private var browser: NWBrowser?

    func start() {
        stop()
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: Framing.serviceType, domain: nil), using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let devices: [DiscoveredDevice] = results.compactMap { result in
                if case let .service(name, _, _, _) = result.endpoint {
                    return DiscoveredDevice(id: name, name: name, endpoint: result.endpoint)
                }
                return nil
            }
            DispatchQueue.main.async { self?.onChange?(devices) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}

/// TCP connection to the Mac. Sends framed messages with low latency (TCP_NODELAY).
final class TrackpadClient {
    var onStateChange: ((ConnectionState) -> Void)?

    private let endpoint: NWEndpoint
    private let deviceName: String
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.drakonis96.mytrackpad.client")
    private var didConnect = false
    private var timeoutItem: DispatchWorkItem?

    init(endpoint: NWEndpoint, name: String? = nil) {
        self.endpoint = endpoint
        if let name {
            self.deviceName = name
        } else if case let .service(serviceName, _, _, _) = endpoint {
            self.deviceName = serviceName
        } else {
            self.deviceName = "Mac"
        }
    }

    /// Manual connection by IP/host using the server's fixed port.
    convenience init(host: String, name: String) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: Framing.port) ?? .any
        )
        self.init(endpoint: endpoint, name: name)
    }

    func start() {
        let params = NWParameters.tcp
        if let tcp = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
        }
        params.includePeerToPeer = true

        let connection = NWConnection(to: endpoint, using: params)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.didConnect = true
                self.timeoutItem?.cancel()
                self.send(ControlMessage(kind: .hello, name: Self.localDeviceName()))
                DispatchQueue.main.async { self.onStateChange?(.connected(self.deviceName)) }
            case .waiting:
                DispatchQueue.main.async { self.onStateChange?(.connecting(self.deviceName)) }
            case .failed(let error):
                self.timeoutItem?.cancel()
                DispatchQueue.main.async { self.onStateChange?(.failed(error.localizedDescription)) }
            case .cancelled:
                DispatchQueue.main.async { self.onStateChange?(.idle) }
            default:
                break
            }
        }
        self.connection = connection

        // If it does not connect within a reasonable time (wrong IP, Mac
        // turned off, different network), notify instead of staying on "Connecting…".
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, !self.didConnect else { return }
            self.connection?.cancel()
            DispatchQueue.main.async {
                self.onStateChange?(.failed("Could not connect. Check the IP and that the Mac is on the same network with MyTrackpad Server open."))
            }
        }
        self.timeoutItem = timeout
        queue.asyncAfter(deadline: .now() + 8, execute: timeout)

        connection.start(queue: queue)
    }

    func stop() {
        timeoutItem?.cancel()
        connection?.cancel()
        connection = nil
    }

    func send(_ message: ControlMessage) {
        let data = Framing.encode(message)
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    private static func localDeviceName() -> String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "iPhone"
        #endif
    }
}

#if canImport(UIKit)
import UIKit
#endif
