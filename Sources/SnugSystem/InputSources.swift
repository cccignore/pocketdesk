// 键盘输入法（Text Input Sources）：读此刻用的、找能直接打英文的、切换。只在已经启用的输入法之间切，不增删、不改设置
import Carbon
import Foundation
import SnugCore

public enum InputSources {
    /// 此刻的输入法：ID 和它能不能直接打英文；读不到为 nil
    public static func current() -> (id: String, isASCII: Bool)? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(), let id = string(source, kTISPropertyInputSourceID) else { return nil }
        return (id, bool(source, kTISPropertyInputSourceIsASCIICapable))
    }

    /// 用户的英文键盘（系统按输入法设置挑的那一个，通常是 ABC）；没有为 nil
    public static func asciiCapable() -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        return string(source, kTISPropertyInputSourceID)
    }

    /// 换成这个已启用的输入法，交回换成了没有
    @discardableResult
    public static func select(_ id: String) -> Bool {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource], let source = list.first else {
            Log.warn("要换的输入法 \(id) 没有启用，没换")
            return false
        }
        let status = TISSelectInputSource(source)
        guard status == noErr else {
            Log.warn("换输入法 \(id) 失败（\(status)）")
            return false
        }
        return true
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    private static func bool(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let raw = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(raw).takeUnretainedValue())
    }
}
