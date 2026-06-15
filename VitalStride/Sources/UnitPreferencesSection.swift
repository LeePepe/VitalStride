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

    var a11yName: String {
        switch self {
        case .kg: String(localized: "公斤", comment: "Kilogram a11y name")
        case .lb: String(localized: "磅", comment: "Pound a11y name")
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

    var abbreviation: String {
        switch self {
        case .km: return "km"
        case .mi: return "mi"
        }
    }

    var accessibilityName: String {
        switch self {
        case .km: return String(localized: "公里", comment: "Kilometer a11y name")
        case .mi: return String(localized: "英里", comment: "Mile a11y name")
        }
    }

    static let metersPerMile = 1609.344
    static let kmPerMile = 1.609344

    func convert(fromMeters value: Double) -> Double {
        switch self {
        case .km: return value / 1000.0
        case .mi: return value / Self.metersPerMile
        }
    }

    func convert(fromKilometers value: Double) -> Double {
        switch self {
        case .km: return value
        case .mi: return value / Self.kmPerMile
        }
    }
}

enum EnergyUnit: String, CaseIterable {
    case kcal
    case kJ

    var displayName: String {
        switch self {
        case .kcal: return "千卡 (kcal)"
        case .kJ: return "千焦 (kJ)"
        }
    }

    var abbreviation: String {
        switch self {
        case .kcal: return "kcal"
        case .kJ: return "kJ"
        }
    }

    var accessibilityName: String {
        switch self {
        case .kcal: return String(localized: "千卡", comment: "Kilocalorie a11y name")
        case .kJ: return String(localized: "千焦", comment: "Kilojoule a11y name")
        }
    }

    static let kcalToKJFactor = 4.184

    func convert(fromKcal value: Double) -> Double {
        switch self {
        case .kcal: return value
        case .kJ: return value * Self.kcalToKJFactor
        }
    }
}

struct UnitPreferencesSection: View {
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .kg
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .km
    @AppStorage("energyUnit") private var energyUnit: EnergyUnit = .kcal

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

            Picker(selection: $energyUnit) {
                ForEach(EnergyUnit.allCases, id: \.self) { unit in
                    Text(unit.displayName).tag(unit)
                }
            } label: {
                Label("能量", systemImage: "flame")
            }
        }
    }
}

#Preview {
    Form {
        UnitPreferencesSection()
    }
}
