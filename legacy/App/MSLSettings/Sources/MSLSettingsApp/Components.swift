import MSLControlCore
import SwiftUI

enum MSLPalette {
    static let accent = Color(red: 0.24, green: 0.76, blue: 0.58)
    static let warning = Color(red: 0.95, green: 0.67, blue: 0.24)
    static let danger = Color(red: 0.93, green: 0.34, blue: 0.35)
}

struct SurfaceCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            }
    }
}

struct StatusPill: View {
    let state: RuntimeState
    var compact = false

    private var color: Color {
        switch state {
        case .running: return MSLPalette.accent
        case .starting, .stopping: return MSLPalette.warning
        case .stopped: return .secondary
        case .unknown: return MSLPalette.danger
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            if !compact {
                Text(state.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, compact ? 5 : 9)
        .padding(.vertical, compact ? 5 : 6)
        .background(color.opacity(0.13), in: Capsule())
        .accessibilityLabel("Status: \(state.rawValue)")
    }
}

struct MetricTile: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(label, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .monospaced, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct PageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var state: RuntimeState?

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(MSLPalette.accent)
                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let state { StatusPill(state: state) }
        }
    }
}

extension UInt64 {
    var mslFileSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: self), countStyle: .binary)
    }
}
