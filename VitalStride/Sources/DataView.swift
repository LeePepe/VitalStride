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

struct DataSectionCard<Destination: View, Content: View>: View {
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
        .accessibilityElement(children: .combine)
        .accessibilityHint(String(localized: "轻点查看详情", comment: "Card navigation a11y hint"))
    }
}


#Preview {
    DataView()
}
