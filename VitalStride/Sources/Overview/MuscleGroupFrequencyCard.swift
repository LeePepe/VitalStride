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
        VStack(alignment: .leading, spacing: 12) {
            Text(
                String(
                    localized: "overview_muscle_group_frequency_title",
                    defaultValue: "Muscle group frequency (last 7 days)"
                )
            )
            .font(.headline)
            .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: gridColumns, spacing: 8) {
                ForEach(sortedEntries, id: \.0) { entry in
                    MuscleGroupChip(group: entry.0, count: entry.1)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct MuscleGroupChip: View {
    let group: MuscleGroup
    let count: Int

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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
                .foregroundStyle(level.iconColor)
                .frame(width: 20)

            Text(group.localizedName)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 4)

            Text("\(count)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(level.badgeForeground)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(level.badgeBackground)
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(reduceTransparency ? level.solidChipBackground : level.chipBackground)
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

    var iconColor: Color {
        switch self {
        case .zero: .secondary
        case .low: .accentColor
        case .high: .orange
        }
    }

    var badgeForeground: Color {
        switch self {
        case .zero: .secondary
        case .low: .white
        case .high: .white
        }
    }

    var badgeBackground: Color {
        switch self {
        case .zero: Color.secondary.opacity(0.2)
        case .low: Color.accentColor
        case .high: Color.orange
        }
    }

    var chipBackground: Color {
        switch self {
        case .zero: Color.secondary.opacity(0.08)
        case .low: Color.accentColor.opacity(0.10)
        case .high: Color.orange.opacity(0.12)
        }
    }

    var solidChipBackground: Color {
        switch self {
        case .zero: Color.secondary.opacity(0.18)
        case .low: Color.accentColor.opacity(0.22)
        case .high: Color.orange.opacity(0.24)
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
    .padding()
}

#Preview("Empty data") {
    MuscleGroupFrequencyCard(counts: [:])
        .padding()
}
