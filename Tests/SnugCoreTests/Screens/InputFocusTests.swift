import Testing
@testable import SnugCore

@Suite("点完一下聚焦在哪 InputFocus、键盘让位跟着焦点 KeyboardFollow")
struct InputFocusTests {
    @Test("认焦点：文本框、文本区、可编辑的网页内容是输入框（Claude 的输入框读出来是 AXTextArea，11-24）；按钮、菜单、链接是控件；别的是内容；读不到为 nil")
    func classify() {
        #expect(InputFocus.of(role: "AXTextArea", subrole: nil, editable: true) == .text)
        #expect(InputFocus.of(role: "AXTextField", subrole: "AXSearchField", editable: false) == .text)
        #expect(InputFocus.of(role: "AXComboBox", subrole: nil, editable: false) == .text)
        // 网页里 contenteditable 的块：角色不是文本区，但在可编辑的区域里
        #expect(InputFocus.of(role: "AXGroup", subrole: nil, editable: true) == .text)
        #expect(InputFocus.of(role: "AXButton", subrole: nil, editable: false) == .control)
        #expect(InputFocus.of(role: "AXPopUpButton", subrole: nil, editable: false) == .control)
        #expect(InputFocus.of(role: "AXMenuItem", subrole: nil, editable: false) == .control)
        #expect(InputFocus.of(role: "AXLink", subrole: nil, editable: false) == .control)
        // 飞书点在聊天记录上，读出来是 AXWebArea（11-24）
        #expect(InputFocus.of(role: "AXWebArea", subrole: nil, editable: false) == .content)
        #expect(InputFocus.of(role: "AXScrollArea", subrole: nil, editable: false) == .content)
        #expect(InputFocus.of(role: nil, subrole: nil, editable: false) == nil)
    }

    @Test("从别处进了输入框就让出键盘，从输入框出来落在内容上就铺回；在输入框里再点（挪光标）不重复让")
    func entersAndLeaves() {
        var follow = KeyboardFollow()
        #expect(follow.observe(.content) == nil)
        #expect(follow.observe(.text) == true)
        #expect(follow.observe(.text) == nil)
        #expect(follow.observe(.content) == false)
        #expect(follow.observe(.content) == nil)
        #expect(follow.observe(.text) == true)
    }

    @Test("头一下就点在输入框里：让出键盘")
    func firstTapInInput() {
        var follow = KeyboardFollow()
        #expect(follow.observe(.text) == true)
    }

    @Test("点发送键、附件键（控件）、读不到焦点：不动，也不忘记是不是在输入框里")
    func controlsAndUnknownKeepState() {
        var follow = KeyboardFollow()
        #expect(follow.observe(.text) == true)
        #expect(follow.observe(.control) == nil)
        #expect(follow.observe(nil) == nil)
        #expect(follow.observe(.text) == nil)
        #expect(follow.observe(.content) == false)
        #expect(follow.observe(.control) == nil)
        #expect(follow.observe(.content) == nil)
    }

    @Test("这一下没做成（App 卡住）：让位没铺成，下次点进输入框再让；铺不回整屏，下次点在内容上再铺")
    func missedRetries() {
        var follow = KeyboardFollow()
        #expect(follow.observe(.text) == true)
        follow.missed(true)
        #expect(follow.observe(.text) == true)
        #expect(follow.observe(.content) == false)
        follow.missed(false)
        #expect(follow.observe(.content) == false)
        #expect(follow.observe(.content) == nil)
    }
}
