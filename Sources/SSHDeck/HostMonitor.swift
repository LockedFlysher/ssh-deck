import Combine
import Foundation
import SSHDeckCore

@MainActor
final class HostMonitor: ObservableObject {
    @Published private(set) var hosts: [SSHHost] = []
    @Published private(set) var snapshots: [String: HostSnapshot] = [:]
    @Published var selectedAlias: String?
    @Published private(set) var isScanning = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var scanError: String?
    @Published private(set) var lastRefresh: Date?
    @Published var refreshInterval: Double {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: Self.refreshIntervalKey)
            configureAutoRefresh()
        }
    }

    private static let refreshIntervalKey = "sshdeck.refreshInterval"
    private let configURL: URL
    private var hasStarted = false
    private var scanTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?
    private var refreshingAliases = Set<String>()

    init(configURL: URL = SSHConfigParser.defaultConfigURL) {
        self.configURL = configURL
        let storedInterval = UserDefaults.standard.double(forKey: Self.refreshIntervalKey)
        self.refreshInterval = storedInterval > 0 ? storedInterval : 30
    }

    var selectedSnapshot: HostSnapshot? {
        guard let selectedAlias else { return nil }
        return snapshots[selectedAlias]
    }

    var onlineCount: Int {
        snapshots.values.filter { $0.state == .online }.count
    }

    var hasFreshData: Bool {
        snapshots.values.contains { $0.metrics != nil }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        reloadConfiguration()
        configureAutoRefresh()
    }

    func reloadConfiguration() {
        scanTask?.cancel()
        isScanning = true
        scanError = nil

        let url = configURL
        scanTask = Task {
            do {
                let discovered = try await Task.detached(priority: .userInitiated) {
                    try SSHConfigParser.discover(configURL: url)
                }.value

                guard !Task.isCancelled else { return }

                let oldSnapshots = snapshots
                var nextSnapshots: [String: HostSnapshot] = [:]
                for host in discovered {
                    let previous = oldSnapshots[host.alias]
                    nextSnapshots[host.alias] = HostSnapshot(
                        host: host,
                        state: previous?.state ?? .idle,
                        metrics: previous?.metrics,
                        latencyMilliseconds: previous?.latencyMilliseconds,
                        lastUpdated: previous?.lastUpdated,
                        message: previous?.message
                    )
                }

                hosts = discovered
                snapshots = nextSnapshots
                isScanning = false

                if selectedAlias == nil || nextSnapshots[selectedAlias ?? ""] == nil {
                    selectedAlias = discovered.first?.alias
                }

                refreshAll()
            } catch {
                guard !Task.isCancelled else { return }
                isScanning = false
                scanError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                hosts = []
                snapshots = [:]
                selectedAlias = nil
            }
        }
    }

    func refreshAll() {
        guard !isRefreshing, !hosts.isEmpty else { return }

        let hostsToProbe = hosts
        isRefreshing = true

        for host in hostsToProbe {
            if var snapshot = snapshots[host.alias] {
                snapshot.state = .checking
                snapshots[host.alias] = snapshot
            }
        }

        refreshTask = Task {
            let results = await withTaskGroup(
                of: (String, HostProbeResult).self,
                returning: [(String, HostProbeResult)].self
            ) { group in
                for host in hostsToProbe {
                    group.addTask {
                        (host.alias, await RemoteMetricsCollector.collect(host: host))
                    }
                }

                var collected: [(String, HostProbeResult)] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }

            for (alias, result) in results {
                guard var snapshot = snapshots[alias] else { continue }
                apply(result, to: &snapshot)
                snapshots[alias] = snapshot
            }

            isRefreshing = false
            lastRefresh = Date()
        }
    }

    func refresh(alias: String) {
        guard !isRefreshing, !refreshingAliases.contains(alias) else { return }
        guard var snapshot = snapshots[alias] else { return }

        refreshingAliases.insert(alias)
        snapshot.state = .checking
        snapshots[alias] = snapshot
        let host = snapshot.host

        Task {
            let result = await RemoteMetricsCollector.collect(host: host)
            refreshingAliases.remove(alias)

            guard var updated = snapshots[alias] else { return }
            apply(result, to: &updated)
            snapshots[alias] = updated
            lastRefresh = Date()
        }
    }

    private func apply(_ result: HostProbeResult, to snapshot: inout HostSnapshot) {
        snapshot.latencyMilliseconds = result.latencyMilliseconds
        if let metrics = result.metrics {
            snapshot.state = .online
            snapshot.metrics = metrics
            snapshot.lastUpdated = metrics.capturedAt
            snapshot.message = nil
        } else {
            snapshot.state = .offline
            snapshot.message = result.errorMessage
        }
    }

    private func configureAutoRefresh() {
        autoRefreshTask?.cancel()

        guard refreshInterval > 0 else { return }
        let interval = refreshInterval

        autoRefreshTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                refreshAll()
            }
        }
    }
}
