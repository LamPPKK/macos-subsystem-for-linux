import SwiftUI

@main
struct MSLSettingsApplication: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("MSL Settings") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1_020, minHeight: 680)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Runtimes") { model.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.isBusy)
            }
        }
    }
}
