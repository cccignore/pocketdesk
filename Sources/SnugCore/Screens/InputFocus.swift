// 手机上点完一下，屏上那个窗口的 App 聚焦在什么上：键盘让位跟着它走（Desk.followFocus）。
// 远控（CrossDesk）的手机键盘只能在手机上打开，Mac 这边弹不出来；Snug 能做的是点进输入框时先把窗口缩到键盘上方，
// 打开键盘时输入框已经露在上面。读焦点在 SnugSystem（AppService.inputFocus，辅助功能），这里只管认和判
import Foundation

public enum InputFocus: Equatable, Sendable {
    /// 能打字的：文本框、文本区、可编辑的网页内容（Claude 的输入框读出来是 AXTextArea，11-24 实测）
    case text
    /// 按钮、菜单、链接这类点完就完的：点发送键、附件键时不铺回整屏
    case control
    /// 别的：对话内容、网页正文（飞书点在聊天记录上读出来是 AXWebArea，11-24 实测）
    case content

    private static let textRoles: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox"]
    private static let controlRoles: Set<String> = [
        "AXButton", "AXPopUpButton", "AXMenuButton", "AXCheckBox", "AXRadioButton", "AXDisclosureTriangle",
        "AXMenu", "AXMenuItem", "AXMenuBarItem", "AXLink", "AXSlider", "AXIncrementor",
    ]

    /// role、subrole：聚焦元素的辅助功能角色，读不到 role 交回 nil。editable：它在可编辑的区域里（有 AXEditableAncestor），
    /// 网页里 contenteditable 的块角色常是 AXGroup
    public static func of(role: String?, subrole: String?, editable: Bool) -> InputFocus? {
        guard let role else { return nil }
        if textRoles.contains(role) || editable { return .text }
        return controlRoles.contains(role) ? .control : .content
    }
}

/// 键盘让位跟着焦点走：从别处进了输入框就让出键盘，从输入框出来落在内容上就铺回整屏；落在控件上、读不到的不动。
/// 只在进出输入框的那一下动：手动按过键盘键后，焦点没进出输入框就不改回去
public struct KeyboardFollow: Equatable, Sendable {
    /// 上一次读到的焦点在不在输入框里，还没读到过为 nil
    private var inText: Bool?

    public init() {}

    /// 这一下要不要让位：true 让出键盘、false 铺回整屏、nil 不动
    public mutating func observe(_ focus: InputFocus?) -> Bool? {
        switch focus {
        case .text:
            defer { inText = true }
            return inText == true ? nil : true
        case .content:
            defer { inText = false }
            return inText == true ? false : nil
        case .control, nil:
            return nil
        }
    }

    /// 这一下要的没做成（App 卡住，让位没铺成或铺不回整屏）：下次读到同样的焦点再试
    public mutating func missed(_ want: Bool) {
        inText = want ? nil : true
    }
}
