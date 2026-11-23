// 一拍里对 CrossDesk 的观测，怎么算在场，怎么交给核心。
// 在场只认它「正在共享桌面」的电源断言：有控制端连着、在抓屏时持有，最后一个控制端断开时放掉
// （源码 apps/desktop/src/gui/features/devices/screen_sharing_power.cpp）。本机去控制别人时它不抓屏，不持有。
// 日志里没有控制端的名字（INFO 级只记显示器），切屏也不记，所以控制端、推流屏都报不了
import Foundation
import SnugCore

package struct CrossDeskSignals: Equatable, Sendable, CustomStringConvertible {
    /// CrossDesk 在运行
    package var running: Bool
    /// 它持有「正在共享桌面」的电源断言。nil = 读不到（查电源断言失败）
    package var sharing: Bool?
    /// 这次启动登记了几块显示器（日志里的那一批）。nil = 没在运行、还没读到、读不到日志
    package var slots: Int?

    package init(running: Bool, sharing: Bool?, slots: Int? = nil) {
        self.running = running
        self.sharing = sharing
        self.slots = slots
    }

    package var isPresent: Bool { sharing == true }

    package func observation() -> RemoteObservation {
        RemoteObservation(present: isPresent, controllers: [], streamedDisplay: nil, evidence: description, displaySlots: slots)
    }

    package var description: String {
        "进程=\(running ? "在" : "不在") 共享桌面=\(sharing.map { $0 ? "是" : "否" } ?? "读不到")"
    }
}
