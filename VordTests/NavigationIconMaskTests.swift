import AppKit
import XCTest
@testable import Vord

final class NavigationIconMaskTests: XCTestCase {
    func testDebrisAndThinBridgesAreRemovedButSeparateBodiesAndAntialiasingSurvive() throws {
        let width = 128, height = 96
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        func paint(_ x: Int, _ y: Int, alpha: UInt8, value: UInt8 = 230) {
            let offset = (y * width + x) * 4
            let premultiplied = UInt8(Int(value) * Int(alpha) / 255)
            rgba[offset] = premultiplied; rgba[offset + 1] = premultiplied
            rgba[offset + 2] = premultiplied; rgba[offset + 3] = alpha
        }
        // Main paper body and a substantial, separate microphone-like piece.
        for y in 22..<72 { for x in 26..<70 { paint(x, y, alpha: 255) } }
        for y in 32..<68 { for x in 82..<104 { paint(x, y, alpha: 255, value: 70) } }
        for y in 27..<67 { paint(25, y, alpha: 128) }
        // Isolated opaque specks and a tiny chunk joined by a one-pixel bridge.
        for y in 5..<8 { for x in 5..<8 { paint(x, y, alpha: 255) } }
        for y in 10..<22 { paint(38, y, alpha: 255) }
        for y in 8..<11 { for x in 37..<40 { paint(x, y, alpha: 255) } }
        // A distant low-alpha baked shadow must not survive as a third body.
        for y in 76..<88 { for x in 24..<92 { paint(x, y, alpha: 70) } }
        let image = try fixture(rgba, width: width, height: height)
        let cleaned = try XCTUnwrap(NavigationIconMask.sanitized(image))
        let data = try XCTUnwrap(cleaned.dataProvider?.data) as Data
        let bytes = [UInt8](data)
        let alphas = stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }
        XCTAssertTrue(alphas.contains(128), "The source's antialiased edge is retained")
        XCTAssertFalse(alphas.contains(70), "A baked shadow detached from the body is removed")
        XCTAssertGreaterThan(alphas.filter { $0 == 255 }.count, 2_900, "Both substantial components remain")
        XCTAssertLessThanOrEqual(cleaned.height, 58, "Thin attached debris and the distant shadow do not enlarge the crop")
        XCTAssertTrue(stride(from: 0, to: bytes.count, by: 4).contains { bytes[$0] == 70 && bytes[$0 + 3] == 255 },
                      "The separate dark component remains with its original material colour")
    }

    func testEmptyAndTinyDebrisCannotBecomeAnIcon() throws {
        let width = 24, height = 24
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        rgba[(12 * width + 12) * 4 + 3] = 255
        XCTAssertNil(NavigationIconMask.sanitized(try fixture(rgba, width: width, height: height)))
    }

    private func fixture(_ rgba: [UInt8], width: Int, height: Int) throws -> CGImage {
        let data = Data(rgba)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent))
    }
}
