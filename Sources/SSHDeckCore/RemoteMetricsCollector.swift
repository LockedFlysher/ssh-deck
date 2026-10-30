import Foundation

public enum RemoteMetricsCollector {
    public static func collect(
        host: SSHHost,
        timeout: TimeInterval = 16
    ) async -> HostProbeResult {
        await Task.detached(priority: .utility) {
            let startedAt = Date()
            let result = ProcessRunner.run(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-T",
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "-o", "ConnectionAttempts=1",
                    "-o", "ServerAliveInterval=4",
                    "-o", "ServerAliveCountMax=1",
                    "-o", "ClearAllForwardings=yes",
                    "-o", "LogLevel=ERROR",
                    host.alias,
                    "/bin/sh", "-s"
                ],
                input: metricsScript,
                timeout: timeout
            )
            let elapsed = Date().timeIntervalSince(startedAt) * 1_000

            if result.timedOut {
                return HostProbeResult(
                    metrics: nil,
                    latencyMilliseconds: elapsed,
                    errorMessage: "Connection timed out"
                )
            }

            if let metrics = RemoteMetricsParser.parse(result.stdout) {
                return HostProbeResult(
                    metrics: metrics,
                    latencyMilliseconds: elapsed,
                    errorMessage: nil
                )
            }

            let error = meaningfulError(from: result.stderr)
            return HostProbeResult(
                metrics: nil,
                latencyMilliseconds: elapsed,
                errorMessage: error ?? "Remote metrics collection failed"
            )
        }.value
    }

    private static func meaningfulError(from stderr: String) -> String? {
        let lines = stderr
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let last = lines.last {
            let localized: String
            switch true {
            case last.localizedCaseInsensitiveContains("operation timed out"),
                 last.localizedCaseInsensitiveContains("connection timed out"):
                localized = "Connection timed out"
            case last.localizedCaseInsensitiveContains("connection refused"):
                localized = "Connection refused"
            case last.localizedCaseInsensitiveContains("permission denied"):
                localized = "Authentication failed or permission denied"
            case last.localizedCaseInsensitiveContains("no route to host"),
                 last.localizedCaseInsensitiveContains("network is unreachable"):
                localized = "Network unreachable"
            case last.localizedCaseInsensitiveContains("could not resolve hostname"):
                localized = "Could not resolve hostname"
            case last.localizedCaseInsensitiveContains("host key verification failed"):
                localized = "Host key verification failed"
            case last.localizedCaseInsensitiveContains("connection closed"):
                localized = "Connection closed"
            default:
                localized = last
            }

            if localized.count > 180 {
                return String(localized.prefix(177)) + "..."
            }
            return localized
        }
        return nil
    }

    static let metricsScript = #"""
printf 'SSHDECK_BEGIN\n'
printf 'HOSTNAME=%s\n' "$(hostname 2>/dev/null)"
printf 'OS=%s\n' "$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-${NAME:-Linux}}")"
printf 'KERNEL=%s\n' "$(uname -sr 2>/dev/null)"
printf 'ARCH=%s\n' "$(uname -m 2>/dev/null)"
printf 'USER=%s\n' "$(id -un 2>/dev/null)"
printf 'CPU_MODEL=%s\n' "$(awk -F: '/model name|Model/ {gsub(/^ +/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null)"
printf 'CPU_CORES=%s\n' "$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || printf 0)"
set -- $(awk '/^cpu / {print $2,$3,$4,$5,$6,$7,$8,$9; exit}' /proc/stat 2>/dev/null)
cpu_total_1=$(( ${1:-0} + ${2:-0} + ${3:-0} + ${4:-0} + ${5:-0} + ${6:-0} + ${7:-0} + ${8:-0} ))
cpu_idle_1=$(( ${4:-0} + ${5:-0} ))
sleep 0.35
set -- $(awk '/^cpu / {print $2,$3,$4,$5,$6,$7,$8,$9; exit}' /proc/stat 2>/dev/null)
cpu_total_2=$(( ${1:-0} + ${2:-0} + ${3:-0} + ${4:-0} + ${5:-0} + ${6:-0} + ${7:-0} + ${8:-0} ))
cpu_idle_2=$(( ${4:-0} + ${5:-0} ))
printf 'CPU_USAGE=%s\n' "$(awk -v t1="$cpu_total_1" -v i1="$cpu_idle_1" -v t2="$cpu_total_2" -v i2="$cpu_idle_2" 'BEGIN { dt=t2-t1; di=i2-i1; if (dt > 0) printf "%.1f", 100*(dt-di)/dt; else printf "0.0" }')"
set -- $(cat /proc/loadavg 2>/dev/null)
printf 'LOAD1=%s\n' "${1:-0}"
printf 'LOAD5=%s\n' "${2:-0}"
printf 'LOAD15=%s\n' "${3:-0}"
printf 'UPTIME_SECONDS=%s\n' "$(awk '{printf "%d", $1}' /proc/uptime 2>/dev/null)"
mem_total_kb=$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null)
mem_available_kb=$(awk '/^MemAvailable:/ {print $2; exit}' /proc/meminfo 2>/dev/null)
if [ -z "$mem_available_kb" ]; then
  mem_available_kb=$(awk '/^MemFree:/ {print $2; exit}' /proc/meminfo 2>/dev/null)
