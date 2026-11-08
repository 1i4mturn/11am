import AppKit
import CoreImage
import QuickLookThumbnailing
import Quartz
import SwiftUI
import UniformTypeIdentifiers

// Files as a browser: places down the side, the folder's contents as thumbnails, and a quick view of whatever's selected,
// with Preview's tools for pictures.

struct FilesBrowserView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var browser: FileBrowser
    @EnvironmentObject private var files: FileIndex
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            let narrow = proxy.size.width < 960
            HStack(alignment: .top, spacing: 14) {
                if !narrow {
                    PlacesList()
                        .frame(width: 168)
                }
                VStack(alignment: .leading, spacing: 10) {
                    BrowserToolbar(narrow: narrow)
                    ThumbnailGrid()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                if let focused = browser.focused {
                    PreviewPane(url: focused)
                        .frame(width: narrow ? 270 : 310)
                        .transition(.rise(theme.rise))
                }
            }
        }
        .animation(theme.spring, value: browser.focused)
        .onAppear { browser.start() }
        .sheet(item: Binding(get: { browser.editing.map { EditTarget(url: $0) } }, set: { browser.editing = $0?.url })) { target in
            ImageEditorView(url: target.url)
                .environmentObject(browser)
                .environmentObject(theme)
        }
        .sheet(isPresented: $browser.converting) {
            ConvertSheet(urls: browser.selectedImages.isEmpty ? browser.focused.map { [$0] } ?? [] : browser.selectedImages)
                .environmentObject(browser)
                .environmentObject(theme)
        }
    }
}

private struct EditTarget: Identifiable {
    var url: URL
    var id: URL { url }
}

private struct PlacesList: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var browser: FileBrowser
    @EnvironmentObject private var files: FileIndex
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(text: "Places").padding(.bottom, 4)
            ForEach(browser.places) { place in row(place.name, place.symbol, place.url) }
            if !files.folders.isEmpty {
                SectionLabel(text: "Indexed").padding(.top, 12).padding(.bottom, 4)
                ForEach(files.folders, id: \.self) { folder in row(folder.lastPathComponent, "folder", folder) }
            }
            Button {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                guard panel.runModal() == .OK, let url = panel.url else { return }
                browser.open(url)
            } label: {
                Label("Open a folder…", systemImage: "plus")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.inkSecondary(scheme))
            .padding(.top, 10)
            if !FileManager.default.fileExists(atPath: browser.sampleFolder.path) {
                Button("Try the sample photos") { browser.makeSampleFolder() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkSecondary(scheme))
                    .padding(.top, 4)
            }
            Spacer()
        }
    }

    private func row(_ name: String, _ symbol: String, _ url: URL) -> some View {
        let selected = browser.folder == url
        return Button {
            browser.open(url)
        } label: {
            Label(name, systemImage: symbol)
                .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(theme.ink(scheme))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if selected { RoundedRectangle(cornerRadius: 7, style: .continuous).fill(theme.raised(scheme)) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct BrowserToolbar: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var browser: FileBrowser
    @Environment(\.colorScheme) private var scheme
    var narrow: Bool

    var body: some View {
        HStack(spacing: 8) {
            ToolButton(symbol: "chevron.left", help: "Back") { browser.goBack() }
                .disabled(!browser.canGoBack)
            ToolButton(symbol: "arrow.up", help: "Enclosing folder") { browser.goUp() }
            if narrow {
                Menu {
                    ForEach(browser.places) { place in Button(place.name) { browser.open(place.url) } }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
            }
            Text(browser.folder?.lastPathComponent ?? "No folder")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.ink(scheme))
                .lineLimit(1)
            Text("\(browser.items.count) \(browser.items.count == 1 ? "item" : "items")")
                .font(.system(size: 11.5))
                .foregroundStyle(theme.inkTertiary(scheme))
                .lineLimit(1)
            Spacer(minLength: 8)
            if browser.working { ProgressView().controlSize(.small) }
            DeviceImportButton { data, type in browser.imported(data, type: type) }
                .frame(width: 26, height: 24)
                .help("Take a photo or scan a document with your iPhone or iPad")
            ToolButton(symbol: "play.rectangle", help: "Slideshow of the pictures here") { browser.startSlideshow() }
            ToolButton(symbol: "arrow.triangle.2.circlepath", help: "Convert the selected pictures") { browser.converting = true }
                .disabled(browser.selectedImages.isEmpty)
            Slider(value: $browser.thumbnailSize, in: 80...200)
                .frame(width: 90)
                .help("Thumbnail size")
        }
    }
}

private struct ThumbnailGrid: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var browser: FileBrowser
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            if browser.items.isEmpty {
                Text(browser.folder == nil ? "Choose a place on the left." : "This folder is empty.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: browser.thumbnailSize, maximum: browser.thumbnailSize + 40), spacing: 12)], spacing: 14) {
                ForEach(browser.items) { item in
                    ThumbnailCell(item: item, selected: browser.selection.contains(item.url))
                        .onTapGesture(count: 2) { browser.activate(item) }
                        .onTapGesture { browser.select(item, extend: NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift)) }
                        .contextMenu { menu(item) }
                }
            }
            .padding(10)
        }
        .background(RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous).fill(theme.well(scheme)))
        .overlay(RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5))
    }

    @ViewBuilder
    private func menu(_ item: FolderItem) -> some View {
        Button("Open") { browser.activate(item) }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
        if item.kind == .image {
            Divider()
            Button("Edit…") { browser.editing = item.url }
            Button("Copy the text in it") { browser.copyText(item.url) }
            Button("Convert…") {
                if !browser.selection.contains(item.url) { browser.select(item, extend: false) }
                browser.converting = true
            }
        }
    }
}

