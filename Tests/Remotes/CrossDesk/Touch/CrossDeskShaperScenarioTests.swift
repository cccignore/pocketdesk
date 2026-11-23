import CoreGraphics
import Foundation
import RemoteCrossDesk
import SnugCore
import Testing

// 整理器的场景表：正常手势、一笔里的网络毛病、两笔之间、网络卡住后挤在一起到、惯性中点按。
// 按 TouchPipeline 端到端跑，看滚动量、最大的一步、分成了几笔、补发了几次点击。分笔规则改了先跑这张表
private let phone = TouchRegion(frame: CGRect(x: 0, y: 0, width: 540, height: 950), scale: 1)

private enum Ev {
    case move(Double, Double)
    case down(Double, Double)
    case up(Double, Double)
    case expire
}

private struct Outcome {
    var deltas: [Double] = []
    var began = 0
    var replays = 0
    var coasting = false
    var maxStep: Double { deltas.map(abs).max() ?? 0 }
    var total: Double { deltas.reduce(0, +) }
}

private func run(_ events: [Ev]) -> Outcome {
    var pipeline = TouchPipeline(shapers: [CrossDeskShaper()])
    var out = Outcome()
    func take(_ step: TouchStep) {
        for case .command(let command, _) in step.effects {
            switch command {
            case .scroll(let s):
                if s.phase == .began { out.began += 1 }
                if s.deltaY != 0, s.momentum == .none { out.deltas.append(s.deltaY) }
            case .replayPress, .replayCurrent: out.replays += 1
            default: break
            }
        }
    }
    for e in events {
        switch e {
        case .move(let y, let t): take(pipeline.handle(PointerEvent(.move, at: CGPoint(x: 100, y: y), time: t), from: 0, regions: [phone]))
        case .down(let y, let t): take(pipeline.handle(PointerEvent(.leftDown, at: CGPoint(x: 100, y: y), time: t), from: 0, regions: [phone]))
        case .up(let y, let t): take(pipeline.handle(PointerEvent(.leftUp, at: CGPoint(x: 100, y: y), time: t), from: 0, regions: [phone]))
        case .expire: if let d = pipeline.deadline { take(pipeline.expire(now: d, regions: [phone])) }
        }
    }
    out.coasting = pipeline.isCoasting
    return out
}

/// 一串等间隔的移动：从 y0 起每下 step 点、每 dt 秒一下，共 n 下
private func moves(from y0: Double, step: Double, n: Int, at t0: Double, dt: Double = 1.0 / 60) -> [Ev] {
    (0..<n).map { .move(y0 + step * Double($0), t0 + dt * Double($0)) }
}

/// 前一甩：往下 300→700，60Hz、每下 80 点，到点收尾
private let flickDown = moves(from: 300, step: 80, n: 6, at: 0) + [.expire]

@Suite("CrossDesk 整理器场景表")
struct CrossDeskShaperScenarioTests {
    @Test("正常手势：慢滑、快甩成一笔带惯性；点一下补发点击；惯性中点一下只停住")
    func normal() {
        let slow = run(moves(from: 300, step: 30, n: 8, at: 0) + [.expire])
        #expect(slow.began == 1 && abs(slow.total - 210) < 1 && slow.coasting)
        let fast = run(moves(from: 100, step: 110, n: 6, at: 0) + [.expire])
        #expect(fast.began == 1 && fast.total >= 540 && fast.coasting)
        #expect(run([.move(300, 0), .down(300, 0.001), .up(300, 0.002)]).replays == 2)
        #expect(run(flickDown + [.move(500, 0.5), .down(500, 0.501), .up(500, 0.502)]).replays == 0)
    }

