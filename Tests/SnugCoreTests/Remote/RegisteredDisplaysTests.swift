import Testing
@testable import SnugCore

@Suite("只读一次显示器的远控切不切得到 RegisteredDisplays")
struct RegisteredDisplaysTests {
    @Test("Snug 的屏登记过：切得到；之后接上的外接屏、随航不占它的位置，不算")
    func registered() {
        #expect(!RegisteredDisplays.misses([1, 7], snug: [7], online: [1, 7]))
        #expect(!RegisteredDisplays.misses([1, 7], snug: [7], online: [1, 7, 12]))
    }

    @Test("Snug 重启过、屏换了编号：原来那块的位置补上同一序号的新屏，切得到")
    func renumbered() {
        #expect(!RegisteredDisplays.misses([1, 22], snug: [24], online: [1, 24]))
    }

    @Test("它比 Snug 的屏先启动、之后多开了一块 Snug 的屏：没有位置可补，切不到")
    func unregistered() {
        #expect(RegisteredDisplays.misses([1], snug: [7], online: [1, 7]))
        #expect(RegisteredDisplays.misses([1, 7], snug: [7, 9], online: [1, 7, 9]))
        #expect(RegisteredDisplays.misses([1, 22], snug: [24, 25], online: [1, 24, 25]))
    }

    @Test("空出的位置补的是同一序号上的那块：被后接的外接屏、或者另一块登记过的 Snug 屏占了，新屏切不到")
    func slotTakenByOther() {
        // 登记了 #1、#22，之后接上外接屏 #5，再重启 Snug：1 号位补上的是 #5
        #expect(RegisteredDisplays.misses([1, 22], snug: [24], online: [1, 5, 24]))
        // 登记了 #1、#22、#24，关掉再打开 #22 那块（换成 #25）：1 号位补上的是已经登记过的 #24
        #expect(RegisteredDisplays.misses([1, 22, 24], snug: [24, 25], online: [1, 24, 25]))
    }
}
