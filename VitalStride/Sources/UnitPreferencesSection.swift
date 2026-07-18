// swiftlint:disable no_hardcoded_chinese
// Rationale: All CJK literals in this file are wrapped in String(localized:) for i18n;
// the regex-based rule can't distinguish that from a raw literal (MY-1269).
import DesignKit
import SwiftUI

enum WeightUnit: String, CaseIterable {
    case kg
    case lb

    var displayName: String {
        switch self {
        case .kg: return String(localized: "公斤 (kg)", comment: "")
        case .lb: return String(localized: "磅 (lb)", comment: "")
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
        case .km: return String(localized: "公里 (km)", comment: "")
        case .mi: return String(localized: "英里 (mi)", comment: "")
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
        case .kcal: return String(localized: "千卡 (kcal)", comment: "")
        case .kJ: return String(localized: "千焦 (kJ)", comment: "")
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
    @Environment(\.theme) private var theme
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .kg
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .km
    @AppStorage("energyUnit") private var energyUnit: EnergyUnit = .kcal

    var body: some View {
        Section(String(localized: "单位偏好", comment: "")) {
            Picker(selection: $weightUnit) {
                ForEach(WeightUnit.allCases, id: \.self) { unit in
                    Text(unit.displayName).tag(unit)
                }
            } label: {
                Label(String(localized: "重量", comment: ""), systemImage: "scalemass")
                    .tint(theme.primary.primary)
            }

            Picker(selection: $distanceUnit) {
                ForEach(DistanceUnit.allCases, id: \.self) { unit in
                    Text(unit.displayName).tag(unit)
                }
            } label: {
                Label(String(localized: "距离", comment: ""), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .tint(theme.primary.primary)
            }

            Picker(selection: $energyUnit) {
                ForEach(EnergyUnit.allCases, id: \.self) { unit in
                    Text(unit.displayName).tag(unit)
                }
            } label: {
                Label(String(localized: "能量", comment: ""), systemImage: "flame")
                    .tint(theme.primary.primary)
            }
        }
    }
}

#Preview {
    Form {
        UnitPreferencesSection()
    }
    .designThemePreview()
}
