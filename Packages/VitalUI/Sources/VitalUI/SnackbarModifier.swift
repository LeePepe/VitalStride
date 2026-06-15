import SwiftUI

@MainActor
final class SnackbarDismissScheduler {
    private var task: Task<Void, Never>?

    nonisolated init() {}

    func schedule(duration: TimeInterval, dismiss: @escaping @MainActor () -> Void) {
        cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.task = nil
            dismiss()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    var isScheduled: Bool { task != nil && !(task?.isCancelled ?? true) }
}

struct SnackbarModifier<SnackbarContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let edge: VerticalEdge
    let mode: SnackbarMode
    let onDismiss: (() -> Void)?
    @ViewBuilder let snackbarContent: () -> SnackbarContent

    @State private var scheduler = SnackbarDismissScheduler()
    @AccessibilityFocusState private var isSnackbarFocused: Bool

    var overlayAlignment: Alignment {
        edge == .top ? .top : .bottom
    }

    var transitionEdge: Edge {
        edge == .top ? .top : .bottom
    }

    var edgePaddingEdge: Edge.Set {
        edge == .top ? .top : .bottom
    }

    var shadowYOffset: CGFloat { 4 }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: overlayAlignment) {
                if isPresented {
                    snackbarContent()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.bar)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 8, y: shadowYOffset)
                        .padding(.horizontal, 16)
                        .padding(edgePaddingEdge, 16)
                        .transition(.move(edge: transitionEdge).combined(with: .opacity))
                        .accessibilityElement(children: .contain)
                        .accessibilityFocused($isSnackbarFocused)
                }
            }
            .animation(.spring(duration: 0.35, bounce: 0.2), value: isPresented)
            .onAppear {
                if isPresented {
                    handlePresented()
                }
            }
            .onChange(of: isPresented) { oldValue, newValue in
                if newValue {
                    handlePresented()
                } else if oldValue {
                    handleDismissed()
                }
            }
            .onChange(of: mode) { _, _ in
                if isPresented {
                    scheduleAutoDismiss()
                }
            }
    }

    private func handlePresented() {
        scheduleAutoDismiss()
        isSnackbarFocused = true
    }

    private func handleDismissed() {
        scheduler.cancel()
        isSnackbarFocused = false
        onDismiss?()
    }

    private func scheduleAutoDismiss() {
        scheduler.cancel()
        guard case .autoDismiss(let duration) = mode else { return }
        let binding = $isPresented
        scheduler.schedule(duration: duration) {
            binding.wrappedValue = false
        }
    }
}

extension View {
    public func snackbar<Content: View>(
        isPresented: Binding<Bool>,
        edge: VerticalEdge = .bottom,
        mode: SnackbarMode = .autoDismiss(),
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(
            SnackbarModifier(
                isPresented: isPresented,
                edge: edge,
                mode: mode,
                onDismiss: onDismiss,
                snackbarContent: content
            )
        )
    }
}
