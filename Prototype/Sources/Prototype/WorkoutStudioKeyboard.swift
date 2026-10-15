import DesignKit
import SwiftUI

/// Fixture-only keyboard exploration; no UIKit inputView or production model access.
struct StudioNumericEditor: View {
    @Environment(\.theme) private var theme
    let session: StudioSession
    let style: StudioStyle
    let layout: StudioKeyboardLayout
    @State private var showTools = false

    private var radius: CGFloat { style == .graphite ? 8 : (style == .ember ? 18 : 12) }
    private var keyHeight: CGFloat { layout == .sequence ? 44 : 48 }
    private var delta: Double { session.editorField == "weight" ? 2.5 : 1 }

    var body: some View {
        VStack(spacing: 8) {
            fieldBar
            if let error = session.editorError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(session.notice ?? studioText(session.editorSelectAll ? "keyboard.replaceHint" : "keyboard.editHint"))
                    .font(.system(size: 12)).foregroundStyle(theme.neutrals.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if layout == .sequence { presets }
            if layout == .thumb {
                HStack(alignment: .top, spacing: 8) {
                    if !session.keyboardLeftHanded { utilityRail }
                    digitGrid
                    if session.keyboardLeftHanded { utilityRail }
                }
            } else { digitGrid }
            footer
        }
        .padding(10)
        .background(style == .ember ? theme.neutrals.inner : theme.neutrals.card,
                    in: RoundedRectangle(cornerRadius: style.radius))
        .overlay(RoundedRectangle(cornerRadius: style.radius).strokeBorder(theme.neutrals.border, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(studioText("keyboard.title"))
        .sheet(isPresented: $showTools) { toolsSheet }
    }

    private var fieldBar: some View {
        HStack(spacing: 8) {
            fieldButton("weight", value: session.editorWeightText, unit: "kg")
            fieldButton("reps", value: session.editorRepsText, unit: studioText("set.reps"))
            StudioIconButton(symbol: "keyboard.chevron.compact.down", label: studioText("keyboard.saveClose")) {
                session.commitEditor()
            }.disabled(!session.editorCanCommit)
        }
    }

    private func fieldButton(_ field: String, value: String, unit: String) -> some View {
        let selected = session.editorField == field
        return Button {
            if selected { session.editorSelectAll = true }
            else { session.switchEditor(to: field) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(studioText("set.\(field)")).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Text(value).font(.system(size: 21, weight: .semibold, design: .rounded)).monospacedDigit()
                    .padding(.horizontal, 2)
                    .background(selected && session.editorSelectAll ? theme.primary.primaryBorder.opacity(0.35) : .clear,
                                in: RoundedRectangle(cornerRadius: 3))
                if field == "weight" { Text(unit).font(.system(size: 12)) }
            }
            .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(selected ? theme.primary.primaryText : theme.neutrals.text2)
            .background(selected ? theme.primary.primarySubtle : theme.neutrals.inner,
                        in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(selected ? theme.primary.primaryBorder : .clear, lineWidth: 1))
        }.buttonStyle(.plain)
            .accessibilityLabel(studioText("editor.\(field)"))
            .accessibilityValue(value + " " + unit)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var digitGrid: some View {
        VStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { column in
                        let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "delete"]
                        let key = keys[row * 3 + column]
                        digitKey(key)
                    }
                }
            }
        }.frame(maxWidth: .infinity)
    }

