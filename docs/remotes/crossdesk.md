# CrossDesk 适配

[CrossDesk](https://github.com/kunkundi/crossdesk) 是开源（GPL-3.0）的跨平台远控，Mac 可被控，iPhone、iPad 有原生控制端。支持 P2P 直连加 TURN 中继、局域网 IP 直连（不经云端），也可以自建信令与中继服务。接入方式见 [接入新的远控](README.md)，核心怎么判定连接见 [工作原理](../how-it-works.md#连接判定)。

以下事实取自 CrossDesk 源码（`c17bd90`，2026-11-23），标注「未实测」的尚未在真机上核对。

| 位置 | 内容 |
| :--- | :--- |
| `Sources/Remotes/CrossDesk/Logic`（`RemoteCrossDesk`） | 身份 `CrossDeskRemote`、信号 `CrossDeskSignals`、手势整理 `CrossDeskShaper`、日志解析 `CrossDeskLogRecord`、自检判定 `CrossDeskCheck`、重启前的现场确认 `CrossDeskRestartCheck` |
| `Sources/Remotes/CrossDesk/System`（`RemoteCrossDeskSystem`） | 适配器 `CrossDeskRemoteAdapter`、进程与电源断言 `CrossDeskApp`、诊断 `CrossDeskDump` 与 `CrossDeskCheckRun` |
| `Tests/Remotes/CrossDesk`（`RemoteCrossDeskTests`） | 以上纯逻辑的测试，手势整理按 TouchPipeline 端到端跑 |

## 怎么用

1. 被控 Mac 装 CrossDesk（[Releases](https://github.com/kunkundi/crossdesk/releases) 的 `.pkg`），按提示授予屏幕录制与辅助功能权限；iPhone 从 App Store 装 CrossDesk（中国大陆区商店没有上架，香港、台湾、日本、新加坡、美国区有，11-24 查为 1.7.6；没有其他区账号的，按上游 `apps/ios/README.md` 用 Xcode 自己签名装），设置 →「鼠标控制」的控制模式选「绝对位置」（连接中也可以在悬浮菜单里把「相对鼠标」点成「绝对鼠标」，按钮上写的是当前模式，选过会记住）
2. 装着 CrossDesk 时，Snug 屏幕列表里开着的屏常驻（见下文「屏常驻」）。CrossDesk 比屏先启动、看不到屏时，没人远程的话 Snug 会自动重启它，不用管先开哪个。自动重启要先在 CrossDesk 设置里关掉「连接断开后锁屏」（见下文「自动重启」）；开着这一项、或者自动重启没成时，菜单栏留着「重启 CrossDesk」，点一下
3. 手机连上后，在 CrossDesk 的悬浮菜单里切换显示器，选 Snug 的屏
4. 不确定哪里不对时运行 `scripts/snug remote-check crossdesk`

两端默认连 CrossDesk 的公共信令服务器（`api.crossdesk.cn:9099`，Mac 端见 `config_center.h`，iPhone 端见 `RemoteSessionModel.swift` 的 `officialSignalHost`），直连不通时走它的 TURN 中继，不用配置。要自建信令与中继，见上游 `docs/SELF_HOSTING.md`，两端要连同一个服务。

Mac 端 CrossDesk 设置里的「连接断开后锁屏」默认开着（`config_center.h` 的 `lock_on_disconnect`）：最后一个控制端断开时 Mac 锁屏（`connection_runtime.cpp` 的 `HandleScreenLock`）。Snug 照常收尾，下次连上要先解锁。登录框在主屏上，手机上要在显示器菜单里切到主屏输入密码（未实测）。这个设置开着时，有控制端连着就退出 CrossDesk 同样会锁屏（`gui_application.cpp` 的 `Cleanup` 先断开所有会话再 `HandleScreenLock`），所以 Snug 只在这一项关着时才自动重启它（见下文「自动重启」）。

## 身份

| 项 | 值 |
| :--- | :--- |
| 日志名 | `CrossDesk`（日志写「检测到 CrossDesk 连入」，命令行写 `crossdesk`） |
| 自家 App | `cn.crossdesk.app`，不出现在 App 资源库里 |
| 注入事件 | 按记号认：每个注入的鼠标、键盘事件的 `eventSourceUserData` 都是 `0x43524F5353444553`（'CROSSDES'）。Mac 上只有一个进程，界面、抓屏、注入都在里面，按进程名分不清 |
| 只在启动时读一次显示器 | 是（`readsDisplaysOnce`），见下文「屏常驻」 |
| 画面让位 | `clientInsets`：iPhone 客户端把画面等比铺在安全区里（`RemoteSessionView.swift`），按灵动岛机型让位，竖屏上下共 96 点、横屏左右共 124 点、上下共 21 点；键盘盖住约 340 点（见下文「打字」）。模拟器 iPhone 18 Pro 实测画面从 707 点高变成 777 点高，只剩灵动岛和底部横条两条黑边 |
| 输入法 | `needsASCIIInputSource`：它把手机上打好的字按键码 0 加文字注入（`keyboard_capturer.cpp`），Mac 用中文输入法时会被再组一次字。远程期间 Snug 把 Mac 换成英文输入法（见 [工作原理](../how-it-works.md#输入法)） |

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
| 单指滑动 | 只有不按键的移动 | 拼成一笔（只能是滚动），停手 0.12 秒当松手，带惯性。每一下先压着等下一个事件：紧跟着按下的那一下是点按前导，扔掉。相邻两下隔得超过 100 点时尽量只看轨迹，不看到达间隔（丢包、成批到达、卡住后隔几毫秒放出都会打乱它）：上一步看得出方向，大致同向、长度跟得上就是同一笔（快甩、中途丢了几下都算）；上一步太短时掉了头就是两个手势，不掉头的隔了 50 毫秒以上才算两个；前一甩卡住后才到的尾巴（从它终点附近冒出来、还看不出方向）不连到后面跳得远的一下；接上的远的一步等下一下到了才交出去，下一下紧接着掉头就说明它是两次落指之间的空当，前一笔收在它之前。场景表见 `CrossDeskShaperScenarioTests` |
| 按住 | 0.35 秒时才发移动、左键按下，之后带左键移动 | 按下的时刻往前推 0.35 秒：按住满 0.5 秒松手是右键，再拖是选择 |
| 两指点、两指滑 | 右键、行滚动 | 不接管，原样放行 |

不按键的移动原样放行，指针跟着手指走（和 CrossDesk 本来一样），滚动晚一个事件开始。0.35 秒取自它的长按手势设置，0.12 秒是估的，都未实测。

## 打字

CrossDesk 的键盘弹起时不挪画面，键盘连同它加的「电脑键盘」工具条从画面底边往上盖住约 340 点（模拟器 iPhone 18 Pro 实测：键盘顶在 500 点，画面底边在 840 点），AI 应用底部的输入框正好被盖住。`CrossDeskRemote.clientInsets` 声明了这个高度，Snug 的手机屏在小横条右边给键盘键（见 [工作原理](../how-it-works.md#屏幕适配) 的「让出键盘」）：点进输入框时 Snug 自动把窗口缩到键盘上方（也可以先点键盘键），空出来的那块写着「点 CrossDesk 的悬浮球，选「键盘」」，再从悬浮菜单打开键盘。先开了键盘、输入框本来就有焦点时，一打字 Snug 就让位。CrossDesk 的手机键盘只能从悬浮菜单打开，它的协议里没有让电脑端弹出手机键盘的消息（`RemoteSessionView.swift` 里只有悬浮菜单的「键盘」改 `keyboardInputVisible`），也没有手势、URL 能打开它，所以 Snug 只能先让位。键盘弹起后小横条和托盘都被盖住，要铺回整屏得先收起键盘（键盘条右边的键盘键），再点托盘。键盘开着时点对话内容不收起键盘（点击照常落在 Mac 上），所以打过字以后点内容不铺回整屏。模拟器 iPhone 18 Pro 上拼音键盘（带候选栏）和英文键盘一样高，顶边位置一样（截图上量在 500 点上下）。真机键盘比声明的矮时，托盘会在键盘上方露出一条，点它会在键盘开着时铺回整屏。

ChatGPT 的窗口最小 600 点高，540 宽的屏上让出键盘后只剩 558 点，Snug 换到 590 宽放下它，整个输入框（含发送键）露在键盘上方；铺回整屏时换回 540。

## 屏常驻

CrossDesk 在启动时读一次显示器列表，按当时的数目注册视频流（一块一个位置），之后多出来的屏它切不过去（`screen_capturer_sck_impl.mm`、`session_device_manager.cpp`）。位置里原来那块屏不在了，它改抓列表里同一位置上的屏，所以 Snug 重启后屏换了编号，在它的显示器菜单里照样切得到（模拟器实测：#22 换成 #23，手机重连后切到第 2 块，画面是新屏）。Snug 平时是察觉连接后才建屏的，对 CrossDesk 来不及，所以：

- **常驻**：装着 CrossDesk 时，屏幕列表里开着的屏不等远程、一直留着（`ScreenPlan` 的 `resident`）
- **远程结束**：屏不撤，屏上的窗口放回原处、字号复原，回到 App 资源库；设为主屏的那块照旧原样留着
- **没人远程时**：常驻的屏本机看不见，指针停上去就收回
- **启动顺序**：CrossDesk 比 Snug 的屏先启动（开机时两个都自动打开）就少登记了 Snug 的屏。适配器在 CrossDesk 每次启动后到后台读一次它的日志，报这次登记了哪些显示器（`RemoteObservation.registeredDisplays`，取抓屏初始化成功了的那一批）。Snug 的屏登记过的切得到；没登记过的要正好落在一个原来那块已经不在的位置上（此刻显示器列表里同一序号，`RegisteredDisplays`），落不上时 Snug 在没人远程时自动重启它（见下一条）。之后接上的外接屏、随航不算，只在占了空出的位置时影响判断。日志还没读回来、读了 5 次都没找到这一批时按启动时刻比：它比哪块屏这一次上线早就提示。序号按能单独显示的屏（去掉镜像从属屏）的顺序，当它和 CrossDesk 用的 ScreenCaptureKit 一致（模拟器实测 Snug 重启后补上的正是列表里的第 2 块）。CrossDesk 补过位后会改记那个位置抓的是哪块，Snug 只按启动时登记的算，补过位之后又重建了屏时可能判错（未实测）
- **自动重启**：CrossDesk 看不到 Snug 的屏、又没人远程时，Snug 自动重启它：退出、等它退完（最多 10 秒）、再打开（不抢前台），3 秒后还在运行才算成。每个决定在日志里记一行「自动重启 CrossDesk：……」，写明为什么重启、为什么先不重启。判定在 `SnugCore` 的 `AutoRestart`：
  - 远程中（含断开后等重连的 15 秒）不重启，等远程结束
  - 只在 CrossDesk 关着「连接断开后锁屏」时自动重启（读它的 `~/.cache/CrossDesk/config.ini` 的 `lock_on_disconnect`，节名、键名不分大小写；文件位置按 CrossDesk 进程自己的 `XDG_CACHE_HOME`、`HOME` 定，读不到按它的默认当作开着）。开着时有控制端连着就退出它会锁屏，而有没有控制端连着从外面没法完全确认：控制端一连上它就记下了要锁屏（`peer_event_handler.cpp` 的 `disconnect_lock_.Connected`），电源断言要等分辨率设好、开始抓屏才持有（最多约 2 秒，`display_resolution_state.h`），没有屏幕录制权限时一直不持有、日志也不写。关着时锁屏请求根本不会记下（`disconnect_lock_policy.h` 两头都看这一项），退出它不会锁屏。开着时日志里记一行原因，只留菜单栏的手动「重启」
  - 不断掉正在进行的远程：动手前适配器现场确认一次（`restartBlocker`，判定在 `CrossDeskRestartCheck`），读得到电源断言、没持有，并且 `~/Library/Logs/CrossDesk/` 下的 `crossdesk.log`、`minirtc.log` 都静了 10 秒以上（有人在连时握手一直在写，真机 11-26：`minirtc.log` 在持有断言前 1.4 秒写下「Remote user joined transmission」；没人时都静着）。确认不了就等，退出它的前一刻再确认一次
  - 看不到要持续 5 秒才动手：几块屏陆续建好、它的日志还在后台读时结论会变，这一批屏变了就重新等
  - 同一批屏只重启一次（Snug 每次建屏编号都会变，新编号就是新的一批；记得最近 8 批，手动点的「重启」也算），两次重启至少隔 60 秒
  - 退不掉、打不开、打开后 3 秒内又退出，或者重启后还是看不到，这一批屏不再自动重启，菜单栏在没人远程时给「重启 CrossDesk」手动点（打不开时它已经退出了，要手动打开 CrossDesk）。手动点的也先确认一次（开着「连接断开后锁屏」也算确认不了），确认不了就弹窗说明原因，默认「取消」，点「仍要重启」才退出它
- **远程中 Snug 重启**：屏撤掉的那一刻 CrossDesk 改抓内建屏（同一路视频流），手机上的画面换成 Mac 的主屏、比例不对。新屏建好后在 CrossDesk 的显示器菜单里再选一次 Snug 的屏，或者断开重连
- **手势只接管装着的远控**：没装 CrossDesk 时不收不按键的移动，事件监听和只有 UU 时一样；装着时本机的指针移动也会经过 Snug 的事件监听（原样放行）

## 兼容自检

`scripts/snug remote-check crossdesk [小时]`（即 `Snug --check-remote crossdesk`），`--dump-remote crossdesk` 打印原始信号。

- **核对项**：装没装、在不在运行；读不读得到电源断言；Snug 在线的屏 CrossDesk 切不切得到（按它最近一次启动时登记的显示器判，取自它的日志 `~/Library/Logs/CrossDesk/crossdesk.log` 中的 `macOS display discovered`），换了编号的屏占原来那块的位置照样算切得到；回看时段内 CrossDesk 日志里的远程次数和 Snug 察觉到的次数
- **判定**：位于 `RemoteCrossDesk` 的 `CrossDeskCheck`

## 和 UU远程 不同、待真机核对的

- 画面让位按灵动岛机型的安全区算。刘海屏（顶部约 47 点）、带 Home 键（顶部 20 点、底部 0）的 iPhone 安全区不同，上下会多出几十点黑边；键盘高度按模拟器量（英文、拼音一样高），带 Home 键机型的键盘高度未实测
- CrossDesk 的手机端在 Mac 报告指针隐藏时照样画它自己的触控指针（`RemoteSessionView.swift` 的 `visibleCursorShape`），Snug 藏不掉画面上的箭头
- CrossDesk 自带更新检查，夜里从 1.7.6 升到了 1.7.7。升级后先跑一次 `scripts/snug remote-check crossdesk`，确认电源断言的名字、日志格式没变
- CrossDesk 的远端分辨率设置会在最后一个控制端断开时把改过的显示器设回原模式；不要对 Snug 的屏用这个设置，Snug 自己会换档
- iPad 接了触控板或鼠标时，指针悬停也是不按键的移动，会被当成滑动
- 点一下的按下和抬起是两条消息：抬起比按下晚到 0.15 秒以上（网络重传）会被当成长按，点成右键
- 滑到一半停手超过 0.12 秒，这一笔就断开、按停手前的速度带惯性，再动是新的一笔
- 网络卡顿下还会分错的（第九、十轮审查的随机网络模型，场景表里标成已知问题）：
  - 会跳一大步：卡 0.5–2 秒后前一甩只剩一两下尾巴、后一甩隔 6–20 毫秒放出一下时反向跳 400–800 点（这种卡法的随机种子里约 8%）；快甩最后一下单独卡在后面时反向跳 450–570 点（约 3–4%）；快甩后手指顺势往前落、马上往回甩，往前跳约 200 点（网络正常也会，多常见没验证）
  - 不跳的：一笔中途卡 0.15–0.3 秒、卡点正好在加速段，少滚一步；一甩收尾后 0.5 秒内在终点附近马上往回快甩，第一下被扔掉；慢拖后快速往回又丢了一两下，拆成两笔
  - 惯性中在前方点一下、按下比移动晚到 0.13 秒以上（分在两个包）时，这一下会点到内容
  - 试过「接上远的一步后下一下掉头就回头收笔」，能修前两种跳步，但会让快甩完马上点停时点到内容，没用。要先拿真机录的事件时序再定规则
- 惯性中先来孤零零的一下移动（两指点右键的前导），0.12 秒内又在它 100 点以内点一下，这一下会点到内容
- 装上、卸掉远控时手势监听要重开，正按着的那一下、正在走的惯性随之丢掉
- 鼠标模式选「相对位置」时手指移动也是不按键的移动，会被当成滑动，所以要用「绝对位置」
- 在手机上「退出这块屏」会撤掉常驻的屏，下次建出来的新屏 CrossDesk 要重启才看得到，Snug 等这次远程结束后自动重启它
- 自动重启前确认没人正在连靠的是两份日志的写入时刻，没有屏幕录制权限时连上的控制端（抓屏起不来、日志静着）看不出来，赶上自动重启会被断开（关着「连接断开后锁屏」，不会锁屏）。局域网 IP 直连的握手看源码也写进 `minirtc.log`（`lan_runtime.cpp` 用同一个日志路径建连接），未实测
- CrossDesk 升级后核对设置文件的位置和 `lock_on_disconnect` 这个名字（`CrossDeskRestartCheck`）。新版换了名字时，文件里留下的旧名字仍写着关着，Snug 会当它关着，它却按新名字的默认开着
- 本机正用 CrossDesk 控制别的设备时它不持有断言，日志也可能静着，赶上自动重启会断掉那一路（锁屏只管连进来的控制端，不会锁屏）