    @Test("一笔里的网络毛病：丢了几下、开头一步很小、停一下再甩、不松手来回拖，都还是同一笔，跳过的那段照样滚")
    func withinStroke() {
        let dropped = run([.move(300, 0), .move(320, 0.016), .move(340, 0.032), .move(360, 0.048), .move(490, 0.08), .move(510, 0.096), .expire])
        #expect(dropped.began == 1 && dropped.total >= 209)
        let smallStart = run([.move(300, 0), .move(310, 0.016), .move(460, 0.064), .move(510, 0.08), .move(560, 0.096), .expire])
        #expect(smallStart.began == 1 && smallStart.total >= 259)
        let paused = run([.move(300, 0), .move(320, 0.016), .move(320, 0.032), .move(440, 0.048), .move(560, 0.064), .move(680, 0.08), .expire])
        #expect(paused.began == 1 && paused.total >= 379)
        var scrub = moves(from: 300, step: 30, n: 11, at: 0)
        var (y, t) = (600.0, 10.0 / 60)
        for step in [-30.0, -60, -110, -110, -110] { t += 1.0 / 60; y += step; scrub.append(.move(y, t)) }
        let reversal = run(scrub + [.expire])
        #expect(reversal.began == 1)
    }

    @Test("两笔之间（网络正常）：连甩、隔一会儿往回甩、慢收尾后在前方新起一甩：各算各的，不从上一笔跳过去，后一笔照样滚")
    func betweenStrokes() {
        let quick = run(moves(from: 300, step: 30, n: 5, at: 0) + moves(from: 200, step: 30, n: 5, at: 0.16))
        #expect(quick.maxStep <= 31)
        for gap in [0.6, 1.0, 1.9, 3.0] {
            let back = run(flickDown + [.move(690, gap), .move(580, gap + 1.0 / 60), .move(470, gap + 2.0 / 60), .expire])
            #expect(back.began == 2 && abs(back.total - 400 - -220) < 1, "隔 \(gap) 秒往回甩")
        }
        let jitterStart = run(flickDown + [.move(700, 1.0), .move(697, 1.016), .move(695, 1.032),
                                           .move(585, 1.048), .move(475, 1.064), .move(365, 1.08), .expire])
        #expect(jitterStart.total <= 400 - 330 + 1)
        let ahead = run([.move(300, 0), .move(330, 0.016), .move(360, 0.032), .move(365, 0.048)] + moves(from: 665, step: 30, n: 3, at: 0.128) + [.expire])
        #expect(ahead.maxStep <= 31)
        let tailThenAhead = run(moves(from: 300, step: 30, n: 3, at: 0, dt: 0.016) + [.expire, .move(370, 0.3), .move(375, 0.3002),
                                                                                          .move(670, 0.38), .move(700, 0.396), .expire])
        #expect(tailThenAhead.maxStep <= 31)
    }

    @Test("网络卡住后挤在一起到：前一甩的尾巴（快的、慢的、自成一笔的、卡了 0.7 秒的）和后一甩、点按前导都不连在一起")
    func bunched() {
        let fastTail = run(moves(from: 300, step: 30, n: 3, at: 0, dt: 0.02) + [.move(390, 0.1), .move(420, 0.1005)]
                           + moves(from: 90, step: 30, n: 3, at: 0.101, dt: 0.0005))
        #expect(fastTail.maxStep <= 31)
        let slowTail = run(moves(from: 300, step: 30, n: 3, at: 0, dt: 0.02) + [.move(370, 0.1), .move(375, 0.1005)]
                           + moves(from: 90, step: 30, n: 3, at: 0.101, dt: 0.0005))
        #expect(slowTail.maxStep <= 31)
        let twoPointTail = run(moves(from: 300, step: 30, n: 3, at: 0, dt: 0.016) + [.expire, .move(370, 0.3), .move(375, 0.3002)]
                               + moves(from: 90, step: 30, n: 3, at: 0.3005, dt: 0.0005))
        #expect(twoPointTail.maxStep <= 31)
        let longStall = run(moves(from: 300, step: 30, n: 3, at: 0, dt: 0.016) + [.expire, .move(390, 0.7)]
                            + moves(from: 90, step: 30, n: 3, at: 0.7005, dt: 0.0005))
        #expect(longStall.maxStep <= 31)
        let reflick = run(flickDown + [.move(705, 0.4)] + moves(from: 300, step: 80, n: 3, at: 0.4005, dt: 0.0005) + [.expire])
        #expect(reflick.maxStep <= 81)
        let leadIn = run(moves(from: 300, step: 30, n: 6, at: 0, dt: 0.02) + [.move(900, 0.101), .expire, .down(900, 0.3)])
        #expect(leadIn.maxStep <= 31)
    }

