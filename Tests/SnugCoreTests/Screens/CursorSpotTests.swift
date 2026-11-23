import CoreGraphics
import Testing
@testable import SnugCore

@Suite("换档时的光标 CursorSpot")
struct CursorSpotTests {
    /// 590 宽的手机屏（左上原点，在主屏左边）
    private let wide = CGRect(x: -590, y: 0, width: 590, height: 1142)
    private let narrow = CGSize(width: 540, height: 1045)

    @Test("屏变矮时光标在小横条上（590 档 y=1126）：换档前挪到新尺寸里的同一相对位置，不会被夹到底边")
    func shrinkKeepsOffBottomEdge() throws {
        let spot = try #require(CursorSpot(CGPoint(x: -15, y: 1126), on: wide))
        let before = spot.beforeSwitch(to: narrow)
        #expect(wide.contains(before))
        #expect(before.y < wide.minY + narrow.height - 1)
        #expect(abs(before.y - 1126 * 1045 / 1142) < 0.5)
        // 换档后按新屏的边界放回同一相对位置
        let after = spot.afterSwitch(in: CGRect(origin: CGPoint(x: -540, y: 0), size: narrow))
        #expect(abs(after.x - (-540 + 575.0 / 590 * 540)) < 0.5)
        #expect(abs(after.y - 1126 * 1045 / 1142) < 0.5)
    }

    @Test("屏变大：换档前不用挪（原处在新尺寸里也在屏内），换档后放到新屏的同一相对位置")
    func growNeedsNoPreMove() throws {
        let small = CGRect(x: -540, y: 0, width: 540, height: 1045)
        let spot = try #require(CursorSpot(CGPoint(x: -100, y: 1030), on: small))
        #expect(spot.beforeSwitch(to: wide.size) == CGPoint(x: -100, y: 1030))
        let after = spot.afterSwitch(in: wide)
        #expect(abs(after.y - 1030.0 / 1045 * 1142) < 0.5)
    }

    @Test("光标正好在底边、右边上：换档前后都留在屏内一点，不贴着边")
    func edgesStayInside() throws {
        let spot = try #require(CursorSpot(CGPoint(x: -0.5, y: 1141.9), on: wide))
        let before = spot.beforeSwitch(to: narrow)
        #expect(before.y <= wide.minY + narrow.height - 1)
        #expect(before.x <= wide.minX + narrow.width - 1)
        let bounds = CGRect(origin: CGPoint(x: -540, y: 0), size: narrow)
        let after = spot.afterSwitch(in: bounds)
        #expect(after.y <= bounds.maxY - 1)
        #expect(after.x <= bounds.maxX - 1)
    }

    @Test("光标不在这块屏上：不管")
    func elsewhere() {
        #expect(CursorSpot(CGPoint(x: 700, y: 400), on: wide) == nil)
    }
}
