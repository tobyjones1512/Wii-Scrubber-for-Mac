import SwiftUI

@main struct MyApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 720, minHeight: 480)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open ISO...") { openISO() }
                    .keyboardShortcut("o", modifiers: .command)
            }
        }
    }

    private func openISO() {
        PanelPresenter.openFile(configure: { $0.allowsOtherFileTypes = true }) { url in
            guard let url else { return }
            appState.openISO(url: url)
        }
    }
}
