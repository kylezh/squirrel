import Foundation

@main
struct TrackerTests {
  static func main() {
    func snapshot(_ location: Int, _ text: String, marked: NSRange? = nil)
      -> InputContinuityTracker.Snapshot
    {
      .init(location: location, before: text, marked: marked)
    }
    var tracker = InputContinuityTracker()
    tracker.activate(mode: .verified)
    tracker.prepare(snapshot: snapshot(0, ""))
    assert(tracker.state == .empty)
    tracker.didCommit(snapshot: snapshot(2, "中文"))
    tracker.prepare(snapshot: snapshot(2, "中文"))
    assert(tracker.state == .tracking)
    let epoch = tracker.epoch
    tracker.prepare(snapshot: snapshot(1, "中"))
    assert(tracker.epoch > epoch && tracker.state == .empty)
    tracker.didCommit(snapshot: snapshot(2, "中文"))
    tracker.prepare(snapshot: snapshot(2, "英文"))
    assert(tracker.state == .empty, "same-length external replacement must reset")
    tracker.didCommit(snapshot: snapshot(2, "中文"))
    tracker.prepare(snapshot: snapshot(2, "中文", marked: NSRange(location: 2, length: 6)))
    assert(tracker.state == .tracking, "marked text changes must preserve anchor")
    tracker.invalidate(reason: .pointer)
    tracker.prepare(snapshot: snapshot(2, "中文"))
    assert(tracker.state == .empty, "returning to old location cannot resurrect boundary")
    tracker.didCommit(snapshot: snapshot(2, "中文"))
    tracker.expectPassthrough("a", from: snapshot(2, "中文"))
    tracker.prepare(snapshot: snapshot(3, "中文a"))
    assert(tracker.state == .tracking)
    tracker.expectPassthrough("b", from: snapshot(3, "中文a"))
    tracker.prepare(snapshot: snapshot(3, "中文a"))
    assert(tracker.state == .empty, "unconfirmed insertion must reset")
    tracker.didCommit(snapshot: snapshot(2, "中文"))
    tracker.prepare(snapshot: nil)
    assert(tracker.state == .uncertain)
    tracker.didCommit(snapshot: nil)
    assert(tracker.state == .uncertain)
    tracker.suspend()
    tracker.didCommit(snapshot: snapshot(2, "中文"))
    assert(tracker.state == .suspended, "focus teardown must not rearm")
    tracker.activate(mode: .eventsOnly)
    tracker.prepare(snapshot: nil)
    tracker.didCommit(snapshot: nil)
    assert(tracker.state == .tracking)
    tracker.activate(mode: .off)
    tracker.prepare(snapshot: snapshot(0, ""))
    assert(tracker.state == .suspended)
    var other = InputContinuityTracker()
    other.activate(mode: .verified)
    assert(other.identifier != tracker.identifier)
    assert(other.state == .empty)
    print("PASS: continuity snapshots, composition, passthrough, lifecycle, and isolation")
  }
}
