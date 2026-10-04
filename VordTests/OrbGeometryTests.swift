import XCTest
@testable import Vord

final class OrbGeometryTests: XCTestCase {
    func testCompanionSlotRetainsCircularBoundsAcrossWindowAndScreenCoordinates() {
        let anchor = CGRect(x: -1200, y: 456, width: 80, height: 80)
        let original = OrbCompanionGeometry.frame(in: anchor)
        let moved = OrbCompanionGeometry.frame(in: anchor.offsetBy(dx: 340, dy: -120))
        XCTAssertEqual(original.size, CGSize(width: 72, height: 72))
        XCTAssertEqual(original.midX, anchor.midX)
        XCTAssertEqual(original.midY, anchor.midY)
        XCTAssertEqual(moved, original.offsetBy(dx: 340, dy: -120))
        let resized = OrbCompanionGeometry.frame(in: CGRect(x: 100, y: 200, width: 120, height: 90))
        XCTAssertEqual(resized.width, resized.height)
        XCTAssertEqual(resized.size, original.size)
        XCTAssertEqual(resized.midX, 160)
    }

    func testCompanionDropOnlyRejoinsNearReservedSlot() {
        let target = CGRect(x: 1020, y: 600, width: 72, height: 72)
        XCTAssertTrue(OrbCompanionGeometry.acceptsDrop(target, destination: target))
        XCTAssertTrue(OrbCompanionGeometry.acceptsDrop(target.offsetBy(dx: -45, dy: 20), destination: target))
        XCTAssertFalse(OrbCompanionGeometry.acceptsDrop(target.offsetBy(dx: -120, dy: 0), destination: target))
        XCTAssertFalse(OrbCompanionGeometry.acceptsDrop(target.offsetBy(dx: 0, dy: 120), destination: target))
    }

    func testCompanionActivityGazeStaysSubtleAndStopsForDragOrReducedMotion() {
        for time in stride(from: 0.0, through: 30, by: 0.1) {
            let pose = OrbFacePose.sample(elapsed: time, returnElapsed: nil, successful: false,
                hovered: false, dragging: false, displacement: 0, reduced: false, activity: .thinking)
            XCTAssertLessThanOrEqual(abs(pose.gaze.width), 1.4)
            XCTAssertEqual(pose.gaze.height, -1.4)
        }
        let dragged = OrbFacePose.sample(elapsed: 1, returnElapsed: nil, successful: false,
            hovered: false, dragging: true, displacement: -30, reduced: false, activity: .thinking)
        XCTAssertEqual(dragged.gaze, .zero)
        XCTAssertEqual(dragged.tilt, -4)
        let reduced = OrbFacePose.sample(elapsed: 1, returnElapsed: nil, successful: false,
            hovered: false, dragging: false, displacement: 0, reduced: true, activity: .studying)
        XCTAssertEqual(reduced.gaze, .zero)
    }

