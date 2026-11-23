import Testing
@testable import SnugCore

@Suite("连击计数 ClickChain")
struct ClickChainTests {
    @Test("没吞过点按：远控数到几就补发几，一个字都不改（和以前一样）")
    func untouched() {
        var chain = ClickChain()
        #expect([1, 2, 3, 0].map { chain.count($0) } == [1, 2, 3, 0])
    }

    @Test("吞掉一下（只停了惯性）后：这一串都减掉吞掉的数，App 看到的从 1 数起；远控从 1 重新数起时这一串结束")
    func skipsSwallowedTap() {
        var chain = ClickChain()
        // 第二下补发前说明：远控把它数成 2，前面那下吞掉了
        chain.skip(before: 2)
        #expect(chain.count(2) == 1)   // 补发的按下
        #expect(chain.count(2) == 1)   // 补发的抬起
        #expect(chain.count(3) == 2)   // 第三下：App 看到的是双击
        #expect(chain.count(1) == 1)   // 新的一串
        #expect(chain.count(2) == 2)
    }
}