    @Test("网络差（丢包、成批到达、隔 20–60 毫秒才放出）：同一甩照样连成一笔；慢收尾后往回甩照样分开，不管放出间隔多大")
    func poorNetwork() {
        // 60Hz 每下 50 点，中间丢了两下（隔 52 毫秒）
        let droppedTwo = run([.move(300, 0), .move(350, 0.017), .move(400, 0.034), .move(550, 0.086), .move(600, 0.103), .move(650, 0.12), .expire])
        #expect(droppedTwo.began == 1 && droppedTwo.total >= 349)
        // 一批一批到，这一批隔了 57 毫秒
        let batch = run([.move(150, 0), .move(171, 0.017), .move(222, 0.033), .move(305, 0.05), .move(416, 0.067), .move(532, 0.083),
                         .move(649, 0.14), .move(766, 0.1403), .move(882, 0.1406), .expire])
        #expect(batch.began == 1 && batch.total >= 731)
        // 慢收尾后手指回到上面往回甩，卡住后每隔 6 毫秒放出一下
        for spacing in [0.004, 0.006, 0.012, 0.02] {
            let back = run([.move(300, 0), .move(330, 0.016), .move(360, 0.032), .move(364, 0.048), .move(366, 0.14),
                            .move(120, 0.14 + spacing), .move(200, 0.14 + 2 * spacing), .move(300, 0.14 + 3 * spacing), .expire])
            #expect(back.maxStep <= 101, "放出间隔 \(spacing) 秒")
        }
    }

    @Test("远的一步之后紧接着就掉头：那一步是两次落指之间的空当，不当滚动交出去（卡住后放出、快甩后顺势往前落指再往回甩、快甩最后一下单独卡住）")
    func reversalAfterFarStep() {
        // 卡了 0.6 秒，前一甩只剩一下尾巴；后一甩每隔 6 毫秒放出一下
        let stalled = run(flickDown + [.move(705, 0.683), .move(300, 0.689), .move(380, 0.695), .move(460, 0.701), .move(540, 0.707), .expire])
        #expect(stalled.maxStep <= 81)
        // 快甩完手指顺势往前落，马上往回甩
        let landing = run([.move(250, 0), .move(265.9, 0.017), .move(303.5, 0.033), .move(362.9, 0.05), .move(442.3, 0.067), .move(525.7, 0.083),
                           .move(609, 0.1), .move(809, 0.18), .move(793.1, 0.197), .move(755.5, 0.213), .move(696.1, 0.23),
                           .move(616.7, 0.247), .move(533.3, 0.263), .move(450, 0.28), .expire])
        #expect(landing.maxStep <= 84)
        // 快甩的最后一下单独卡在后面（离终点超过 100 点），之后的一甩往回走
        let lastStuck = run([.move(150, 0), .move(171, 0.017), .move(222, 0.033), .move(305, 0.05), .move(416, 0.067), .move(532.6, 0.083), .expire,
                             .move(426.9, 0.435), .move(880, 0.441), .move(800, 0.447), .move(720, 0.453), .move(640, 0.459), .expire])
        #expect(lastStuck.maxStep <= 117)
    }

    @Test("惯性中网络卡住：前一甩的一下尾巴之后紧接着在前方点一下，仍只是停住惯性，不点到内容")
    func tapAfterStragglerDuringCoast() {
        let coast = moves(from: 300, step: 30, n: 5, at: 0, dt: 0.016) + [.expire]
        let tap = run(coast + [.move(425, 0.3), .move(650, 0.3005), .down(650, 0.301), .up(650, 0.302)])
        #expect(tap.replays == 0)
        #expect(run(coast + [.move(650, 0.3005), .down(650, 0.301), .up(650, 0.302)]).replays == 0)
    }
}
