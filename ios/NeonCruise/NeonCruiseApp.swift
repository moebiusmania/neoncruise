import SwiftUI

@main
struct NeonCruiseApp: App {
    @State private var player = Player(meta: MetaStore())
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(player)
                .onAppear {
                    player.meta.start()
                    #if DEBUG
                    // UI tests and simulator runs: `-autoplay` starts the stream on launch.
                    if ProcessInfo.processInfo.arguments.contains("-autoplay") { player.play() }
                    #endif
                }
                .onChange(of: phase) { _, p in player.setVisible(p == .active) }
        }
    }
}
