import DesignKit
import SwiftUI
import VitalModels

struct MuscleGroupFrequencyCard: View {
    let counts: [MuscleGroup: Int]

    static func sortedEntries(counts: [MuscleGroup: Int]) -> [(MuscleGroup, Int)] {
        let all = MuscleGroup.allCases.map { ($0, counts[$0] ?? 0) }
        let orderIndex = Dictionary(
            uniqueKeysWithValues: MuscleGroup.allCases.enumerated().map { ($1, $0) }
        )
        return all.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return (orderIndex[lhs.0] ?? 0) < (orderIndex[rhs.0] ?? 0)
        }
    }

    private var sortedEntries: [(MuscleGroup, Int)] {
        Self.sortedEntries(counts: counts)
    }

    private let gridColumns = [
        GridItem(.adaptive(minimum: 108), spacing: 8),
    ]

    var body: some View {
        Card {
            SectionHeader(
                String(
                    localized: "overview_muscle_group_frequency_title",
                    defaultValue: "Muscle group frequency (last 7 days)"
                )
            )
            .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: gridColumns, spacing: 8) {
                ForEach(sortedEntries, id: \.0) { entry in
                    MuscleGroupChip(group: entry.0, count: entry.1)
                }
            }
        }
    }
}

private struct MuscleGroupChip: View {
    let group: MuscleGroup
    let count: Int

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.theme) private var theme

    private var level: FrequencyLevel {
        switch count {
        case 0: .zero
        case 1...2: .low
        default: .high
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: group.sfSymbol)
                .font(.subheadline)
                .foregroundStyle(level.iconColor(theme))
                .frame(width: 20)

            Text(group.localizedName)
                .font(TypeScale.body)
                .foregroundStyle(theme.neutrals.text1)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 4)

            Text("\(count)")
                .font(TypeScale.meta.monospacedDigit()).fontWeight(.bold)
                .foregroundStyle(level.badgeForeground(theme))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(level.badgeBackground(theme))
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(reduceTransparency ? level.solidChipBackground(theme) : level.chipBackground(theme))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text(
                String(
                    localized: "overview_muscle_group_chip_a11y",
                    defaultValue: "\(group.localizedName): \(count) times"
                )
            )
        )
    }
}

private enum FrequencyLevel {
    case zero
    case low
    case high

    func iconColor(_ theme: Theme) -> Color {
        switch self {
        case .zero: theme.neutrals.text3
        case .low: theme.primary.primary
        case .high: theme.primary.primaryText
        }
    }

    func badgeForeground(_ theme: Theme) -> Color {
        switch self {
        case .zero: theme.neutrals.text3
        case .low: theme.primary.onPrimary
        case .high: theme.primary.onPrimary
        }
    }

    func badgeBackground(_ theme: Theme) -> Color {
        switch self {
        case .zero: theme.neutrals.text3.opacity(0.2)
        case .low: theme.primary.primary
        case .high: theme.primary.primaryText
        }
    }

    func chipBackground(_ theme: Theme) -> Color {
        switch self {
        case .zero: theme.neutrals.inner
        case .low: theme.primary.primary.opacity(0.10)
        case .high: theme.primary.primary.opacity(0.16)
        }
    }

    func solidChipBackground(_ theme: Theme) -> Color {
        switch self {
        case .zero: theme.neutrals.inner
        case .low: theme.primary.primary.opacity(0.22)
        case .high: theme.primary.primary.opacity(0.30)
        }
    }
}

#Preview("Mixed data") {
    MuscleGroupFrequencyCard(counts: [
        .chest: 3,
        .back: 2,
        .legs: 4,
        .arms: 1,
        .shoulders: 0,
        .core: 0,
        .fullBody: 0,
    ])
    .designThemePreview()
    .padding()
}

#Preview("Empty data") {
    MuscleGroupFrequencyCard(counts: [:])
        .designThemePreview()
        .padding()
}