private struct ThumbnailCell: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var browser: FileBrowser
    @Environment(\.colorScheme) private var scheme
    var item: FolderItem
    var selected: Bool
    @State private var thumbnail: NSImage?

    var body: some View {
        let side = browser.thumbnailSize
        VStack(spacing: 6) {
            ZStack {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                } else {
                    Image(systemName: item.kind.symbol)
                        .font(.system(size: side * 0.3, weight: .light))
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
            }
            .frame(width: side, height: side * 0.78)
            .padding(4)
            .background {
                if selected { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.raised(scheme)) }
            }
            .overlay {
                if selected { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.ink(scheme).opacity(0.5), lineWidth: 1) }
            }
            Text(item.name)
                .font(.system(size: 11.5, weight: selected ? .medium : .regular))
                .foregroundStyle(theme.ink(scheme))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: side + 8)
        }
        .contentShape(Rectangle())
        .task(id: "\(item.url.path)|\(item.modified.timeIntervalSince1970)|\(Int(side))") {
            thumbnail = await Self.thumbnail(item.url, side: side)
        }
    }

    static func thumbnail(_ url: URL, side: Double) async -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: scale, representationTypes: .thumbnail)
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }
}

/// Quick Look's own preview: almost any file.
struct QuickLookView: NSViewRepresentable {
    var url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .compact) ?? QLPreviewView()
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? URL) != url { view.previewItem = url as NSURL }
    }
}

/// The selected file: a quick view, what it is, and Preview's tools for pictures.
private struct PreviewPane: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var browser: FileBrowser
    @Environment(\.colorScheme) private var scheme
    var url: URL
    @State private var confirmingLocation = false

    var body: some View {
        let item = browser.items.first { $0.url == url }
        let kind = item?.kind ?? FileKind.of(url)
        let info = kind == .image ? browser.info(url) : nil
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                QuickLookView(url: url)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(url.lastPathComponent)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.ink(scheme))
                    .lineLimit(2)
                if kind == .image {
                    HStack(spacing: 6) {
                        Button("Edit…") { browser.editing = url }.buttonStyle(.vellumPrimary)
                        Button("Copy text") { browser.copyText(url) }.buttonStyle(.vellumSecondary)
                        Button("Convert…") {
                            if !browser.selection.contains(url) { browser.selection = [url] }
                            browser.converting = true
                        }
                        .buttonStyle(.vellumSecondary)
                    }
                } else {
                    Button("Open") { NSWorkspace.shared.open(url) }.buttonStyle(.vellumSecondary)
                }
                VStack(alignment: .leading, spacing: 5) {
                    if let info {
                        row("Size", "\(info.dimensions) · \(String(format: "%.1f", info.megapixels)) MP")
                        row("Format", info.format + (info.hasTransparency ? ", see-through" : ""))
                        if let profile = info.colourProfile { row("Colour", profile) }
                        if let camera = info.camera { row("Camera", camera) }
                        if let lens = info.lens { row("Lens", lens) }
                        if let exposure = info.exposure { row("Exposure", exposure) }
                        if let taken = info.taken { row("Taken", taken.formatted(date: .abbreviated, time: .shortened)) }
                    }
                    if let item {
                        row("File", ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))
                        row("Changed", item.modified.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                if let info, info.hasLocation, let latitude = info.latitude, let longitude = info.longitude {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "location.fill").font(.system(size: 11))
                            Text(String(format: "%.4f, %.4f", latitude, longitude))
                                .font(.system(size: 12).monospacedDigit())
                            Spacer()
                            Button("Map") {
                                if let map = URL(string: "https://maps.apple.com/?ll=\(latitude),\(longitude)&q=Photo") { NSWorkspace.shared.open(map) }
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11.5))
                        }
                        .foregroundStyle(theme.ink(scheme))
                        Text("This picture says where it was taken. Anyone you send it to can see that.")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.inkTertiary(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Remove location…") { confirmingLocation = true }
                            .buttonStyle(.vellumSecondary)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.well(scheme)))
                }
            }
            .padding(12)
        }
        .vellum(level: 2, radius: max(theme.radius - 2, 10))
        .confirmationDialog("Take the location out of \(url.lastPathComponent)?", isPresented: $confirmingLocation) {
            Button("Remove location") { browser.removeLocation(url) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The picture and its other details stay as they are.")
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.inkTertiary(scheme))
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(theme.ink(scheme))
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }
}

