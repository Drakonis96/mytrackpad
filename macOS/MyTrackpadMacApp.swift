import SwiftUI
import ApplicationServices

@main
struct MyTrackpadMacApp: App {
    @StateObject private var state = MacAppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(state)
        } label: {
            Image(systemName: state.connectedClient != nil ? "cursorarrow.click.2" : "cursorarrow.rays")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class MacAppState: ObservableObject {
    @Published var running = false
    @Published var connectedClient: String?
    @Published var accessibilityGranted = false
    @Published var localIP: String?
    @Published var didCopy = false

    private let server = TrackpadServer()
    private var pollTimer: Timer?
    private var didInitialCheck = false
    private var isRelaunching = false

    init() {
        server.onRunningChange = { [weak self] running in self?.running = running }
        server.onClientChange = { [weak self] name in self?.connectedClient = name }
        refreshAccessibility()
        refreshLocalIP()
        server.start()
        // Refresh Accessibility and IP in case they change while the app is running
        // (the user grants the permission, or switches Wi-Fi networks).
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAccessibility()
                self?.refreshLocalIP()
            }
        }
    }

    func refreshLocalIP() {
        localIP = LocalAddress.wifiIPv4()
    }

    func copyIP() {
        guard let ip = localIP else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ip, forType: .string)
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            self?.didCopy = false
        }
    }

    func refreshAccessibility() {
        let granted = AXIsProcessTrusted()
        let wasGranted = accessibilityGranted
        accessibilityGranted = granted
        // If the permission was just granted while the app was running, restart it
        // so that event injection becomes active without any manual steps.
        if granted && !wasGranted && didInitialCheck && !isRelaunching {
            relaunchApp()
        }
        didInitialCheck = true
    }

    private func relaunchApp() {
        isRelaunching = true
        let path = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        // Wait for this process to terminate, then reopen the bundle.
        let script = "while /bin/kill -0 \(pid) >/dev/null 2>&1; do /bin/sleep 0.2; done; /usr/bin/open \"\(path)\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]
        try? task.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject private var state: MacAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "cursorarrow.rays")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 1) {
                    Text("MyTrackpad Server")
                        .font(.headline)
                    Text(state.running ? "Advertising on the local network" : "Starting…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            statusRow(
                ok: state.running,
                title: state.running ? "Server running" : "Server stopped",
                detail: "Bonjour service _mytrackpad._tcp"
            )

            statusRow(
                ok: state.connectedClient != nil,
                title: state.connectedClient ?? "No device connected",
                detail: state.connectedClient != nil ? "iPhone connected" : "Waiting for a connection"
            )

            statusRow(
                ok: state.accessibilityGranted,
                title: state.accessibilityGranted ? "Accessibility granted" : "Accessibility permission missing",
                detail: "Required to move the cursor and type"
            )

            Divider()

            manualConnectSection

            if !state.accessibilityGranted {
                Button {
                    state.requestAccessibility()
                    state.openAccessibilitySettings()
                } label: {
                    Label("Grant Accessibility…", systemImage: "lock.shield")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    @ViewBuilder
    private var manualConnectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "wifi")
                    .foregroundStyle(.secondary)
                Text("Manual connection by IP")
                    .font(.subheadline.weight(.medium))
            }

            if let ip = state.localIP {
                HStack(spacing: 8) {
                    Text(ip)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                    Button {
                        state.copyIP()
                    } label: {
                        Label(state.didCopy ? "Copied" : "Copy",
                              systemImage: state.didCopy ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                Text("If the iPhone can't find the Mac on its own, type or paste this IP into the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No network. Connect the Mac to a Wi-Fi network to see its IP.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusRow(ok: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
