import Foundation
import Testing

@testable import VitalStride

/// Verifies plural-aware behavior for `workout_calendar_date_a11y_format`
/// (MY-1215 follow-up to MY-1214). The English catalog value must fold to a
/// singular form for count == 1 ("1 workout") and a plural form for other
/// counts ("2 workouts"). Chinese has no grammatical number, so both forms
/// share the same value.
@Suite("WorkoutCalendarDateA11yPlural")
struct WorkoutCalendarDateA11yPluralTests {
    private static let dateSample = "July 9"
    private static let zhDateSample = "7 月 9 日"

    private func localized(_ count: Int, date: String) -> String {
        String(
            format: NSLocalizedString(
                "workout_calendar_date_a11y_format",
                comment: ""
            ),
            date,
            count
        )
    }

    @Test("Count == 1 announces singular form (no '1 workouts')")
    func singularForOneWorkout() {
        let rendered = localized(1, date: Self.dateSample)
        // Whatever the runtime locale is, the rendered string MUST NOT contain
        // the ungrammatical "1 workouts" sequence; the singular English form
        // must appear when English is active.
        #expect(!rendered.contains("1 workouts"),
                "workout_calendar_date_a11y_format must not produce '1 workouts' for count == 1 (got: \(rendered))")

        // If English is the resolved language, assert the exact singular form.
        if Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true {
            #expect(rendered == "\(Self.dateSample), 1 workout")
        }
    }

    @Test("Count > 1 announces plural form")
    func pluralForMultipleWorkouts() {
        let rendered = localized(3, date: Self.dateSample)
        if Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true {
            #expect(rendered == "\(Self.dateSample), 3 workouts")
        } else {
            // Non-English locales: at minimum the count digit must appear.
            #expect(rendered.contains("3"))
        }
    }

    @Test("Count == 0 uses plural 'other' form in English")
    func zeroUsesOtherForm() {
        // English CLDR plural rule: zero maps to "other" (→ "0 workouts").
        // The no-workout path uses a separate key
        // (`workout_calendar_date_a11y_no_workout_format`); this asserts that
        // if callers ever pass 0 to the with-workout key, English still
        // reads grammatically.
        let rendered = localized(0, date: Self.dateSample)
        if Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true {
            #expect(rendered == "\(Self.dateSample), 0 workouts")
        }
    }
}
