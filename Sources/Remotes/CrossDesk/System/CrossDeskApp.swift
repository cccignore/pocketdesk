// CrossDesk 在本机的进程和它持有的电源断言。只读：不碰 CrossDesk
import AppKit
import IOKit.pwr_mgt
import RemoteCrossDesk
import SnugCore

@MainActor
package enum CrossDeskApp {
    /// 在运行的 CrossDesk（Mac 上只有一个进程）；没在运行为空
    package static func running() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: CrossDeskRemote.bundleID)
    }

    /// 这几个进程持有不持有「正在共享桌面」的电源断言；读不到时交回 IOPMCopyAssertionsByProcess 的返回码。
    /// 一次查询是一次到 powerd 的调用（每拍一次），没在运行时不查
    package static func sharing(pids: [pid_t]) -> Result<Bool, AssertionReadFailure> {
        guard !pids.isEmpty else { return .success(false) }
        var byProcess: Unmanaged<CFDictionary>?
        let status = IOPMCopyAssertionsByProcess(&byProcess)
        guard status == kIOReturnSuccess, let table = byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else {
            return .failure(AssertionReadFailure(status: status))
        }
        return .success(pids.contains { pid in
            (table[NSNumber(value: pid)] ?? []).contains { $0[kIOPMAssertionNameKey] as? String == CrossDeskRemote.sharingAssertion }
        })
    }

    /// 它的几份日志（CrossDeskRestartCheck.logNames）最后写入的时刻；读不到的为 nil。只读文件属性，不读内容
    package nonisolated static func logsWrittenAt() -> [(name: String, writtenAt: Date?)] {
        let folder = CrossDeskLogRecord.path.deletingLastPathComponent()
        return CrossDeskRestartCheck.logNames.map { name in
            let attributes = try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(name).path)
            return (name, attributes?[.modificationDate] as? Date)
        }
    }

    /// 它的「连接断开后锁屏」设置；读不到设置文件为 nil。它把设置放在 $XDG_CACHE_HOME/CrossDesk/config.ini，没设这个变量时是
    /// ~/.cache/CrossDesk/config.ini（platform/macos/path_backend.cpp）。在设置里改了就写这个文件，所以读到的就是它此刻用的
    package nonisolated static func lockOnDisconnect() -> Bool? {
        let cache = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache")
        guard let text = try? String(contentsOf: cache.appendingPathComponent("CrossDesk/config.ini"), encoding: .utf8) else { return nil }
        return CrossDeskRestartCheck.lockOnDisconnect(config: text)
    }

    /// 装着的 CrossDesk 的版本；没装为 nil，装了读不到版本为「版本未知」
    package static func installedVersion() -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: CrossDeskRemote.bundleID) else { return nil }
        return Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "版本未知"
    }

    /// 它自己的日志，滚动过的旧日志在前（spdlog 滚动，留 3 份：crossdesk.3.log 最旧，源码 log/rd_log.cpp）；一份都读不到为 nil。
    /// 启动时读到的显示器可能已经滚进旧日志，所以都读
    /// 认登记了哪些显示器要的那几种行（CrossDeskLogRecord.enumerationMarkers），先按字样挑出来再交给调用方解析：
    /// 日志按 5MB 滚动、留 3 份，逐行解析日期要好几秒。在后台线程上调
    package nonisolated static func enumerationLines() -> [String]? {
        logLines()?.filter { line in CrossDeskLogRecord.enumerationMarkers.contains { line.contains($0) } }
    }

    package nonisolated static func logLines() -> [String]? {
        let current = CrossDeskLogRecord.path
        let folder = current.deletingLastPathComponent()
        let rotated = (1...3).reversed().map { folder.appendingPathComponent("crossdesk.\($0).log") }
        let texts = (rotated + [current]).compactMap { try? String(contentsOf: $0, encoding: .utf8) }
        guard !texts.isEmpty else { return nil }
        return texts.flatMap { $0.split(separator: "\n").map(String.init) }
    }
}

/// 读不到电源断言：IOPMCopyAssertionsByProcess 的返回码（成功却交回了认不出的格式时也记成成功码）
package struct AssertionReadFailure: Error, Equatable, CustomStringConvertible {
    package var status: IOReturn
    package var description: String { "IOPMCopyAssertionsByProcess 返回 \(status)" }
}
