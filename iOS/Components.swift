import SwiftUI
import UIKit

// MARK: - Function/media button

struct FunctionButton: Identifiable {
    let id = UUID()
    let label: String
    let systemImage: String
    let media: String
}

enum FunctionButtons {
    /// Media / quick functions row.
    static let all: [FunctionButton] = [
        .init(label: "Brightness −", systemImage: "sun.min",                media: "brightDown"),
        .init(label: "Brightness +", systemImage: "sun.max.fill",           media: "brightUp"),
        .init(label: "Mission",      systemImage: "rectangle.3.group",      media: "missionControl"),
        .init(label: "App windows",  systemImage: "macwindow.on.rectangle", media: "appExpose"),
        .init(label: "Prev space",   systemImage: "chevron.left.2",         media: "spacePrev"),
        .init(label: "Next space",   systemImage: "chevron.right.2",        media: "spaceNext"),
        .init(label: "Spotlight",    systemImage: "magnifyingglass",        media: "spotlight"),
        .init(label: "Zoom +",       systemImage: "plus.magnifyingglass",   media: "zoomIn"),
        .init(label: "Zoom −",       systemImage: "minus.magnifyingglass",  media: "zoomOut"),
        .init(label: "Dictation",    systemImage: "mic.fill",               media: "dictation"),
        .init(label: "Previous",     systemImage: "backward.end.fill",      media: "prev"),
        .init(label: "Play/Pause",   systemImage: "playpause.fill",         media: "playPause"),
        .init(label: "Next",         systemImage: "forward.end.fill",       media: "next"),
        .init(label: "Mute",         systemImage: "speaker.slash.fill",     media: "mute"),
        .init(label: "Vol −",        systemImage: "speaker.wave.1.fill",    media: "volDown"),
        .init(label: "Vol +",        systemImage: "speaker.wave.3.fill",    media: "volUp")
    ]
}

// MARK: - Hold-to-repeat key button

/// A glass button that sends `keyDown` while held and `keyUp` on release, so the Mac
/// generates the native key auto-repeat. A quick tap sends a single key press.
struct HoldKeyButton<Label: View>: View {
    @EnvironmentObject private var model: AppModel
    let key: String
    var modifiers: [String] = []
    var cornerRadius: CGFloat = 16
    @ViewBuilder var label: () -> Label

    @State private var pressing = false
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        label()
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            .scaleEffect(pressing ? 0.93 : 1)
            .animation(.easeOut(duration: 0.12), value: pressing)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressing else { return }
                        pressing = true
                        if model.hapticsEnabled { haptic.impactOccurred(intensity: 0.5) }
                        model.send(ControlMessage(kind: .keyDown, key: key,
                                                  modifiers: modifiers.isEmpty ? nil : modifiers))
                    }
                    .onEnded { _ in
                        guard pressing else { return }
                        pressing = false
                        model.send(ControlMessage(kind: .keyUp, key: key,
                                                  modifiers: modifiers.isEmpty ? nil : modifiers))
                    }
            )
            .onDisappear {
                // Safety: release the key if the view goes away while still held.
                if pressing {
                    pressing = false
                    model.send(ControlMessage(kind: .keyUp, key: key,
                                              modifiers: modifiers.isEmpty ? nil : modifiers))
                }
            }
    }
}

// MARK: - Functions panel (arrows + media)

struct FunctionsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    sectionTitle("Keys")
                    SpecialKeysRow()
                    ArrowPad()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)

                    sectionTitle("Quick functions")
                    GlassEffectContainer(spacing: 12) {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(FunctionButtons.all) { item in
                                Button {
                                    model.send(ControlMessage(kind: .media, media: item.media))
                                } label: {
                                    VStack(spacing: 8) {
                                        Image(systemName: item.systemImage)
                                            .font(.title2)
                                        Text(item.label)
                                            .font(.caption2)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 72)
                                }
                                .buttonStyle(.glass)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Keys and functions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.thinMaterial)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Special keys

struct SpecialKeysRow: View {
    private let keys: [(String, String)] = [
        ("Esc", "escape"),
        ("Tab", "tab"),
        ("Return", "return"),
        ("Delete", "delete")
    ]

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(keys, id: \.1) { item in
                    HoldKeyButton(key: item.1, cornerRadius: 14) {
                        Text(item.0)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                }
            }
        }
    }
}

// MARK: - Arrow pad

struct ArrowPad: View {
    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                arrow("chevron.up", "up")
                HStack(spacing: 10) {
                    arrow("chevron.left", "left")
                    arrow("chevron.down", "down")
                    arrow("chevron.right", "right")
                }
            }
        }
    }

    private func arrow(_ symbol: String, _ key: String) -> some View {
        HoldKeyButton(key: key, cornerRadius: 16) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .frame(width: 66, height: 52)
        }
    }
}

// MARK: - Settings

struct SettingsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Cursor") {
                    VStack(alignment: .leading) {
                        Text("Speed: \(model.sensitivity, specifier: "%.1f")×")
                        Slider(value: $model.sensitivity, in: 0.6...3.5, step: 0.1)
                    }
                }
                Section("Scrolling") {
                    Toggle("Natural scrolling", isOn: $model.naturalScroll)
                }
                Section("General") {
                    Toggle("Haptic feedback on tap", isOn: $model.hapticsEnabled)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(.thinMaterial)
    }
}
