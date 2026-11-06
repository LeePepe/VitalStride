import Foundation

public protocol RemoteFlightProviding: Sendable {
    func remoteValue(for key: String) -> Bool?
}

public struct DefaultRemoteFlightProvider: RemoteFlightProviding, Sendable {
    public let isRemoteEnabled: Bool

    public init(isRemoteEnabled: Bool = false) {
        self.isRemoteEnabled = isRemoteEnabled
    }

    public func remoteValue(for key: String) -> Bool? {
        false
    }
}
