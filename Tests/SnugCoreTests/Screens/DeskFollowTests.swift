import CoreGraphics
import Testing
@testable import SnugCore

@Suite("键盘让位跟着焦点、小横条切回上一个窗口 Desk")
@MainActor
struct DeskFollowTests {
    /// 手机屏的比例声明了键盘高度（CrossDesk）
    private func keyboardRig() async throws -> Rig {
        let rig = try Rig()
        var fit = ScreenFit.standard
        fit.keyboardKeep = 0.6
        rig.desk.setFit(fit)
        await rig.ready()
        return rig
    }

    private func follow(_ rig: Rig, _ focus: InputFocus?, in window: WindowInfo = ghostty) async {
        rig.desk.followFocus(focus, in: window.key)
        await rig.desk.idle()
    }

    @Test("点进输入框自动让出键盘，点发送键（控件）不动，点回对话内容铺回整屏")
    func followsFocus() async throws {
        let rig = try await keyboardRig()
        await rig.pull(ghostty)
        let full = try #require(rig.windows.window(ghostty.key)?.frame)
        await follow(rig, .text)
        #expect(rig.desk.state.keyboardRoom)
        #expect(try #require(rig.windows.window(ghostty.key)?.frame).height < full.height)
        await follow(rig, .control)
        #expect(rig.desk.state.keyboardRoom)
        await follow(rig, .content)
        #expect(!rig.desk.state.keyboardRoom)
        #expect(rig.windows.window(ghostty.key)?.frame == full)
    }

    @Test("手动按了键盘键：焦点没变（在输入框里挪光标）就不改回去，下次进出输入框照常跟着走")
    func manualToggleWins() async throws {
        let rig = try await keyboardRig()
        await rig.pull(ghostty)
        await follow(rig, .text)
        rig.desk.toggleKeyboardRoom()
        await rig.desk.idle()
        #expect(!rig.desk.state.keyboardRoom)
        await follow(rig, .text)
        #expect(!rig.desk.state.keyboardRoom)
        await follow(rig, .content)
        await follow(rig, .text)
        #expect(rig.desk.state.keyboardRoom)
    }

    @Test("读到的焦点不是屏上这个窗口的（点完换了窗口）、露着资源库、比例没声明键盘高度：不管")
    func ignored() async throws {
        let rig = try await keyboardRig()
        await rig.pull(ghostty)
        await follow(rig, .text, in: finder)
        #expect(!rig.desk.state.keyboardRoom)
        rig.desk.showList()
        await rig.desk.idle()
        await follow(rig, .text)
        #expect(!rig.desk.state.keyboardRoom)

        rig.desk.setFit(.standard)
        await rig.desk.idle()
        await rig.pull(finder)
        rig.journal.clear()
        await follow(rig, .text, in: finder)
        #expect(!rig.desk.state.keyboardRoom)
        #expect(rig.journal.all.isEmpty)
    }

    @Test("换了窗口从头认：上一个窗口停在输入框里，新窗口头一下点在输入框里照样让位")
    func newWindowStartsFresh() async throws {
        let rig = try await keyboardRig()
        await rig.pull(ghostty)
        await follow(rig, .text)
        await rig.pull(finder)
        #expect(!rig.desk.state.keyboardRoom)
        await follow(rig, .text, in: finder)
        #expect(rig.desk.state.keyboardRoom)
    }

    @Test("回资源库再回来也从头认：返回窗口后点进输入框照样让位")
    func listStartsFresh() async throws {
        let rig = try await keyboardRig()
        await rig.pull(ghostty)
        await follow(rig, .text)
        rig.desk.showList()
        await rig.desk.idle()
        rig.desk.returnToPlaced()
        await rig.desk.idle()
        #expect(!rig.desk.state.keyboardRoom)
        await follow(rig, .text)
        #expect(rig.desk.state.keyboardRoom)
    }

    @Test("换了比例从头认：让位被换比例关掉后，点在同一个输入框里照样再让")
    func reshapeStartsFresh() async throws {
        let rig = try await keyboardRig()
        await rig.pull(ghostty)
        await follow(rig, .text)
        var fit = ScreenFit.standard
        fit.keyboardKeep = 0.55
        rig.desk.setFit(fit)
        await rig.desk.idle()
        #expect(!rig.desk.state.keyboardRoom)
        await follow(rig, .text)
        #expect(rig.desk.state.keyboardRoom)
    }

    @Test("让位没铺成（App 卡住）：从头认，下次点进输入框再试")
    func retriesAfterFailedFill() async throws {
        let rig = try await keyboardRig()
        await rig.pull(ghostty)
        rig.windows.blockMoves()
        await follow(rig, .text)
        #expect(!rig.desk.state.keyboardRoom)
        rig.windows.blockMoves(false)
        await follow(rig, .text)
        #expect(rig.desk.state.keyboardRoom)
    }

