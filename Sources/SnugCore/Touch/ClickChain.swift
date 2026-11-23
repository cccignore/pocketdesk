// 补发点击时的连击计数。远控自己按时间、位置数连击（CrossDesk 的 Mac 端 500 毫秒、8 像素以内算连击，最多数到 3），
// Snug 吞掉的那一下（惯性中点一下只停住，见 TouchTranslator）它照样数进去了：不改的话 App 看到的是孤零零的双击、三击。
// 吞掉之后这一串连击补发时都减掉吞掉的数；远控从 1 重新数起时这一串结束。没吞过就原样，不碰
public struct ClickChain: Equatable, Sendable {
    private var skipped: Int64 = 0

    public init() {}

    /// TouchCommand.resetClickCount：接下来补发的这一下远控数到 raw，前面吞掉的不该算
    public mutating func skip(before raw: Int64) {
        skipped = max(0, raw - 1)
    }

    /// 补发一个按下或抬起：远控数的是 raw，交回 App 该看到的数
    public mutating func count(_ raw: Int64) -> Int64 {
        if raw <= 1 { skipped = 0 }
        guard skipped > 0 else { return raw }
        return max(1, raw - skipped)
    }
}
