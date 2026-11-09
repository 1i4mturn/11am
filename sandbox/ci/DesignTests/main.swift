import Foundation

// Checks Robert's design extras: charts drawn as layers (columns and bars, redrawn, linked to Sheets), picture frames
// and grids, print sizes, and the new templates staying on the page.

var failures = 0
func check(_ condition: Bool, _ name: String) {
    print(condition ? "PASS" : "FAIL", name)
    if !condition { failures += 1 }
}
func same<T: Equatable>(_ actual: T, _ expected: T, _ name: String) {
    if actual == expected {
        print("PASS", name)
    } else {
        print("FAIL", name, "· expected", expected, "· got", actual)
        failures += 1
    }
}
func inside(_ frame: CanvasRect, _ rect: CanvasRect, slack: Double = 0.5) -> Bool {
    frame.minX >= rect.minX - slack && frame.minY >= rect.minY - slack && frame.maxX <= rect.maxX + slack && frame.maxY <= rect.maxY + slack
}

let grey = CanvasColor(red: 0.8, green: 0.8, blue: 0.8)
let orange = CanvasColor(red: 0.96, green: 0.42, blue: 0.24)
let points = [ChartPoint(label: "Jul", value: 12), ChartPoint(label: "Aug", value: 19), ChartPoint(label: "Sep", value: 31), ChartPoint(label: "Oct", value: 48)]

// MARK: Charts

let area = CanvasRect(x: 100, y: 100, width: 800, height: 500)
let chart = CanvasChart(kind: .columns, points: points, color: grey, accent: orange, ink: .black)
let drawn = CanvasCharts.layers(chart, in: area)
same(drawn.count, 13, "chart: a frame, then a bar, a value and a label for each point")
same(drawn.first?.role, "chart", "chart: the frame comes first")
same(drawn.first?.chart, chart, "chart: the frame remembers the chart")
check(Set(drawn.compactMap(\.group)).count == 1 && drawn.allSatisfy { $0.group != nil }, "chart: one group")
check(drawn.allSatisfy { inside($0.frame, area) }, "chart: everything inside its area")
let bars = drawn.filter { $0.role == "chart-bar" }
same(bars.map(\.name), ["Jul", "Aug", "Sep", "Oct"], "chart: bars named for their labels")
let heights = bars.map(\.frame.height)
check(abs(heights[3] / heights[0] - 4) < 0.01, "chart: heights in proportion (48 is four times 12)")
same(bars.map(\.fill), [.solid(grey), .solid(grey), .solid(grey), .solid(orange)], "chart: the biggest in the accent colour")
check(Set(bars.map { $0.frame.maxY }).count == 1, "chart: columns stand on one line")
same(drawn.filter { $0.role == "chart-value" }.compactMap(\.text), ["12", "19", "31", "48"], "chart: values over the bars")

let sideways = CanvasCharts.layers(CanvasChart(kind: .bars, points: points, color: grey, accent: orange, ink: .black), in: area)
let widths = sideways.filter { $0.role == "chart-bar" }.map(\.frame.width)
check(abs(widths[3] / widths[1] - 48.0 / 19) < 0.01 && sideways.allSatisfy { inside($0.frame, area) }, "chart: bars run across, in proportion")
let flat = CanvasCharts.layers(CanvasChart(kind: .columns, points: [ChartPoint(label: "A", value: 0), ChartPoint(label: "B", value: -5)]), in: area)
check(flat.filter { $0.role == "chart-bar" }.allSatisfy { $0.frame.height == 0 }, "chart: nothing and less than nothing draw no bar")
same(CanvasCharts.layers(CanvasChart(kind: .columns, points: []), in: area).count, 1, "chart: no points, just the frame")

var design = CanvasDocument(name: "Report", size: CanvasSize(width: 1080, height: 1080))
design.layers = [CanvasLayer.shapeLayer(.rectangle, frame: CanvasRect(x: 0, y: 0, width: 1080, height: 80), fill: .solid(grey))] + drawn
    + [CanvasLayer.textLayer("Footer", TextStyle(), frame: CanvasRect(x: 40, y: 1000, width: 400, height: 40))]
let frameID = drawn[0].id
var asBars = chart
asBars.kind = .bars
design.redrawChart(frameID, chart: asBars)
same(design.layers.count, 15, "redraw: the same number of layers")
same(design.layers.first?.role, nil, "redraw: layers below the chart stay where they were")
same(design.layers.last?.text, "Footer", "redraw: layers above stay above")
same(design.layer(frameID)?.chart?.kind, .bars, "redraw: the frame knows its new kind")
check(design.layers.filter { $0.role == "chart-bar" }.allSatisfy { $0.frame.height < $0.frame.width || $0.frame.height < 100 }, "redraw: drawn as bars now")
same(design.chartFrames.count, 1, "redraw: still one chart")

