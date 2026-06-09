import SwiftUI

@MainActor
final class SnackbarDismissScheduler {
    private var task: Task<Void, Never>?

    func schedule(duration: TimeInterval, dismiss: @escaping @MainActor () -> Void) {
        cancel()
        task = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    var isScheduled: Bool { task != nil && !(task?.isCancelled ?? true) }
}

private struct SnackbarModifier<SnackbarContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let mode: SnackbarMode
    let onDismiss: (() -> Void)?
    @ViewBuilder let snackbarContent: () -> SnackbarContent

    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isPresented {
                    snackbarContent()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.bar)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .accessibilityElement(children: .contain)
                }
            }
            .animation(.spring(duration: 0.35, bounce: 0.2), value: isPresented)
            .onChange(of: isPresented) { oldValue, newValue in
                if !oldValue, newValue {
                    AccessibilityNotification.LayoutChanged(nil).post()
                    scheduleDismissIfNeeded()
                } else if oldValue, !newValue {
                    dismissTask?.cancel()
                    dismissTask = nil
                    if case .autoDismiss = mode {
                        AccessibilityNotification.LayoutChanged(nil).post()
                    }
                    onDismiss?()
                }
            }
    }

    private func scheduleDismissIfNeeded() {
        dismissTask?.cancel()
        guard case .autoDismiss(let duration) = mode else { return }
        let binding = $isPresented
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            binding.wrappedValue = false
        }
    }
}

extension View {
    public func snackbar<Content: View>(
        isPresented: Binding<Bool>,
        mode: SnackbarMode = .autoDismiss(),
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(
            SnackbarModifier(
                isPresented: isPresented,
                mode: mode,
                onDismiss: onDismiss,
                snackbarContent: content
            )
        )
    }
}
