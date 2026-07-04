import SwiftUI

// ============================================================================
//  Component vocabulary — SAME names/roles/rules as the web components.
//  Elevation = luminance tiers (bg < card < inner) + 1px border, no shadows.
// ============================================================================

// MARK: - Card (L1) + CardInner (L2)

public struct Card<Content: View>: View {
    @Environment(\.theme) private var theme
    @ViewBuilder private let content: () -> Content
    public init(@ViewBuilder content: @escaping () -> Content) { self.content = content }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.gap) { content() }
            .padding(Space.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.neutrals.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card)
                    .stroke(theme.neutrals.border, lineWidth: 1)
            )
    }
}

public struct CardInner<Content: View>: View {
    @Environment(\.theme) private var theme
    @ViewBuilder private let content: () -> Content
    public init(@ViewBuilder content: @escaping () -> Content) { self.content = content }

    public var body: some View {
        HStack { content() }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.neutrals.inner)
            .clipShape(RoundedRectangle(cornerRadius: Radius.inner))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.inner)
                    .stroke(theme.neutrals.border, lineWidth: 1)
            )
    }
}

// MARK: - Metric — tabular value + label + optional delta

public struct Metric: View {
    @Environment(\.theme) private var theme
    private let value: String
    private let label: String?
    private let delta: (value: String, positive: Bool)?

    public init(value: String, label: String? = nil, delta: (value: String, positive: Bool)? = nil) {
        self.value = value
        self.label = label
        self.delta = delta
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(TypeScale.display)
            HStack(spacing: 8) {
                if let label { Text(label).font(TypeScale.meta).foregroundStyle(theme.neutrals.text2) }
                if let delta {
                    Text("\(delta.positive ? "▲" : "▼") \(delta.value)")
                        .font(TypeScale.meta.monospacedDigit())
                        .foregroundStyle(delta.positive ? theme.success : theme.danger)
                }
            }
        }
    }
}

// MARK: - Sparkline — area + line

public struct Sparkline: View {
    private let data: [Double]
    private let color: Color
    public init(data: [Double], color: Color) {
        self.data = data
        self.color = color
    }

    public var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if pts.count > 1 {
                    areaPath(pts, height: geo.size.height)
                        .fill(LinearGradient(
                            colors: [color.opacity(0.22), color.opacity(0)],
                            startPoint: .top, endPoint: .bottom))
                    linePath(pts)
                        .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }
            }
        }
        .frame(height: 36)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard data.count > 1 else { return [] }
        let minV = data.min() ?? 0
        let maxV = data.max() ?? 1
        let span = maxV - minV == 0 ? 1 : maxV - minV
        let step = size.width / CGFloat(data.count - 1)
        return data.enumerated().map { i, d in
            CGPoint(x: CGFloat(i) * step, y: size.height - CGFloat((d - minV) / span) * size.height)
        }
    }

    private func linePath(_ pts: [CGPoint]) -> Path {
        var p = Path()
        p.addLines(pts)
        return p
    }

    private func areaPath(_ pts: [CGPoint], height: CGFloat) -> Path {
        var p = Path()
        p.addLines(pts)
        if let last = pts.last, let first = pts.first {
            p.addLine(to: CGPoint(x: last.x, y: height))
            p.addLine(to: CGPoint(x: first.x, y: height))
            p.closeSubpath()
        }
        return p
    }
}

// MARK: - RingGauge — ratio as an arc

public struct RingGauge: View {
    @Environment(\.theme) private var theme
    private let value: Double
    private let size: CGFloat
    private let stroke: CGFloat
    private let color: Color?

    public init(value: Double, size: CGFloat = 56, stroke: CGFloat = 6, color: Color? = nil) {
        self.value = value
        self.size = size
        self.stroke = stroke
        self.color = color
    }

    public var body: some View {
        let clamped = min(1, max(0, value))
        ZStack {
            Circle().stroke(theme.neutrals.border, lineWidth: stroke)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(color ?? theme.primary.primary, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(clamped * 100))%").font(TypeScale.meta.monospacedDigit()).fontWeight(.semibold)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - StatusPill — colored pill, never grey text

public enum PillTone { case primary, success, warning, danger, neutral }

public struct StatusPill: View {
    @Environment(\.theme) private var theme
    private let text: String
    private let tone: PillTone
    public init(_ text: String, tone: PillTone = .neutral) {
        self.text = text
        self.tone = tone
    }

    private var color: Color {
        switch tone {
        case .primary: return theme.primary.primary
        case .success: return theme.success
        case .warning: return theme.warning
        case .danger: return theme.danger
        case .neutral: return theme.neutrals.text3
        }
    }

    public var body: some View {
        Text(text)
            .font(TypeScale.meta).fontWeight(.medium)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.16))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - SectionHeader

public struct SectionHeader: View {
    @Environment(\.theme) private var theme
    private let icon: String?
    private let title: String
    public init(_ title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
            Text(title.uppercased()).font(TypeScale.meta).fontWeight(.semibold)
        }
        .foregroundStyle(theme.neutrals.text2)
    }
}