// MARK: Editing a picture

struct ImageEditorView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var browser: FileBrowser
    @Environment(\.colorScheme) private var scheme
    var url: URL
    @State private var edits = ImageEdits()
    @State private var original: CIImage?
    @State private var preview: NSImage?
    @State private var cropping = false
    @State private var cutout: CIImage?
    @State private var lifting = false
    @State private var width = 0.0
    @State private var height = 0.0
    @State private var keepProportions = true
    @State private var replacing = false

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Color.black.opacity(scheme == .dark ? 0.35 : 0.06)
                if let preview {
                    GeometryReader { proxy in
                        let fitted = fit(preview.size, in: proxy.size)
                        ZStack {
                            Image(nsImage: preview)
                                .resizable()
                                .frame(width: fitted.width, height: fitted.height)
                                .background(CheckerBoard().opacity(cutout == nil ? 0 : 1))
                            if cropping {
                                CropOverlay(crop: Binding(get: { edits.crop ?? CGRect(x: 0, y: 0, width: 1, height: 1) }, set: { edits.crop = $0 }))
                                    .frame(width: fitted.width, height: fitted.height)
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                    .padding(24)
                } else {
                    ProgressView()
                }
            }
            .frame(minWidth: 520, minHeight: 460)
            controls
                .frame(width: 280)
        }
        .frame(width: 900, height: 620)
        .task { load() }
        .onChange(of: edits) { _, _ in render() }
        .onChange(of: cropping) { _, _ in render() }
        .confirmationDialog("Replace \(url.lastPathComponent)?", isPresented: $replacing) {
            Button("Replace the original") { browser.save(url, edits: finalEdits, cutout: cutout, asCopy: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Or save a copy and keep the original as it is.")
        }
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(url.lastPathComponent).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    ToolButton(symbol: "rotate.left", help: "Turn left") { edits.turn(clockwise: false); swapSize() }
                    ToolButton(symbol: "rotate.right", help: "Turn right") { edits.turn(clockwise: true); swapSize() }
                    ToolButton(symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", help: "Flip left to right") { edits.flipHorizontal.toggle() }
                    ToolButton(symbol: "arrow.up.and.down.righttriangle.up.righttriangle.down", help: "Flip top to bottom") { edits.flipVertical.toggle() }
                    ToolButton(symbol: "crop", help: "Crop", on: cropping) { cropping.toggle() }
                }
                if cropping {
                    HStack {
                        Menu("Shape") {
                            Button("Free") {}
                            Button("Square") { aspect(1) }
                            Button("4:3") { aspect(4.0 / 3) }
                            Button("3:2") { aspect(3.0 / 2) }
                            Button("16:9") { aspect(16.0 / 9) }
                            Button("Portrait 4:5") { aspect(4.0 / 5) }
                        }
                        .fixedSize()
                        Button("Reset crop") { edits.crop = nil }
                        Spacer()
                    }
                    .font(.system(size: 12))
                }
                SectionLabel(text: "Light and colour")
                slider("Exposure", value: $edits.exposure, range: -2...2)
                slider("Contrast", value: $edits.contrast, range: 0.5...1.5)
                slider("Saturation", value: $edits.saturation, range: 0...2)
                slider("Warmth", value: $edits.warmth, range: -1...1)
                slider("Tint", value: $edits.tint, range: -1...1)
                slider("Sharpness", value: $edits.sharpness, range: 0...1)
                slider("Sepia", value: $edits.sepia, range: 0...1)
                Toggle("Black and white", isOn: $edits.blackAndWhite).font(.system(size: 12))
                SectionLabel(text: "Size")
                HStack(spacing: 6) {
                    TextField("Width", value: Binding(get: { width }, set: { setWidth($0) }), format: .number).frame(width: 70)
                    Text("×")
                    TextField("Height", value: Binding(get: { height }, set: { setHeight($0) }), format: .number).frame(width: 70)
                    Text("px").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Toggle("Keep proportions", isOn: $keepProportions).font(.system(size: 12))
                SectionLabel(text: "Subject")
                Button {
                    liftSubject()
                } label: {
                    Label(cutout == nil ? "Remove background" : "Put the background back", systemImage: "person.crop.rectangle")
                }
                .disabled(lifting)
                if lifting { ProgressView("Finding the subject…").controlSize(.small) }
                Divider()
                HStack {
                    Button("Reset") {
                        edits = ImageEdits()
                        cutout = nil
                        resetSize()
                    }
                    Spacer()
                    Button("Cancel") { browser.editing = nil }
                        .keyboardShortcut(.cancelAction)
                }
                HStack {
                    Button("Save a copy") { browser.save(url, edits: finalEdits, cutout: cutout, asCopy: true) }
                        .buttonStyle(.vellumSecondary)
                    Spacer()
                    Button("Save") { replacing = true }
                        .buttonStyle(.vellumPrimary)
                        .keyboardShortcut(.defaultAction)
                        .disabled(edits.isEmpty && cutout == nil && !sizeChanged)
                }
                Text(cutout != nil && !(ImageFormat.of(url)?.keepsTransparency ?? false)
                     ? "A JPEG can't be see-through, so the cut-out is saved as a PNG beside it."
                     : "Camera details and the place are kept. Remove the place in the inspector before sharing.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .textFieldStyle(.roundedBorder)
        .controlSize(.small)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 11.5))
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue)).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    // MARK: Working

    private var fullSize: CGSize {
        guard let original else { return .zero }
        var size = original.extent.size
        if edits.quarterTurns % 2 == 1 { size = CGSize(width: size.height, height: size.width) }
        if let crop = edits.crop { size = CGSize(width: (size.width * crop.width).rounded(), height: (size.height * crop.height).rounded()) }
        return size
    }

    private var sizeChanged: Bool { width > 0 && height > 0 && (Int(width) != Int(fullSize.width) || Int(height) != Int(fullSize.height)) }

    /// The edits as saved: with the new size only when it differs from the picture's own.
    private var finalEdits: ImageEdits {
        var final = edits
        final.size = sizeChanged ? CGSize(width: width, height: height) : nil
        return final
    }

    private func load() {
        original = ImageKit.load(url)
        resetSize()
        render()
    }

    private func resetSize() {
        width = Double(fullSize.width)
        height = Double(fullSize.height)
    }

    private func swapSize() {
        let oldWidth = width
        width = height
        height = oldWidth
    }

    private func setWidth(_ value: Double) {
        width = max(1, value)
        if keepProportions, fullSize.width > 0 { height = (width * fullSize.height / fullSize.width).rounded() }
    }

    private func setHeight(_ value: Double) {
        height = max(1, value)
        if keepProportions, fullSize.height > 0 { width = (height * fullSize.width / fullSize.height).rounded() }
    }

    /// A centred crop of a shape.
    private func aspect(_ ratio: Double) {
        guard let original else { return }
        var size = original.extent.size
        if edits.quarterTurns % 2 == 1 { size = CGSize(width: size.height, height: size.width) }
        let current = size.width / size.height
        if ratio > current {
            let height = current / ratio
            edits.crop = CGRect(x: 0, y: (1 - height) / 2, width: 1, height: height)
        } else {
            let width = ratio / current
            edits.crop = CGRect(x: (1 - width) / 2, y: 0, width: width, height: 1)
        }
        resetSize()
    }

    /// A smaller copy for the screen, redrawn as the edits change. While cropping, the whole picture shows under the frame.
    private func render() {
        guard let base = cutout ?? original else { return }
        let scale = min(1, 1_400 / max(base.extent.width, base.extent.height))
        let small = base.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        var shown = edits
        shown.size = nil
        if cropping { shown.crop = nil }
        guard let pixels = ImageKit.render(ImageKit.apply(shown, to: small)) else { return }
        preview = NSImage(cgImage: pixels, size: NSSize(width: pixels.width, height: pixels.height))
    }

    private func liftSubject() {
        if cutout != nil {
            cutout = nil
            render()
            return
        }
        guard let original, let pixels = ImageKit.render(original) else { return }
        lifting = true
        Task { @MainActor in
            let lifted = await FileBrowser.liftSubject(pixels)
            lifting = false
            if let lifted {
                cutout = lifted
                render()
            } else {
                browser.notice = "No clear subject found in \(url.lastPathComponent)."
            }
        }
    }

    private func fit(_ size: CGSize, in box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

/// A crop frame with corner handles, in 0–1 of the picture.
private struct CropOverlay: View {
    @Binding var crop: CGRect
    @State private var start: CGRect?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let frame = CGRect(x: crop.minX * size.width, y: crop.minY * size.height, width: crop.width * size.width, height: crop.height * size.height)
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: size))
                    path.addRect(frame)
                }
                .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
                Rectangle()
                    .strokeBorder(Color.white, lineWidth: 1.5)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .gesture(DragGesture().onChanged { value in move(value.translation, size) }.onEnded { _ in start = nil })
                ForEach(0..<4, id: \.self) { corner in
                    let x = corner % 2 == 0 ? frame.minX : frame.maxX
                    let y = corner < 2 ? frame.minY : frame.maxY
                    Circle()
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                        .shadow(radius: 1)
                        .position(x: x, y: y)
                        .gesture(DragGesture().onChanged { value in resize(corner, value.translation, size) }.onEnded { _ in start = nil })
                }
            }
        }
    }

    private func move(_ translation: CGSize, _ size: CGSize) {
        let origin = start ?? crop
        if start == nil { start = crop }
        var moved = origin.offsetBy(dx: translation.width / size.width, dy: translation.height / size.height)
        moved.origin.x = min(max(0, moved.minX), 1 - moved.width)
        moved.origin.y = min(max(0, moved.minY), 1 - moved.height)
        crop = moved
    }

    private func resize(_ corner: Int, _ translation: CGSize, _ size: CGSize) {
        let origin = start ?? crop
        if start == nil { start = crop }
        let dx = translation.width / size.width, dy = translation.height / size.height
        var left = origin.minX, right = origin.maxX, top = origin.minY, bottom = origin.maxY
        if corner % 2 == 0 { left = min(max(0, left + dx), right - 0.05) } else { right = max(min(1, right + dx), left + 0.05) }
        if corner < 2 { top = min(max(0, top + dy), bottom - 0.05) } else { bottom = max(min(1, bottom + dy), top + 0.05) }
        crop = CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}

