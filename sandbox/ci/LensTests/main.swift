// The lens: which words count as under it, in what order, and the line it hands to a task or a look-up.
import CoreGraphics
import Foundation

var failures = 0

func check(_ condition: Bool, _ label: String) {
    print(condition ? "PASS" : "FAIL", label)
    if !condition { failures += 1 }
}

func word(_ text: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 40, _ h: CGFloat = 14) -> LensKit.Word {
    LensKit.Word(text: text, box: CGRect(x: x, y: y, width: w, height: h))
}

let circle = LensKit.circle(in: CGSize(width: 200, height: 200))
check(circle.center == CGPoint(x: 100, y: 100) && circle.radius == 100, "the circle fills the square")

let words = [
    word("confirm", 40, 60), word("how", 90, 61), word("much", 135, 59),
    word("Before", 30, 30), word("our", 80, 31), word("partner", 120, 29),
    word("the", 60, 90), word("round", 105, 91),
    word("corner", 0, 0),          // outside: the square's corner isn't in the circle
    word("   ", 90, 120),           // blank
    word("far", 300, 100),          // outside the picture
]
let lines = LensKit.lines(words, center: circle.center, radius: circle.radius)
check(lines == ["Before our partner", "confirm how much", "the round"], "lines: top to bottom, left to right, inside the circle only")
check(!lines.joined().contains("corner"), "the corners of the square aren't read")
check(LensKit.lines([], center: circle.center, radius: circle.radius).isEmpty, "nothing under it, nothing read")

check(LensKit.headline(["Hi", "Confirm the allocation by Friday."]) == "Confirm the allocation by Friday", "headline: the first real line, no full stop")
let long = LensKit.headline(["Before our partner meeting on Thursday could you confirm how much of the round is already committed"], limit: 40)
check(long.count <= 41 && long.hasSuffix("…") && !long.dropLast().hasSuffix(" "), "headline: long lines cut at a word")
check(LensKit.headline([]) == "", "headline: empty when nothing was read")

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
