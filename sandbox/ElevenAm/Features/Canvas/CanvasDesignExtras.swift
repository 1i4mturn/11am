import Foundation

/// Charts, picture frames and grids on the canvas you're editing.
extension CanvasController {
    private func centreRect(_ widthShare: Double, _ heightShare: Double) -> CanvasRect {
        let width = document.size.width * widthShare, height = document.size.height * heightShare
        return CanvasRect(x: (document.size.width - width) / 2, y: (document.size.height - height) / 2, width: width, height: height)
    }

    /// A chart in the middle of the design, selected as one group.
    func addChart(_ chart: CanvasChart) {
        let layers = CanvasCharts.layers(chart, in: centreRect(0.72, 0.5))
        change { $0.layers.append(contentsOf: layers) }
        selection = Set(layers.map(\.id))
    }

    /// The selected chart drawn again: as columns or bars, or with new numbers.
    func redrawChart(_ transform: (inout CanvasChart) -> Void) {
        guard let frame = document.layers.first(where: { selection.contains($0.id) && $0.chart != nil })
                ?? document.layers.first(where: { layer in layer.chart != nil && layer.group != nil && document.layers.contains { selection.contains($0.id) && $0.group == layer.group } }),
              var chart = frame.chart else { return }
        transform(&chart)
        change { $0.redrawChart(frame.id, chart: chart) }
        if let group = document.layer(frame.id)?.group { selection = Set(document.layers.filter { $0.group == group }.map(\.id)) }
    }

    /// The chart the selection belongs to.
    var selectedChart: CanvasChart? {
        let groups = Set(selectedLayers.compactMap(\.group))
        return document.layers.first { $0.chart != nil && (selection.contains($0.id) || $0.group.map { groups.contains($0) } == true) }?.chart
    }

    /// Empty picture frames, laid out as a grid in the middle.
    func addFrames(_ grid: PhotoGrid, fill: CanvasColor) {
        let unit = min(document.size.width, document.size.height)
        let rect = grid == .one ? centreRect(0.5, 0.5) : centreRect(0.84, 0.7)
        let layers = CanvasFrames.layers(grid, in: rect, gap: unit * 0.02, radius: unit * 0.012, fill: fill)
        change { $0.layers.append(contentsOf: layers) }
        selection = Set(layers.map(\.id))
    }

    /// A picture into a frame, cropped to fill it.
    func fillFrame(_ id: UUID, with data: Data) {
        let asset = assets.add(data)
        change { document in
            guard let index = document.index(of: id) else { return }
            document.layers[index].content = .image(asset, .fill)
            document.layers[index].name = "Picture"
        }
        selection = [id]
    }

    /// Linked charts brought up to date. Returns how many changed.
    @discardableResult
    func refreshCharts(from workbook: (String) -> Workbook?) -> Int {
        guard document.layers.contains(where: { $0.chart?.link != nil }) else { return 0 }
        var copy = document
        let changed = copy.refreshCharts(from: workbook)
        if copy != document { change { $0 = copy } }
        return changed
    }
}
