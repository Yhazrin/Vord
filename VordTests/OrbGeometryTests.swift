import XCTest
@testable import Vord

final class OrbGeometryTests: XCTestCase {
    func testEdgeDockPersistsRelativeHeightAcrossResolutionChange() throws {
        let visible = CGRect(x: -1920, y: 32, width: 1920, height: 1048)
        let position = OrbDockPosition(edge: .left, heightFraction: 0.7, displayID: 17)
        let restored = try JSONDecoder().decode(OrbDockPosition.self, from: JSONEncoder().encode(position))
        XCTAssertEqual(restored, position)
        let first = restored.frame(in: visible)
        let second = restored.frame(in: CGRect(x: -1440, y: 32, width: 1440, height: 868))
        XCTAssertEqual(first.minX, visible.minX + OrbDockPosition.inset)
        XCTAssertEqual(first.width, first.height)
        XCTAssertEqual(second.width, second.height)
        XCTAssertEqual((first.minY - visible.minY - 8) / (visible.height - 88), 0.7, accuracy: 0.001)
        XCTAssertEqual((second.minY - 40) / (868 - 88), 0.7, accuracy: 0.001)
    }

    func testReleaseChoosesNearestEdgeAndClampsHeight() {
        let visible = CGRect(x: 1200, y: -600, width: 1920, height: 1000)
        let left = OrbDockPosition.nearest(to: CGRect(x: 1220, y: -900, width: 72, height: 72), in: visible, displayID: 9)
        let right = OrbDockPosition.nearest(to: CGRect(x: 2900, y: 900, width: 72, height: 72), in: visible, displayID: 9)
        XCTAssertEqual(left.edge, .left); XCTAssertEqual(left.heightFraction, 0)
        XCTAssertEqual(right.edge, .right); XCTAssertEqual(right.heightFraction, 1)
        XCTAssertTrue(visible.contains(left.frame(in: visible)))
        XCTAssertTrue(visible.contains(right.frame(in: visible)))
    }

    func testDraggingNeverChangesCircularWindowDimensions() {
        let visible = CGRect(x: -1280, y: 20, width: 1280, height: 780)
        let outside = CGRect(x: -1700, y: -300, width: 72, height: 72)
        let frame = OrbDockPosition.clamped(outside, in: visible)
        XCTAssertEqual(frame.size, outside.size)
        XCTAssertEqual(frame.width, frame.height)
        XCTAssertTrue(visible.contains(frame))
    }

    func testInteriorInertiaSettlesAfterReleaseWithoutIdleOscillation() {
        var state = (position: 5.0, velocity: -18.0)
        var crossedZero = false
        for _ in 0..<120 {
            state = OrbPhysics.advance(position: state.position, velocity: state.velocity, target: 0, seconds: 1 / 60)
            crossedZero = crossedZero || state.position < 0
            XCTAssertTrue(state.position.isFinite && state.velocity.isFinite)
            XCTAssertLessThan(abs(state.position), 6)
        }
        XCTAssertTrue(crossedZero)
        XCTAssertEqual(state.position, 0, accuracy: 0.001)
        XCTAssertEqual(state.velocity, 0, accuracy: 0.001)
    }
}
