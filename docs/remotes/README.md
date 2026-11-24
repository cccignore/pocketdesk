# 接入新的远控

Snug 只对接 UU远程，但对接的部分是一层可替换的适配器：核心不认识任何一家远控，接一家新的主要是加它自己的适配器，多数情况下端口不用改（例外见下文「不在端口里的」一段）。UU远程 的适配器是现成的样板，见 [UU远程 适配](uu.md)；为什么这样切、考虑过哪些方案，见 [设计记录](../remote-adapter/README.md)。

## 分层

```
  手机 ── 远控 ──▶ Mac：进程、系统日志、界面、注入的鼠标事件
                   │
  适配器（每家一个）│  sample() 每 0.5 秒交一份中性的观测
                   ▼
  核心（各家共用）    RemoteSession 归属 → ConnectionTracker 连入 / 断开 → SessionEpisode 重连窗口
                   → ScreenPlan → DeskSet / ScreenSet 建屏、换档、撤屏；AppList 资源库排除；TouchTranslator
                   ▼
  系统层             虚拟屏、显示模式、窗口、事件监听（只接管登记的远控注入的事件）
```

## 端口

定义在 `Sources/SnugCore/Remote/RemoteAdapter.swift`。

| 类型 | 要交什么 |
| :--- | :--- |
| `RemoteIdentity` | 日志名（写进日志与命令行，不含空格、不和别家重名）；界面名；自家 App 的 bundle（不出现在资源库里）；注入事件怎么认（`InjectedEventSource`）；是不是只在启动时读一次显示器（`readsDisplaysOnce`，为真时屏常驻）；在手机上压住画面的部分（`clientInsets`，屏的比例按它让位，竖屏键盘盖住多高也在里面，默认是 UU 实测的工具栏）；注入文字时要不要把 Mac 换成英文输入法（`needsASCIIInputSource`）；在手机上怎么打开它的键盘（`keyboardHint`，一句话，让出键盘后空出来的那块上显示，只对声明了键盘高度的有意义） |
| `RemoteObservation` | 在不在场：只在有正面证据时为真；控制端：认不出为空；推流屏：不知道为 nil；信号快照：写进连入、断开日志；只在启动时读一次显示器的远控，这次启动登记的显示器（`registeredDisplays`，不知道为 nil，核心改按启动时刻判断要不要重启它；切不切得到见 `RegisteredDisplays`） |
| `RemoteAdapter` | 静态的 `identity`（身份属于这家远控，登记处、诊断命令、运行中的实例都从这里取）；`init()`；`start()`、`stop()`；`sample(wallClock:)` 每拍调一次；`makeTouchShaper()` 手势整理，默认原样直通 |
| `TouchShaper` | 定义在 `Sources/SnugCore/Touch/TouchShaper.swift`：把自家注入的原始指针事件整理成翻译器认的「按下 → 拖动 → 抬起」。要接管的事件种类、整理、不发抬起时的到点收尾。纯状态机，放各家的纯逻辑目标里，可以按 `TouchPipeline` 端到端测 |

