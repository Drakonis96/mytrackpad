import SwiftUI
import Network

@MainActor
final class AppModel: ObservableObject {
    @Published var devices: [DiscoveredDevice] = []
    @Published var connection: ConnectionState = .idle

    // Settings
    @Published var sensitivity: Double = 1.8      // cursor speed multiplier
    @Published var naturalScroll: Bool = true
    @Published var hapticsEnabled: Bool = true

    /// Last manually entered IP; remembered across sessions.
    @Published var manualHost: String {
        didSet { UserDefaults.standard.set(manualHost, forKey: Self.manualHostKey) }
    }
    private static let manualHostKey = "manualHost"

    private let browser = BonjourBrowser()
    private var client: TrackpadClient?

    init() {
        manualHost = UserDefaults.standard.string(forKey: Self.manualHostKey) ?? ""
        browser.onChange = { [weak self] devices in
            self?.devices = devices
        }
    }

    var isConnected: Bool {
        if case .connected = connection { return true }
        return false
    }

    func startScanning() {
        if case .connected = connection { return }
        connection = .scanning
        browser.start()
    }

    func stopScanning() {
        browser.stop()
    }

    func connect(to device: DiscoveredDevice) {
        client?.stop()
        let client = TrackpadClient(endpoint: device.endpoint)
        client.onStateChange = { [weak self] state in
            self?.connection = state
        }
        self.client = client
        connection = .connecting(device.name)
        client.start()
    }

    /// Manual connection by IP when Bonjour does not discover the Mac.
    func connectManually() {
        let host = manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }
        manualHost = host
        client?.stop()
        let client = TrackpadClient(host: host, name: host)
        client.onStateChange = { [weak self] state in
            self?.connection = state
        }
        self.client = client
        connection = .connecting(host)
        client.start()
    }

    func disconnect() {
        client?.stop()
        client = nil
        connection = .idle
        startScanning()
    }

    func send(_ message: ControlMessage) {
        client?.send(message)
    }
}
