# VitalStride Context

## Product Identity

VitalStride is a **health data collection + AI analysis** app. Strength training is one data source among many — the app's value is aggregating body data and providing AI-powered insights, not being a workout-only tool.

## Glossary

- **Health Data (健康数据)**: Any data readable from HealthKit — heart rate, steps, sleep, body mass, active energy, etc. This is the primary content of the Data Tab.
- **Workout Data (训练数据)**: Detailed exercise/set/rep data from in-app strength training sessions. Stored in SwiftData because HealthKit cannot represent per-set detail. Displayed in the Workout Tab.
- **Data Tab (数据 Tab)**: Tab 3 — a health data dashboard showing a summary card + grouped list of data types. NOT a training-specific view.

## Data Architecture Decisions

### HealthKit data is NOT cached in SwiftData

HealthKit is queried directly at read time. No `HealthSample` or `HealthKitAnchor` models. Rationale: HealthKit is already a local database with its own iCloud sync; duplicating it into SwiftData creates consistency risks and bloats CloudKit sync.

SwiftData stores only data that HealthKit cannot represent: `Workout`, `WorkoutExercise`, `ExerciseSet`, `Exercise`, `WorkoutTemplate`, `TemplateExercise`.

### macOS uses HealthKit for reading

macOS 13+ supports HealthKit (read-only, via iCloud Health sync). VitalStride's minimum is macOS 15.0, so the Data Tab uses the same HealthKit queries on both iOS and macOS. No platform-specific guards needed for data access.

### Single HealthKitService for all data types

One `HealthKitService` in `Shared/Services/` handles all HealthKit queries. Adding a new data type = registering a new type identifier, not creating a new file. Sleep (`HKCategoryType`) has special handling internally but the same external API.

## Data Tab Structure

### Summary Card (top)

2×2 grid of today's body metrics (complements Overview Tab's training summary):
- Steps (today)
- Resting heart rate (latest)
- Sleep (last night duration)
- Body weight (most recent)

### Grouped List

| Group | V1 Data Types |
|-------|---------------|
| 活动 (Activity) | 步数 (.stepCount), 活动能量 (.activeEnergyBurned) |
| 心脏 (Heart) | 心率 (.heartRate) |
| 身体测量 (Body) | 体重 (.bodyMass) |
| 睡眠 (Sleep) | 睡眠分析 (.sleepAnalysis) |

Tapping a row → Detail page.

### Detail Page (per data type)

- Time range Picker (day / week / month / year)
- Swift Charts graph with `chartXSelection` interaction
- Statistics summary (avg / max / min)
- No raw data point list in V1

## V1 Scope Boundaries

- 5 HealthKit data types (see table above)
- No background sync (Observer Query / BGHealthQuery deferred to V2)
- No data point list in detail pages
- Extensible: new types added via HealthKitService registration

## Project Structure: SPM Local Packages

The project uses XcodeGen + local SPM packages. Business logic lives in packages; app targets only contain platform-specific entry points and UI.

### Packages

| Package | Contents | Dependencies |
|---------|----------|-------------|
| VitalModels | SwiftData models (Workout, Exercise, etc.), enums, ModelContainerConfiguration | None |
| HealthKitService | HealthKitService, HealthDataPoint, HealthKitAnchorStore, HealthSampleType | VitalModels |
| AIService | AIProvider protocol, ZhipuProvider (智谱 GLM), ChatMessage/ChatResponse models | None |
| VitalUI | Shared UI components (DataStoreErrorView) | VitalModels |

### Rules

- App targets (iOS/macOS/watchOS) depend on packages, not on each other
- DataView + DataSections remain in app target (shared via project.yml), not in a package
- XcodeGen is retained for managing app targets, entitlements, and package references
- Adding a new AI provider = implementing `AIProvider` protocol in AIService package

## AI Architecture

### Provider

智谱 AI (GLM-4-Flash, free tier). OpenAI-compatible REST API via URLSession. No third-party SDK.

- Endpoint: `https://open.bigmodel.cn/api/paas/v4/chat/completions`
- Auth: `Authorization: Bearer <api-key>`
- Key stored in Keychain, not hardcoded

### AIService Package Interface

```swift
public protocol AIProvider: Sendable {
    func chat(messages: [ChatMessage], model: String?) async throws -> ChatResponse
    func chatStream(messages: [ChatMessage], model: String?) -> AsyncThrowingStream<ChatStreamChunk, Error>
}
```

Swappable: ZhipuProvider now, DeepSeek/OpenAI/通义 later — same protocol.
