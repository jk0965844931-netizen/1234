import SwiftUI

@main
struct LocalVoicePiPTranslatorApp: App {
    @StateObject private var coordinator = SpeechTranslationCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
        }
    }
}