    private func digitKey(_ key: String) -> some View {
        let disabled = key == "." && session.editorField == "reps"
        return Button { session.pressEditorKey(key) } label: {
            Group {
                if key == "delete" { Image(systemName: "delete.left").font(.title3) }
                else { Text(key).font(.system(size: 24, weight: style == .graphite ? .medium : .regular, design: .rounded)).monospacedDigit() }
            }
            .frame(maxWidth: .infinity, minHeight: keyHeight)
            .foregroundStyle(disabled ? theme.neutrals.text3 : theme.neutrals.text1)
            .background(style == .ember ? theme.neutrals.card : theme.neutrals.inner,
                        in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(style == .graphite ? theme.neutrals.border : .clear, lineWidth: 0.5))
            .opacity(disabled ? 0.35 : 1)
            .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(disabled)
            .accessibilityLabel(key == "delete" ? studioText("action.deleteDigit") : (key == "." ? studioText("keyboard.decimal") : key))
            .accessibilityAddTraits(.isKeyboardKey)
    }

    private var utilityRail: some View {
        VStack(spacing: 6) {
            utilityKey("−" + delta.formatted(), label: studioText("keyboard.decrease")) { session.adjustEditor(-delta) }
            utilityKey("+" + delta.formatted(), label: studioText("keyboard.increase")) { session.adjustEditor(delta) }
            utilityKey(studioText("keyboard.previousShort"), label: studioText("keyboard.previous")) { session.usePreviousEditorValues() }
            utilityKey(studioText("keyboard.copyShort"), label: studioText("keyboard.copy"), size: 12) { session.copyEditorToNext() }
                .disabled(!session.editorCanCommit)
        }.frame(width: 64)
    }

    private func utilityKey(_ text: String, label: String, size: CGFloat = 14, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.system(size: size, weight: .semibold)).monospacedDigit().multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: keyHeight)
                .foregroundStyle(theme.primary.primaryText)
                .background(theme.primary.primarySubtle, in: RoundedRectangle(cornerRadius: radius))
        }.buttonStyle(.plain).accessibilityLabel(label)
    }

    private var presets: some View {
        HStack(spacing: 8) {
            ForEach([8, 10, 12], id: \.self) { reps in
                Button { session.presetEditorReps(reps) } label: {
                    Text("\(reps) " + studioText("keyboard.repsUnit")).font(.system(size: 14, weight: .medium)).monospacedDigit()
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(theme.primary.primaryText)
                        .background(theme.primary.primarySubtle, in: RoundedRectangle(cornerRadius: radius))
                }.buttonStyle(.plain).accessibilityLabel(studioText("keyboard.preset") + " \(reps)")
            }
            utilityKey(studioText("keyboard.copyShort"), label: studioText("keyboard.copy"), size: 12) { session.copyEditorToNext() }
                .frame(width: 64)
                .disabled(!session.editorCanCommit)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button { showTools = true } label: {
                VStack(spacing: 2) {
                    Image(systemName: "ellipsis").font(.system(size: 16))
                    Text(studioText("keyboard.toolsShort")).font(.system(size: 12))
                }.frame(width: 48, height: 52).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(studioText("keyboard.tools"))
            if layout == .thumb {
                StudioIconButton(symbol: "arrow.left.arrow.right", label: studioText(session.keyboardLeftHanded ? "keyboard.useRight" : "keyboard.useLeft")) {
                    session.keyboardLeftHanded.toggle()
                }
            }
            StudioAction(title: studioText(layout == .sequence ? "keyboard.saveComplete" : (session.editorField == "weight" ? "keyboard.nextReps" : "keyboard.save")),
                         symbol: layout == .sequence || session.editorField == "reps" ? "checkmark" : "arrow.right",
                         style: style, disabled: !session.editorCanCommit) {
                if layout == .sequence { session.commitEditor(completeSet: true) }
                else if session.editorField == "weight" { session.switchEditor(to: "reps") }
                else { session.commitEditor() }
            }
        }
    }

    private var toolsSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(studioText("keyboard.tools")).font(.title2.bold())
                Spacer()
                StudioIconButton(symbol: "xmark", label: studioText("action.dismiss")) { showTools = false }
            }
            Button(studioText("keyboard.cancel"), role: .destructive) { session.cancelEditor(); showTools = false }.frame(minHeight: 44)
            Divider()
            Button(studioText("keyboard.previous")) { session.usePreviousEditorValues(); showTools = false }.frame(minHeight: 44)
            Button(studioText("keyboard.copy")) { session.copyEditorToNext(); showTools = false }
                .frame(minHeight: 44).disabled(!session.editorCanCommit)
            Divider()
            Text(studioText("keyboard.advancedNote")).font(.body).foregroundStyle(theme.neutrals.text2)
        }.buttonStyle(.plain).padding(24).frame(minWidth: 330, minHeight: 360)
            .foregroundStyle(theme.neutrals.text1).background(theme.neutrals.bg)
    }
}

#Preview("Tide full-width keyboard") {
    StudioNumericEditor(session: StudioSession(screen: .workout, scenario: .keyboard), style: .tide, layout: .grid)
        .environment(\.theme, StudioStyle.tide.theme(dark: false)).frame(width: 353)
}

#Preview("Graphite thumb keyboard dark") {
    StudioNumericEditor(session: StudioSession(screen: .workout, scenario: .keyboard), style: .graphite, layout: .thumb)
        .environment(\.theme, StudioStyle.graphite.theme(dark: true)).environment(\.colorScheme, .dark).frame(width: 353)
}
