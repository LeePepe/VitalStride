import Charts
import SwiftData
import SwiftUI
import VitalModels

private let oneRepMaxTrendFetchLimit = 200

struct OneRepMaxTrendPoint: Identifiable {
    let id: Date
    let date: Date
    let oneRepMax: Double

    init(date: Date, oneRepMax: Double) {
        self.id = date
        self.date = date
        self.oneRepMax = oneRepMax
    }
}

struct OneRepMaxTrendView: View {
    let exercise: Exercise

    @Environment(\.modelContext) private var modelContext
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .kg

    @State private var points: [OneRepMaxTrendPoint] = []
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if !hasLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if points.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .navigationTitle(exercise.localizedName)
        .task {
            reload()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(String(
                localized: "one_rep_max_trend_empty",
                defaultValue: "No 1RM history yet",
                comment: "Empty-state text on per-exercise 1RM trend view"
            ))
            .font(.headline)
            Text(String(
                localized: "one_rep_max_trend_empty_hint",
                defaultValue: "Log working sets (1–12 reps) to see this exercise's estimated 1RM trend.",
                comment: "Empty-state hint on per-exercise 1RM trend view"
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        List {
            Section {
                chartSection
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                Text(String(
                    localized: "one_rep_max_trend_caveat",
                    defaultValue: "Estimates are most accurate for 3–10 reps; sets with >15 reps can deviate significantly (Epley formula).",
                    comment: "Caveat about Epley 1RM estimation accuracy"
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            chartHeader
            chartBody
            singlePointHintIfNeeded
        }
        .padding()
    }

    private var chartHeader: some View {
        HStack {
            Text(String(
                localized: "one_rep_max_trend_title",
                defaultValue: "Estimated 1RM Trend",
                comment: "Title on per-exercise 1RM trend chart"
            ))
            .font(.headline)
            Spacer()
            Text(String(
                localized: "one_rep_max_trend_point_count \(points.count)",
                comment: "Number of sessions on trend chart, e.g. \"7 sessions\""
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var chartBody: some View {
        let yRange = computeYRange()
        let unitRaw = weightUnit.rawValue
        return Chart {
            if points.count >= 2 {
                ForEach(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("1RM", displayWeight(point.oneRepMax))
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.monotone)

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("1RM", displayWeight(point.oneRepMax))
                    )
                    .foregroundStyle(.blue)
                    .symbolSize(40)
                }
            } else if let point = points.first {
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("1RM", displayWeight(point.oneRepMax))
                )
                .foregroundStyle(.blue)
                .symbolSize(80)
            }
        }
        .chartYScale(domain: yRange)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                AxisGridLine()
                AxisTick()
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let doubleValue = value.as(Double.self) {
                        Text("\(Int(doubleValue)) \(unitRaw)")
                    }
                }
                AxisGridLine()
            }
        }
        .frame(height: 240)
        .accessibilityLabel(chartA11yLabel)
    }

    @ViewBuilder
    private var singlePointHintIfNeeded: some View {
        if points.count == 1 {
            Text(String(
                localized: "one_rep_max_trend_single_point_hint",
                defaultValue: "Only one session available — log more to see a trend line.",
                comment: "Hint shown when only a single 1RM data point exists"
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private func computeYRange() -> ClosedRange<Double> {
        let values = points.map { displayWeight($0.oneRepMax) }
        guard let minVal = values.min(), let maxVal = values.max() else {
            return 0...100
        }
        if abs(maxVal - minVal) < 0.5 {
            let center = maxVal
            let padding = max(center * 0.1, 5.0)
            return (center - padding)...(center + padding)
        }
        let padding = max((maxVal - minVal) * 0.15, 1.0)
        let lower = max(0, minVal - padding)
        return lower...(maxVal + padding)
    }

    private var chartA11yLabel: String {
        guard let first = points.first, let last = points.last else {
            return String(localized: "one_rep_max_trend_empty", defaultValue: "No 1RM history yet", comment: "Empty a11y")
        }
        let firstValue = String(format: "%.1f", displayWeight(first.oneRepMax))
        let lastValue = String(format: "%.1f", displayWeight(last.oneRepMax))
        let unit = weightUnit.a11yName
        let count = points.count
        return String(
            localized: "one_rep_max_trend_a11y \(count) \(firstValue) \(lastValue) \(unit)",
            comment: "1RM trend chart a11y: sessions count, first value, last value, unit"
        )
    }

    private func displayWeight(_ kgValue: Double) -> Double {
        weightUnit == .lb ? kgValue * 2.20462 : kgValue
    }

    private func reload() {
        let exerciseID = exercise.persistentModelID
        var descriptor = FetchDescriptor<WorkoutExercise>(
            predicate: #Predicate<WorkoutExercise> { we in
                we.exercise?.persistentModelID == exerciseID
                    && we.workout?.endDate != nil
            }
        )
        descriptor.fetchLimit = oneRepMaxTrendFetchLimit
        descriptor.relationshipKeyPathsForPrefetching = [\.sets, \.workout]

        do {
            let workoutExercises = try modelContext.fetch(descriptor)
            points = OneRepMaxTrendAggregator.aggregate(from: workoutExercises)
        } catch {
            points = []
        }
        hasLoaded = true
    }
}

enum OneRepMaxTrendAggregator {
    static func aggregate(from workoutExercises: [WorkoutExercise]) -> [OneRepMaxTrendPoint] {
        let calendar = Calendar.current
        var perDayMax: [Date: Double] = [:]

        for we in workoutExercises {
            guard let workout = we.workout,
                  workout.endDate != nil,
                  let best = we.bestEstimatedOneRepMax else {
                continue
            }
            let day = calendar.startOfDay(for: workout.startDate)
            if let existing = perDayMax[day] {
                perDayMax[day] = max(existing, best)
            } else {
                perDayMax[day] = best
            }
        }

        return perDayMax
            .map { OneRepMaxTrendPoint(date: $0.key, oneRepMax: $0.value) }
            .sorted { $0.date < $1.date }
    }
}

#Preview("Multi-point trend") {
    NavigationStack {
        OneRepMaxTrendView(
            exercise: Exercise(nameEn: "Bench Press", nameZh: "Bench Press", muscleGroup: .chest, equipment: .barbell)
        )
    }
    // swiftlint:disable:next force_try
    .modelContainer(try! ModelContainerConfiguration.makeTestContainer())
}

#Preview("Empty state") {
    NavigationStack {
        OneRepMaxTrendView(
            exercise: Exercise(nameEn: "Squat", nameZh: "Squat", muscleGroup: .legs, equipment: .barbell)
        )
    }
    // swiftlint:disable:next force_try
    .modelContainer(try! ModelContainerConfiguration.makeTestContainer())
}
