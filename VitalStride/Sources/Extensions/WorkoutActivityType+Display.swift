import HealthKitService

extension WorkoutActivityType {
    var localizedName: String {
        switch self {
        case .cycling: String(localized: "骑行", comment: "Cycling")
        case .dance: String(localized: "舞蹈", comment: "Dance")
        case .elliptical: String(localized: "椭圆机", comment: "Elliptical")
        case .functionalStrengthTraining: String(localized: "功能性力量训练", comment: "Functional strength")
        case .hiking: String(localized: "徒步", comment: "Hiking")
        case .rowing: String(localized: "划船", comment: "Rowing")
        case .running: String(localized: "跑步", comment: "Running")
        case .swimming: String(localized: "游泳", comment: "Swimming")
        case .traditionalStrengthTraining: String(localized: "力量训练", comment: "Strength training")
        case .walking: String(localized: "步行", comment: "Walking")
        case .yoga: String(localized: "瑜伽", comment: "Yoga")
        case .highIntensityIntervalTraining: String(localized: "HIIT", comment: "HIIT")
        case .other: String(localized: "其他运动", comment: "Other workout")
        }
    }

    var systemImage: String {
        switch self {
        case .cycling: "bicycle"
        case .dance: "figure.dance"
        case .elliptical: "figure.elliptical"
        case .functionalStrengthTraining: "figure.strengthtraining.functional"
        case .hiking: "figure.hiking"
        case .rowing: "figure.rowing"
        case .running: "figure.run"
        case .swimming: "figure.pool.swim"
        case .traditionalStrengthTraining: "figure.strengthtraining.traditional"
        case .walking: "figure.walk"
        case .yoga: "figure.yoga"
        case .highIntensityIntervalTraining: "figure.highintensity.intervaltraining"
        case .other: "figure.mixed.cardio"
        }
    }
}
