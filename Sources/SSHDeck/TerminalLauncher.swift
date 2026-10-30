import AppKit
import Foundation
import SSHDeckCore

enum TerminalLauncher {
    static func openTerminal(for host: SSHHost) {
        let command = host.terminalCommand
        let escaped = appleScriptString(command)
        let source = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """

        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        script?.executeAndReturnError(&error)
    }

    static func copyCommand(for host: SSHHost) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(host.terminalCommand, forType: .string)
    }

    static func copyText(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private static func appleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