    func testCollapseSurfaceFollowsWindowAndEndsAtLensBounds() {
        let origin = CGSize(width: 440, height: 360)
        let start = CaptureCollapseGeometry(size: origin, origin: origin)
        XCTAssertEqual(start.progress, 0)
        XCTAssertEqual(start.inset, 0)
        XCTAssertEqual(start.glassOpacity, 0)
        XCTAssertEqual(start.faceOpacity, 0)
        XCTAssertEqual(start.lensSize, origin)
        var previousProgress: CGFloat = 0
        var previousOpacity = 0.0
        for step in 0...100 {
            let t = CGFloat(step) / 100
            let size = CGSize(width: 440 - 368 * t, height: 360 - 288 * t)
            let shell = CaptureCollapseGeometry(size: size, origin: origin)
            XCTAssertGreaterThanOrEqual(shell.progress, previousProgress)
            XCTAssertGreaterThanOrEqual(shell.glassOpacity, previousOpacity)
            XCTAssertLessThanOrEqual(shell.radius * 2 + shell.inset * 2, min(size.width, size.height))
            XCTAssertEqual(shell.lensSize.width + 2 * shell.inset, size.width, accuracy: 0.001)
            XCTAssertEqual(shell.lensSize.height + 2 * shell.inset, size.height, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(shell.faceOpacity, 0)
            XCTAssertLessThanOrEqual(shell.faceOpacity, shell.glassOpacity)
            previousProgress = shell.progress; previousOpacity = shell.glassOpacity
        }
        let end = CaptureCollapseGeometry(size: CGSize(width: 72, height: 72), origin: origin)
        XCTAssertEqual(end.progress, 1)
        XCTAssertEqual(end.inset, 8)
        XCTAssertEqual(end.radius, 28)
        XCTAssertEqual(end.glassOpacity, 1)
        XCTAssertEqual(end.faceOpacity, 1)
        XCTAssertEqual(end.lensSize, CGSize(width: 56, height: 56))
    }

    func testSavedBannerCollapseUsesWidthWhenHeightAlreadySmallerThanOrb() {
        let origin = CGSize(width: 220, height: 64)
        XCTAssertEqual(CaptureCollapseGeometry(size: origin, origin: origin).progress, 0)
        let midway = CaptureCollapseGeometry(size: CGSize(width: 146, height: 68), origin: origin)
        XCTAssertEqual(midway.progress, 0.5)
        XCTAssertLessThan(midway.glassOpacity, 0.01)
        XCTAssertEqual(midway.faceOpacity, 0)
        let tiny = CaptureCollapseGeometry(size: CGSize(width: 32, height: 32), origin: origin)
        XCTAssertGreaterThanOrEqual(tiny.radius, 0)
        XCTAssertLessThanOrEqual(tiny.radius * 2 + tiny.inset * 2, 32)
    }

    func testClosingMaterialHandoffCompletesBeforeWindowSettles() {
        // Both surfaces share their bounds throughout the handoff, including a
        // tall dictionary result and the shorter-than-orb success banner.
        for origin in [CGSize(width: 440, height: 420), CGSize(width: 220, height: 64)] {
            let size = CGSize(width: origin.width + (72 - origin.width) * 0.98,
                              height: origin.height + (72 - origin.height) * 0.98)
            let shell = CaptureCollapseGeometry(size: size, origin: origin)
            XCTAssertEqual(shell.glassOpacity, 1)
            XCTAssertEqual(shell.faceOpacity, 1)
            XCTAssertLessThan(abs(shell.radius - min(shell.lensSize.width, shell.lensSize.height) / 2), 0.1)
        }
    }

    func testEyesBlinkWithSmallStaggerAndSuccessEasesBackToNeutral() {
        func pose(_ time: Double, success: Bool = false) -> OrbFacePose {
            OrbFacePose.sample(elapsed: time, returnElapsed: success ? time : nil,
                successful: success, hovered: false, dragging: false, displacement: 0, reduced: false)
        }
        let closing = pose(5.79)
        XCTAssertLessThan(closing.openness, closing.rightOpenness)
        XCTAssertEqual(pose(5.905).rightOpenness, 1, accuracy: 0.001)
        XCTAssertEqual(pose(0, success: true).lift, 0)
        XCTAssertEqual(pose(0.4, success: true).lift, -0.8)
        XCTAssertEqual(pose(1.5, success: true).lift, 0)
        // Smooth attack/release avoid sudden facial velocity changes.
        XCTAssertLessThan(pose(0.001, success: true).smile, 0.001)
        XCTAssertLessThan(pose(1.499, success: true).smile, 0.001)
        let reduced = OrbFacePose.sample(elapsed: 5.79, returnElapsed: 0.4, successful: true,
            hovered: true, dragging: true, displacement: 5, reduced: true)
        XCTAssertEqual(reduced.rightOpenness, 1)
        XCTAssertEqual(reduced.lift, 0)
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
