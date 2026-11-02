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
    func renderPickerEvidence() async throws {
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
                .dynamicTypeSize(size)
                .preferredColorScheme(scheme)
                .designTheme()
            let image = try await TK1SnapshotRenderer.render(
                view, size: CGSize(width: 393, height: 852), appearance: scheme
            ) { root in
                if size.isAccessibilitySize {
                    try await revealBottomExerciseRow(in: root)
                }
            }
            let data = try #require(image.pngData())
            #expect(image.cgImage?.width == 1179)
            #expect(image.cgImage?.height == 2556)
            let output = TK1SnapshotRenderer.outputDirectory
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let path = output.appendingPathComponent(
                "tk1-exercise-picker-\(name)-393x852.png"
            )
            try data.write(to: path)
            Attachment.record(Array(data), named: "vswr-t2-picker-\(name).png")
            #expect(data.count > 15_000)
        }
    }
    /// At accessibility sizes the fixture is taller than the viewport. Scroll
    /// the real grid to its final row to verify Cable Row's full title and
    /// metadata, plus the bottom clearance provided by the production dock.
    @MainActor
    private func revealBottomExerciseRow(in root: UIView) async throws {
        func scrollViews(in view: UIView) -> [UIScrollView] {
            (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
        }
        let grids = scrollViews(in: root).filter {
            $0.bounds.width > root.bounds.width / 2 && $0.bounds.height > root.bounds.height / 2
        }
        let grid = try #require(grids.first)
        #expect(grids.count == 1)
        let bottom = max(-grid.adjustedContentInset.top,
                         grid.contentSize.height - grid.bounds.height + grid.adjustedContentInset.bottom)
        grid.setContentOffset(CGPoint(x: grid.contentOffset.x, y: bottom), animated: false)
        // Wait for the normal 700ms equipment-index HUD to dismiss before
        // inspecting the underlying title and metadata.
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(50))
            TK1SnapshotRenderer.pumpRunLoop()
            grid.layoutIfNeeded()
        }
        #expect(grid.contentOffset.y == bottom)
    }
    #endif
}