private struct CheckerBoard: View {
    var body: some View {
        Canvas { context, size in
            let side: CGFloat = 10
            for row in 0..<Int(size.height / side) + 1 {
                for column in 0..<Int(size.width / side) + 1 where (row + column) % 2 == 0 {
                    context.fill(Path(CGRect(x: CGFloat(column) * side, y: CGFloat(row) * side, width: side, height: side)), with: .color(.gray.opacity(0.25)))
                }
            }
        }
    }
}

// MARK: Converting

private struct ConvertSheet: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var browser: FileBrowser
    @Environment(\.colorScheme) private var scheme
    var urls: [URL]
    @State private var format: ImageFormat = .jpeg
    @State private var quality = 0.85
    @State private var shrink = false
    @State private var longest = 2048.0
    @State private var keepLocation = false
    @State private var destination: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(urls.count == 1 ? "Convert \(urls[0].lastPathComponent)" : "Convert \(urls.count) pictures")
                .font(theme.display(22))
                .foregroundStyle(theme.ink(scheme))
            Picker("Format", selection: $format) {
                ForEach(ImageFormat.allCases) { format in Text(format.title).tag(format) }
            }
            .pickerStyle(.segmented)
            if format.hasQuality {
                HStack {
                    Text("Quality").font(.system(size: 12))
                    Slider(value: $quality, in: 0.1...1)
                    Text("\(Int((quality * 100).rounded()))%").font(.system(size: 11.5).monospacedDigit()).frame(width: 40)
                }
            }
            HStack {
                Toggle("Shrink to fit", isOn: $shrink)
                TextField("", value: $longest, format: .number).frame(width: 70).disabled(!shrink)
                Text("pixels on the longest side").font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Toggle("Keep where they were taken", isOn: $keepLocation)
            Text(keepLocation ? "Camera details and places go with the copies." : "Camera details go with the copies; places are left out, so they're safe to share.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack {
                Text(destination.map { "Into \($0.lastPathComponent)" } ?? "Next to the originals").font(.system(size: 12))
                Spacer()
                Button("Choose a folder…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.canCreateDirectories = true
                    if panel.runModal() == .OK { destination = panel.url }
                }
            }
            if format == .pdf {
                Text(urls.count > 1 ? "All \(urls.count) pictures go into one PDF, a page each." : "One page, the size of the picture.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { browser.converting = false }
                    .buttonStyle(.vellumSecondary)
                    .keyboardShortcut(.cancelAction)
                Button("Convert") {
                    browser.convert(urls, to: format, quality: quality, longestSide: shrink ? longest : nil, keepLocation: keepLocation, into: destination)
                }
                .buttonStyle(.vellumPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(urls.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 460)
        .textFieldStyle(.roundedBorder)
    }
}

// MARK: Slideshow

struct SlideshowView: View {
    @EnvironmentObject private var browser: FileBrowser
    @State private var playing = true
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(30)
                    .transition(.opacity)
                    .id(browser.slideIndex)
            }
            VStack {
                Spacer()
                HStack(spacing: 18) {
                    Button { browser.stepSlide(-1) } label: { Image(systemName: "chevron.left") }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                    Button { playing.toggle() } label: { Image(systemName: playing ? "pause.fill" : "play.fill") }
                        .keyboardShortcut(.space, modifiers: [])
                    Button { browser.stepSlide(1) } label: { Image(systemName: "chevron.right") }
                        .keyboardShortcut(.rightArrow, modifiers: [])
                    Text(browser.slideshow.indices.contains(browser.slideIndex) ? "\(browser.slideIndex + 1) of \(browser.slideshow.count) · \(browser.slideshow[browser.slideIndex].lastPathComponent)" : "")
                        .font(.system(size: 12))
                    Button { browser.slideshow = [] } label: { Image(systemName: "xmark") }
                        .keyboardShortcut(.cancelAction)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .padding(.bottom, 24)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: browser.slideIndex)
        .task(id: browser.slideIndex) {
            if browser.slideshow.indices.contains(browser.slideIndex) { image = NSImage(contentsOf: browser.slideshow[browser.slideIndex]) }
        }
        .task(id: playing) {
            while playing, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                if playing, !Task.isCancelled { browser.stepSlide(1) }
            }
        }
    }
}

