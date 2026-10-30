import XCTest
@testable import SSHDeckCore

final class SSHDeckCoreTests: XCTestCase {
    func testDiscoversConcreteAliasesAndIncludes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SSHDeckTests-\(UUID().uuidString)")
        let configDirectory = root.appendingPathComponent("config.d")
        try FileManager.default.createDirectory(
            at: configDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let mainConfig = root.appendingPathComponent("config")
        try """
        # primary hosts
        Host alpha beta
          HostName example.com

        Host *
          ServerAliveInterval 30

        Include config.d/*
        """.write(to: mainConfig, atomically: true, encoding: .utf8)

        try """
        Host gamma
          HostName 203.0.113.20
        """.write(
            to: configDirectory.appendingPathComponent("extra"),
            atomically: true,
            encoding: .utf8
        )

        let aliases = try SSHConfigParser.discoverAliases(configURL: mainConfig)
        XCTAssertEqual(aliases, ["alpha", "beta", "gamma"])
    }

    func testParsesRemoteMetrics() throws {
        let output = """
        SSHDECK_BEGIN
        HOSTNAME=lab-node
        OS=Ubuntu 24.04.1 LTS
        KERNEL=Linux 6.8.0
        ARCH=x86_64
        USER=operator
        CPU_MODEL=AMD EPYC 7763
        CPU_CORES=128
        CPU_USAGE=23.5
        LOAD1=4.20
        LOAD5=3.80
        LOAD15=3.10
        UPTIME_SECONDS=259200
        MEM_TOTAL=1099511627776
        MEM_AVAILABLE=549755813888
        SWAP_TOTAL=17179869184
        SWAP_FREE=8589934592
        DISK_TOTAL=4000000000000
        DISK_USED=1000000000000
        DISK_AVAILABLE=3000000000000
        GPU=NVIDIA A800, 71, 40960, 81920, 63, 240.5
        SLURM=1
        SLURM_NODE=cpu-40-1|cpu-40|idle|0/40/0/40|386000|(null)|cpu,40
        SLURM_NODE=cpu-40-2|cpu-40|allocated|40/0/0/40|386000|(null)|cpu,40
        SLURM_NODE=gpu-a100-1|gpu-a100|mixed|32/16/0/48|386000|gpu:a100:1|gpu,a100
        PROC=python|120.5|2.4
        SSHDECK_END
        """

        let metrics = try XCTUnwrap(RemoteMetricsParser.parse(output))
        XCTAssertEqual(metrics.hostname, "lab-node")
        XCTAssertEqual(metrics.cpuCores, 128)
        XCTAssertEqual(metrics.cpuUsage, 23.5, accuracy: 0.001)
        XCTAssertEqual(metrics.memoryFraction, 0.5, accuracy: 0.001)
        XCTAssertEqual(metrics.diskFraction, 0.25, accuracy: 0.001)
        XCTAssertEqual(metrics.gpus.count, 1)
        XCTAssertEqual(metrics.gpus[0].name, "NVIDIA A800")
        XCTAssertEqual(metrics.gpus[0].utilization, 71)
        XCTAssertEqual(metrics.processes.first?.name, "python")

        let slurm = try XCTUnwrap(metrics.slurm)
        XCTAssertEqual(slurm.nodes.count, 3)
        XCTAssertEqual(slurm.idleNodeCount, 1)
        XCTAssertEqual(slurm.allocatedNodeCount, 1)
        XCTAssertEqual(slurm.mixedNodeCount, 1)
        XCTAssertEqual(slurm.idleCPUs, 56)
        XCTAssertEqual(slurm.totalCPUs, 128)
        XCTAssertEqual(
            slurm.nodes.first(where: { $0.name == "gpu-a100-1" })?.gpuDescription,
            "A100 x1"
        )
    }

    func testShellQuotesAliasesWithSpaces() {
        XCTAssertEqual(Shell.quote("lab"), "lab")
        XCTAssertEqual(Shell.quote("cloud (Shanghai)"), "'cloud (Shanghai)'")
        XCTAssertEqual(Shell.quote("my host"), "'my host'")
    }
}
