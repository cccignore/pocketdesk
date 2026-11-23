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

    /// 装着的 CrossDesk 的版本；没装为 nil，装了读不到版本为「版本未知」
    package static func installedVersion() -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: CrossDeskRemote.bundleID) else { return nil }
        return Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "版本未知"
    }

    /// 它自己的日志，滚动过的旧日志在前（spdlog 滚动：crossdesk.1.log 比 crossdesk.log 旧）；一份都读不到为 nil
    package static func logLines() -> [String]? {
        let current = CrossDeskLogRecord.path
        let rotated = current.deletingLastPathComponent().appendingPathComponent("crossdesk.1.log")
        let texts = [rotated, current].compactMap { try? String(contentsOf: $0, encoding: .utf8) }
        guard !texts.isEmpty else { return nil }
        return texts.flatMap { $0.split(separator: "\n").map(String.init) }
    }
}

/// 读不到电源断言：IOPMCopyAssertionsByProcess 的返回码（成功却交回了认不出的格式时也记成成功码）
package struct AssertionReadFailure: Error, Equatable, CustomStringConvertible {
    package var status: IOReturn
    package var description: String { "IOPMCopyAssertionsByProcess 返回 \(status)" }
}