// Linked to a sheet.
var workbook = Workbook(name: "Growth", sheets: [GridSheet(name: "Customers")])
func set(_ address: String, _ input: String) { workbook.sheets[0][CellAddress(address)!] = GridCell(input: input) }
set("A1", "Month"); set("B1", "Customers")
for (row, month) in ["Jul", "Aug", "Sep", "Oct"].enumerated() { set("A\(row + 2)", month); set("B\(row + 2)", ["12", "19", "31", "48"][row]) }
var linked = chart
linked.link = ChartLink(workbook: "Growth", sheet: "Customers", labels: "A2:A5", values: "B2:B5")
var report = CanvasDocument(name: "Linked", size: CanvasSize(width: 1080, height: 1080))
report.layers = CanvasCharts.layers(linked, in: area)
same(report.refreshCharts(from: { $0 == "Growth" ? workbook : nil }), 0, "linked: nothing to change while the sheet matches")
check(report.chartFrames.first?.chart?.link?.updated != nil, "linked: when it was last checked")
set("B5", "96")
same(report.refreshCharts(from: { $0 == "Growth" ? workbook : nil }), 1, "linked: a change in the sheet redraws the chart")
same(report.chartFrames.first?.chart?.points.last?.value, 96, "linked: with the new number")
let tallest = report.layers.filter { $0.role == "chart-bar" }.map(\.frame.height)
check(abs(tallest[3] / tallest[0] - 8) < 0.01, "linked: and the bars in proportion again")

// MARK: Frames and grids

let page = CanvasRect(x: 0, y: 0, width: 1000, height: 600)
for grid in PhotoGrid.allCases {
    let rects = grid.rects(in: page, gap: 10)
    let expected = [PhotoGrid.one: 1, .two: 2, .three: 3, .four: 4, .six: 6][grid]!
    var overlaps = false
    for a in rects.indices { for b in rects.indices where a < b {
        let r1 = rects[a], r2 = rects[b]
        if r1.minX < r2.maxX - 0.01 && r2.minX < r1.maxX - 0.01 && r1.minY < r2.maxY - 0.01 && r2.minY < r1.maxY - 0.01 { overlaps = true }
    } }
    check(rects.count == expected && rects.allSatisfy { inside($0, page) } && !overlaps, "grid: \(grid.title), \(expected) frames on the page, none overlapping")
}
same(PhotoGrid.three.rects(in: page, gap: 10).first?.width, 594, "grid: one large frame takes 60%")
same(PhotoGrid.two.rects(in: CanvasRect(x: 0, y: 0, width: 400, height: 900), gap: 10).map(\.width), [400, 400], "grid: two stack on a tall page")

let frames = CanvasFrames.layers(.four, in: page, gap: 10, radius: 8, fill: grey)
check(frames.count == 4 && frames.allSatisfy { $0.role == "frame" } && Set(frames.compactMap(\.group)).count == 1, "frames: four empty frames, grouped")
var scrapbook = CanvasDocument(name: "Frames", size: CanvasSize(width: 1000, height: 600))
var picture = CanvasLayer(name: "Picture", content: .image("photo-1", .fill), frame: CanvasRect(x: 600, y: 350, width: 300, height: 200))
scrapbook.layers = frames + [picture]
let hasImage: (String) -> Bool = { $0 == "photo-1" }
same(CanvasFrames.frame(at: 100, 100, in: scrapbook, hasImage: hasImage), frames[0].id, "frames: a drop finds the frame under it")
same(CanvasFrames.frame(at: 700, 400, in: scrapbook, hasImage: hasImage), nil, "frames: a picture on top isn't a frame")
picture.content = .image("missing", .fill)
scrapbook.layers[4] = picture
same(CanvasFrames.frame(at: 700, 400, in: scrapbook, hasImage: hasImage), picture.id, "frames: a picture whose file is gone takes a new one")
same(CanvasFrames.frame(at: 500, 100, in: scrapbook, hasImage: hasImage), nil, "frames: nothing in the gap between frames")

// MARK: Print sizes

same(PrintUnit.millimetres.pixels(210), 2480, "print: 210 mm is 2480 pixels at 300 dpi")
same(PrintUnit.millimetres.pixels(297), 3508, "print: 297 mm is 3508 pixels")
same(PrintUnit.inches.pixels(8.5), 2550, "print: inches")
same(PrintUnit.millimetres.value(2480), 210, "print: back to millimetres")
same(PrintUnit.inches.value(2550), 8.5, "print: back to inches")
same(PrintUnit.pixels.pixels(1080.4), 1080, "print: pixels are whole")

// MARK: Templates

let sizes = [CanvasSize(width: 1240, height: 1754), CanvasSize(width: 1080, height: 1080), CanvasSize(width: 1080, height: 1920), CanvasSize(width: 1754, height: 1240)]
for template in [CanvasTemplate.invitation, .certificate, .menu, .resume] {
    for size in sizes {
        let document = template.document(CanvasPreset(id: "test", name: "Test", size: size, group: "Test"), brand: CanvasBrand())
        check(!document.layers.isEmpty && document.layers.allSatisfy { inside($0.frame, size.rect, slack: 1) },
              "template: \(template.title) at \(Int(size.width))×\(Int(size.height)) stays on the page")
    }
}

print(failures == 0 ? "All design checks passed." : "\(failures) design checks failed.")
exit(failures == 0 ? 0 : 1)
