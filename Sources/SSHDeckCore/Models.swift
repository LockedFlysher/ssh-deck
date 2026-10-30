import Foundation

public struct SSHHost: Identifiable, Hashable, Sendable {
    public let alias: String
    public let hostName: String
    public let user: String
    public let port: Int
    public let identityFile: String?
    public let proxyJump: String?
    public let serverAliveInterval: Int?
    public let compression: Bool
    public let localForwards: [String]

    public var id: String { alias }

    public init(
        alias: String,
        hostName: String,
        user: String,
        port: Int,
        identityFile: String? = nil,
        proxyJump: String? = nil,
        serverAliveInterval: Int? = nil,
        compression: Bool = false,
        localForwards: [String] = []
    ) {
        self.alias = alias
        self.hostName = hostName
        self.user = user
        self.port = port
        self.identityFile = identityFile
        self.proxyJump = proxyJump
        self.serverAliveInterval = serverAliveInterval
        self.compression = compression
        self.localForwards = localForwards
    }

    public var endpoint: String {
        port == 22 ? hostName : "\(hostName):\(port)"
    }

    public var loginTarget: String {
        port == 22 ? "\(user)@\(hostName)" : "\(user)@\(hostName):\(port)"
    }

    public var terminalCommand: String {
        "ssh \(Shell.quote(alias))"
    }

    public var shortEndpoint: String {
        if hostName.count > 34 {
            return String(hostName.prefix(31)) + "..."
        }
        return endpoint
    }
}

public struct GPUInfo: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let name: String
    public let utilization: Double?
    public let memoryUsedMB: Double?
    public let memoryTotalMB: Double?
    public let temperatureC: Double?
    public let powerW: Double?

    public init(
        name: String,
        utilization: Double? = nil,
        memoryUsedMB: Double? = nil,
        memoryTotalMB: Double? = nil,
        temperatureC: Double? = nil,
        powerW: Double? = nil
    ) {
        self.name = name
        self.utilization = utilization
        self.memoryUsedMB = memoryUsedMB
        self.memoryTotalMB = memoryTotalMB
        self.temperatureC = temperatureC
        self.powerW = powerW
    }

    public var memoryFraction: Double? {
        guard let used = memoryUsedMB, let total = memoryTotalMB, total > 0 else {
            return nil
        }
        return min(max(used / total, 0), 1)
    }
}

public struct RemoteProcess: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let name: String
    public let cpuPercent: Double
    public let memoryPercent: Double

    public init(name: String, cpuPercent: Double, memoryPercent: Double) {
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
    }
}

public enum SlurmNodeCategory: String, Sendable {
    case idle
    case allocated
    case mixed
    case unavailable
    case other

    public var label: String {
        switch self {
        case .idle: return "Idle"
        case .allocated: return "Allocated"
        case .mixed: return "Mixed"
        case .unavailable: return "Unavailable"
        case .other: return "Other"
        }
    }
}

public struct SlurmNode: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let partition: String
    public let state: String
    public let allocatedCPUs: Int
    public let idleCPUs: Int
    public let otherCPUs: Int
    public let totalCPUs: Int
    public let memoryMB: UInt64
    public let gres: String
    public let features: String

    public init(
        name: String,
        partition: String,
        state: String,
        allocatedCPUs: Int,
        idleCPUs: Int,
        otherCPUs: Int,
        totalCPUs: Int,
        memoryMB: UInt64,
        gres: String,
        features: String
    ) {
        self.name = name
        self.partition = partition
        self.state = state
        self.allocatedCPUs = allocatedCPUs
        self.idleCPUs = idleCPUs
        self.otherCPUs = otherCPUs
        self.totalCPUs = totalCPUs
        self.memoryMB = memoryMB
        self.gres = gres
        self.features = features
    }

    public var category: SlurmNodeCategory {
        let normalized = state.lowercased()
        if normalized.hasPrefix("idle") {
            return .idle
        }
        if normalized.hasPrefix("alloc") {
            return .allocated
        }
        if normalized.hasPrefix("mix") {
            return .mixed
        }
        if normalized.hasPrefix("down") ||
            normalized.hasPrefix("drain") ||
            normalized.hasPrefix("fail") ||
            normalized.hasPrefix("error") ||
            normalized.hasPrefix("unknown") ||
            normalized.hasPrefix("maint") ||
            normalized.hasPrefix("power") {
            return .unavailable
        }
        return .other
    }

    public var gpuDescription: String? {
        guard gres.hasPrefix("gpu:"), !gres.contains("(null)") else {
            return nil
        }
        let parts = gres.split(separator: ":").map(String.init)
        guard parts.count >= 3 else { return nil }
        let model = parts[1].uppercased()
        let count = parts[2]
        return "\(model) x\(count)"
    }
}

public struct SlurmInfo: Sendable {
    public let nodes: [SlurmNode]

    public init(nodes: [SlurmNode]) {
        self.nodes = nodes
    }

    public var idleNodeCount: Int {
        nodes.filter { $0.category == .idle }.count
    }