// MARK: From iPhone

/// Continuity Camera: a button whose menu macOS fills with "Take Photo" and "Scan Documents" from a nearby iPhone or iPad.
struct DeviceImportButton: NSViewRepresentable {
    var onImport: (Data, UTType) -> Void

    func makeNSView(context: Context) -> DeviceImportView {
        let view = DeviceImportView()
        view.onImport = onImport
        return view
    }

    func updateNSView(_ view: DeviceImportView, context: Context) {
        view.onImport = onImport
    }
}

final class DeviceImportView: NSView, NSServicesMenuRequestor {
    var onImport: ((Data, UTType) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let symbol = NSImage(systemSymbolName: "iphone.and.arrow.forward", accessibilityDescription: "Import from iPhone") else { return }
        let configured = symbol.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)) ?? symbol
        let size = configured.size
        let rect = NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
        NSColor.secondaryLabelColor.set()
        configured.draw(in: rect)
        NSColor.secondaryLabelColor.setFill()
        rect.fill(using: .sourceAtop)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let menu = NSMenu()
        let item = NSMenuItem(title: "Import from iPhone or iPad", action: nil, keyEquivalent: "")
        item.identifier = NSMenuItem.importFromDeviceIdentifier
        menu.addItem(item)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
        if let returnType, returnType == .pdf || NSImage.imageTypes.contains(returnType.rawValue) { return self }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    func readSelection(from pasteboard: NSPasteboard) -> Bool {
        if let pdf = pasteboard.data(forType: .pdf) {
            onImport?(pdf, .pdf)
            return true
        }
        if let jpeg = pasteboard.data(forType: NSPasteboard.PasteboardType(UTType.jpeg.identifier)) {
            onImport?(jpeg, .jpeg)
            return true
        }
        if let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
           let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) {
            onImport?(jpeg, .jpeg)
            return true
        }
        return false
    }

    func writeSelection(to pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool { false }
}
