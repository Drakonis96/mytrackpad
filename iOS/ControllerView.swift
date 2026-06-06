import SwiftUI

struct ControllerView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showFunctions = false
    @State private var showSettings = false
    @State private var keyboardActive = false

    var body: some View {
        VStack(spacing: 14) {
            header
            trackpadSurface
            controlBar
        }
        .padding(16)
        .overlay(alignment: .bottom) {
            if keyboardActive { keyboardHint }
        }
        .background {
            // Invisible field that receives the system keyboard.
            KeyboardCaptureField(
                onText: { text in model.send(ControlMessage(kind: .text, text: text)) },
                onBackspace: { model.send(ControlMessage(kind: .key, key: "delete")) },
                onReturn: { model.send(ControlMessage(kind: .key, key: "return")) },
                isActive: $keyboardActive
            )
            .frame(width: 1, height: 1)
            .opacity(0.01)
        }
        .sheet(isPresented: $showFunctions) { FunctionsSheet() }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.green)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(deviceName)
                    .font(.headline)
                Text("Connected")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill").font(.title3)
            }
            .buttonStyle(.glass)

            Button(role: .destructive) {
                model.disconnect()
            } label: {
                Image(systemName: "xmark").font(.title3)
            }
            .buttonStyle(.glass)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private var deviceName: String {
        if case let .connected(name) = model.connection { return name }
        return "Mac"
    }

    // MARK: - Trackpad surface

    private var trackpadSurface: some View {
        ZStack {
            TrackpadView(model: model)
            VStack {
                Spacer()
                Text("Move · tap = click · two-finger tap = menu · two fingers scroll/pinch · three fingers switch spaces")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 14)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
        .contentShape(Rectangle())
    }

    // MARK: - Control bar

    private var controlBar: some View {
        VStack(spacing: 12) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    clickButton(title: "Left click", symbol: "cursorarrow.click") {
                        model.send(ControlMessage(kind: .leftClick))
                    }
                    clickButton(title: "Right click", symbol: "cursorarrow.click.badge.clock") {
                        model.send(ControlMessage(kind: .rightClick))
                    }
                }
            }

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    utilityButton(title: "Keyboard", symbol: "keyboard", active: keyboardActive) {
                        keyboardActive.toggle()
                    }
                    utilityButton(title: "Functions", symbol: "slider.horizontal.3", active: false) {
                        showFunctions = true
                    }
                }
            }
        }
    }

    private func clickButton(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                Text(title).font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
        }
        .buttonStyle(.glass)
    }

    private func utilityButton(title: String, symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                Text(title).font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .buttonStyle(.glass)
        .tint(active ? .accentColor : nil)
    }

    private var keyboardHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard")
            Text("Typing on the Mac")
                .font(.subheadline)
            Spacer()
            Button("Hide") { keyboardActive = false }
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }
}
