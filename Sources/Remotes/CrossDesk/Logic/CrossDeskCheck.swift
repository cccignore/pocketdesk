// CrossDesk 兼容自检（scripts/snug remote-check crossdesk → Snug --check-remote crossdesk）：Snug 依赖它的几处逐项核对，出一份报告。
// 这里只做判定，事实由系统部分（RemoteCrossDeskSystem 的 CrossDeskCheckRun）收集。
// 最常见的问题不是 CrossDesk 变了，而是它比 Snug 的屏先启动、看不到屏：它只在启动时读一次显示器（见 CrossDeskLogRecord）
import Foundation
import SnugCore

package enum CrossDeskCheck {
    package enum Status: Equatable, Sendable {
        case ok, warn, fail, info

        var symbol: String {
            switch self {
            case .ok: "✅"
            case .warn: "⚠️"
            case .fail: "❌"
            case .info: "ℹ️"
            }
        }
    }

    package struct Item: Equatable, Sendable {
        package var status: Status
        package var title: String
        package var detail: String
    }

    /// 系统部分收集到的事实
    package struct Facts: Sendable {
        /// CrossDesk 的版本；没装为 nil
        package var version: String?
        package var running: Bool
        /// 此刻的信号（电源断言）
        package var signals: CrossDeskSignals
        /// 它的日志读得到
        package var logReadable: Bool
        /// 它最近一次启动时读到的显示器
        package var enumerated: [DisplayID]
        /// 此刻在线的 Snug 的屏
        package var onlineSnugDisplays: Set<DisplayID>
        /// 此刻在线、能单独显示的屏一共几块（含 Snug 的，不含镜像组里的从属屏）
        package var onlineDisplays: Int
        /// 回看的这段时间里，它的日志记了几次远程开始（有控制端连上、开始抓屏）
        package var sessionsInLog: Int
        /// 同一段时间里，Snug 日志记了几次「检测到 CrossDesk 连入」
        package var detectionsInSnugLog: Int

        package init(version: String?, running: Bool, signals: CrossDeskSignals, logReadable: Bool, enumerated: [DisplayID],
                     onlineSnugDisplays: Set<DisplayID>, onlineDisplays: Int, sessionsInLog: Int, detectionsInSnugLog: Int) {
            self.version = version
            self.running = running
            self.signals = signals
            self.logReadable = logReadable
            self.enumerated = enumerated
            self.onlineSnugDisplays = onlineSnugDisplays
            self.onlineDisplays = onlineDisplays
            self.sessionsInLog = sessionsInLog
            self.detectionsInSnugLog = detectionsInSnugLog
        }
    }

    package static func evaluate(_ f: Facts) -> [Item] {
        guard let version = f.version else {
            return [Item(status: .fail, title: "CrossDesk", detail: "没装（应用程序里找不到 \(CrossDeskRemote.bundleID)）")]
        }
        return [
            Item(status: .ok, title: "CrossDesk", detail: "版本 \(version)"),
            f.running ? Item(status: .ok, title: "进程", detail: "在运行")
                : Item(status: .warn, title: "进程", detail: "没在运行：远程前要先打开它（它在 Mac 上只有这一个进程，界面、抓屏、键鼠都在里面）"),
            sharing(f.signals),
            screens(f),
            detection(f),
        ]
    }

    /// 报告正文：标题、结论、逐项
    package static func report(_ items: [Item], hours: Int, at date: Date) -> String {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "MM-dd HH:mm"
        let fails = items.filter { $0.status == .fail }.count
        let warns = items.filter { $0.status == .warn }.count
        let verdict = fails > 0 ? "发现 \(fails) 项问题" : warns > 0 ? "未发现问题，\(warns) 项需留意" : "未发现兼容问题"
        return (["CrossDesk 兼容自检 · \(stamp.string(from: date)) · 回看 \(hours) 小时", "结论：\(verdict)", ""]
            + items.map { "\($0.status.symbol) \($0.title)：\($0.detail)" }).joined(separator: "\n")
    }

    // MARK: 逐项

    private static func sharing(_ s: CrossDeskSignals) -> Item {
        switch s.sharing {
        case true?: Item(status: .ok, title: "共享桌面断言", detail: "此刻持有：有控制端连着")
        case false?: Item(status: .ok, title: "共享桌面断言", detail: "读得到，此刻没持有（没人在控制）")
        case nil: Item(status: .fail, title: "共享桌面断言", detail: "读不到电源断言：Snug 判断有没有人在控制全靠它")
        }
    }

    private static func screens(_ f: Facts) -> Item {
        let title = "看得到 Snug 的屏"
        guard !f.onlineSnugDisplays.isEmpty else {
            return Item(status: .warn, title: title, detail: "此刻没有 Snug 的屏在线：用 CrossDesk 时屏要一直挂着，看设置里屏幕是否开着")
        }
        guard f.logReadable else {
            return Item(status: .warn, title: title, detail: "读不到 CrossDesk 的日志（\(CrossDeskLogRecord.path.path)），看不出它启动时读到了哪些显示器")
        }
        // 它按启动时登记的几个位置切显示器，编号变了的屏落在同一位置照样切得到：只看块数够不够
        let unseen = f.onlineSnugDisplays.subtracting(f.enumerated).sorted().map { "#\($0)" }.joined(separator: "、")
        guard f.onlineDisplays <= f.enumerated.count else {
            return Item(status: .fail, title: title,
                        detail: "CrossDesk 启动时登记了 \(f.enumerated.count) 块显示器，此刻在线 \(f.onlineDisplays) 块（Snug 的屏 \(unseen)）："
                            + "多出来的它切不过去（它只在启动时读一次显示器），屏建好之后重启 CrossDesk")
        }
        let list = f.enumerated.map { "#\($0)" }.joined(separator: "、")
        guard unseen.isEmpty else {
            return Item(status: .ok, title: title,
                        detail: "它启动时读到 \(list)；Snug 的屏 \(unseen) 是之后换了编号的，落在它登记的位置里，在它的显示器菜单里照样切得到")
        }
        return Item(status: .ok, title: title, detail: "它启动时读到 \(list)，在线的 Snug 屏都在里面")
    }

    private static func detection(_ f: Facts) -> Item {
        let title = "连接检测"
        if f.sessionsInLog == 0 {
            return Item(status: .info, title: title, detail: "这段时间 CrossDesk 没被控制过（Snug 察觉到 \(f.detectionsInSnugLog) 次）：用手机连一次再回看")
        }
        if f.detectionsInSnugLog == 0 {
            return Item(status: .fail, title: title,
                        detail: "CrossDesk 日志里有 \(f.sessionsInLog) 次远程，Snug 一次都没察觉：电源断言的名字可能改了")
        }
        return Item(status: .ok, title: title, detail: "CrossDesk 日志里 \(f.sessionsInLog) 次远程，Snug 察觉到 \(f.detectionsInSnugLog) 次")
    }
}
