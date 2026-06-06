import SwiftUI

public struct DataStoreErrorView: View {
    public let errorMessage: String

    public init(errorMessage: String) {
        self.errorMessage = errorMessage
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text("Unable to Load Data")
                .font(.headline)
            Text(errorMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}
