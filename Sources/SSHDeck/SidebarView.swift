import SSHDeckCore
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: HostMonitor
    @Binding var searchText: String

    private var filteredHosts: [SSHHost] {
        guard !searchText.isEmpty else { return store.hosts }
        return store.hosts.filter {
            $0.alias.localizedCaseInsensitiveContains(searchText) ||
                $0.hostName.localizedCaseInsensitiveContains(searchText) ||
                $0.user.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            if let scanError = store.scanError {
                Text(scanError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            Divider()

            hostList

            Divider()
            footer
        }
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.accent)
                Image(systemName: "terminal.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("SSH Deck")
                    .font(.system(size: 16, weight: .semibold))
                HStack(spacing: 5) {
                    StatusDot(state: store.onlineCount > 0 ? .online : .idle, size: 6)
                    Text("\(store.onlineCount) online · \(store.hosts.count) hosts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            if store.isRefreshing || store.isScanning {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 24, height: 24)
            } else {
                Button {
                    store.refreshAll()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help("Refresh all hosts")
            }
        }
        .padding(.top, 32)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search hosts, addresses, or users", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(AppTheme.subtleBorder, lineWidth: 1)
        )
    }

    private var hostList: some View {
        ScrollView {
            LazyVStack(spacing: 3) {
                ForEach(filteredHosts) { host in
                    if let snapshot = store.snapshots[host.alias] {
                        Button {
                            store.selectedAlias = host.alias
                        } label: {
                            HostRow(
                                snapshot: snapshot,
                                isSelected: store.selectedAlias == host.alias
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Auto refresh", selection: $store.refreshInterval) {
                    Text("Manual").tag(0.0)
                    Text("Every 15 seconds").tag(15.0)
                    Text("Every 30 seconds").tag(30.0)
                    Text("Every 1 minute").tag(60.0)
                    Text("Every 2 minutes").tag(120.0)
                    Text("Every 5 minutes").tag(300.0)
                }
                .pickerStyle(.inline)
            } label: {
                Label(refreshLabel, systemImage: "clock.arrow.circlepath")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            if let lastRefresh = store.lastRefresh {
                Text(DisplayFormat.time(lastRefresh))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
    }

    private var refreshLabel: String {
        switch Int(store.refreshInterval) {
        case 0: return "Manual"
        case 15: return "15s refresh"
        case 30: return "30s refresh"
        case 60: return "1m refresh"
        case 120: return "2m refresh"
        case 300: return "5m refresh"
        default: return "\(Int(store.refreshInterval))s refresh"
        }
    }
}

private struct HostRow: View {
    let snapshot: HostSnapshot
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            HostAvatar(host: snapshot.host, size: 34)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(snapshot.host.alias)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    StatusDot(state: snapshot.state, size: 6)
                }

                Text(snapshot.host.shortEndpoint)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if snapshot.state == .checking {
                ProgressView()
                    .controlSize(.mini)
            } else if snapshot.metrics != nil {
                Text(DisplayFormat.latency(snapshot.latencyMilliseconds))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? AppTheme.accent.opacity(0.14) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isSelected ? AppTheme.accent.opacity(0.22) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}