不在端口里的：主屏策略、模式恢复、断开时序。这些按 UU远程 实测标定、各家暂时一样，留在共用代码里（[清单](uu.md#留在共用代码里的-uu-实测值)）；新的远控实测不同，改共用代码并补测试。手势形态已进端口：事件形态和 UU 不同的远控（CrossDesk 单指滑动只发不按键的移动，RustDesk 触摸模式同样）在自己的 `TouchShaper` 里整理，共用的翻译器不动，样板见 [CrossDesk 适配](crossdesk.md#手势整理)。注入事件有两种认法：按进程名（`InjectedEventSource(executableName:)`，UU 的 `UURemoteServer`），或按事件自带的 `eventSourceUserData` 记号（`InjectedEventSource(marker:)`，CrossDesk 给每个注入事件写同一个记号）。界面与服务是同一个可执行文件的远控用记号认。注意 Snug 补发事件时改写的是这个字段：记号写在事件源上的远控（RustDesk 实测）改不动，补发要改用自己的事件源重建，见[设计记录 12.4](../remote-adapter/README.md#124-已知疏漏手势只拆了一半)。

## 步骤

以 RustDesk 为例。名字只用英文字母，目录、目标、适配器类型、驱动都用它（门禁按 `Sources/Remotes` 下的目录名找）。

1. **目录**：`Sources/Remotes/RustDesk/Logic`（纯逻辑：信号怎么认、怎么算在场）、`Sources/Remotes/RustDesk/System`（调系统、实现 `RemoteAdapter`）、`Tests/Remotes/RustDesk`（纯逻辑的单测，至少一个文件：空目录进不了 git，别人克隆下来门禁会报目录对不上）
2. **`Package.swift`**：照 UU 的写法加三个目标并写明 `path`：`RemoteRustDesk` 依赖 `SnugCore`；`RemoteRustDeskSystem` 依赖 `RemoteRustDesk`、`SnugCore`、`SnugSystem`；`RemoteRustDeskTests` 依赖 `RemoteRustDesk`、`SnugCore`。另外 `Snug` 依赖 `RemoteRustDeskSystem`，`RemoteContractTests` 依赖 `RemoteRustDesk`
3. **适配器**：
   - 纯逻辑只 import Foundation 和 SnugCore，内容是身份和信号映射。身份（`RemoteIdentity`）定义在这里，只此一份（UU 见 `UURemote.identity`），适配器和契约驱动都引用它
   - 信号映射把原始信号变成 `RemoteObservation`（UU 见 `UUSignals.observation`）
   - 系统部分实现 `RemoteAdapter`，类型叫 `RustDeskRemoteAdapter`，`static let identity` 指向纯逻辑里那份，另写 `package init() {}`
   - 注入事件的进程和自家界面是同一个可执行文件时（RustDesk 就是），先照上文「不在端口里的」一段改核心和系统层
   - 内部类型用 `package`，不用 `public`
4. **登记**：`Sources/Snug/App/Remotes.swift` import `RemoteRustDeskSystem`，`all` 加一行 `Entry(adapter: RustDeskRemoteAdapter.self, dump: …, check: …)`，`dump`、`check` 是 `--dump-remote`、`--check-remote` 的实现（UU 见 `UUDump.run`、`UUCheckRun.run`）。登记顺序即两家同时报在场时的归属顺序
5. **契约测试**：`Tests/RemoteContractTests/Drivers/RustDeskDriver.swift`，照 `UUDriver` 实现 `RemoteDriver`（协议在 `RemoteDriver.swift`），把空闲、读不到、连入、推流几种情形翻译成它的原始信号，经它自己的映射交出观测；放进同一文件里的 `drivers`
6. **验收**：
   - `scripts/snug check` 全绿
   - `swift build && "$(swift build --show-bin-path)/Snug" --dump-remote rustdesk`（日志名，大小写都行），看读得到信号
   - `scripts/snug install` 装上带适配器的版本。没有 Developer ID 证书时用 ad-hoc 签名，每次重新构建都要重新授权辅助功能（见[开发文档](../development.md#构建与发布)）
   - 真机连一次，`~/Library/Logs/Snug.log` 里连入、会话、建屏、断开、撤屏几行对得上

## 提交

- **合进本仓库**：提 PR，写明接的是哪家远控、哪个版本，附 `scripts/snug check` 的结果和一次真机连接的 Snug.log 片段（连入到撤屏）；照 [uu.md](uu.md) 写一份 `docs/remotes/<名字小写>.md`（身份、信号、兼容自检、共用实测值是否相同）。作者只用 UU远程，别家的真机验证靠提交者
- **自己维护**：fork 后照上面的步骤接；MIT 许可，保留 LICENSE 里的版权声明即可

## 几家并存

一次远程只归一家（`RemoteSession`）：未连接时归登记顺序里第一家报在场的；已连接时不换，别家也报在场只记一条日志；重连等待期里换了一家连入，算同一次远程；远程结束清空归属。手势翻译接管所有登记的远控注入的事件。

## 防回潮

`scripts/snug check` 在构建之前先查：

- 核心（`SnugCore`）、系统层（`SnugSystem`）、核心测试的代码行不出现任何一家远控的名字：名字取 `Sources/Remotes` 下的目录名，按子串查，大小写都算。出处写在单独一行的注释里（`//`、`///`），跟在代码后面的注释也会被拦。撞上和远控无关的子串（`UUID`、Cursor 的 bundle `com.todesktop…`），加进 `scripts/snug` 里 `check_remote_boundaries` 的放行表 `allowed` 并写明是谁。bundle、进程名里不带这个名字的，门禁认不出，靠审查
- 只有 `Sources/Snug/App/Remotes.swift` 能 import 适配器（`@testable`、`@preconcurrency`、`internal import` 等写法同样算，只认行首的 import 语句）；核心测试只用假远控
- 适配器的纯逻辑只 import Foundation 和 SnugCore，目标只依赖 SnugCore
- 声明的测试目标与 `Tests/` 下的目录一一对应（`Package.swift` 交给 SwiftPM 解析，不限写法）
- `Sources/Remotes` 下每个目录：三个目标的名字与路径对得上、已登记、契约测试依赖它并有它的驱动（注释掉的登记、驱动不算）；叫 `Remote…` 的目标都在 `Sources/Remotes`、`Tests/Remotes` 下（契约测试 `RemoteContractTests` 除外）

类型引用由编译器拦：核心不依赖任何 `Remote*` 目标，写了也编译不过。