fi
swap_total_kb=$(awk '/^SwapTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null)
swap_free_kb=$(awk '/^SwapFree:/ {print $2; exit}' /proc/meminfo 2>/dev/null)
printf 'MEM_TOTAL=%s\n' "$(( ${mem_total_kb:-0} * 1024 ))"
printf 'MEM_AVAILABLE=%s\n' "$(( ${mem_available_kb:-0} * 1024 ))"
printf 'SWAP_TOTAL=%s\n' "$(( ${swap_total_kb:-0} * 1024 ))"
printf 'SWAP_FREE=%s\n' "$(( ${swap_free_kb:-0} * 1024 ))"
df -Pk / 2>/dev/null | awk 'NR==2 {printf "DISK_TOTAL=%d\nDISK_USED=%d\nDISK_AVAILABLE=%d\n", $2*1024, $3*1024, $4*1024}'
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw --format=csv,noheader,nounits 2>/dev/null | while IFS= read -r gpu_line; do
    printf 'GPU=%s\n' "$gpu_line"
  done
fi
if command -v sinfo >/dev/null 2>&1; then
  printf 'SLURM=1\n'
  sinfo -h -N -o '%N|%P|%T|%C|%m|%G|%f' 2>/dev/null | awk -F'|' '{ nodes[$1]=$0 } END { for (node in nodes) print "SLURM_NODE=" nodes[node] }'
fi
ps -eo comm=,pcpu=,pmem= --sort=-pcpu 2>/dev/null | head -n 5 | while read -r process_name process_cpu process_mem; do
  printf 'PROC=%s|%s|%s\n' "$process_name" "$process_cpu" "$process_mem"
done
printf 'SSHDECK_END\n'
"""#
}

public enum RemoteMetricsParser {
    public static func parse(_ output: String, capturedAt: Date = Date()) -> HostMetrics? {
        guard output.contains("SSHDECK_BEGIN"), output.contains("SSHDECK_END") else {
            return nil
        }

        var values: [String: String] = [:]
        var gpuLines: [String] = []
        var processLines: [String] = []
        var slurmNodeLines: [String] = []

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separator])
            let value = String(line[line.index(after: separator)...])

            switch key {
            case "GPU":
                gpuLines.append(value)
            case "PROC":
                processLines.append(value)
            case "SLURM_NODE":
                slurmNodeLines.append(value)
            default:
                values[key] = value
            }
        }

        guard let hostname = values["HOSTNAME"], !hostname.isEmpty else {
            return nil
        }

        let slurmNodes = slurmNodeLines.compactMap(parseSlurmNode)
        let slurm = values["SLURM"] == "1" && !slurmNodes.isEmpty
            ? SlurmInfo(nodes: slurmNodes)
            : nil

        return HostMetrics(
            hostname: hostname,
            osName: values["OS"] ?? "Linux",
            kernel: values["KERNEL"] ?? "",
            architecture: values["ARCH"] ?? "",
            user: values["USER"] ?? "",
            cpuModel: values["CPU_MODEL"] ?? "",
            cpuCores: Int(values["CPU_CORES"] ?? "") ?? 0,
            cpuUsage: Double(values["CPU_USAGE"] ?? "") ?? 0,
            load1: Double(values["LOAD1"] ?? "") ?? 0,
            load5: Double(values["LOAD5"] ?? "") ?? 0,
            load15: Double(values["LOAD15"] ?? "") ?? 0,
            memoryTotal: UInt64(values["MEM_TOTAL"] ?? "") ?? 0,
            memoryAvailable: UInt64(values["MEM_AVAILABLE"] ?? "") ?? 0,
            swapTotal: UInt64(values["SWAP_TOTAL"] ?? "") ?? 0,
            swapFree: UInt64(values["SWAP_FREE"] ?? "") ?? 0,
            diskTotal: UInt64(values["DISK_TOTAL"] ?? "") ?? 0,
            diskUsed: UInt64(values["DISK_USED"] ?? "") ?? 0,
            diskAvailable: UInt64(values["DISK_AVAILABLE"] ?? "") ?? 0,
            uptimeSeconds: TimeInterval(values["UPTIME_SECONDS"] ?? "") ?? 0,
            gpus: gpuLines.compactMap(parseGPU),
            processes: processLines.compactMap(parseProcess),
            slurm: slurm,
            capturedAt: capturedAt
        )
    }

    private static func parseGPU(_ rawLine: String) -> GPUInfo? {
        let fields = rawLine.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let name = fields.first, !name.isEmpty else { return nil }

        func number(at index: Int) -> Double? {
            guard fields.indices.contains(index) else { return nil }
            let value = fields[index]
            guard value != "[N/A]", value != "N/A", !value.isEmpty else { return nil }
            return Double(value)
        }

        return GPUInfo(
            name: name,
            utilization: number(at: 1),
            memoryUsedMB: number(at: 2),
            memoryTotalMB: number(at: 3),
            temperatureC: number(at: 4),
            powerW: number(at: 5)
        )
    }

    private static func parseProcess(_ rawLine: String) -> RemoteProcess? {
        let fields = rawLine.split(separator: "|", omittingEmptySubsequences: false)
            .map(String.init)
        guard fields.count >= 3, !fields[0].isEmpty else { return nil }
        return RemoteProcess(
            name: fields[0],
            cpuPercent: Double(fields[1]) ?? 0,
            memoryPercent: Double(fields[2]) ?? 0
        )
    }

    private static func parseSlurmNode(_ rawLine: String) -> SlurmNode? {
        let fields = rawLine.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard fields.count >= 7, !fields[0].isEmpty else { return nil }

        let cpuParts = fields[3].split(separator: "/").compactMap { Int($0) }
        guard cpuParts.count >= 4 else { return nil }

        let partition = fields[1].hasSuffix("*")
            ? String(fields[1].dropLast())
            : fields[1]

        return SlurmNode(
            name: fields[0],
            partition: partition,
            state: fields[2],
            allocatedCPUs: cpuParts[0],
            idleCPUs: cpuParts[1],
            otherCPUs: cpuParts[2],
            totalCPUs: cpuParts[3],
            memoryMB: UInt64(fields[4]) ?? 0,
            gres: fields[5],
            features: fields[6]
        )
    }
}
