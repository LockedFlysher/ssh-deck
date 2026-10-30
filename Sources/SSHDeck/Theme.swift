import AppKit
import SSHDeckCore
import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.08, green: 0.52, blue: 0.46)
    static let cpu = Color(red: 0.10, green: 0.54, blue: 0.48)
    static let memory = Color(red: 0.78, green: 0.45, blue: 0.15)
    static let disk = Color(red: 0.18, green: 0.42, blue: 0.70)
    static let load = Color(red: 0.67, green: 0.29, blue: 0.31)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let subtleBorder = Color(nsColor: .separatorColor).opacity(0.45)

    static func statusColor(_ state: HostConnectionState) -> Color {
        switch state {
        case .online:
            return Color(red: 0.16, green: 0.62, blue: 0.37)
        case .offline:
            return Color(red: 0.78, green: 0.25, blue: 0.27)
        case .checking:
            return Color(red: 0.82, green: 0.54, blue: 0.13)
        case .idle:
            return Color(nsColor: .tertiaryLabelColor)
        }
    }

    static func slurmColor(_ category: SlurmNodeCategory) -> Color {
        switch category {
        case .idle:
            return Color(red: 0.16, green: 0.62, blue: 0.37)
        case .allocated:
            return Color(red: 0.78, green: 0.25, blue: 0.27)
        case .mixed:
            return Color(red: 0.82, green: 0.54, blue: 0.13)
        case .unavailable:
            return Color(nsColor: .secondaryLabelColor)
        case .other:
            return Color(red: 0.32, green: 0.46, blue: 0.68)
        }
    }

    static func avatarColor(for host: SSHHost) -> Color {
        let value = host.alias.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let palette: [Color] = [
            Color(red: 0.12, green: 0.47, blue: 0.45),
            Color(red: 0.20, green: 0.38, blue: 0.62),
            Color(red: 0.57, green: 0.38, blue: 0.19),
            Color(red: 0.44, green: 0.34, blue: 0.55)
        ]
        return palette[value % palette.count]
    }
}

enum DisplayFormat {
    static func bytes(_ value: UInt64) -> String {
        let number = Double(value)
        let units: [(String, Double)] = [
            ("TB", 1_000_000_000_000),
            ("GB", 1_000_000_000),
            ("MB", 1_000_000),
            ("KB", 1_000)
        ]

        for (unit, divisor) in units where number >= divisor {
            let converted = number / divisor
            if converted >= 100 {
                return String(format: "%.0f %@", converted, unit)
            }
            if converted >= 10 {
                return String(format: "%.1f %@", converted, unit)
            }
            return String(format: "%.2f %@", converted, unit)
        }
        return "\(value) B"
    }

    static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", min(max(fraction, 0), 1) * 100)
    }

    static func number(_ value: Double, digits: Int = 2) -> String {
        String(format: "%.\(digits)f", value)
    }

    static func latency(_ milliseconds: Double?) -> String {
        guard let milliseconds else { return "--" }
        if milliseconds >= 1_000 {
            return String(format: "%.1f s", milliseconds / 1_000)
        }
        return String(format: "%.0f ms", milliseconds)
    }

    static func uptime(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "--" }
        let days = Int(seconds) / 86_400
        let hours = (Int(seconds) % 86_400) / 3_600
        let minutes = (Int(seconds) % 3_600) / 60

        if days > 0 {
            return "\(days)d \(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    static func time(_ date: Date?) -> String {
        guard let date else { return "--" }
        return date.formatted(date: .omitted, time: .standard)
    }
}

struct HostAvatar: View {
    let host: SSHHost
    var size: CGFloat = 38

    private var symbolName: String {
        let alias = host.alias.lowercased()
        if alias.contains("phone") || alias.contains("termux") {
            return "iphone"
        }
        if alias.contains("cluster") || alias.contains("hpcc") {
            return "server.rack"
        }
        if alias.contains("workstation") ||
            alias.contains("mechrevo") ||
            alias.contains("3050") ||
            alias.contains("mac") {
            return "desktopcomputer"
        }
        if alias.contains("cloud") || alias.contains("tencent") {
            return "cloud"
        }
        return "server.rack"
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.avatarColor(for: host).opacity(0.16))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.avatarColor(for: host).opacity(0.24), lineWidth: 1)
            Image(systemName: symbolName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(AppTheme.avatarColor(for: host))
        }
        .frame(width: size, height: size)
    }
}

struct StatusDot: View {
    let state: HostConnectionState
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(AppTheme.statusColor(state))
            .frame(width: size, height: size)
            .overlay {
                if state == .checking {
                    Circle()
                        .stroke(AppTheme.statusColor(state).opacity(0.35), lineWidth: 2)
                        .scaleEffect(1.8)
                }
            }
            .accessibilityHidden(true)
    }
}

struct StatusBadge: View {
    let state: HostConnectionState

    private var label: String {
        switch state {
        case .online: return "Online"
        case .offline: return "Offline"
        case .checking: return "Checking"
        case .idle: return "Waiting"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(state: state, size: 7)
            Text(label)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(AppTheme.statusColor(state))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(AppTheme.statusColor(state).opacity(0.11))
        )
    }
}

struct MeterBar: View {
    let value: Double
    let color: Color
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geometry in
            let fraction = min(max(value, 0), 1)
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(color.opacity(0.13))
                Capsule(style: .continuous)
                    .fill(color)
                    .frame(width: fraction > 0 ? max(geometry.size.width * fraction, 3) : 0)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(DisplayFormat.percent(value))
    }
}

struct SectionTitle: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.subtleBorder, lineWidth: 1)
            )
    }
}

extension View {
    func cardBackground() -> some View {
        modifier(CardBackground())
    }
}
