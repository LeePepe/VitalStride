import DesignKit
import SwiftUI

/// Shared chrome for every Overview adaptive-grid card (LLM-driven variants all
/// wrap this). Re-skinned to DesignKit `Card` so the whole grid inherits the
/// app's luminance-tier elevation + hairline + theme tokens in one place.
struct OverviewCardContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Card {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
