import Testing
@testable import SnugCore

// 菜单原样抄自 11-14 在本机用辅助功能读出的结果（只留快捷键是 N、或标题带「窗口」的项）。修饰键：1 ⇧、2 ⌥、4 ⌃
private func item(_ title: String, _ key: String? = nil, _ modifiers: Int = 0, submenu: Bool = false, in parent: String? = nil) -> MenuCommand {
    MenuCommand(title: title, key: key, modifiers: modifiers, opensSubmenu: submenu, parent: parent)
}

private func picked(_ items: [MenuCommand]) -> String? { NewWindowMenu.pick(items).map { items[$0].title } }

@Suite("新建窗口按哪一项 NewWindowMenu")
struct NewWindowMenuTests {
    @Test("标题就叫「New Window / 新建窗口」：快捷键是什么都认（Safari ⌥⌘N、VS Code ⇧⌘N），不认带私密、移动的")
    func exactTitle() {
        #expect(picked([item("Quit and Keep Windows", "Q", 2), item("New Window", "N"), item("Close Window", "W", 1)]) == "New Window")
        #expect(picked([item("New Window", "N", 2), item("New Private Window", "N", 1), item("New Empty Tab Group", "N", 4),
                        item("Move Tab to New Window"), item("Reopen Last Closed Window", "T", 1)]) == "New Window")
        #expect(picked([item("新建文本文件", "N"), item("新建文件…", "N", 6), item("新建窗口", "N", 1),
                        item("使用配置文件新建窗口", submenu: true), item("新建配置文件…", in: "使用配置文件新建窗口"),
                        item("新建终端窗口")]) == "新建窗口")
        #expect(picked([item("New Window", "N"), item("New Window with Current Profile", "N", 3),
                        item("New Floating Pane with Current Profile", "N", 2)]) == "New Window")
    }

    @Test("终端：「New Window」是个子菜单，按它里面快捷键是 ⌘N 的那一项")
    func terminalSubmenu() {
        let terminal = [item("New Window", submenu: true),
                        item("New Window with Profile - Clear Dark", "N", in: "New Window"),
                        item("New Window with Same Command", "N", 4, in: "New Window"),
                        item("Basic", in: "New Window"), item("Clear Dark", in: "New Window"),
                        item("New Command…", "N", 1), item("Close Window", "W")]
        #expect(picked(terminal) == "New Window with Profile - Clear Dark")
    }

    @Test("访达「New Finder Window」、Cursor「Open Editor Window」⇧⌘N")
    func otherWindowTitles() {
        #expect(picked([item("New Finder Window", "N"), item("New Folder", "N", 1), item("New Folder with Selection", "N", 4),
                        item("Open in New Window", "O", 4), item("Close Window", "W")]) == "New Finder Window")
        #expect(picked([item("New Agent", "N"), item("Open Editor Window", "N", 1), item("Switch Window…")]) == "Open Editor Window")
    }

    @Test("Claude 的「在新窗口中新建会话」没有快捷键，⌘N 是在当前窗口新建会话（11-24 读菜单）；移到、打开到新窗口的不认")
    func newConversationInNewWindow() {
        let claude = [item("新建会话", "N"), item("在新窗口中新建会话"), item("新建侧边对话"),
                      item("重新打开已关闭的会话", "T", 1), item("关闭会话", "W"), item("关闭窗口", "W", 1), item("全部关闭", "W", 1)]
        #expect(picked(claude) == "在新窗口中新建会话")
        #expect(picked([item("将标签页移到新窗口"), item("在新窗口中打开", "O", 4), item("合并所有窗口")]) == nil)
    }

    @Test("文本编辑的「New」：新建文稿就是新窗口")
    func newDocument() {
        #expect(picked([item("Quit and Keep Windows", "Q", 2), item("New", "N")]) == "New")
        #expect(picked([item("新建…", "N")]) == "新建…")
    }

    @Test("⌘N 是新建一条的不按：日历、备忘录、预览")
    func itemCreatorsSkipped() {
        #expect(picked([item("New Event or Reminder", "N"), item("Move Tab to New Window"), item("Merge All Windows")]) == nil)
        #expect(picked([item("New Note", "N"), item("New Folder", "N", 1)]) == nil)
        #expect(picked([item("New from Clipboard", "N"), item("Close Window", "W")]) == nil)
        #expect(picked([]) == nil)
    }

    @Test("只展开标题带「窗口」的子菜单")
    func worthOpening() {
        #expect(NewWindowMenu.worthOpening("New Window"))
        #expect(NewWindowMenu.worthOpening("使用配置文件新建窗口"))
        #expect(!NewWindowMenu.worthOpening("Open Recent"))
    }
}