    @Test("铺回整屏没铺成（App 卡住）：之后点在内容上再试")
    func retriesFailedRestore() async throws {
        let rig = try await keyboardRig()
        await rig.pull(ghostty)
        await follow(rig, .text)
        rig.windows.blockMoves()
        await follow(rig, .content)
        #expect(rig.desk.state.keyboardRoom)
        rig.windows.blockMoves(false)
        await follow(rig, .content)
        #expect(!rig.desk.state.keyboardRoom)
    }

    @Test("连滑两下（第一下还没切完）：第二下不算，不会切过去又切回来；第一下滑完马上显示正在打开")
    func doubleSwipe() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        await rig.pull(safari)
        await rig.pull(finder)
        rig.desk.switchBack()
        #expect(rig.desk.state.work == .placing(safari))
        rig.desk.switchBack()
        await rig.desk.idle()
        #expect(rig.desk.state.placed?.window == safari)
    }

    @Test("远程结束：这次放过的窗口不带到下一次，下一次滑了什么都不做")
    func sessionEndForgets() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        await rig.pull(finder)
        rig.desk.setRemote(true)
        rig.desk.setRemote(false)
        await rig.desk.idle()
        rig.journal.clear()
        rig.desk.switchBack()
        await rig.desk.idle()
        #expect(!rig.journal.all.contains { $0.hasPrefix("move") })
        #expect(rig.desk.state.placed?.window != ghostty)
    }

    private func switchBack(_ rig: Rig) async {
        rig.desk.switchBack()
        await rig.desk.idle()
    }

    @Test("左右滑切回上一个窗口：来回切；换下去的窗口放回原位，切回来的铺满")
    func switchBackAndForth() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        await rig.pull(finder)
        await switchBack(rig)
        #expect(rig.desk.state.placed?.window == ghostty)
        #expect(rig.windows.window(finder.key)?.frame == finderHome)
        #expect(rig.windows.window(ghostty.key)?.frame == phoneArea)
        await switchBack(rig)
        #expect(rig.desk.state.placed?.window == finder)
        #expect(rig.windows.window(ghostty.key)?.frame == ghosttyHome)
    }

    @Test("点了「还原」再从资源库挑了别的：滑一下回到还原前那个")
    func afterPutBackAndPick() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        rig.desk.putBack()
        await rig.desk.idle()
        await rig.pull(finder)
        await switchBack(rig)
        #expect(rig.desk.state.placed?.window == ghostty)
    }

    @Test("上一个窗口关了：跳过它、切回再往前那个（审查实测的顺序：放 Ghostty、放访达、关访达、放 Safari、滑）")
    func skipsClosed() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        await rig.pull(finder)
        rig.desk.close(finder)
        await rig.desk.idle()
        await rig.pull(safari)
        await switchBack(rig)
        #expect(rig.desk.state.placed?.window == ghostty)
        #expect(rig.desk.state.notice == nil)
    }

    @Test("铺不上的窗口不记：没放成访达，滑一下还是回到 Ghostty")
    func failedLandNotRemembered() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        await rig.pull(safari)
        rig.windows.refuseMoves { key, rect in key == finder.key && rect != finderHome }
        await rig.pull(finder)
        #expect(rig.desk.state.placed == nil)
        rig.windows.refuseMoves { _, _ in false }
        await rig.pull(notes)
        await switchBack(rig)
        #expect(rig.desk.state.placed?.window == safari)
    }

    @Test("最近的窗口都关了：屏上的窗口不动，不报错")
    func allGone() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        await rig.pull(finder)
        rig.windows.vanish(ghostty.key)
        rig.journal.clear()
        await switchBack(rig)
        #expect(rig.desk.state.placed?.window == finder)
        #expect(rig.desk.state.notice == nil)
        #expect(!rig.journal.all.contains { $0.hasPrefix("move") })
    }

    @Test("还没换过窗口：滑了什么都不做")
    func nothingToSwitchBack() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        rig.journal.clear()
        await switchBack(rig)
        #expect(rig.desk.state.placed?.window == ghostty)
        #expect(rig.journal.all.isEmpty)
    }

    @Test("上一个窗口正放在另一块手机屏上：不抢过来，往前找；这块屏最近放过的只有它就什么都不做")
    func skipsWindowOnAnotherScreen() async throws {
        let rig = try Rig()
        let second = ScreenID("second")
        let spec = ScreenSpec(name: "Snug 第二块", productID: ScreenSpec.portraitProductID,
                              serials: [200_100_000, 200_100_001, 200_100_002], maxPixels: ScreenFit.portraitPixels)
        rig.set.setWishes([rig.desk.wish, ScreenWish(id: second, spec: spec, fit: .standard, behavior: .touchScreen)])
        await rig.set.idle()
        await rig.pull(ghostty)
        await rig.pull(finder)
        rig.set.pull(ghostty, on: second)
        await rig.set.idle()
        await switchBack(rig)
        #expect(rig.desk.state.placed?.window == finder)
        #expect(rig.set.state.desks[second]?.placed?.window == ghostty)
    }
}
