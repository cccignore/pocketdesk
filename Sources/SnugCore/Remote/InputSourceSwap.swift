// 远程期间临时换成英文输入法。有的远控把手机上打好的字当成「按键 + 文字」注入（RemoteIdentity.needsASCIIInputSource），
// Mac 正用着中文输入法时，输入法会拿这些按键再组一次字，打出来是乱的（CrossDesk 模拟器实测：手机上打「处理厂」，
// Mac 上出来「lx厂 lx」；换成 ABC 后一字不差）。中文在手机的键盘上打，Mac 这边只要收字。
// 远程开始时记下原来的、换成英文；结束时换回去。用户远程中途自己换过就不动，以用户为准
import Foundation

public struct InputSourceSwap: Equatable, Sendable {
    /// 换之前的输入法
    private var original: String?
    /// 换成的英文输入法
    private var applied: String?

    public init() {}

    /// 远程开始。current：此刻的输入法；currentIsASCII：它能不能直接打英文（ABC、美国英文这类键盘）；
    /// ascii：可以换成的英文输入法（没有为 nil）。返回要换成的，nil = 不用换
    public mutating func begin(current: String, currentIsASCII: Bool, ascii: String?) -> String? {
        guard original == nil, !currentIsASCII, let ascii, ascii != current else { return nil }
        original = current
        applied = ascii
        return ascii
    }

    /// 远程结束。current：此刻的输入法。返回要换回的，nil = 不用动（没换过，或者用户中途自己换了）
    public mutating func end(current: String) -> String? {
        defer { original = nil; applied = nil }
        guard let original, let applied, current == applied else { return nil }
        return original
    }
}
