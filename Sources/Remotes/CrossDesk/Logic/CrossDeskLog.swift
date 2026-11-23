// CrossDesk 自己的日志（~/Library/Logs/CrossDesk/crossdesk.log，spdlog 默认格式「[年-月-日 时:分:秒.毫秒] [crossdesk] [级别] 内容」，本地时间）。
// 只给诊断用（--dump-remote、--check-remote）：在场判断看电源断言，不看日志。
// 最要紧的一条是它启动时读到了哪些显示器：它只在启动时读一次，之后加的屏看不到（源码 screen_capturer_sck_impl.mm），
// Snug 的屏不在这一批里，就要在屏建好之后重启 CrossDesk
import Foundation
import SnugCore

package struct CrossDeskLogRecord: Equatable, Sendable {
    package enum Event: Equatable, Sendable {
        /// 有控制端连上、开始抓屏（「Start screen capturer」）
        case captureStarted
        /// 最后一个控制端断开（「Last remote controller disconnected」）
        case lastControllerLeft
        /// 启动时读到一块显示器（「macOS display discovered: index=…, display_id=…」）
        case displayDiscovered(index: Int, display: DisplayID)
    }

    package var date: Date
    /// 认不出的内容为 nil
    package var event: Event?

    package static let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/CrossDesk/crossdesk.log")

    /// 不是这种格式的行（换行续写、别的程序写的）为 nil
    package init?(line: String) {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]"),
              let date = Self.dateFormat.date(from: String(line[line.index(after: line.startIndex)..<close])) else { return nil }
        self.date = date
        let message = Self.message(of: line[line.index(after: close)...])
        event = Self.event(in: message)
    }

    /// 最近一次启动时读到的显示器，按它的顺序。index 从 0 重新数起就是新的一批
    package static func lastEnumeration(_ records: [CrossDeskLogRecord]) -> [DisplayID] {
        var batch: [DisplayID] = []
        for record in records {
            guard case .displayDiscovered(let index, let display) = record.event else { continue }
            if index == 0 { batch = [] }
            batch.append(display)
        }
        return batch
    }

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// 去掉后面的「 [crossdesk] [info] 」两段
    private static func message(of rest: Substring) -> Substring {
        var rest = rest
        for _ in 0..<2 {
            rest = rest.drop { $0 == " " }
            guard rest.hasPrefix("["), let close = rest.firstIndex(of: "]") else { break }
            rest = rest[rest.index(after: close)...]
        }
        return rest.drop { $0 == " " }
    }

    private static func event(in message: Substring) -> Event? {
        if message.hasPrefix("Start screen capturer") { return .captureStarted }
        if message.hasPrefix("Last remote controller disconnected") { return .lastControllerLeft }
        guard message.hasPrefix("macOS display discovered:"),
              let index = number(after: "index=", in: message), let display = number(after: "display_id=", in: message),
              let id = DisplayID(exactly: display) else { return nil }
        return .displayDiscovered(index: index, display: id)
    }

    private static func number(after key: String, in text: Substring) -> Int? {
        guard let start = text.range(of: key)?.upperBound else { return nil }
        return Int(text[start...].prefix(while: \.isNumber))
    }
}
