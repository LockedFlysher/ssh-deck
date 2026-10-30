import Darwin
import Foundation

struct ProcessRunResult {
    let stdout: String
    let stderr: String
    let status: Int32
    let timedOut: Bool
}

enum ProcessRunner {
    static func run(
        executable: String,
        arguments: [String],
        input: String? = nil,
        timeout: TimeInterval
    ) -> ProcessRunResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        if input != nil {
            process.standardInput = inputPipe
        }

        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        environment["LANG"] = "C"
        process.environment = environment

        do {
            try process.run()
        } catch {
            return ProcessRunResult(
                stdout: "",
                stderr: error.localizedDescription,
                status: -1,
                timedOut: false
            )
        }

        if let input {
            inputPipe.fileHandleForWriting.write(Data(input.utf8))
            try? inputPipe.fileHandleForWriting.close()
        }

        let waitGroup = DispatchGroup()
        waitGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            waitGroup.leave()
        }

        var timedOut = false
        if waitGroup.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if waitGroup.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = waitGroup.wait(timeout: .now() + 1)
            }
        }

        let stdout = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = errorPipe.fileHandleForReading.readDataToEndOfFile()

        return ProcessRunResult(
            stdout: String(decoding: stdout, as: UTF8.self),
            stderr: String(decoding: stderr, as: UTF8.self),
            status: process.terminationStatus,
            timedOut: timedOut
        )
    }
}
