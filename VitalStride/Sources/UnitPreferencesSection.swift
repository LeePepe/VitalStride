import SwiftUI

enum WeightUnit: String, CaseIterable {
    case kg
    case lb

    var displayName: String {
        switch self {
        case .kg: return "公斤 (kg)"
        case .lb: return "磅 (lb)"
        }
    }
}

enum DistanceUnit: String, CaseIterable {
    case km
    case mi

    var displayName: String {
        switch self {
        case .km: return "公里 (km)"
        case .mi: return "英里 (mi)"
        }
    }
}

struct UnitPreferencesSection: View {
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .kg
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .km

    var body: some View {
        Section("单位偏好") {
            Picker(selection: $weightUnit) {
                ForEach(WeightUnit.allCases, id: \.self) { unit in
                    Text(unit.displayName).tag(unit)
                }
            } label: {
                Label("重量", systemImage: "scalemass")
            }

            Picker(selection: $distanceUnit) {
                ForEach(DistanceUnit.allCases, id: \.self) { unit in
                    Text(unit.displayName).tag(unit)
                }
            } label: {
                Label("距离", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
        }
    }
}

#Preview {
    Form {
        UnitPreferencesSection()
    }
}
