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

    /// 这个进程的「连接断开后锁屏」设置；读不到它的环境变量、设置文件为 nil。文件在哪按它自己的环境变量定
    /// （CrossDeskRestartCheck.configPath）。它在设置里改了先写文件、写成功才改内存（config_center.cpp），所以读到的就是它此刻用的
    package nonisolated static func lockOnDisconnect(pid: pid_t) -> Bool? {
        guard let environment = environment(of: pid), let path = CrossDeskRestartCheck.configPath(environment: environment),
              let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return CrossDeskRestartCheck.lockOnDisconnect(config: text)
    }

    /// 另一个进程的环境变量（KEY=VALUE），同一个用户的进程读得到；读不到为 nil。
    /// KERN_PROCARGS2 交回的是 argc（Int32），可执行文件路径，再是 argv、环境变量，都以 NUL 结尾、中间可能有补齐的 NUL
    private nonisolated static func environment(of pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        let argc = Int(buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        let strings = buffer[MemoryLayout<Int32>.size..<size].split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
        guard strings.count > argc else { return nil }
        return Array(strings.dropFirst(1 + argc))
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
