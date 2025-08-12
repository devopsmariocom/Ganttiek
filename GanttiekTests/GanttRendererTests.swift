import XCTest
@testable import Ganttiek
import SwiftUI

final class GanttRendererTests: XCTestCase {

    @MainActor
    func testRenderSampleTasksProducesPNG() {
        // Arrange: sample tasks -> resolved
        let tasks = sampleTasks()
        let resolved: [ResolvedTask]
        do {
            resolved = try DependencyResolver.resolve(tasks)
        } catch {
            XCTFail("Resolver failed: \(error)")
            return
        }

        // Act
        let size = CGSize(width: 800, height: 400)
        let data = ContentView.renderChartPNG(items: resolved, size: size)

        // Assert: non-nil & looks like PNG
        XCTAssertNotNil(data, "Renderer returned nil data")
        if let d = data {
            // PNG signature 89 50 4E 47 0D 0A 1A 0A
            let sig = Array(d.prefix(8))
            XCTAssertEqual(sig, [0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A], "Not a PNG file")
            // reasonable size
            XCTAssertGreaterThan(d.count, 1024, "PNG seems too small")
        }
    }
}
