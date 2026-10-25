import DesignKit
import SwiftUI

/// Replaces the digits without increasing keyboard height.
struct CompactWeightPanel: View {
    @Environment(\.theme) private var theme
    let session: CompactSession

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 4) {
            HStack {
                Text(studioText("weight.entry")).font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Button { session.accessory = .digits } label: {
                    Label(studioText("compact.backDigits"), systemImage: "keyboard")
                        .font(.caption).frame(minHeight: 44)
                }.buttonStyle(.plain)
            }
            HStack(spacing: 6) {
                mode("weight.total", selected: !session.core.editorIsSplit) { session.core.setEditorSplit(false) }
                    .disabled(!session.core.editorCanUseTotal)
                mode("weight.split", selected: session.core.editorIsSplit) { session.core.setEditorSplit(true) }
                    .disabled(!session.core.editorCanCommit)
            }
            HStack(spacing: 6) {
                if session.core.editorIsSplit {
                    action("weight.match", symbol: "arrow.right") { session.core.matchEditorSides() }
                        .disabled(!session.core.editorCanCommit)
                    action("weight.swap", symbol: "arrow.left.arrow.right") { session.core.swapEditorSides() }
                        .disabled(!session.core.editorCanCommit)
                } else if session.supportsEquipmentDefault {
                    Button { session.applyEquipmentDefault() } label: {
                        Text(studioText("weight.useDefault") + (session.equipmentDefault.map { " · " + $0.formatted(.number.precision(.fractionLength(0...2))) + " kg" } ?? ""))
                            .font(.caption).frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.plain).disabled(session.equipmentDefault == nil)
                    action("weight.setDefault", symbol: "slider.horizontal.3") { session.beginEquipmentDefault() }
                } else {
                    Text(studioText("weight.modeHint")).font(.system(size: 12)).foregroundStyle(theme.neutrals.text2)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
            Text(studioText(session.core.editorCanUseTotal ? (session.core.editorIsSplit ? "weight.splitHint" : "weight.totalHint") : "weight.totalRange"))
                .font(.system(size: 11)).foregroundStyle(theme.neutrals.text2)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        }.padding(.horizontal, 8).frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func mode(_ key: String, selected: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 4) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").accessibilityHidden(true)
                Text(studioText(key)).font(.subheadline.weight(.semibold))
                Text("kg").font(.caption)
            }.frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? theme.primary.primarySubtle : theme.neutrals.inner, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: Radius.inner, style: .continuous).strokeBorder(selected ? theme.primary.primaryText : .clear, lineWidth: 1) }
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func action(_ key: String, symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(studioText(key), systemImage: symbol).font(.caption)
                .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

#Preview("Weight modes light") {
    let session = CompactSession()
    CompactWeightPanel(session: session)
        .environment(\.theme, Theme(seed: .blue, neutral: .slate, isDark: false)).frame(width: 377, height: 188)
}

#Preview("Weight modes dark") {
    let session = CompactSession()
    CompactWeightPanel(session: session)
        .environment(\.theme, Theme(seed: .blue, neutral: .slate, isDark: true)).frame(width: 359, height: 188)
}
