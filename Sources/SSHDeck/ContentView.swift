import SSHDeckCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: HostMonitor
    @State private var searchText = ""

    var body: some View {
        HSplitView {
            SidebarView(searchText: $searchText)
                .frame(minWidth: 280, idealWidth: 308, maxWidth: 360)

            DetailPane(searchText: searchText)
                .frame(minWidth: 620)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            store.start()
        }
    }
}

private struct DetailPane: View {
    @EnvironmentObject private var store: HostMonitor
    let searchText: String

    private var filteredHosts: [SSHHost] {
        guard !searchText.isEmpty else { return store.hosts }
        return store.hosts.filter {
            $0.alias.localizedCaseInsensitiveContains(searchText) ||
                $0.hostName.localizedCaseInsensitiveContains(searchText) ||
                $0.user.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var visibleSnapshot: HostSnapshot? {
        if let selected = store.selectedSnapshot,
           filteredHosts.contains(where: { $0.alias == selected.host.alias }) {
            return selected
        }
        guard let first = filteredHosts.first else { return nil }
        return store.snapshots[first.alias]
    }

    var body: some View {
        Group {
            if let snapshot = visibleSnapshot {
                HostDetailView(snapshot: snapshot)
            } else if store.isScanning {
                EmptyStateView(
                    symbol: "terminal",
                    title: "Reading SSH config",
                    message: nil,
                    showsProgress: true
                )
            } else if let scanError = store.scanError {
                EmptyStateView(
                    symbol: "exclamationmark.triangle",
                    title: "Unable to read SSH config",
                    message: scanError,
                    showsProgress: false,
                    actionTitle: "Reload",
                    action: { store.reloadConfiguration() }
                )
            } else {
                EmptyStateView(
                    symbol: "magnifyingglass",
                    title: "No matching hosts",
                    message: nil,
                    showsProgress: false
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String?
    let showsProgress: Bool
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title3.weight(.semibold))

            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            }

            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
            }
        }
        .padding(40)
    }
}
