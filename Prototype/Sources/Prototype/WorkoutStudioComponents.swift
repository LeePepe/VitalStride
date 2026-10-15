import DesignKit
import SwiftUI

struct StudioSurface: ViewModifier {
    @Environment(\.theme) private var theme
    let style: StudioStyle
    var emphasized = false
    func body(content: Content) -> some View {
        content
            .background(emphasized ? theme.primary.primarySubtle : theme.neutrals.card)
            .clipShape(RoundedRectangle(cornerRadius: style.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: style.radius, style: .continuous)
                    .strokeBorder(emphasized ? theme.primary.primaryBorder : theme.neutrals.border, lineWidth: 0.5)
            }
    }
}

struct StudioAction: View {
    @Environment(\.theme) private var theme
    let title: String
    let symbol: String
    let style: StudioStyle
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).font(.system(.body, weight: .semibold))
                Image(systemName: symbol).font(.body.weight(.semibold)).accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(style == .graphite ? theme.neutrals.card : theme.primary.onPrimary)
            .background(style == .graphite ? theme.neutrals.text1 : theme.primary.primary)
            .clipShape(RoundedRectangle(cornerRadius: style.radius == 24 ? 26 : 14))
            .opacity(disabled ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct StudioIconButton: View {
    @Environment(\.theme) private var theme
    let symbol: String
    let label: String
    var filled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(theme.neutrals.text1)
                .background(filled ? theme.neutrals.inner : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct StudioChip: View {
    @Environment(\.theme) private var theme
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.subheadline, weight: selected ? .semibold : .medium))
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .foregroundStyle(selected ? theme.primary.primaryText : theme.neutrals.text2)
                .background(selected ? theme.primary.primarySubtle : theme.neutrals.inner, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? theme.primary.primaryBorder : .clear, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct StudioSelectionMark: View {
    @Environment(\.theme) private var theme
    let index: Int?
    var body: some View {
        ZStack {
            Circle().fill(index == nil ? theme.neutrals.card : theme.primary.primary)
            Circle().strokeBorder(index == nil ? theme.neutrals.border : .clear, lineWidth: 1.5)
            if let index {
                Text("\(index + 1)").font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.primary.onPrimary)
            } else {
                Image(systemName: "plus").font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.neutrals.text2)
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}

struct StudioSessionBand: View {
    @Environment(\.theme) private var theme
    let session: StudioSession
    let style: StudioStyle
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(studioText("workout.elapsed")).font(.caption).foregroundStyle(theme.neutrals.text2)
                Text("24:18").font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) {
                Text(studioText("workout.sets")).font(.caption).foregroundStyle(theme.neutrals.text2)
                Text("\(session.completedCount) / \(session.totalCount)")
                    .font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text(studioText("workout.volume")).font(.caption).foregroundStyle(theme.neutrals.text2)
                Text(session.totalVolume.formatted(.number.precision(.fractionLength(0))) + " kg")
                    .font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
            }
        }
        .padding(16)
        .modifier(StudioSurface(style: style))
        .accessibilityElement(children: .combine)
    }
}

/// The only view that ticks. Date-based rest survives editing and layout changes.
struct StudioRestPanel: View {
    @Environment(\.theme) private var theme
    let session: StudioSession
    let style: StudioStyle
    var body: some View {
        if let end = session.restEnd {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = max(0, Int(ceil(end.timeIntervalSince(context.date))))
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: seconds == 0 ? "checkmark.circle" : "timer").accessibilityHidden(true)
                        Text(studioText(seconds == 0 ? "rest.ready" : "rest.title")).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                            .font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(theme.neutrals.border)
                            Capsule().fill(theme.primary.primary)
                                .frame(width: proxy.size.width * min(1, Double(seconds) / session.restTotal))
                        }
                    }.frame(height: 3).accessibilityHidden(true)
                    HStack(spacing: 12) {
                        Button(studioText("rest.minusShort")) { session.adjustRest(-10) }.frame(minWidth: 60, minHeight: 44)
                            .accessibilityLabel(studioText("rest.minus"))
                        Button(studioText("rest.plusShort")) { session.adjustRest(10) }.frame(minWidth: 60, minHeight: 44)
                            .accessibilityLabel(studioText("rest.plus"))
                        Spacer()
                        Button(studioText(seconds == 0 ? "rest.continue" : "rest.skip")) { session.restEnd = nil }
                            .frame(minWidth: 64, minHeight: 44).font(.subheadline.weight(.semibold))
                    }.buttonStyle(.plain)
                }
                .foregroundStyle(theme.primary.primaryText)
                .padding(.horizontal, 16).padding(.top, 12)
                .modifier(StudioSurface(style: style, emphasized: true))
            }
        }
    }
}

struct StudioNumericEditor: View {
    @Environment(\.theme) private var theme
    let session: StudioSession
    let style: StudioStyle
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(studioText(session.editorField == "weight" ? "editor.weight" : "editor.reps"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(session.editorValue).font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
                StudioIconButton(symbol: "xmark", label: studioText("action.cancel")) { session.editorField = nil }
            }
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { column in
                        let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"]
                        let key = keys[row * 3 + column]
                        Button {
                            if key == "⌫" {
                                if !session.editorValue.isEmpty { session.editorValue.removeLast() }
                            } else if key != "." || (session.editorField == "weight" && !session.editorValue.contains(".")) {
                                session.editorValue = session.editorValue == "0" ? key : String((session.editorValue + key).prefix(6))
                            }
                        } label: {
                            Text(key).font(.system(.title3, weight: .semibold)).monospacedDigit()
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(key == "⌫" ? studioText("action.deleteDigit") : key)
                    }
                }
            }
            StudioAction(title: studioText("action.done"), symbol: "checkmark", style: style,
                         disabled: Double(session.editorValue.replacingOccurrences(of: ",", with: ".")) == nil) {
                session.commitEditor()
            }
        }
        .padding(12)
        .background(theme.neutrals.card)
    }
}
