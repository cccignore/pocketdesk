// 让出键盘后空出来的那块：窗口缩到键盘上方，手机键盘却要在远控里自己打开，这块在键盘弹起前露着。
// 盖上 Snug 的底色和一句怎么开键盘，不露 Mac 的桌面。手机键盘弹起后正好盖住它；键盘收起后点它铺回整屏
// （点得到它就说明键盘收起了）
import SnugCore
import SwiftUI

struct KeyboardTrayView: View {
    /// 远控说的怎么打开手机键盘（RemoteIdentity.keyboardHint），没说的给一句通用的
    let hint: String?
    /// 这一档比基准宽度宽几倍（ScreenFit.scale）：字在手机上看着一样大
    let scale: CGFloat
    let onLeave: () -> Void

    var body: some View {
        Button(action: onLeave) {
            VStack(spacing: 10 * scale) {
                Image(systemName: "keyboard")
                    .font(.system(size: 28 * scale, weight: .regular))
                Text(hint ?? "在手机上打开远控的键盘")
                    .font(.system(size: TouchTokens.Font.label.size * scale, weight: TouchTokens.Font.label.weight))
                    .foregroundStyle(TouchTokens.Color.label)
                Text("键盘收起后，点这里铺回整屏")
                    .font(.system(size: TouchTokens.Font.caption.size * scale, weight: TouchTokens.Font.caption.weight))
            }
            .foregroundStyle(TouchTokens.Color.secondaryLabel)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TouchTokens.Color.background)
        }
        .buttonStyle(PressableStyle())
    }
}
