# PocketDesk 图标资源

| 文件 | 用途 |
|---|---|
| `AppIcon-1024.png` | App 图标 1024×1024 PNG（母版，含 macOS 圆角底板与阴影，底板外透明） |
| `AppIcon.icns` | macOS 应用图标，放进 `.app/Contents/Resources/`，并在 Info.plist 设 `CFBundleIconFile = AppIcon` |

界面里的其它图标（菜单栏、设置页、屏上面板）一律用 SF Symbols，不另外绘制。

## 设计说明

方案「口袋里的桌面」（3.0 起，改名 PocketDesk 时换的）：一扇 Mac 窗口插在口袋里，窗口里是一段对话（左边两条消息、右边一条蓝色回复），口袋带一道贴边和虚线缝线。底是蓝到青的渐变，和 Snug、CrossDesk 的白底图标放在一起认得出。

- 配色：底板 `#22D3FF → #1F63FF → #0638E8`（左上到右下），窗口和口袋是白到 `#E3ECFF`，缝线 `#9DB6EE`，回复条 `#1F63FF`
- 规格：1024 画布、824 底板（超椭圆 n = 5）；阴影下移 10、模糊 12、`#0B2A55` 不透明度 0.22
- 矢量源：宣传片仓库（kineto）的 `videos/snug-crossdesk/components/brand.tsx`，母版由那里的 Still `snug-crossdesk-appicon` 渲染

Snug 时期的「三屏叠片」图标留在 git 历史里。

重新生成 icns（`scripts/snug app` 只拷 icns，不从 PNG 生成）：

```bash
mkdir AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s AppIcon-1024.png --out AppIcon.iconset/icon_${s}x${s}.png
  sips -z $((s*2)) $((s*2)) AppIcon-1024.png --out AppIcon.iconset/icon_${s}x${s}@2x.png
done
iconutil -c icns AppIcon.iconset -o AppIcon.icns && rm -r AppIcon.iconset
```
