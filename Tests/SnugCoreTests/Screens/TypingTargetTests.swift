import Testing
@testable import SnugCore

@Suite("手机上打的字落在哪块屏上 DeskSet.State.typingTarget")
struct TypingTargetTests {
    private let claudeA = WindowInfo(key: WindowKey(pid: 20, id: 1), app: "Claude", bundleID: "com.anthropic.claudefordesktop", title: "甲")
    private let claudeB = WindowInfo(key: WindowKey(pid: 20, id: 2), app: "Claude", bundleID: "com.anthropic.claudefordesktop", title: "乙")

    /// 声明了键盘高度、露着窗口的手机屏
    private func phone(_ window: WindowInfo?, room: Bool = false, list: Bool = false, keep: Double? = 0.6,
                       behavior: ScreenBehavior = .touchScreen) -> Desk.State {
        var desk = Desk.State()
        desk.behavior = behavior
        desk.placed = window.map { Desk.Placed(window: $0, zoom: 0) }
        desk.listVisible = list
        desk.keyboardRoom = room
        desk.keyboardKeep = keep
        return desk
    }

    @Test("前台 App 的窗口放在哪块手机屏上就是哪块，带上它让没让着键盘")
    func frontmostAppsScreen() {
        var state = DeskSet.State()
        state.desks = [ScreenID("a"): phone(claudeA, room: true), ScreenID("b"): phone(ghostty)]
        #expect(state.typingTarget(frontmost: 20, watched: nil).map { [$0.id.rawValue, "\($0.room)"] } == ["a", "true"])
        #expect(state.typingTarget(frontmost: ghostty.key.pid, watched: nil)?.window == ghostty.key)
        #expect(state.typingTarget(frontmost: 99, watched: nil) == nil)
    }

    @Test("两块屏上放着同一个 App 的窗口：取手机在看的那块；不知道在看哪块（有的远控报不了推流屏）就不认，不缩错窗口")
    func sameAppOnTwoScreens() {
        var state = DeskSet.State()
        state.desks = [ScreenID("a"): phone(claudeA), ScreenID("b"): phone(claudeB, room: true)]
        #expect(state.typingTarget(frontmost: 20, watched: ScreenID("b"))?.window == claudeB.key)
        #expect(state.typingTarget(frontmost: 20, watched: ScreenID("a"))?.window == claudeA.key)
        #expect(state.typingTarget(frontmost: 20, watched: nil) == nil)
    }

    @Test("露着资源库、没声明键盘高度、电脑屏、没放窗口的屏不算")
    func ineligibleScreens() {
        var state = DeskSet.State()
        state.desks = [ScreenID("list"): phone(claudeA, list: true), ScreenID("noKeyboard"): phone(claudeB, keep: nil),
                       ScreenID("mac"): phone(ghostty, behavior: .computer), ScreenID("empty"): phone(nil)]
        #expect(state.typingTarget(frontmost: 20, watched: nil) == nil)
        #expect(state.typingTarget(frontmost: ghostty.key.pid, watched: nil) == nil)
    }
}
