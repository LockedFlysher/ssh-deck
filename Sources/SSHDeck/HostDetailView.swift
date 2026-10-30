import SSHDeckCore
import SwiftUI

struct HostDetailView: View {
    @EnvironmentObject private var store: HostMonitor
    let snapshot: HostSnapshot

    @State private var didCopyCommand = false
    @State private var slurmFilter = "idle"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hostHeader

                if snapshot.state == .offline {
                    offlineBanner
                }

                if let metrics = snapshot.metrics {
                    metricsSection(metrics)
                    gpuSection(metrics)
                    slurmSection(metrics)
                    processSection(metrics)
                    informationSection(metrics)
                } else if snapshot.state == .checking {
                    connectingPlaceholder
                } else {
                    noMetricsPlaceholder
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 34)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .id(snapshot.id)
    }

    private var hostHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            HostAvatar(host: snapshot.host, size: 54)

            VStack(alignment: .leading, spacing: 7) {
                Text(snapshot.host.alias)
                    .font(.system(size: 26, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                HStack(spacing: 7) {
                    Image(systemName: "network")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(snapshot.host.loginTarget)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack(spacing: 8) {
                    StatusBadge(state: snapshot.state)
                    if let latency = snapshot.latencyMilliseconds {
                        Label(DisplayFormat.latency(latency), systemImage: "bolt.horizontal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button {
                    TerminalLauncher.openTerminal(for: snapshot.host)
                } label: {
                    Label("Open Terminal", systemImage: "terminal")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .help("Run \(snapshot.host.terminalCommand) in Terminal")

                Button {
                    TerminalLauncher.copyCommand(for: snapshot.host)
                    didCopyCommand = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_300_000_000)
                        didCopyCommand = false
                    }
                } label: {
                    Label(
                        didCopyCommand ? "Copied" : "Copy Command",
                        systemImage: didCopyCommand ? "checkmark" : "doc.on.doc"
                    )
                }
                .buttonStyle(.bordered)
                .help("Copy SSH command")

                Button {
                    store.refresh(alias: snapshot.host.alias)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.bordered)
                .disabled(store.isRefreshing || snapshot.state == .checking)
                .help("Refresh this host")
            }
        }
    }

    private var offlineBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(AppTheme.statusColor(.offline))
                .font(.system(size: 15, weight: .medium))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text("Unable to connect")
                    .font(.callout.weight(.medium))
                Text(snapshot.message ?? "SSH probe failed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                if let lastUpdated = snapshot.lastUpdated {
                    Text("Showing the last successful data from \(DisplayFormat.time(lastUpdated))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.statusColor(.offline).opacity(0.075))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.statusColor(.offline).opacity(0.16), lineWidth: 1)
        )
    }

    private func metricsSection(_ metrics: HostMetrics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(
                title: "Resource Usage",
                detail: snapshot.lastUpdated.map { "Updated \(DisplayFormat.time($0))" }
            )

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(minimum: 126), spacing: 10), count: 4),
                spacing: 10
            ) {
                MetricTile(
                    title: "CPU",
                    value: DisplayFormat.percent(metrics.cpuUsage / 100),
                    subtitle: "\(metrics.cpuCores) cores · load \(DisplayFormat.number(metrics.load1))",
                    fraction: metrics.cpuUsage / 100,
                    color: AppTheme.cpu,
                    symbol: "cpu"
                )

                MetricTile(
                    title: "Memory",
                    value: DisplayFormat.percent(metrics.memoryFraction),
                    subtitle: "\(DisplayFormat.bytes(metrics.memoryUsed)) / \(DisplayFormat.bytes(metrics.memoryTotal))",
                    fraction: metrics.memoryFraction,
                    color: AppTheme.memory,
                    symbol: "memorychip"
                )

                MetricTile(
                    title: "Disk",
                    value: DisplayFormat.percent(metrics.diskFraction),
                    subtitle: "\(DisplayFormat.bytes(metrics.diskUsed)) / \(DisplayFormat.bytes(metrics.diskTotal))",
                    fraction: metrics.diskFraction,
                    color: AppTheme.disk,
                    symbol: "internaldrive"
                )

                MetricTile(
                    title: "Load",
                    value: DisplayFormat.number(metrics.load1),
                    subtitle: "5m \(DisplayFormat.number(metrics.load5)) · 15m \(DisplayFormat.number(metrics.load15))",
                    fraction: metrics.cpuCores > 0
                        ? min(metrics.load1 / Double(metrics.cpuCores), 1)
                        : 0,
                    color: AppTheme.load,
                    symbol: "waveform.path.ecg"
                )
            }
        }
    }

    @ViewBuilder
    private func gpuSection(_ metrics: HostMetrics) -> some View {
        if !metrics.gpus.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "GPU", detail: "\(metrics.gpus.count) devices")

                VStack(spacing: 0) {
                    ForEach(Array(metrics.gpus.enumerated()), id: \.element.id) { index, gpu in
                        GPURow(gpu: gpu)
                        if index < metrics.gpus.count - 1 {
                            Divider()
                                .padding(.leading, 14)
                        }
                    }
                }
                .cardBackground()
            }
        }
    }

    @ViewBuilder
    private func slurmSection(_ metrics: HostMetrics) -> some View {
        if let slurm = metrics.slurm {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    SectionTitle(
                        title: "Slurm Cluster",
                        detail: "\(slurm.nodes.count) nodes · \(slurm.idleNodeCount) idle · \(slurm.occupiedNodeCount) occupied"
                    )

                    SlurmFilterControl(
                        selection: $slurmFilter,
                        idleCount: slurm.idleNodeCount,
                        allocatedCount: slurm.allocatedNodeCount,
                        mixedCount: slurm.mixedNodeCount,
                        totalCount: slurm.nodes.count
                    )
                    .frame(width: 340)
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(minimum: 108), spacing: 10), count: 4),
                    spacing: 10
                ) {
                    SlurmSummaryTile(
                        title: "Idle Nodes",
                        value: "\(slurm.idleNodeCount)",
                        subtitle: "Ready to use",
                        color: AppTheme.slurmColor(.idle),
                        symbol: "checkmark.circle"
                    )
                    SlurmSummaryTile(
                        title: "Fully Allocated",
                        value: "\(slurm.allocatedNodeCount)",
                        subtitle: "All CPUs allocated",
                        color: AppTheme.slurmColor(.allocated),
                        symbol: "lock.circle"
                    )
                    SlurmSummaryTile(
                        title: "Partially Used",
                        value: "\(slurm.mixedNodeCount)",
                        subtitle: "Free CPUs remain",
                        color: AppTheme.slurmColor(.mixed),
                        symbol: "circle.lefthalf.filled"
                    )
                    SlurmSummaryTile(
                        title: "Idle CPUs",
                        value: "\(slurm.idleCPUs)",
                        subtitle: "of \(slurm.totalCPUs) cores",
                        color: AppTheme.disk,
                        symbol: "cpu"
                    )
                }

                VStack(spacing: 0) {
                    slurmTableHeader
                    Divider()

                    let visibleNodes = filteredSlurmNodes(slurm)
                    if visibleNodes.isEmpty {
                        Text("No nodes match this filter")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(visibleNodes.enumerated()), id: \.element.id) { index, node in
                                    SlurmNodeRow(node: node)
                                    if index < visibleNodes.count - 1 {
                                        Divider()
                                            .padding(.leading, 14)
                                    }
                                }
                            }
                        }
                        .frame(height: min(max(CGFloat(visibleNodes.count) * 38, 60), 300))
                    }
                }
                .cardBackground()
            }
        }
    }

    private var slurmTableHeader: some View {
        HStack(spacing: 10) {
            Text("Node")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("State")
                .frame(width: 54, alignment: .leading)
            Text("Idle CPUs")
                .frame(width: 72, alignment: .trailing)
            Text("Memory")
                .frame(width: 58, alignment: .trailing)
            Text("GPU")
                .frame(width: 76, alignment: .leading)
            Text("Partition")
                .frame(width: 92, alignment: .leading)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func filteredSlurmNodes(_ slurm: SlurmInfo) -> [SlurmNode] {
        let nodes: [SlurmNode]
        switch slurmFilter {
        case "idle":
            nodes = slurm.nodes.filter { $0.category == .idle }
        case "allocated":
            nodes = slurm.nodes.filter { $0.category == .allocated }
        case "mixed":
            nodes = slurm.nodes.filter { $0.category == .mixed }
        default:
            nodes = slurm.nodes
        }

        return nodes.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    @ViewBuilder
    private func processSection(_ metrics: HostMetrics) -> some View {
        if !metrics.processes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Top Processes", detail: "Sorted by CPU")

                VStack(spacing: 0) {
                    HStack {
                        Text("Process")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("CPU")
                            .frame(width: 64, alignment: .trailing)
                        Text("Memory")
                            .frame(width: 64, alignment: .trailing)
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                    Divider()

                    ForEach(Array(metrics.processes.enumerated()), id: \.element.id) { index, process in
                        HStack {
                            Text(process.name)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(String(format: "%.1f%%", process.cpuPercent))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(process.cpuPercent > 50 ? AppTheme.load : .primary)
                                .frame(width: 64, alignment: .trailing)
                            Text(String(format: "%.1f%%", process.memoryPercent))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 64, alignment: .trailing)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)

                        if index < metrics.processes.count - 1 {
                            Divider()
                                .padding(.leading, 14)
                        }
                    }
                }
                .cardBackground()
            }
        }
    }

    private func informationSection(_ metrics: HostMetrics) -> some View {
        HStack(alignment: .top, spacing: 12) {
            InfoPanel(
                title: "Connection",
                rows: [
                    InfoRowData(label: "Alias", value: snapshot.host.alias, monospaced: true),
                    InfoRowData(label: "Host", value: snapshot.host.hostName, monospaced: true),
                    InfoRowData(label: "User", value: snapshot.host.user, monospaced: true),
                    InfoRowData(label: "Port", value: "\(snapshot.host.port)", monospaced: true),
                    InfoRowData(
                        label: "Identity",
                        value: snapshot.host.identityFile ?? "Default key",
                        monospaced: true
                    ),
                    InfoRowData(
                        label: "Jump",
                        value: snapshot.host.proxyJump ?? "None",
                        monospaced: true
                    ),
                    InfoRowData(
                        label: "Forward",
                        value: snapshot.host.localForwards.isEmpty
                            ? "None"
                            : snapshot.host.localForwards.joined(separator: ", "),
                        monospaced: true
                    ),
                    InfoRowData(
                        label: "Keepalive",
                        value: snapshot.host.serverAliveInterval.map { "\($0)s" } ?? "Not set",
                        monospaced: false
                    )
                ]
            )

            InfoPanel(
                title: "System",
                rows: [
                    InfoRowData(label: "Hostname", value: metrics.hostname, monospaced: true),
                    InfoRowData(label: "OS", value: metrics.osName, monospaced: false),
                    InfoRowData(label: "Kernel", value: metrics.kernel, monospaced: true),
                    InfoRowData(label: "Arch", value: metrics.architecture, monospaced: true),
                    InfoRowData(
                        label: "Processor",
                        value: metrics.cpuModel.isEmpty ? "--" : metrics.cpuModel,
                        monospaced: false
                    ),
                    InfoRowData(label: "Uptime", value: DisplayFormat.uptime(metrics.uptimeSeconds), monospaced: false),
                    InfoRowData(
                        label: "Swap",
                        value: metrics.swapTotal > 0
                            ? "\(DisplayFormat.bytes(metrics.swapUsed)) / \(DisplayFormat.bytes(metrics.swapTotal))"
                            : "Disabled",
                        monospaced: false
                    ),
                    InfoRowData(
                        label: "SSH RTT",
                        value: DisplayFormat.latency(snapshot.latencyMilliseconds),
                        monospaced: true
                    )
                ]
            )
        }
    }

    private var connectingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Collecting remote metrics")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    private var noMetricsPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.0percent")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text("No performance data yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Check Now") {
                store.refresh(alias: snapshot.host.alias)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 70)
    }
}

