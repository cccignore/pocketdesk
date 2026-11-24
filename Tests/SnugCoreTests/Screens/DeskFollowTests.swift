import CoreGraphics
import Testing
@testable import SnugCore

@Suite("键盘让位跟着焦点 Desk")
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
}
