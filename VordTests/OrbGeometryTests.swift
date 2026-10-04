import XCTest
@testable import Vord

final class OrbGeometryTests: XCTestCase {
    func testCollapseSurfaceFollowsWindowAndEndsAtLensBounds() {
        let origin = CGSize(width: 440, height: 360)
        let start = CaptureCollapseGeometry(size: origin, origin: origin)
        XCTAssertEqual(start.progress, 0)
        XCTAssertEqual(start.inset, 0)
        XCTAssertEqual(start.glassOpacity, 0)
        var previousProgress: CGFloat = 0
        var previousOpacity = 0.0
        for step in 0...100 {
            let t = CGFloat(step) / 100
            let size = CGSize(width: 440 - 368 * t, height: 360 - 288 * t)
            let shell = CaptureCollapseGeometry(size: size, origin: origin)
            XCTAssertGreaterThanOrEqual(shell.progress, previousProgress)
            XCTAssertGreaterThanOrEqual(shell.glassOpacity, previousOpacity)
            XCTAssertLessThanOrEqual(shell.radius * 2 + shell.inset * 2, min(size.width, size.height))
            previousProgress = shell.progress; previousOpacity = shell.glassOpacity
        }
        let end = CaptureCollapseGeometry(size: CGSize(width: 72, height: 72), origin: origin)
        XCTAssertEqual(end.progress, 1)
        XCTAssertEqual(end.inset, 8)
        XCTAssertEqual(end.radius, 28)
        XCTAssertEqual(end.glassOpacity, 1)
    }

    func testSavedBannerCollapseUsesWidthWhenHeightAlreadySmallerThanOrb() {
        let origin = CGSize(width: 220, height: 64)
        XCTAssertEqual(CaptureCollapseGeometry(size: origin, origin: origin).progress, 0)
        let midway = CaptureCollapseGeometry(size: CGSize(width: 146, height: 68), origin: origin)
        XCTAssertEqual(midway.progress, 0.5)
        XCTAssertEqual(midway.glassOpacity, 0)
        let tiny = CaptureCollapseGeometry(size: CGSize(width: 32, height: 32), origin: origin)
        XCTAssertGreaterThanOrEqual(tiny.radius, 0)
        XCTAssertLessThanOrEqual(tiny.radius * 2 + tiny.inset * 2, 32)
    }

    func testClosingSpringSettlesWithLessThanOnePointUndershoot() {
        var state = (position: 440.0, velocity: 0.0)
        for _ in 0..<120 {
            state = CaptureSpringCurve.advance(position: state.position, velocity: state.velocity,
                target: 72, seconds: 1 / 60, damping: 0.94)
            XCTAssertTrue(state.position.isFinite && state.velocity.isFinite)
            XCTAssertGreaterThan(state.position, 71)
            XCTAssertLessThanOrEqual(state.position, 440)
        }
        XCTAssertEqual(state.position, 72, accuracy: 0.001)
        XCTAssertEqual(state.velocity, 0, accuracy: 0.001)
    }

    func testFaceBlinkSmileAndReducedMotion() {
        func face(_ elapsed: Double, returned: Double? = nil, success: Bool = false,
                  dragging: Bool = false, reduced: Bool = false) -> OrbFacePose {
            OrbFacePose.sample(elapsed: elapsed, returnElapsed: returned, successful: success,
                hovered: false, dragging: dragging, displacement: 50, reduced: reduced)
        }
        XCTAssertEqual(face(5.7).openness, 1, accuracy: 0.0001)
        XCTAssertEqual(face(5.79).openness, 0.07, accuracy: 0.0001)
        XCTAssertEqual(face(5.88).openness, 1, accuracy: 0.0001)
        XCTAssertEqual(face(0, returned: 0, success: true).smile, 0)
        XCTAssertEqual(face(0, returned: 0.4, success: true).smile, 1)
        XCTAssertEqual(face(0, returned: 1.5, success: true).smile, 0)
        XCTAssertEqual(face(0, returned: 0.22).openness, 0.07, accuracy: 0.0001)
        XCTAssertEqual(face(0, dragging: true).tilt, 4)
        let still = face(5.79, returned: 0.4, success: true, dragging: true, reduced: true)
        XCTAssertEqual(still.openness, 1)
        XCTAssertEqual(still.smile, 0)
        XCTAssertEqual(still.tilt, 0)
    }

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