private struct SlurmSummaryTile: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)

            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .cardBackground()
    }
}

private struct SlurmFilterControl: View {
    @Binding var selection: String
    let idleCount: Int
    let allocatedCount: Int
    let mixedCount: Int
    let totalCount: Int

    var body: some View {
        HStack(spacing: 2) {
            item(id: "idle", title: "Idle \(idleCount)")
            item(id: "allocated", title: "Full \(allocatedCount)")
            item(id: "mixed", title: "Partial \(mixedCount)")
            item(id: "all", title: "All \(totalCount)")
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(AppTheme.subtleBorder, lineWidth: 1)
        )
    }

    private func item(id: String, title: String) -> some View {
        Button {
            selection = id
        } label: {
            Text(title)
                .font(.system(size: 10.5, weight: selection == id ? .semibold : .regular))
                .foregroundStyle(selection == id ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(selection == id ? AppTheme.accent.opacity(0.16) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SlurmNodeRow: View {
    let node: SlurmNode

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Circle()
                    .fill(AppTheme.slurmColor(node.category))
                    .frame(width: 6, height: 6)

                Text(node.name)
                    .font(.system(size: 11.5, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(node.category.label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.slurmColor(node.category))
                .frame(width: 54, alignment: .leading)

            Text("\(node.idleCPUs) / \(node.totalCPUs)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(node.idleCPUs > 0 ? .primary : .secondary)
                .frame(width: 72, alignment: .trailing)

            Text("\(node.memoryMB / 1024) GB")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)

            Text(node.gpuDescription ?? "--")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(node.gpuDescription == nil ? .tertiary : .secondary)
                .lineLimit(1)
                .frame(width: 76, alignment: .leading)

            Text(node.partition)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 92, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .help("\(node.name) · \(node.state) · \(node.features)")
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let subtitle: String
    let fraction: Double
    let color: Color
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(value)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            MeterBar(value: fraction, color: color)

            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 102, alignment: .topLeading)
        .cardBackground()
    }
}

private struct GPURow: View {
    let gpu: GPUInfo

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.cpu)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 6) {
                Text(gpu.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let fraction = gpu.memoryFraction {
                    HStack(spacing: 8) {
                        MeterBar(value: fraction, color: AppTheme.cpu, height: 4)
                        Text("\(Int(gpu.memoryUsedMB ?? 0)) / \(Int(gpu.memoryTotalMB ?? 0)) MB")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
            }

            Spacer(minLength: 8)

            if let utilization = gpu.utilization {
                Text("\(Int(utilization))%")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.cpu)
                    .frame(width: 44, alignment: .trailing)
            }

            if let temperature = gpu.temperatureC {
                Label("\(Int(temperature))°", systemImage: "thermometer.medium")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }

            if let power = gpu.powerW {
                Text("\(Int(power)) W")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct InfoPanel: View {
    let title: String
    let rows: [InfoRowData]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 11)
                .padding(.bottom, 7)

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(row.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .leading)
                    Text(row.value)
                        .font(row.monospaced ? .system(size: 11.5, design: .monospaced) : .system(size: 12))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)

                if index < rows.count - 1 {
                    Divider()
                        .padding(.leading, 82)
                }
            }
        }
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .cardBackground()
    }
}

private struct InfoRowData {
    let label: String
    let value: String
    let monospaced: Bool
}
