# CrossDesk 适配

[CrossDesk](https://github.com/kunkundi/crossdesk) 是开源（GPL-3.0）的跨平台远控，Mac 可被控，iPhone、iPad 有原生控制端。支持 P2P 直连加 TURN 中继、局域网 IP 直连（不经云端），也可以自建信令与中继服务。接入方式见 [接入新的远控](README.md)，核心怎么判定连接见 [工作原理](../how-it-works.md#连接判定)。

以下事实取自 CrossDesk 源码（`c17bd90`，2026-11-23），标注「未实测」的尚未在真机上核对。

| 位置 | 内容 |
| :--- | :--- |
| `Sources/Remotes/CrossDesk/Logic`（`RemoteCrossDesk`） | 身份 `CrossDeskRemote`、信号 `CrossDeskSignals`、手势整理 `CrossDeskShaper`、日志解析 `CrossDeskLogRecord`、自检判定 `CrossDeskCheck` |
| `Sources/Remotes/CrossDesk/System`（`RemoteCrossDeskSystem`） | 适配器 `CrossDeskRemoteAdapter`、进程与电源断言 `CrossDeskApp`、诊断 `CrossDeskDump` 与 `CrossDeskCheckRun` |
| `Tests/Remotes/CrossDesk`（`RemoteCrossDeskTests`） | 以上纯逻辑的测试，手势整理按 TouchPipeline 端到端跑 |

## 怎么用

1. 被控 Mac 装 CrossDesk（[Releases](https://github.com/kunkundi/crossdesk/releases) 的 `.pkg`），按提示授予屏幕录制与辅助功能权限；iPhone 从 App Store 装 CrossDesk，设置里鼠标模式选「绝对位置」
2. 装着 CrossDesk 时，Snug 屏幕列表里开着的屏常驻（见下文「屏常驻」），先让 Snug 把屏建好，再打开 CrossDesk。菜单栏出现「重启 CrossDesk」时点一下
3. 手机连上后，在 CrossDesk 的悬浮菜单里切换显示器，选 Snug 的屏
4. 不确定哪里不对时运行 `scripts/snug remote-check crossdesk`

## 身份

| 项 | 值 |
| :--- | :--- |
| 日志名 | `CrossDesk`（日志写「检测到 CrossDesk 连入」，命令行写 `crossdesk`） |
| 自家 App | `cn.crossdesk.app`，不出现在 App 资源库里 |
| 注入事件 | 按记号认：每个注入的鼠标、键盘事件的 `eventSourceUserData` 都是 `0x43524F5353444553`（'CROSSDES'）。Mac 上只有一个进程，界面、抓屏、注入都在里面，按进程名分不清 |
| 只在启动时读一次显示器 | 是（`readsDisplaysOnce`），见下文「屏常驻」 |

## 信号

- **在场**：有控制端连着、在抓屏时，CrossDesk 持有名为 `CrossDesk is sharing the desktop` 的电源断言（防系统和显示器空闲睡眠各一个），最后一个控制端断开时放掉。每拍用 `IOPMCopyAssertionsByProcess` 查一次，本机实测 0.7–2.4 毫秒；没在运行时不查。本机去控制别人时它不抓屏，不持有
- **控制端**：认不出。INFO 级日志不记控制端，界面上「此设备被控中」的面板没有接
- **推流屏**：报不了。切换显示器成功时不写日志；报 nil，资源库在每块 Snug 屏上都照常刷新
- **信号快照**：`进程=在 共享桌面=是`，写进连入、断开日志

## 手势整理

CrossDesk 的 iPhone 客户端（绝对位置模式）把手指操作发成这样（`apps/ios/CrossDeskMobile/Input/RemoteTouchInputView.swift`，Mac 端的转换见 `platform/macos/input/mouse/mouse_controller.cpp`）：

| 手指操作 | CrossDesk 发来的 | `CrossDeskShaper` 整理成 |
| :--- | :--- | :--- |
| 点一下 | 移动、左键按下、左键抬起，几乎同时 | 按下、抬起，翻译器判为点击 |
| 单指滑动 | 只有不按键的移动 | 拼成一笔（只能是滚动），停手 0.12 秒当松手，带惯性。每一下先压着等下一个事件：紧跟着按下的那一下是点按前导，扔掉。相邻两下隔得超过 100 点时看轨迹：和上一步大致同向、长度跟得上（快甩、中途丢了几下）是同一笔，掉头或一下跳出老远是两个手势；不看到达间隔，网络卡顿后两甩会挤在一起到 |
| 按住 | 0.35 秒时才发移动、左键按下，之后带左键移动 | 按下的时刻往前推 0.35 秒：按住满 0.5 秒松手是右键，再拖是选择 |
| 两指点、两指滑 | 右键、行滚动 | 不接管，原样放行 |

不按键的移动原样放行，指针跟着手指走（和 CrossDesk 本来一样），滚动晚一个事件开始。0.35 秒取自它的长按手势设置，0.12 秒是估的，都未实测。

## 打字

CrossDesk 的键盘弹起时不挪画面，键盘连同它加的「电脑键盘」工具条从画面底边往上盖住约 340 点（模拟器 iPhone 18 Pro 实测：键盘顶在 500 点，画面底边在 840 点），AI 应用底部的输入框正好被盖住。`CrossDeskRemote.clientInsets` 声明了这个高度，Snug 的手机屏在小横条右边给键盘键（见 [工作原理](../how-it-works.md#屏幕适配) 的「让出键盘」）：先点键盘键，窗口缩到键盘上方，再从 CrossDesk 的悬浮菜单打开键盘。键盘弹起后小横条也被盖住，要铺回整屏得先收起键盘。

ChatGPT 的窗口最小 600 点高，540 宽的屏上让出键盘后只剩 558 点，Snug 换到 590 宽放下它，整个输入框（含发送键）露在键盘上方；铺回整屏时换回 540。

## 屏常驻

CrossDesk 在启动时读一次显示器列表，按当时的数目注册视频流，之后加的屏它看不到、切不过去（`screen_capturer_sck_impl.mm`、`session_device_manager.cpp`）。Snug 平时是察觉连接后才建屏的，对 CrossDesk 来不及，所以：

- **常驻**：装着 CrossDesk 时，屏幕列表里开着的屏不等远程、一直留着（`ScreenPlan` 的 `resident`）
- **远程结束**：屏不撤，屏上的窗口放回原处、字号复原，回到 App 资源库；设为主屏的那块照旧原样留着
- **没人远程时**：常驻的屏本机看不见，指针停上去就收回
- **启动顺序**：CrossDesk 比 Snug 的屏先启动（开机时两个都自动打开）就看不到屏。Snug 每拍比较它的启动时刻和每块屏头一回上线的时刻，菜单栏在没人远程时给「重启 CrossDesk」：退出、等它退完、再打开
- **手势只接管装着的远控**：没装 CrossDesk 时不收不按键的移动，事件监听和只有 UU 时一样；装着时本机的指针移动也会经过 Snug 的事件监听（原样放行）

## 兼容自检

`scripts/snug remote-check crossdesk [小时]`（即 `Snug --check-remote crossdesk`），`--dump-remote crossdesk` 打印原始信号。

- **核对项**：装没装、在不在运行；读不读得到电源断言；Snug 在线的屏在不在 CrossDesk 最近一次启动时读到的显示器里（取自它的日志 `~/Library/Logs/CrossDesk/crossdesk.log` 中的 `macOS display discovered`）；回看时段内 CrossDesk 日志里的远程次数和 Snug 察觉到的次数
- **判定**：位于 `RemoteCrossDesk` 的 `CrossDeskCheck`

## 和 UU远程 不同、待真机核对的

- 屏幕比例的让位按 UU 的工具栏标定（`ScreenFit`）。CrossDesk 的画面铺法未实测，比例可能要另调
- CrossDesk 的远端分辨率设置会在最后一个控制端断开时把改过的显示器设回原模式；不要对 Snug 的屏用这个设置，Snug 自己会换档
- iPad 接了触控板或鼠标时，指针悬停也是不按键的移动，会被当成滑动
- 点一下的按下和抬起是两条消息：抬起比按下晚到 0.15 秒以上（网络重传）会被当成长按，点成右键
- 滑到一半停手超过 0.12 秒，这一笔就断开、按停手前的速度带惯性，再动是新的一笔
- 惯性中先来孤零零的一下移动（两指点右键的前导），0.12 秒内又在它 100 点以内点一下，这一下会点到内容
- 装上、卸掉远控时手势监听要重开，正按着的那一下、正在走的惯性随之丢掉
- 鼠标模式选「相对位置」时手指移动也是不按键的移动，会被当成滑动，所以要用「绝对位置」
- 在手机上「退出这块屏」会撤掉常驻的屏，CrossDesk 要重启才能再看到
