import SwiftUI

struct DataView: View {
    @State private var selectedRange: TimeRange = .week

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                timeRangePicker
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                ScrollView {
                    VStack(spacing: 16) {
                        HeartRateSection(range: selectedRange)
                        StepsSection(range: selectedRange)
                        BodyWeightSection(range: selectedRange)
                        SleepSection(range: selectedRange)
                        ActiveEnergySection(range: selectedRange)
                    }
                    .padding()
                }
            }
            .navigationTitle(String(localized: "数据", comment: "Data tab title"))
        }
    }

    private var timeRangePicker: some View {
        Picker(selection: $selectedRange) {
            ForEach(TimeRange.allCases) { range in
                Text(range.localizedLabel).tag(range)
            }
        } label: {
            Text("时间范围", comment: "Time range picker label")
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(String(localized: "选择时间范围", comment: "Time range picker a11y"))
    }
}

// MARK: - Section Card Container

private struct DataSectionCard<Destination: View, Content: View>: View {
    let title: String
    let systemImage: String
    let destination: Destination
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationLink {
            destination
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: systemImage)
                    .font(.headline)

                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
    }
}

private struct PlaceholderChart: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.quaternary)
            .frame(height: 120)
            .overlay {
                Text(String(localized: "图表", comment: "Chart placeholder"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
    }
}

private struct PlaceholderSummary: View {
    var body: some View {
        HStack {
            Text(String(localized: "统计摘要", comment: "Stats summary placeholder"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - Section Placeholder Detail

private struct SectionDetailPlaceholder: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(title)
    }
}

// MARK: - Sections

private struct HeartRateSection: View {
    let range: TimeRange

    var body: some View {
        DataSectionCard(
            title: String(localized: "心率", comment: "Heart rate section"),
            systemImage: "heart.fill",
            destination: SectionDetailPlaceholder(
                title: String(localized: "心率", comment: "Heart rate detail")
            )
        ) {
            PlaceholderChart()
            PlaceholderSummary()
        }
    }
}

private struct StepsSection: View {
    let range: TimeRange

    var body: some View {
        DataSectionCard(
            title: String(localized: "步数", comment: "Steps section"),
            systemImage: "figure.walk",
            destination: SectionDetailPlaceholder(
                title: String(localized: "步数", comment: "Steps detail")
            )
        ) {
            PlaceholderChart()
            PlaceholderSummary()
        }
    }
}

private struct BodyWeightSection: View {
    let range: TimeRange

    var body: some View {
        DataSectionCard(
            title: String(localized: "体重", comment: "Body weight section"),
            systemImage: "scalemass.fill",
            destination: SectionDetailPlaceholder(
                title: String(localized: "体重", comment: "Body weight detail")
            )
        ) {
            PlaceholderChart()
            PlaceholderSummary()
        }
    }
}

private struct SleepSection: View {
    let range: TimeRange

    var body: some View {
        DataSectionCard(
            title: String(localized: "睡眠", comment: "Sleep section"),
            systemImage: "bed.double.fill",
            destination: SectionDetailPlaceholder(
                title: String(localized: "睡眠", comment: "Sleep detail")
            )
        ) {
            PlaceholderChart()
            PlaceholderSummary()
        }
    }
}

private struct ActiveEnergySection: View {
    let range: TimeRange

    var body: some View {
        DataSectionCard(
            title: String(localized: "活动能量", comment: "Active energy section"),
            systemImage: "flame.fill",
            destination: SectionDetailPlaceholder(
                title: String(localized: "活动能量", comment: "Active energy detail")
            )
        ) {
            PlaceholderChart()
            PlaceholderSummary()
        }
    }
}

#Preview {
    DataView()
}
