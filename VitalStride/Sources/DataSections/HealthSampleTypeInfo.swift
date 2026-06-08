import HealthKitService
import SwiftUI

enum HealthDataAggregationMode: Sendable {
    case cumulative
    case discrete
}

extension HealthSampleType {

    var localizedName: String {
        switch self {
        case .stepCount:
            String(localized: "步数", comment: "Steps")
        case .activeEnergyBurned:
            String(localized: "活动能量", comment: "Active energy burned")
        case .basalEnergyBurned:
            String(localized: "基础代谢能量", comment: "Basal energy burned")
        case .distanceWalkingRunning:
            String(localized: "步行+跑步距离", comment: "Walking + running distance")
        case .distanceCycling:
            String(localized: "骑行距离", comment: "Cycling distance")
        case .appleExerciseTime:
            String(localized: "锻炼时间", comment: "Exercise time")
        case .appleStandTime:
            String(localized: "站立时间", comment: "Stand time")
        case .flightsClimbed:
            String(localized: "已爬楼层", comment: "Flights climbed")
        case .heartRate:
            String(localized: "心率", comment: "Heart rate")
        case .restingHeartRate:
            String(localized: "静息心率", comment: "Resting heart rate")
        case .heartRateVariabilitySDNN:
            String(localized: "心率变异性", comment: "Heart rate variability")
        case .vo2Max:
            String(localized: "最大摄氧量", comment: "VO2 Max")
        case .bodyMass:
            String(localized: "体重", comment: "Body weight")
        case .bodyFatPercentage:
            String(localized: "体脂率", comment: "Body fat percentage")
        case .leanBodyMass:
            String(localized: "去脂体重", comment: "Lean body mass")
        case .height:
            String(localized: "身高", comment: "Height")
        case .bodyMassIndex:
            String(localized: "BMI", comment: "Body mass index")
        case .sleepAnalysis:
            String(localized: "睡眠", comment: "Sleep analysis")
        case .dietaryEnergyConsumed:
            String(localized: "膳食能量摄入", comment: "Dietary energy consumed")
        case .dietaryProtein:
            String(localized: "蛋白质", comment: "Dietary protein")
        case .dietaryCarbohydrates:
            String(localized: "碳水化合物", comment: "Dietary carbohydrates")
        case .dietaryFatTotal:
            String(localized: "脂肪", comment: "Dietary fat total")
        case .dietaryWater:
            String(localized: "饮水量", comment: "Dietary water")
        }
    }

    var systemImage: String {
        switch self {
        case .stepCount: "figure.walk"
        case .activeEnergyBurned: "flame.fill"
        case .basalEnergyBurned: "flame"
        case .distanceWalkingRunning: "figure.walk.motion"
        case .distanceCycling: "bicycle"
        case .appleExerciseTime: "figure.run"
        case .appleStandTime: "figure.stand"
        case .flightsClimbed: "figure.stairs"
        case .heartRate: "heart.fill"
        case .restingHeartRate: "heart"
        case .heartRateVariabilitySDNN: "waveform.path.ecg"
        case .vo2Max: "lungs.fill"
        case .bodyMass: "scalemass.fill"
        case .bodyFatPercentage: "percent"
        case .leanBodyMass: "scalemass"
        case .height: "ruler"
        case .bodyMassIndex: "number"
        case .sleepAnalysis: "bed.double.fill"
        case .dietaryEnergyConsumed: "fork.knife"
        case .dietaryProtein: "fish.fill"
        case .dietaryCarbohydrates: "leaf.fill"
        case .dietaryFatTotal: "drop.fill"
        case .dietaryWater: "drop.dewy.fill"
        }
    }

    var unitLabel: String {
        switch self {
        case .stepCount: String(localized: "步", comment: "Steps unit")
        case .activeEnergyBurned, .basalEnergyBurned, .dietaryEnergyConsumed:
            String(localized: "kcal", comment: "Kilocalories unit")
        case .distanceWalkingRunning, .distanceCycling:
            String(localized: "km", comment: "Kilometers unit")
        case .appleExerciseTime, .appleStandTime:
            String(localized: "分钟", comment: "Minutes unit")
        case .flightsClimbed:
            String(localized: "层", comment: "Flights unit")
        case .heartRate, .restingHeartRate:
            String(localized: "BPM", comment: "Beats per minute")
        case .heartRateVariabilitySDNN:
            String(localized: "ms", comment: "Milliseconds")
        case .vo2Max:
            String(localized: "mL/kg/min", comment: "VO2 Max unit")
        case .bodyMass, .leanBodyMass:
            String(localized: "kg", comment: "Kilograms unit")
        case .bodyFatPercentage:
            "%"
        case .height:
            String(localized: "cm", comment: "Centimeters unit")
        case .bodyMassIndex:
            ""
        case .sleepAnalysis:
            String(localized: "小时", comment: "Hours unit")
        case .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal:
            String(localized: "g", comment: "Grams unit")
        case .dietaryWater:
            String(localized: "mL", comment: "Milliliters unit")
        }
    }

    var chartColor: Color {
        switch self {
        case .stepCount: .blue
        case .activeEnergyBurned, .basalEnergyBurned: .orange
        case .distanceWalkingRunning, .distanceCycling: .cyan
        case .appleExerciseTime: .green
        case .appleStandTime: .mint
        case .flightsClimbed: .teal
        case .heartRate, .restingHeartRate: .red
        case .heartRateVariabilitySDNN: .pink
        case .vo2Max: .purple
        case .bodyMass, .leanBodyMass: .green
        case .bodyFatPercentage: .yellow
        case .height: .indigo
        case .bodyMassIndex: .brown
        case .sleepAnalysis: .indigo
        case .dietaryEnergyConsumed: .orange
        case .dietaryProtein: .red
        case .dietaryCarbohydrates: .green
        case .dietaryFatTotal: .yellow
        case .dietaryWater: .blue
        }
    }

    var aggregationMode: HealthDataAggregationMode {
        switch self {
        case .stepCount, .activeEnergyBurned, .basalEnergyBurned,
             .distanceWalkingRunning, .distanceCycling,
             .appleExerciseTime, .appleStandTime, .flightsClimbed,
             .dietaryEnergyConsumed, .dietaryProtein,
             .dietaryCarbohydrates, .dietaryFatTotal, .dietaryWater:
            .cumulative
        case .heartRate, .restingHeartRate, .heartRateVariabilitySDNN,
             .vo2Max, .bodyMass, .bodyFatPercentage, .leanBodyMass,
             .height, .bodyMassIndex, .sleepAnalysis:
            .discrete
        }
    }

    var fractionDigits: Int {
        switch self {
        case .stepCount, .flightsClimbed, .appleExerciseTime, .appleStandTime:
            0
        case .distanceWalkingRunning, .distanceCycling, .bodyMass, .leanBodyMass,
             .bodyFatPercentage, .bodyMassIndex, .height, .vo2Max:
            1
        case .heartRate, .restingHeartRate, .heartRateVariabilitySDNN:
            0
        case .activeEnergyBurned, .basalEnergyBurned, .dietaryEnergyConsumed:
            0
        case .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal:
            1
        case .dietaryWater:
            0
        case .sleepAnalysis:
            1
        }
    }
}
