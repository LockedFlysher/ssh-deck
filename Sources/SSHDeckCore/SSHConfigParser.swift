import Darwin
import Foundation

public enum SSHConfigError: LocalizedError {
    case configNotFound(String)
    case unreadable(String)
    case noHosts

    public var errorDescription: String? {
        switch self {
        case .configNotFound(let path):
            return "SSH config not found: \(path)"
        case .unreadable(let path):
            return "Unable to read SSH config: \(path)"
        case .noHosts:
            return "No usable hosts found in the SSH config"
        }
    }
}

public enum SSHConfigParser {
    public static var defaultConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh")
            .appendingPathComponent("config")
    }

    public static func discover(configURL: URL = defaultConfigURL) throws -> [SSHHost] {
        let aliases = try discoverAliases(configURL: configURL)
        guard !aliases.isEmpty else {
            throw SSHConfigError.noHosts
        }
        return aliases.map(resolve)
    }

    public static func discoverAliases(configURL: URL) throws -> [String] {
        var visitedFiles = Set<String>()
        var seenAliases = Set<String>()
        var aliases: [String] = []

        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw SSHConfigError.configNotFound(configURL.path)
        }

        try parseFile(
            at: configURL,
            depth: 0,
            visitedFiles: &visitedFiles,
            seenAliases: &seenAliases,
            aliases: &aliases
        )
        return aliases
    }

    private static func parseFile(
        at url: URL,
        depth: Int,
        visitedFiles: inout Set<String>,
        seenAliases: inout Set<String>,
        aliases: inout [String]
    ) throws {
        guard depth < 12 else { return }

        let canonicalPath = url.standardizedFileURL.path
        guard !visitedFiles.contains(canonicalPath) else { return }
        visitedFiles.insert(canonicalPath)

        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            throw SSHConfigError.unreadable(url.path)
        }

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let tokens = tokenize(String(rawLine))
            guard let keyword = tokens.first?.lowercased() else { continue }

            switch keyword {
            case "host":
                for alias in tokens.dropFirst() {
                    guard isConcreteHostPattern(alias), !seenAliases.contains(alias) else {
                        continue
                    }
                    seenAliases.insert(alias)
                    aliases.append(alias)
                }

            case "include":
                for pattern in tokens.dropFirst() {
                    for includeURL in expandInclude(pattern, relativeTo: url) {
                        try? parseFile(
                            at: includeURL,
                            depth: depth + 1,
                            visitedFiles: &visitedFiles,
                            seenAliases: &seenAliases,
                            aliases: &aliases
                        )
                    }
                }

            default:
                continue
            }
        }
    }

    private static func resolve(_ alias: String) -> SSHHost {
        let result = ProcessRunner.run(
            executable: "/usr/bin/ssh",
            arguments: ["-G", alias],
            timeout: 4
        )

        guard result.status == 0 else {
            return SSHHost(
                alias: alias,
                hostName: alias,
                user: NSUserName(),
                port: 22
            )
        }

        var values: [String: [String]] = [:]
        for line in result.stdout.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            values[parts[0].lowercased(), default: []].append(parts[1])
        }

        let port = values["port"].flatMap { Int($0.first ?? "") } ?? 22
        let interval = values["serveraliveinterval"].flatMap { Int($0.first ?? "") }
        let compression = values["compression"]?.first?.lowercased() == "yes"

        return SSHHost(
            alias: alias,
            hostName: values["hostname"]?.first ?? alias,
            user: values["user"]?.first ?? NSUserName(),
            port: port,
            identityFile: values["identityfile"]?.first,
            proxyJump: values["proxyjump"]?.first,
            serverAliveInterval: interval,
            compression: compression,
            localForwards: values["localforward"] ?? []
        )
    }

    private static func tokenize(_ rawLine: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var isEscaped = false

        for character in rawLine {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }

            if character == "\\" {
                isEscaped = true
                continue
            }

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
                continue
            }

            if character == "#" {
                break
            }

            if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private static func isConcreteHostPattern(_ value: String) -> Bool {
        !value.isEmpty &&
            !value.hasPrefix("!") &&
            !value.contains("*") &&
            !value.contains("?")
    }

    private static func expandInclude(_ rawPattern: String, relativeTo configURL: URL) -> [URL] {
        let expanded = (rawPattern as NSString).expandingTildeInPath
        let url: URL
        if expanded.hasPrefix("/") {
            url = URL(fileURLWithPath: expanded)
        } else {
            url = configURL.deletingLastPathComponent().appendingPathComponent(expanded)
        }

        guard url.lastPathComponent.contains("*") || url.lastPathComponent.contains("?") else {
            return FileManager.default.fileExists(atPath: url.path) ? [url] : []
        }

        let directory = url.deletingLastPathComponent()
        let pattern = url.lastPathComponent
        let children = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        return children
            .filter { fnmatch(pattern, $0.lastPathComponent, 0) == 0 }
            .sorted { $0.path < $1.path }
    }
}
