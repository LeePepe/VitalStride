import DesignKit
import SwiftData
import SwiftUI
import Testing
import VitalModels
#if canImport(UIKit)
import UIKit
#endif
@testable import VitalStride

@Suite("ExercisePicker single-row search dock", .serialized)
struct ExercisePickerSearchLayoutTests {
    #if canImport(UIKit)
    @Test("Production search, create and done controls stay in one row at phone widths")
    @MainActor
    func dockStaysInOneRow() {
        for width: CGFloat in [296, 369, 406, 720] {
            for query in ["", "bench", "no results"] {
                let host = UIHostingController(rootView: PickerBottomBar(
                    searchText: .constant(query), selectedCount: 3, isMultiSelect: true,
                    onCreate: {}, onConfirm: {}
                ).designTheme())
                let size = host.sizeThatFits(in: CGSize(width: width, height: .infinity))
                #expect(size.width <= width + 1)
                #expect(size.height >= 44)
                #expect(size.height <= 64, "Dock must remain a single control row at \(width)pt")
            }
        }
    }

    @Test("Rendered picker evidence: light, dark, filtered empty and accessibility size")
    @MainActor
    func renderPickerEvidence() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        for (name, group, equipment) in [
            ("Bench Press", MuscleGroup.chest, Equipment.barbell),
            ("Incline Press", .chest, .barbell),
            ("Goblet Squat", .legs, .dumbbell),
            ("Dumbbell Row", .back, .dumbbell),
            ("Cable Fly", .chest, .cable),
            ("Cable Row", .back, .cable),
            ("Push Up", .chest, .bodyweight)
        ] {
            container.mainContext.insert(Exercise(nameEn: name, nameZh: name,
                                                   muscleGroup: group, equipment: equipment))
        }
        try container.mainContext.save()
        for (name, scheme, size, group) in [
            ("light", ColorScheme.light, DynamicTypeSize.large, MuscleGroup?.none),
            ("dark", .dark, .large, nil),
            ("empty", .light, .large, .arms),
            ("accessibility", .dark, .accessibility1, nil)
        ] {
            let view = ExercisePickerView(initialMuscleGroup: group, onSelect: { _ in })
                .modelContainer(container)
                .environment(\.dynamicTypeSize, size)
                .preferredColorScheme(scheme)
                .designTheme()
            let host = UIHostingController(rootView: view)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = window.bounds
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.4))
            host.view.layoutIfNeeded()
            let renderer = UIGraphicsImageRenderer(size: window.bounds.size)
            let image = renderer.image { _ in
                host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let data = try #require(image.pngData())
            #expect(image.cgImage?.width == 1179)
            #expect(image.cgImage?.height == 2556)
            let output = URL(fileURLWithPath: "/Users/lee/Development/handoff/vs-rem-1101/snapshots", isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let path = output.appendingPathComponent(
                "tk1-exercise-picker-\(name)-393x852.png"
            )
            try data.write(to: path)
            Attachment.record(Array(data), named: "vswr-t2-picker-\(name).png")
            #expect(data.count > 15_000)
            window.isHidden = true
            window.rootViewController = nil
        }
    }
    #endif
}
