import Testing
@testable import SnugCore

private let pinyin = "com.apple.inputmethod.SCIM.ITABC"
private let abc = "com.apple.keylayout.ABC"

@Suite("远程期间换英文输入法 InputSourceSwap")
struct InputSourceSwapTests {
    @Test("用着中文输入法：远程开始换成英文，结束换回原来的")
    func swapsAndRestores() {
        var swap = InputSourceSwap()
        #expect(swap.begin(current: pinyin, currentIsASCII: false, ascii: abc) == abc)
        #expect(swap.end(current: abc) == pinyin)
        // 换回之后不再记着
        #expect(swap.end(current: abc) == nil)
    }

    @Test("本来就是英文（能直接打 ASCII 的键盘）：不换，结束也不动")
    func alreadyASCII() {
        var swap = InputSourceSwap()
        #expect(swap.begin(current: abc, currentIsASCII: true, ascii: abc) == nil)
        #expect(swap.end(current: abc) == nil)
    }

    @Test("远程中用户自己换了输入法：结束时不动；重连再开始也不重复记")
    func userChangedMeanwhile() {
        var swap = InputSourceSwap()
        _ = swap.begin(current: pinyin, currentIsASCII: false, ascii: abc)
        #expect(swap.begin(current: abc, currentIsASCII: true, ascii: abc) == nil)
        #expect(swap.end(current: "com.apple.keylayout.US") == nil)
        // 下一次远程照常
        #expect(swap.begin(current: pinyin, currentIsASCII: false, ascii: abc) == abc)
    }

    @Test("找不到能换成的英文输入法：不换")
    func noASCIISource() {
        var swap = InputSourceSwap()
        #expect(swap.begin(current: pinyin, currentIsASCII: false, ascii: nil) == nil)
        #expect(swap.end(current: pinyin) == nil)
    }
}
