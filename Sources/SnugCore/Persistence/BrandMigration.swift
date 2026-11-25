// 从 Snug 迁到 PocketDesk：PocketDesk 第一次启动、自己还没有设置时，把 Snug 的设置拷过来。
// 只拷设置（config.json）和每个 App 记住的字号（zoom.json）；还原账（placed/、left-behind.json）记的是 Snug 自己放上去的窗口，
// 留给 Snug 还原，拷过来 PocketDesk 会去还原别人放的窗口。Snug 的目录只读不写，退回 Snug 照常用（回滚就是卸掉 PocketDesk）。
import Foundation

public enum BrandMigration {
    public enum Outcome: Equatable, Sendable {
        /// 拷过来了
        case copied
        /// PocketDesk 已经有自己的设置（迁过了，或者新装后用过），不动
        case alreadyThere
        /// 没装过 Snug（或者 Snug 还没写过设置），按新装处理
        case nothingToCopy
        /// Snug 的 config.json 解不开：不拷，坏文件留在原处给 Snug 自己隔离
        case sourceCorrupt
    }

    /// 屏名开头的品牌名：Snug 起的默认名（「Snug 手机屏」「Snug iPad」）迁过来换成 PocketDesk 的，用户自己起的不动
    static let oldPrefix = "Snug "

    /// 拷贝失败（磁盘满、没权限）抛错。config.json 最后写：它在就算迁过，半路失败下次启动还会再拷
    public static func run(from snug: SnugPaths, to pocket: SnugPaths, fileManager fm: FileManager = .default) throws -> Outcome {
        guard !fm.fileExists(atPath: pocket.config.path) else { return .alreadyThere }
        var config: AppConfig
        switch JSONFile<AppConfig>(url: snug.config).load() {
        case .missing: return .nothingToCopy
        case .corrupt: return .sourceCorrupt
        case .loaded(let loaded): config = loaded
        }
        for i in config.screens.indices {
            config.screens[i].name = rebrand(config.screens[i].name)
        }
        if fm.fileExists(atPath: snug.zoomBook.path) {
            try fm.createDirectory(at: pocket.dataDirectory, withIntermediateDirectories: true)
            if fm.fileExists(atPath: pocket.zoomBook.path) { try fm.removeItem(at: pocket.zoomBook) }
            try fm.copyItem(at: snug.zoomBook, to: pocket.zoomBook)
        }
        try JSONFile<AppConfig>(url: pocket.config).save(config)
        return .copied
    }

    static func rebrand(_ name: String) -> String {
        name.hasPrefix(oldPrefix) ? ScreenConfig.namePrefix + name.dropFirst(oldPrefix.count) : name
    }
}
