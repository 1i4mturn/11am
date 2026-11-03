import AppKit
import SwiftUI

/// Robert's canvas: your designs down the side, the canvas with its tools, and the inspector.
struct DesignsPanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var studio: DesignStudio
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            DesignList()
                .frame(width: 168)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    CanvasToolbar(controller: studio.controller, brand: studio.brand, addPicture: studio.addPicture)
                    moreMenu
                }
                if let notice = studio.notice {
                    HStack {
                        AgentLogo(code: "rt", size: 16, color: theme.inkSecondary(scheme))
                        Text(notice).font(.system(size: 12)).foregroundStyle(theme.ink(scheme)).lineLimit(2)
                        Spacer()
                        Button { studio.notice = nil } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                            .buttonStyle(.plain)
                            .foregroundStyle(theme.inkTertiary(scheme))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.well(scheme)) }
                }
                CanvasEditorView(controller: studio.controller, backdrop: .clear, accent: NSColor(theme.ink(scheme)))
                    .background { RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous).fill(theme.well(scheme)) }
                    .clipShape(RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            CanvasInspector(controller: studio.controller, brand: studio.brand, removeBackground: studio.removeBackground)
                .frame(width: 224)
                .vellum(level: 3, radius: max(theme.radius - 4, 8))
        }
        .task(id: studio.notice) {
            guard studio.notice != nil, (try? await Task.sleep(for: .seconds(8))) != nil else { return }
            studio.notice = nil
        }
        .onDisappear { studio.flushSave() }
    }

    private var moreMenu: some View {
        Menu {
            Section("Export") {
                ForEach(DesignStudio.Export.allCases) { kind in
                    Button(kind.title + "…") { studio.export(kind) }
                }
            }
            Section("Resize into a new design") {
                ForEach(CanvasPreset.all) { preset in
                    Button("\(preset.name) · \(Int(preset.size.width))×\(Int(preset.size.height))") { studio.resize(to: preset) }
                }
            }
            Divider()
            Button("Use the brand kit's colours and fonts") { studio.applyBrand() }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .foregroundStyle(theme.inkSecondary(scheme))
    }
}

private struct DesignList: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var studio: DesignStudio
    @Environment(\.colorScheme) private var scheme
    @State private var making = false
    @State private var request = ""
    @State private var makeSize = "instagram"
    @State private var renaming: DesignEntry?
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                ForEach(groups, id: \.self) { group in
                    Section(group) {
                        ForEach(CanvasPreset.all.filter { $0.group == group }) { preset in
                            Menu("\(preset.name) · \(Int(preset.size.width))×\(Int(preset.size.height))") {
                                ForEach(CanvasTemplate.allCases) { template in
                                    Button(template.title) { studio.create(template, preset: preset) }
                                }
                            }
                        }
                    }
                }
            } label: {
                Label("New design", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .menuStyle(.button)
            .buttonStyle(.vellumPrimary)
            Button {
                making = true
            } label: {
                Label("Make me a graphic…", systemImage: "sparkle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.vellumSecondary)
            .popover(isPresented: $making, arrowEdge: .trailing) { makeForm }
            SectionLabel(text: "Your designs").padding(.top, 6)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(studio.entries) { entry in row(entry) }
                }
            }
        }
        .alert("Rename design", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let entry = renaming { studio.rename(entry.id, to: newName) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private var groups: [String] {
        var seen: [String] = []
        for preset in CanvasPreset.all where !seen.contains(preset.group) { seen.append(preset.group) }
        return seen
    }

    private var makeForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AgentLogo(code: "rt", size: 18, color: theme.ink(scheme))
                Text("What's the graphic for?").font(.system(size: 13, weight: .semibold))
            }
            AskField(placeholder: "e.g. we hit 1,000 customers", text: $request) {
                studio.make(from: request, preset: CanvasPreset.named(makeSize) ?? CanvasPreset.all[0])
            }
            Picker("Size", selection: $makeSize) {
                ForEach(CanvasPreset.all) { preset in Text(preset.name).tag(preset.id) }
            }
            if let run = studio.makeRun { RunView(run: run) }
            Text("Robert writes the words in your voice and lays them out with your brand kit. You can change anything after.")
                .font(.system(size: 10.5))
                .foregroundStyle(theme.inkTertiary(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 340)
    }

    private func row(_ entry: DesignEntry) -> some View {
        let selected = studio.currentID == entry.id
        let document = selected ? studio.controller.document : studio.previews[entry.id]
        let assets = studio.assets
        return Button {
            studio.open(entry.id)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4).fill(theme.raised(scheme))
                    if let document {
                        CanvasThumbnail(document: document, images: { assets.image($0) }, height: min(34, 44 / CGFloat(max(document.size.aspect, 0.1))))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    } else {
                        Image(systemName: "rectangle.on.rectangle").font(.system(size: 11)).foregroundStyle(theme.inkTertiary(scheme))
                    }
                }
                .frame(width: 48, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(selected ? (studio.controller.document.name) : entry.name)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .foregroundStyle(theme.ink(scheme))
                        .lineLimit(2)
                    Text("\(Int(entry.size.width))×\(Int(entry.size.height))")
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .background { if selected { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.raised(scheme)) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename…") {
                newName = entry.name
                renaming = entry
            }
            Button("Duplicate") { studio.duplicate(entry.id) }
            Divider()
            Button("Move to Trash") { studio.delete(entry.id) }
        }
    }
}
