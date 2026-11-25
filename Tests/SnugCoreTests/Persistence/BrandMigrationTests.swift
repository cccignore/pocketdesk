import Foundation
import Testing
@testable import SnugCore

@Suite("从 Snug 迁到 PocketDesk")
struct BrandMigrationTests {
    private func paths(_ dir: URL, _ name: String) -> SnugPaths {
        SnugPaths(dataDirectory: dir.appendingPathComponent(name, isDirectory: true), logFile: dir.appendingPathComponent("\(name).log"))
    }

    private func snugConfig() -> AppConfig {
        var config = AppConfig()
        config.screens = [
            ScreenConfig(id: .phone, orientation: .portrait, device: .standard, name: "Snug 手机屏", serials: [200_000_108]),
            ScreenConfig(id: ScreenID("tablet"), orientation: .landscape, device: .standard, name: "书房的平板", serials: [200_100_000]),
        ]
        config.zoomSteps = 3
        config.welcomed = true
        return config
    }

    @Test("PocketDesk 还没有设置：拷来设置和字号记录，屏名开头的「Snug 」换成「PocketDesk 」；还原账不拷；Snug 的目录原样不动")
    func copiesSettings() throws {
        let dir = try TempDir()
        let snug = paths(dir.url, "Snug"), pocket = paths(dir.url, "PocketDesk")
        try JSONFile<AppConfig>(url: snug.config).save(snugConfig())
        try Data(#"{"com.mitchellh.ghostty":3}"#.utf8).write(to: snug.zoomBook)
        try FileManager.default.createDirectory(at: snug.placedRecords, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: snug.placedRecord(for: .phone))
        try Data("[]".utf8).write(to: snug.leftBehind)

        #expect(try BrandMigration.run(from: snug, to: pocket) == .copied)

        guard case .loaded(let moved) = JSONFile<AppConfig>(url: pocket.config).load() else { Issue.record("PocketDesk 的目录里应有 config.json"); return }
        #expect(moved.screens.map(\.name) == ["PocketDesk 手机屏", "书房的平板"])
        #expect(moved.screens.map(\.serials) == [[200_000_108], [200_100_000]])
        #expect(moved.zoomSteps == 3)
        #expect(moved.welcomed)
        #expect(try Data(contentsOf: pocket.zoomBook) == Data(#"{"com.mitchellh.ghostty":3}"#.utf8))
        // 还原账是 Snug 自己放上去的窗口，留给 Snug 还原
        #expect(!FileManager.default.fileExists(atPath: pocket.placedRecords.path))
        #expect(!FileManager.default.fileExists(atPath: pocket.leftBehind.path))
        guard case .loaded(let kept) = JSONFile<AppConfig>(url: snug.config).load() else { Issue.record("Snug 的 config.json 应还在"); return }
        #expect(kept == snugConfig())
        #expect(FileManager.default.fileExists(atPath: snug.placedRecord(for: .phone).path))
    }

    @Test("PocketDesk 已经有设置：不动它，也不再拷")
    func keepsExisting() throws {
        let dir = try TempDir()
        let snug = paths(dir.url, "Snug"), pocket = paths(dir.url, "PocketDesk")
        try JSONFile<AppConfig>(url: snug.config).save(snugConfig())
        var mine = AppConfig()
        mine.zoomSteps = 1
        try JSONFile<AppConfig>(url: pocket.config).save(mine)

        #expect(try BrandMigration.run(from: snug, to: pocket) == .alreadyThere)
        guard case .loaded(let kept) = JSONFile<AppConfig>(url: pocket.config).load() else { Issue.record("应读回原来的设置"); return }
        #expect(kept == mine)
    }

    @Test("没装过 Snug：什么都不做，按新装处理")
    func nothingToCopy() throws {
        let dir = try TempDir()
        let snug = paths(dir.url, "Snug"), pocket = paths(dir.url, "PocketDesk")
        #expect(try BrandMigration.run(from: snug, to: pocket) == .nothingToCopy)
        #expect(!FileManager.default.fileExists(atPath: pocket.config.path))
    }

    @Test("Snug 的 config.json 坏了：不拷，PocketDesk 从默认设置起；坏文件留在原处给 Snug 自己处理")
    func corruptSource() throws {
        let dir = try TempDir()
        let snug = paths(dir.url, "Snug"), pocket = paths(dir.url, "PocketDesk")
        try FileManager.default.createDirectory(at: snug.dataDirectory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: snug.config)

        #expect(try BrandMigration.run(from: snug, to: pocket) == .sourceCorrupt)
        #expect(!FileManager.default.fileExists(atPath: pocket.config.path))
        #expect(try Data(contentsOf: snug.config) == Data("{not json".utf8))
    }
}
