import Foundation
import Network

/// Advertises the Bonjour service, accepts the iPhone connection, and applies the events.
final class TrackpadServer {
    var onClientChange: ((String?) -> Void)?
    var onRunningChange: ((Bool) -> Void)?

    private var listener: NWListener?
    private var connection: NWConnection?
    private let decoder = FrameDecoder()
    private let injector = EventInjector()
    private var clientName: String?

    /// Dedicated queue for networking and event injection. Keeping it off the main
    /// thread prevents UI rendering from causing the cursor to stutter.
    private let queue = DispatchQueue(label: "com.drakonis96.mytrackpad.server", qos: .userInteractive)

    func start() {
        do {
            let params = NWParameters.tcp
            if let tcp = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
                tcp.noDelay = true
            }
            params.includePeerToPeer = true

            // Fixed port so the iPhone can connect via manual IP, in addition to
            // advertising over Bonjour for automatic discovery.
            let port = NWEndpoint.Port(rawValue: Framing.port) ?? .any
            let listener = try NWListener(using: params, on: port)
            let hostName = Host.current().localizedName ?? "Mac"
            listener.service = NWListener.Service(name: hostName, type: Framing.serviceType)
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    DispatchQueue.main.async { self?.onRunningChange?(true) }
                case .failed, .cancelled:
                    DispatchQueue.main.async { self?.onRunningChange?(false) }
                default:
                    break
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            DispatchQueue.main.async { self.onRunningChange?(false) }
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.connection?.cancel()
            self?.listener?.cancel()
            self?.connection = nil
            self?.listener = nil
        }
    }

    private func accept(_ connection: NWConnection) {
        self.connection?.cancel()
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                DispatchQueue.main.async { self?.onClientChange?(self?.clientName ?? "iPhone") }
            case .failed, .cancelled:
                DispatchQueue.main.async { self?.onClientChange?(nil) }
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                for message in self.decoder.append(data) {
                    self.handle(message)
                }
            }
            if isComplete || error != nil {
                connection.cancel()
                DispatchQueue.main.async { self.onClientChange?(nil) }
                return
            }
            self.receive(on: connection)
        }
    }

    private func handle(_ message: ControlMessage) {
        switch message.kind {
        case .hello:
            clientName = message.name
            DispatchQueue.main.async { self.onClientChange?(message.name ?? "iPhone") }
        case .move:       injector.move(dx: message.dx ?? 0, dy: message.dy ?? 0)
        case .scroll:     injector.scroll(dx: message.dx ?? 0, dy: message.dy ?? 0)
        case .leftClick:  injector.leftClick()
        case .rightClick: injector.rightClick()
        case .leftDown:   injector.leftDown()
        case .leftUp:     injector.leftUp()
        case .zoom:       injector.zoom(amount: message.amount ?? 0)
        case .text:       if let text = message.text { injector.typeText(text) }
        case .key:        if let key = message.key { injector.pressKey(key, modifiers: message.modifiers ?? []) }
        case .media:      if let media = message.media { injector.media(media) }
        }
    }
}
