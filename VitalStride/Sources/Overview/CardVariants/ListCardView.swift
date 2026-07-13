import AIService
import DesignKit
import SwiftUI

// MARK: - Wide List (2-3 rows preview)

struct ListWideCardView: View {
    let insight: OverviewInsight
    @Environment(\.theme) private var theme

    private var items: [ListItem] {
        CardContentParser.parseListItems(insight.content)
    }

    var body: some View {
        OverviewCardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text(insight.title)
                    .font(TypeScale.title)
                    .foregroundStyle(theme.neutrals.text1)
                    .lineLimit(1)

                if items.isEmpty {
                    emptyContent
                } else {
                    listContent(maxItems: 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(listAccessibilityLabel(maxItems: 3))
        }
        .onAppear { recordTelemetry() }
    }

    private func listContent(maxItems: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items.prefix(maxItems)) { item in
                HStack {
                    Text(item.label)
                        .font(TypeScale.body)
                        .foregroundStyle(theme.neutrals.text1)
                    Spacer()
                    if let value = item.value {
                        Text(value)
                            .font(TypeScale.num)
                            .foregroundStyle(theme.neutrals.text2)
                    }
                }
            }

            if items.count > maxItems {
                let remaining = items.count - maxItems
                Text("+\(remaining) \(String(localized: "list_more", defaultValue: "more"))")
                    .font(TypeScale.meta)
                    .foregroundStyle(theme.neutrals.text3)
            }
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        Text(String(localized: "no_data", defaultValue: "No data"))
            .font(TypeScale.meta)
            .foregroundStyle(theme.neutrals.text3)
    }

    private func listAccessibilityLabel(maxItems: Int) -> String {
        let visibleItems = items.prefix(maxItems)
        let itemDescriptions = visibleItems.map { item in
            if let value = item.value {
                return "\(item.label), \(value)"
            }
            return item.label
        }
        return "\(insight.title), \(itemDescriptions.joined(separator: "; "))"
    }

    private func recordTelemetry() {
        guard let size = insight.parsedCardSize, let type = insight.parsedCardType else { return }
        if items.isEmpty {
            CardTelemetry.recordRenderFailed(size: size, type: type)
        } else {
            CardTelemetry.recordRendered(size: size, type: type)
        }
    }
}

// MARK: - Large List (full list)

struct ListLargeCardView: View {
    let insight: OverviewInsight
    @Environment(\.theme) private var theme

    private var items: [ListItem] {
        CardContentParser.parseListItems(insight.content)
    }

    var body: some View {
        OverviewCardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text(insight.title)
                    .font(TypeScale.title)
                    .foregroundStyle(theme.neutrals.text1)
                    .lineLimit(1)

                if items.isEmpty {
                    emptyContent
                } else {
                    fullList
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(fullListAccessibilityLabel)
        }
        .onAppear { recordTelemetry() }
    }

    private var fullList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items) { item in
                HStack {
                    Text(item.label)
                        .font(TypeScale.body)
                        .foregroundStyle(theme.neutrals.text1)
                    Spacer()
                    if let value = item.value {
                        Text(value)
                            .font(TypeScale.num)
                            .foregroundStyle(theme.neutrals.text2)
                    }
                }
                if item.id != items.last?.id {
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        Text(String(localized: "no_data", defaultValue: "No data"))
            .font(TypeScale.meta)
            .foregroundStyle(theme.neutrals.text3)
    }

    private var fullListAccessibilityLabel: String {
        let itemDescriptions = items.map { item in
            if let value = item.value {
                return "\(item.label), \(value)"
            }
            return item.label
        }
        return "\(insight.title), \(itemDescriptions.joined(separator: "; "))"
    }

    private func recordTelemetry() {
        guard let size = insight.parsedCardSize, let type = insight.parsedCardType else { return }
        if items.isEmpty {
            CardTelemetry.recordRenderFailed(size: size, type: type)
        } else {
            CardTelemetry.recordRendered(size: size, type: type)
        }
    }
}

#Preview("List Wide") {
    ListWideCardView(insight: OverviewInsight(
        key: "top_exercises", cardType: "list", cardSize: "wide",
        title: "Top Exercises",
        content: "[{\"label\":\"Bench Press\",\"value\":\"3 sets\"},{\"label\":\"Squat\",\"value\":\"4 sets\"},{\"label\":\"Deadlift\",\"value\":\"3 sets\"},{\"label\":\"Overhead Press\",\"value\":\"3 sets\"}]"
    ))
    .designThemePreview()
    .padding()
}

#Preview("List Large") {
    ListLargeCardView(insight: OverviewInsight(
        key: "top_exercises", cardType: "list", cardSize: "large",
        title: "This Week's Exercises",
        content: "[{\"label\":\"Bench Press\",\"value\":\"12 sets\"},{\"label\":\"Squat\",\"value\":\"16 sets\"},{\"label\":\"Deadlift\",\"value\":\"9 sets\"},{\"label\":\"Overhead Press\",\"value\":\"8 sets\"},{\"label\":\"Barbell Row\",\"value\":\"10 sets\"}]"
    ))
    .designThemePreview()
    .padding()
}
