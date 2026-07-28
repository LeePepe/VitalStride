// WorkoutListPrototype.swift — isolated SwiftUI visual prototype of the
// production WorkoutListView so the MY-1361 design-gate fixture PNGs can be
// exported deterministically via PrototypeShotExporter (SwiftUI ImageRenderer,
// no simulator / HealthKit needed).
//
// This prototype target does NOT import VitalStride / VitalModels / SwiftData
// / HealthKit — it reconstructs the minimum visual shape (badge + banner +
// row + list scaffold) using only DesignKit tokens. The production widget
// stays the source of truth; this file exists solely to render the
// design-gate PNGs listed in `docs/reports/018-workout-list-redesign-screenshots.md`.
//
// Design tokens: DesignKit only. No hardcoded colours, radii, or font sizes
// beyond frame widths matched to the iPhone 16 preview device.

import DesignKit
import SwiftUI

// MARK: - Mock device kinds (mirror SourceDeviceKind for badge glyph mapping)

public enum PrototypeSourceDeviceKind: Equatable, Sendable {
    case appleWatch
    case iPhone
    case iPad
    case mac
    case other
}

// MARK: - Mock rows

public struct PrototypeAppRow: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let subtitle: String

    public init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }
}

public struct PrototypeHKRow: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let subtitle: String
    public let avgHR: Int?
    public let sourceKind: PrototypeSourceDeviceKind
    public let sourceName: String

    public init(
        title: String,
        subtitle: String,
        avgHR: Int?,
        sourceKind: PrototypeSourceDeviceKind,
        sourceName: String
    ) {
        self.title = title
        self.subtitle = subtitle
        self.avgHR = avgHR
        self.sourceKind = sourceKind
        self.sourceName = sourceName
    }
}

// MARK: - Prototype badge (mirror of WorkoutSourceBadge)

struct PrototypeSourceBadge: View {
    @Environment(\.theme) private var theme

    let kind: PrototypeSourceDeviceKind?
    let sourceName: String?
    let isApp: Bool

    var body: some View {
        HStack(spacing: Space.hair) {
            Image(systemName: glyphName)
                .font(TypeScale.meta.weight(.medium))
            Text(label)
                .font(TypeScale.meta)
                .lineLimit(1)
        }
        .foregroundStyle(theme.neutrals.text2)
        .padding(.horizontal, Space.inline)
        .padding(.vertical, Space.chipVertical)
        .background(
            RoundedRectangle(cornerRadius: Radius.badge, style: .continuous)
                .fill(theme.neutrals.inner)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.badge, style: .continuous)
                .stroke(theme.neutrals.border, lineWidth: 0.5)
        )
    }

    private var glyphName: String {
        if isApp { return "dumbbell.fill" }
        switch kind {
        case .appleWatch: return "applewatch"
        case .iPhone: return "iphone"
        case .iPad: return "ipad"
        case .mac: return "laptopcomputer"
        case .other, .none: return "heart.text.square"
        }
    }

    private var label: String {
        if isApp { return "App" }
        switch kind {
        case .appleWatch: return "Apple Watch"
        case .iPhone: return "iPhone"
        case .iPad: return "iPad"
        case .mac: return "Mac"
        case .other, .none: return sourceName ?? "HealthKit"
        }
    }
}

// MARK: - Prototype state banner (mirror of WorkoutListStateBanner)

public enum PrototypeBannerState: Equatable, Sendable {
    case loading
    case failed
    case unauthorized
}

struct PrototypeStateBanner: View {
    @Environment(\.theme) private var theme
    let state: PrototypeBannerState

    var body: some View {
        HStack(alignment: .top, spacing: Space.gap) {
            iconView

            VStack(alignment: .leading, spacing: Space.hair) {
                Text(title)
                    .font(TypeScale.title)
                    .foregroundStyle(theme.neutrals.text1)
                Text(subtitle)
                    .font(TypeScale.body)
                    .foregroundStyle(theme.neutrals.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if state == .unauthorized {
                Button(action: {}) {
                    Text("Open Settings")
                        .font(TypeScale.body.weight(.medium))
                        .padding(.horizontal, Space.gap)
                        .frame(minHeight: Space.minTapTarget)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(Space.gap)
        .background(
            RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
                .fill(theme.neutrals.inner)
        )
    }

    @ViewBuilder
    private var iconView: some View {
        switch state {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(width: Space.minTapTarget / 2, height: Space.minTapTarget / 2)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(TypeScale.title)
                .foregroundStyle(theme.warning)
        case .unauthorized:
            Image(systemName: "lock.shield")
                .font(TypeScale.title)
                .foregroundStyle(theme.primary.primary)
        }
    }

    private var title: String {
        switch state {
        case .loading: return "Loading workouts"
        case .failed: return "Couldn't load Apple Health workouts"
        case .unauthorized: return "Grant HealthKit access"
        }
    }

    private var subtitle: String {
        switch state {
        case .loading: return "Fetching your Apple Watch and Health data."
        case .failed: return "Pull to refresh, or try again later."
        case .unauthorized: return "Enable Workouts in Settings to see Apple Watch training here."
        }
    }
}

// MARK: - Prototype rows

struct PrototypeAppRowView: View {
    @Environment(\.theme) private var theme
    let row: PrototypeAppRow

    var body: some View {
        VStack(alignment: .leading, spacing: Space.hair) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title)
                    .font(TypeScale.body.weight(.medium))
                    .foregroundStyle(theme.neutrals.text1)
                Spacer(minLength: Space.inline)
                PrototypeSourceBadge(kind: nil, sourceName: nil, isApp: true)
            }
            Text(row.subtitle)
                .font(TypeScale.meta)
                .foregroundStyle(theme.neutrals.text2)
        }
        .padding(.vertical, Space.hair)
    }
}

struct PrototypeHKRowView: View {
    @Environment(\.theme) private var theme
    let row: PrototypeHKRow

    var body: some View {
        VStack(alignment: .leading, spacing: Space.hair) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title)
                    .font(TypeScale.body.weight(.medium))
                    .foregroundStyle(theme.neutrals.text1)
                Spacer(minLength: Space.inline)
                PrototypeSourceBadge(
                    kind: row.sourceKind,
                    sourceName: row.sourceName,
                    isApp: false
                )
            }
            HStack(spacing: Space.inline) {
                Text(row.subtitle)
                    .font(TypeScale.meta)
                    .foregroundStyle(theme.neutrals.text2)
                if let avgHR = row.avgHR {
                    HStack(spacing: Space.hair) {
                        Image(systemName: "heart.fill")
                            .font(TypeScale.meta.weight(.medium))
                        Text("\(avgHR) bpm")
                            .font(TypeScale.meta)
                    }
                    .foregroundStyle(theme.neutrals.text2)
                    .padding(.horizontal, Space.inline)
                    .padding(.vertical, Space.chipVertical)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.badge, style: .continuous)
                            .fill(theme.neutrals.inner)
                    )
                }
            }
        }
        .padding(.vertical, Space.hair)
    }
}

