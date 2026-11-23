import Testing
@testable import SnugCore

@Suite("只读一次显示器的远控切不切得到 RegisteredDisplays")
struct RegisteredDisplaysTests {
    @Test("Snug 的屏登记过：切得到；之后接上的外接屏、随航不占它的位置，不算")
    func registered() {
        #expect(!RegisteredDisplays.misses([1, 7], snug: [7], online: [1, 7]))
        #expect(!RegisteredDisplays.misses([1, 7], snug: [7], online: [1, 7, 12]))
    }

    @Test("Snug 重启过、屏换了编号：原来那块不在了，空出的位置给新屏，切得到")
    func renumbered() {
        #expect(!RegisteredDisplays.misses([1, 22], snug: [24], online: [1, 24]))
    }

    @Test("它比 Snug 的屏先启动、或者之后多开了一块 Snug 的屏：没有空出的位置，切不到")
    func unregistered() {
        #expect(RegisteredDisplays.misses([1], snug: [7], online: [1, 7]))
        #expect(RegisteredDisplays.misses([1, 7], snug: [7, 9], online: [1, 7, 9]))
        // 两块新屏只空出一个位置
        #expect(RegisteredDisplays.misses([1, 22], snug: [24, 25], online: [1, 24, 25]))
    }
}
