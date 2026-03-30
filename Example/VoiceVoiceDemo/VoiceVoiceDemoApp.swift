import SwiftUI

@main
struct VoiceVoiceDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .frame(minWidth: 500, minHeight: 600)
                #endif
        }
    }
}