// MARK: - Full-list prototype (parameterised by scenario)

public enum PrototypeListScenario: Sendable {
    case loading
    case empty
    case failed
    case unauthorized
    case mixed
}

public struct WorkoutListPrototype: View {
    @Environment(\.theme) private var theme
    public let scenario: PrototypeListScenario

    public init(scenario: PrototypeListScenario) {
        self.scenario = scenario
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Navigation-title-shape header (not real NavigationStack —
            // macOS ImageRenderer doesn't honour navigation chrome tint,
            // so we render the title inline using theme tokens.
            HStack {
                Text("Workouts")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(theme.neutrals.text1)
                Spacer()
            }
            .padding(.horizontal, Space.cardPadding)
            .padding(.top, Space.cardPadding)
            .padding(.bottom, Space.gap)

            listBody
                .padding(.horizontal, Space.cardPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.neutrals.bg)
    }

    @ViewBuilder
    private var listBody: some View {
        switch scenario {
        case .empty:
            emptyState
        case .loading, .failed, .unauthorized:
            VStack {
                PrototypeStateBanner(state: bannerState)
                Spacer()
            }
        case .mixed:
            VStack(alignment: .leading, spacing: Space.gap) {
                rowCard {
                    PrototypeAppRowView(row: PrototypeAppRow(
                        title: "Push day",
                        subtitle: "6 exercises · 42 min"
                    ))
                }
                rowCard {
                    PrototypeHKRowView(row: PrototypeHKRow(
                        title: "Running",
                        subtitle: "5.2 km · 28 min",
                        avgHR: 148,
                        sourceKind: .appleWatch,
                        sourceName: "Apple Watch"
                    ))
                }
                rowCard {
                    PrototypeHKRowView(row: PrototypeHKRow(
                        title: "Walking",
                        subtitle: "1.8 km · 22 min",
                        avgHR: 112,
                        sourceKind: .iPhone,
                        sourceName: "iPhone"
                    ))
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func rowCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(Space.gap)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
                    .fill(theme.neutrals.inner.opacity(0.5))
            )
    }

    private var bannerState: PrototypeBannerState {
        switch scenario {
        case .loading: return .loading
        case .failed: return .failed
        case .unauthorized: return .unauthorized
        default: return .loading
        }
    }

    private var emptyState: some View {
        VStack(spacing: Space.gap) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(TypeScale.display)
                .foregroundStyle(theme.neutrals.text2)
            Text("No workouts yet")
                .font(TypeScale.title)
                .foregroundStyle(theme.neutrals.text1)
            Text("Tap + to start your first workout")
                .font(TypeScale.body)
                .foregroundStyle(theme.neutrals.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Space.cardPadding)
    }

    // Two seeded fixture rows — one Apple Watch HK, one iPhone HK, plus one App
    // row — chosen so the mixed scenario clearly demonstrates the badge +
    // avg-HR chip contract. Kept inline in `listBody` to satisfy the
    // SwiftUI @ViewBuilder single-typed constraint.
}

#Preview("Loading — light") {
    WorkoutListPrototype(scenario: .loading)
        .designThemePreview()
}

#Preview("Empty — light") {
    WorkoutListPrototype(scenario: .empty)
        .designThemePreview()
}

#Preview("Failed — light") {
    WorkoutListPrototype(scenario: .failed)
        .designThemePreview()
}

#Preview("Unauthorized — light") {
    WorkoutListPrototype(scenario: .unauthorized)
        .designThemePreview()
}

#Preview("Mixed App + HK (Apple Watch) — light") {
    WorkoutListPrototype(scenario: .mixed)
        .designThemePreview()
}

#Preview("Mixed App + HK (Apple Watch) — dark, Large") {
    WorkoutListPrototype(scenario: .mixed)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility1)
        .designThemePreview()
}
