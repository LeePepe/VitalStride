import SwiftUI

public struct FlightDebugView: View {
    private let store: FlightStore
    private let descriptors: [FlightDescriptor]
    @State private var searchText = ""

    public init(store: FlightStore, descriptors: [FlightDescriptor]) {
        self.store = store
        self.descriptors = descriptors
    }

    private var filteredDescriptors: [FlightDescriptor] {
        FlightDescriptor.filtered(descriptors, query: searchText)
    }

    private var groupedDescriptors: [(String, [FlightDescriptor])] {
        FlightDescriptor.grouped(filteredDescriptors)
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }

    public var body: some View {
        List {
            if groupedDescriptors.isEmpty {
                ContentUnavailableView(
                    String(localized: "No flight flags", comment: "Empty FlightKit debug state title"),
                    systemImage: "flag.slash",
                    description: Text(String(localized: "No descriptors are registered.", comment: "Empty FlightKit debug state message"))
                )
            } else {
                ForEach(groupedDescriptors, id: \.0) { category, flags in
                    Section(category) {
                        ForEach(flags) { descriptor in
                            FlightDebugRow(store: store, descriptor: descriptor)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: String(localized: "Search flags", comment: "FlightKit debug search prompt"))
        .navigationTitle(String(localized: "Flight flags", comment: "FlightKit debug screen title"))
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(String(localized: "Reset all", comment: "Reset all FlightKit overrides")) {
                    store.resetAll()
                }
            }
        }
    }
}

private struct FlightDebugRow: View {
    @Bindable private var store: FlightStore
    private let descriptor: FlightDescriptor

    init(store: FlightStore, descriptor: FlightDescriptor) {
        self._store = Bindable(store)
        self.descriptor = descriptor
    }

    var body: some View {
        let readout = store.readout(for: descriptor)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(descriptor.title)
                    .font(.headline)
                Spacer()
                Text(readout.value ? String(localized: "ON", comment: "Effective flight flag on state") : String(localized: "OFF", comment: "Effective flight flag off state"))
                    .font(.caption.weight(.semibold))
                    .monospaced()
                    .accessibilityLabel(String(localized: "Effective state", comment: "Flight flag effective state label"))
            }
            Text(descriptor.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(descriptor.key) · \(sourceLabel(readout.source)) · \(remoteLabel(readout.remoteValue)) · \(defaultLabel(readout.defaultValue))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Picker(
                String(localized: "Override", comment: "Flight flag override picker label"),
                selection: Binding(
                    get: { store.override(for: descriptor.key) },
                    set: { store.setOverride($0, for: descriptor.key) }
                )
            ) {
                ForEach(FlightOverrideState.allCases, id: \.self) { state in
                    Text(state.displayName).tag(state)
                }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func sourceLabel(_ source: FlightReadout.Source) -> String {
        switch source {
        case .localOverride: String(localized: "Local", comment: "Flight flag local override source")
        case .remote: String(localized: "Remote", comment: "Flight flag remote source")
        case .default: String(localized: "Default", comment: "Flight flag default source")
        }
    }

    private func remoteLabel(_ value: Bool?) -> String {
        let value = value.map { $0 ? "ON" : "OFF" } ?? "—"
        return String(localized: "Remote \(value)", comment: "Flight flag remote readout")
    }

    private func defaultLabel(_ value: Bool) -> String {
        String(localized: "Default \(value ? "ON" : "OFF")", comment: "Flight flag default readout")
    }
}
