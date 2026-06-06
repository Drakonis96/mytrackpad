import SwiftUI
import UIKit

struct DiscoveryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pulse = false
    @FocusState private var manualFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                VStack(spacing: 16) {
                    ZStack {
                        ForEach(0..<3) { i in
                            Circle()
                                .stroke(Color.white.opacity(0.12), lineWidth: 1.5)
                                .frame(width: 90 + CGFloat(i) * 46, height: 90 + CGFloat(i) * 46)
                                .scaleEffect(pulse ? 1.06 : 0.96)
                                .opacity(pulse ? 0.2 : 0.6)
                                .animation(.easeInOut(duration: 1.6).repeatForever().delay(Double(i) * 0.25), value: pulse)
                        }
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .frame(height: 180)

                    Text("MyTrackpad")
                        .font(.largeTitle.bold())
                    Text(statusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                if case let .failed(message) = model.connection {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                GlassEffectContainer(spacing: 14) {
                    VStack(spacing: 12) {
                        if model.devices.isEmpty {
                            emptyState
                        } else {
                            ForEach(model.devices) { device in
                                deviceRow(device)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                manualConnectCard
                    .padding(.horizontal, 20)

                Text("Find your Mac on the same Wi-Fi network. Make sure\nMyTrackpad Server is open on your Mac.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            pulse = true
            model.startScanning()
        }
        .onDisappear { model.stopScanning() }
    }

    // MARK: - Manual connection by IP

    private var manualConnectCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .foregroundStyle(.secondary)
                Text("Don't see your Mac?")
                    .font(.subheadline.weight(.semibold))
            }
            Text("Type or paste the IP shown by MyTrackpad Server on your Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField("192.168.1.42", text: $model.manualHost)
                    .font(.body.monospaced())
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($manualFieldFocused)
                    .onSubmit(connectManually)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .glassEffect(.regular, in: .rect(cornerRadius: 14))

                Button(action: pasteFromClipboard) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.title3)
                        .frame(width: 50, height: 48)
                }
                .buttonStyle(.glass)
            }

            Button(action: connectManually) {
                Text("Connect by IP")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.glass)
            .disabled(trimmedHost.isEmpty)
            .opacity(trimmedHost.isEmpty ? 0.5 : 1)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private var trimmedHost: String {
        model.manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func connectManually() {
        manualFieldFocused = false
        model.connectManually()
    }

    private func pasteFromClipboard() {
        if let text = UIPasteboard.general.string {
            model.manualHost = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private var statusText: String {
        switch model.connection {
        case .connecting(let name): return "Connecting to \(name)…"
        default: return model.devices.isEmpty ? "Searching for devices…" : "Choose your Mac"
        }
    }

    private var emptyState: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Scanning the local network…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func deviceRow(_ device: DiscoveredDevice) -> some View {
        Button {
            model.connect(to: device)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "macbook")
                    .font(.title2)
                    .frame(width: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.headline)
                    Text("Tap to connect")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isConnecting(device) {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
    }

    private func isConnecting(_ device: DiscoveredDevice) -> Bool {
        if case let .connecting(name) = model.connection { return name == device.name }
        return false
    }
}