    public var allocatedNodeCount: Int {
        nodes.filter { $0.category == .allocated }.count
    }

    public var mixedNodeCount: Int {
        nodes.filter { $0.category == .mixed }.count
    }

    public var unavailableNodeCount: Int {
        nodes.filter { $0.category == .unavailable }.count
    }

    public var idleCPUs: Int {
        nodes.reduce(0) { $0 + $1.idleCPUs }
    }

    public var totalCPUs: Int {
        nodes.reduce(0) { $0 + $1.totalCPUs }
    }

    public var occupiedNodeCount: Int {
        allocatedNodeCount + mixedNodeCount
    }
}

public struct HostMetrics: Sendable {
    public let hostname: String
    public let osName: String
    public let kernel: String
    public let architecture: String
    public let user: String
    public let cpuModel: String
    public let cpuCores: Int
    public let cpuUsage: Double
    public let load1: Double
    public let load5: Double
    public let load15: Double
    public let memoryTotal: UInt64
    public let memoryAvailable: UInt64
    public let swapTotal: UInt64
    public let swapFree: UInt64
    public let diskTotal: UInt64
    public let diskUsed: UInt64
    public let diskAvailable: UInt64
    public let uptimeSeconds: TimeInterval
    public let gpus: [GPUInfo]
    public let processes: [RemoteProcess]
    public let slurm: SlurmInfo?
    public let capturedAt: Date

    public init(
        hostname: String,
        osName: String,
        kernel: String,
        architecture: String,
        user: String,
        cpuModel: String,
        cpuCores: Int,
        cpuUsage: Double,
        load1: Double,
        load5: Double,
        load15: Double,
        memoryTotal: UInt64,
        memoryAvailable: UInt64,
        swapTotal: UInt64,
        swapFree: UInt64,
        diskTotal: UInt64,
        diskUsed: UInt64,
        diskAvailable: UInt64,
        uptimeSeconds: TimeInterval,
        gpus: [GPUInfo] = [],
        processes: [RemoteProcess] = [],
        slurm: SlurmInfo? = nil,
        capturedAt: Date = Date()
    ) {
        self.hostname = hostname
        self.osName = osName
        self.kernel = kernel
        self.architecture = architecture
        self.user = user
        self.cpuModel = cpuModel
        self.cpuCores = cpuCores
        self.cpuUsage = cpuUsage
        self.load1 = load1
        self.load5 = load5
        self.load15 = load15
        self.memoryTotal = memoryTotal
        self.memoryAvailable = memoryAvailable
        self.swapTotal = swapTotal
        self.swapFree = swapFree
        self.diskTotal = diskTotal
        self.diskUsed = diskUsed
        self.diskAvailable = diskAvailable
        self.uptimeSeconds = uptimeSeconds
        self.gpus = gpus
        self.processes = processes
        self.slurm = slurm
        self.capturedAt = capturedAt
    }

    public var memoryUsed: UInt64 {
        memoryTotal > memoryAvailable ? memoryTotal - memoryAvailable : 0
    }

    public var memoryFraction: Double {
        guard memoryTotal > 0 else { return 0 }
        return min(max(Double(memoryUsed) / Double(memoryTotal), 0), 1)
    }

    public var swapUsed: UInt64 {
        swapTotal > swapFree ? swapTotal - swapFree : 0
    }

    public var swapFraction: Double {
        guard swapTotal > 0 else { return 0 }
        return min(max(Double(swapUsed) / Double(swapTotal), 0), 1)
    }

    public var diskFraction: Double {
        guard diskTotal > 0 else { return 0 }
        return min(max(Double(diskUsed) / Double(diskTotal), 0), 1)
    }
}

public enum HostConnectionState: String, Sendable {
    case idle
    case checking
    case online
    case offline
}

public struct HostSnapshot: Identifiable, Sendable {
    public let host: SSHHost
    public var state: HostConnectionState
    public var metrics: HostMetrics?
    public var latencyMilliseconds: Double?
    public var lastUpdated: Date?
    public var message: String?

    public var id: String { host.alias }

    public init(
        host: SSHHost,
        state: HostConnectionState = .idle,
        metrics: HostMetrics? = nil,
        latencyMilliseconds: Double? = nil,
        lastUpdated: Date? = nil,
        message: String? = nil
    ) {
        self.host = host
        self.state = state
        self.metrics = metrics
        self.latencyMilliseconds = latencyMilliseconds
        self.lastUpdated = lastUpdated
        self.message = message
    }
}

public struct HostProbeResult: Sendable {
    public let metrics: HostMetrics?
    public let latencyMilliseconds: Double?
    public let errorMessage: String?

    public init(
        metrics: HostMetrics?,
        latencyMilliseconds: Double?,
        errorMessage: String?
    ) {
        self.metrics = metrics
        self.latencyMilliseconds = latencyMilliseconds
        self.errorMessage = errorMessage
    }

    public var isSuccess: Bool { metrics != nil }
}
