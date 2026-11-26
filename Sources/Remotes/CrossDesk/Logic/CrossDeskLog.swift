// CrossDesk 自己的日志（~/Library/Logs/CrossDesk/crossdesk.log，本地时间）。发布版（v1.7.6 真机）每行是
// 「[年-月-日 时:分:秒.毫秒] [crossdesk] [级别] [源文件:行号] 内容」，源码位置那段按 spdlog 默认格式可能没有，两种都认。
// 在场判断看电源断言，不看日志。日志用在两处：诊断（--dump-remote、--check-remote），和它这次启动登记了哪些显示器：
// 它只在启动时读一次，按当时的块数分位置（源码 screen_capturer_sck_impl.mm），Snug 的屏切不切得到看 RegisteredDisplays
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
        /// 读完显示器、抓屏初始化成功（「Init screen capturer success」）：这一批写完了
        case captureInitialized
        /// 给控制端发主机信息时列出本机显示器（「Local display [序号:名字]」）。只在有控制端会话时写：控制端连上时
        /// （peer_event_handler.cpp 的 BuildHostInformation，比开始抓屏早），之后分辨率变了重发（display_resolution_runtime.cpp，
        /// 没有控制端时直接返回）
        case hostAnnounced
    }

    /// 认这几种事件要的行里都有的字样：读日志时先按它挑出来再解析日期（日志最多约 20MB，逐行解析日期要好几秒）
    package static let enumerationMarkers = ["macOS display discovered:", "Init screen capturer success"]
    /// 认有没有控制端连着要的两种行（controllerConnected）
    package static let connectionMarkers = ["Local display [", "Last remote controller disconnected"]

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

    /// 最近一次启动时读到的显示器，按它的顺序（不管写没写完，诊断用）。index 从 0 重新数起就是新的一批
    package static func lastEnumeration(_ records: [CrossDeskLogRecord]) -> [DisplayID] {
        lastBatch(records)?.displays ?? []
    }

    /// 这次启动登记的显示器：最后一批在 since（这个进程的启动时刻）之后才开始读、而且抓屏初始化成功了。
    /// 刚启动还没写完、初始化失败（没有录屏权限）为 nil：只写了一半的那一批会少算块数
    package static func enumeration(since: Date, in records: [CrossDeskLogRecord]) -> [DisplayID]? {
        guard let batch = lastBatch(records), batch.start >= since, batch.complete else { return nil }
        return batch.displays
    }

    /// 这次启动（since 是这个进程的启动时刻）以来，最近连上的控制端断开了没有：最后一行发主机信息之后有「最后一个控制端断开」、
    /// 或者一直没人连过为 false，还没断开为 true。和它的锁屏是同一个状态：控制端连上时记下要锁屏，最后一个断开时（同一处写这一行）
    /// 才清掉，所以「还没断开」时退出它会锁屏。logStart 是读到的日志里最早一行的时刻：晚于启动（之前的滚动掉了）、读不到日志为 nil
    package static func controllerConnected(since: Date, in records: [CrossDeskLogRecord], logStart: Date?) -> Bool? {
        // 日志的时间戳精确到毫秒，系统记的启动时刻和它差不了一秒（同 CrossDeskRemoteAdapter 读登记的显示器）
        guard let logStart, logStart <= since.addingTimeInterval(1) else { return nil }
        let last = records.last { record in
            record.date >= since.addingTimeInterval(-1) && (record.event == .hostAnnounced || record.event == .lastControllerLeft)
        }
        return last?.event == .hostAnnounced
    }

    private static func lastBatch(_ records: [CrossDeskLogRecord]) -> (start: Date, displays: [DisplayID], complete: Bool)? {
        var batch: (start: Date, displays: [DisplayID], complete: Bool)?
        for record in records {
            switch record.event {
            case .displayDiscovered(let index, let display):
                if index == 0 || batch == nil || batch?.complete == true { batch = (record.date, [], false) }
                batch?.displays.append(display)
            case .captureInitialized:
                batch?.complete = true
            default:
                continue
            }
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

    /// 去掉后面的「 [crossdesk] [info] 」两段，和紧跟着的源码位置「[文件:行号]」（有的话）
    private static func message(of rest: Substring) -> Substring {
        var rest = rest
        for _ in 0..<2 { rest = dropBracket(rest) ?? rest }
        if let location = bracket(rest), let colon = location.lastIndex(of: ":"),
           !location[location.index(after: colon)...].isEmpty, location[location.index(after: colon)...].allSatisfy(\.isNumber),
           location[..<colon].contains(".") {
            rest = dropBracket(rest) ?? rest
        }
        return rest.drop { $0 == " " }
    }

    /// 开头那段方括号里的内容；开头不是方括号为 nil
    private static func bracket(_ text: Substring) -> Substring? {
        let text = text.drop { $0 == " " }
        guard text.hasPrefix("["), let close = text.firstIndex(of: "]") else { return nil }
        return text[text.index(after: text.startIndex)..<close]
    }

    private static func dropBracket(_ text: Substring) -> Substring? {
        let text = text.drop { $0 == " " }
        guard text.hasPrefix("["), let close = text.firstIndex(of: "]") else { return nil }
        return text[text.index(after: close)...]
    }

    private static func event(in message: Substring) -> Event? {
        if message.hasPrefix("Start screen capturer") { return .captureStarted }
        if message.hasPrefix("Last remote controller disconnected") { return .lastControllerLeft }
        if message.hasPrefix("Init screen capturer success") { return .captureInitialized }
        if message.hasPrefix("Local display [") { return .hostAnnounced }
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
