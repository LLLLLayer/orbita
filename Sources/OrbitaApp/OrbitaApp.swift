import SwiftUI
import OrbitaCore

@main
struct OrbitaApp: App {
    var body: some Scene {
        WindowGroup("Orbita") {
            ContentView()
                .frame(minWidth: 1180, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
