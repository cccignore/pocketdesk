// 「新建窗口」按的是 App 菜单里的哪一项：按标题认，不按快捷键认。各 App 的快捷键不统一（11-14 读菜单实测）：
// Safari 是 ⌥⌘N，VS Code 是 ⇧⌘N（⌘N 是新建文件），终端藏在「Shell › New Window ›」子菜单里，Cursor 叫「Open Editor Window」；
// 备忘录、日历的 ⌘N 是新建一条备忘录、日程，按了会留下一条空白的，所以不按。读菜单在 SnugSystem（AX），这里只管挑
import Foundation

/// 菜单里的一项
public struct MenuCommand: Equatable, Sendable {
    public let title: String
    /// 快捷键的字符，没有快捷键为 nil
    public let key: String?
    /// 快捷键的修饰键，辅助功能的位：1 ⇧、2 ⌥、4 ⌃、8 不带 ⌘
    public let modifiers: Int
    /// 它自己是个子菜单（终端的「New Window ›」），按它没用
    public let opensSubmenu: Bool
    /// 在哪一项的子菜单里，顶层为 nil
    public let parent: String?

    public init(title: String, key: String? = nil, modifiers: Int = 0, opensSubmenu: Bool = false, parent: String? = nil) {
        self.title = title
        self.key = key
        self.modifiers = modifiers
        self.opensSubmenu = opensSubmenu
        self.parent = parent
    }
}

public enum NewWindowMenu {
    /// 要不要展开这一项的子菜单找：只看标题带「窗口」的（大 App 的菜单有上千项，不能全展开）
    public static func worthOpening(_ title: String) -> Bool { mentionsWindow(title) }

    /// 挑出「新建窗口」那一项，返回下标；没有返回 nil（这个 App 没有新建窗口，或 ⌘N 只是新建一条）。
    /// 由准到宽一档档找，同一档里有快捷键的优先、修饰键少的优先
    public static func pick(_ items: [MenuCommand]) -> Int? {
        let tiers: [(MenuCommand) -> Bool] = [
            // 「New Window / 新建窗口」，或这一项的子菜单里的（终端）
            { isNewWindow($0.title) || $0.parent.map(isNewWindow) == true },
            // 「New Finder Window」
            { startsNew($0.title) && mentionsWindow($0.title) },
            // Claude 的「在新窗口中新建会话」：⌘N 是在当前窗口新建会话（11-24 读菜单）
            { $0.title.contains("新窗口") && $0.title.contains("新建") },
            // Cursor 的「Open Editor Window」⇧⌘N
            { mentionsWindow($0.title) && $0.key?.uppercased() == "N" },
            // 文本编辑的「New」：新建文稿就是开一个新窗口
            { isNewDocument($0.title) && $0.key?.uppercased() == "N" && $0.modifiers == 0 },
        ]
        for tier in tiers {
            let matches = items.indices.filter { !items[$0].opensSubmenu && tier(items[$0]) }
            if let best = matches.min(by: { rank(items[$0]) < rank(items[$1]) }) { return best }
        }
        return nil
    }

    private static func rank(_ item: MenuCommand) -> (Int, Int) {
        (item.key?.isEmpty == false && item.modifiers & 8 == 0 ? 0 : 1, item.modifiers.nonzeroBitCount)
    }

    private static func normalized(_ title: String) -> String {
        title.lowercased().trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "….")))
    }

    private static func isNewWindow(_ title: String) -> Bool { ["new window", "新建窗口"].contains(normalized(title)) }
    private static func startsNew(_ title: String) -> Bool { normalized(title).hasPrefix("new ") || title.hasPrefix("新建") }
    private static func mentionsWindow(_ title: String) -> Bool { normalized(title).contains("window") || title.contains("窗口") }
    private static func isNewDocument(_ title: String) -> Bool { ["new", "新建", "new document", "新建文稿"].contains(normalized(title)) }
}
