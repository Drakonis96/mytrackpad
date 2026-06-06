import SwiftUI

@main
struct MyTrackpadApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            BackgroundView()
            if model.isConnected {
                ControllerView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                DiscoveryView()
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.35), value: model.isConnected)
    }
}

/// Vivid gradient background that makes the liquid glass shine.
struct BackgroundView: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.06, blue: 0.12),
                Color(red: 0.10, green: 0.05, blue: 0.18),
                Color(red: 0.02, green: 0.10, blue: 0.16)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            RadialGradient(
                colors: [Color.purple.opacity(0.35), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 420
            )
        )
        .overlay(
            RadialGradient(
                colors: [Color.cyan.opacity(0.25), .clear],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 420
            )
        )
        .ignoresSafeArea()
    }
}
