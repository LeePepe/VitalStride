import Foundation

public enum SnackbarMode: Sendable, Equatable {
    case persistent
    case autoDismiss(duration: TimeInterval = 3)
}
