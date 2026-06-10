import Foundation

struct OverviewContext: Sendable {
    let todaySteps: Int?
    let todayActiveEnergy: Double?
    let restingHeartRate: Int?
    let lastNightSleepHours: Double?
    let latestWeight: Double?
    let recentWorkoutCount: Int
    let recentMuscleGroups: [String: Int]
    let userLocale: String

    init(
        todaySteps: Int? = nil,
        todayActiveEnergy: Double? = nil,
        restingHeartRate: Int? = nil,
        lastNightSleepHours: Double? = nil,
        latestWeight: Double? = nil,
        recentWorkoutCount: Int = 0,
        recentMuscleGroups: [String: Int] = [:],
        userLocale: String = ""
    ) {
        self.todaySteps = todaySteps
        self.todayActiveEnergy = todayActiveEnergy
        self.restingHeartRate = restingHeartRate
        self.lastNightSleepHours = lastNightSleepHours
        self.latestWeight = latestWeight
        self.recentWorkoutCount = recentWorkoutCount
        self.recentMuscleGroups = recentMuscleGroups
        self.userLocale = userLocale
    }
}

struct TrainingContext: Sendable {
    let recentWorkouts: [WorkoutSummary]
    let muscleGroupFrequency: [String: Int]
    let daysSinceLastWorkout: Int?

    struct WorkoutSummary: Sendable {
        let date: Date
        let durationMinutes: Int
        let exerciseNames: [String]
        let muscleGroups: [String]
        let totalVolume: Double
    }

    init(
        recentWorkouts: [WorkoutSummary] = [],
        muscleGroupFrequency: [String: Int] = [:],
        daysSinceLastWorkout: Int? = nil
    ) {
        self.recentWorkouts = recentWorkouts
        self.muscleGroupFrequency = muscleGroupFrequency
        self.daysSinceLastWorkout = daysSinceLastWorkout
    }
}

struct DataContext: Sendable {
    let sampleType: String
    let dataPointCount: Int
    let timeRangeDescription: String
    let statistics: DataStatistics

    struct DataStatistics: Sendable {
        let average: Double?
        let minimum: Double?
        let maximum: Double?
        let latestValue: Double?
        let unit: String

        init(
            average: Double? = nil,
            minimum: Double? = nil,
            maximum: Double? = nil,
            latestValue: Double? = nil,
            unit: String = ""
        ) {
            self.average = average
            self.minimum = minimum
            self.maximum = maximum
            self.latestValue = latestValue
            self.unit = unit
        }
    }

    init(
        sampleType: String,
        dataPointCount: Int = 0,
        timeRangeDescription: String = "",
        statistics: DataStatistics = DataStatistics()
    ) {
        self.sampleType = sampleType
        self.dataPointCount = dataPointCount
        self.timeRangeDescription = timeRangeDescription
        self.statistics = statistics
    }
}
