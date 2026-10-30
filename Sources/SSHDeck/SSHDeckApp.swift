import SwiftUI

@main
struct SSHDeckApp: App {
    @StateObject private var store = HostMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 980, minHeight: 650)
        }
        .defaultSize(width: 1180, height: 760)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandMenu("Hosts") {
                Button("Refresh All") {
                    store.refreshAll()
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Reload SSH Config") {
                    store.reloadConfiguration()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()

                Button("Open in Terminal") {
                    if let host = store.selectedSnapshot?.host {
                        TerminalLauncher.openTerminal(for: host)
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(store.selectedSnapshot == nil)

                Button("Copy SSH Command") {
                    if let host = store.selectedSnapshot?.host {
                        TerminalLauncher.copyCommand(for: host)
                    }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(store.selectedSnapshot == nil)
            }
        }
    }
}
