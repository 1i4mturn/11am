import AppKit
import SwiftUI

// The panel beside the grid: conditional formatting, validation, cleaning a column and comments; and earlier versions.

struct SheetsSidePanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var sheets: SheetsModel
    @Environment(\.colorScheme) private var scheme
    var panel: SheetsPanel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: panel.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.inkSecondary(scheme))
                Text(panel.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.ink(scheme))
                Spacer()
                Button {
                    sheets.panel = nil
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.inkTertiary(scheme))
                .help("Close")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    switch panel {
                    case .rules: RulesPanel()
                    case .validation: ValidationPanel()
                    case .clean: CleanPanel()
                    case .comments: CommentsPanel()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .vellum(level: 2, radius: max(theme.radius - 2, 10))
        .textFieldStyle(.roundedBorder)
        .controlSize(.small)
    }
}

/// A small card inside a panel.
private struct PanelCard<Content: View>: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var selected = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6, content: content)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? theme.raised(scheme) : theme.well(scheme))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5)
            }
    }
}

private struct PanelHint: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(theme.inkTertiary(scheme))
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: Conditional formatting

private struct RulesPanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var sheets: SheetsModel
    @Environment(\.colorScheme) private var scheme
    @State private var open: UUID?

    var body: some View {
        Menu {
            Section("Compare") {
                ForEach([ConditionalRule.Kind.greaterThan, .lessThan, .between, .equalTo, .notEqualTo, .containsText]) { kind in
                    Button(kind.title) { add(kind) }
                }
            }
            Section("Spot") {
                ForEach([ConditionalRule.Kind.top, .bottom, .aboveAverage, .belowAverage, .duplicate, .unique, .blank, .notBlank]) { kind in
                    Button(kind.title) { add(kind) }
                }
            }
            Section("Paint by value") {
                Button(ConditionalRule.Kind.colorScale.title) { add(.colorScale) }
                Button(ConditionalRule.Kind.dataBar.title) { add(.dataBar) }
            }
            Button(ConditionalRule.Kind.formula.title + "…") { add(.formula) }
        } label: {
            Label("Add a rule for \(sheets.targetRange.a1)", systemImage: "plus")
        }
        .menuStyle(.button)
        .fixedSize()
        if sheets.rules.isEmpty {
            PanelHint(text: "Colour cells by what's in them: over budget in red, the top three, duplicates, a scale from low to high. Select some cells, then add a rule.")
        }
        ForEach(sheets.rules) { rule in
            let index = sheets.rules.firstIndex(where: { $0.id == rule.id }) ?? 0
            PanelCard(selected: open == rule.id) {
                HStack(spacing: 6) {
                    RuleSwatch(rule: rule)
                    Button {
                        open = open == rule.id ? nil : rule.id
                        sheets.select(rule.range)
                    } label: {
                        Text(rule.summary)
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.ink(scheme))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    Menu {
                        Button("Move up") { sheets.moveRule(rule.id, by: -1) }.disabled(index == 0)
                        Button("Move down") { sheets.moveRule(rule.id, by: 1) }.disabled(index == sheets.rules.count - 1)
                        Button("Use the selection (\(sheets.selection.a1))") {
                            var changed = rule
                            changed.range = sheets.selection
                            sheets.updateRule(changed)
                        }
                        Divider()
                        Button("Delete", role: .destructive) { sheets.deleteRule(rule.id) }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                if open == rule.id { RuleEditor(rule: rule) }
            }
        }
        if sheets.rules.count > 1 {
            PanelHint(text: "Where two rules colour the same cell, the one higher up wins.")
        }
    }

    private func add(_ kind: ConditionalRule.Kind) {
        sheets.addRule(kind)
        open = sheets.rules.last?.id
    }
}

private struct RuleSwatch: View {
    var rule: ConditionalRule

    var body: some View {
        Group {
            if rule.kind == .colorScale {
                LinearGradient(colors: [rule.low, rule.middle, rule.high].compactMap { GridColor.swiftUI($0) }, startPoint: .leading, endPoint: .trailing)
            } else if rule.kind == .dataBar {
                HStack(spacing: 0) {
                    (GridColor.swiftUI(rule.high) ?? .gray).opacity(0.6).frame(width: 12)
                    Color.clear
                }
            } else {
                ZStack {
                    (GridColor.swiftUI(rule.style.fill) ?? .clear)
                    Text("A").font(.system(size: 10, weight: rule.style.bold ? .bold : .regular)).foregroundStyle(GridColor.swiftUI(rule.style.color) ?? .primary)
                }
            }
        }
        .frame(width: 22, height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5) }
    }
}

private struct RuleEditor: View {
    @EnvironmentObject private var sheets: SheetsModel
    @State var rule: ConditionalRule
    @State private var range = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: $rule.kind) {
                ForEach(ConditionalRule.Kind.allCases) { kind in Text(kind.title).tag(kind) }
            }
            .labelsHidden()
            HStack {
                Text("Cells").font(.system(size: 11)).frame(width: 40, alignment: .leading)
                TextField("B2:B40", text: $range).onSubmit(apply)
            }
            if rule.kind.values >= 1 {
                HStack {
                    Text(valueLabel)
                        .font(.system(size: 11)).frame(width: 40, alignment: .leading)
                    TextField(placeholder, text: $rule.value1).onSubmit(apply)
                    if rule.kind.values == 2 {
                        Text("and").font(.system(size: 11))
                        TextField("", text: $rule.value2).onSubmit(apply)
                    }
                }
            }
            if rule.kind.isGradient {
                HStack(spacing: 6) {
                    if rule.kind == .colorScale {
                        ColorPicker("Low", selection: colour(\.low))
                        ColorPicker("High", selection: colour(\.high))
                        Toggle("Middle", isOn: Binding(get: { rule.middle != nil }, set: { rule.middle = $0 ? "#FFFFFF" : nil; apply() }))
                    } else {
                        ColorPicker("Bar", selection: colour(\.high))
                    }
                }
                .font(.system(size: 11))
            } else {
                HStack(spacing: 4) {
                    ForEach(RuleStyle.presets.indices, id: \.self) { position in
                        let preset = RuleStyle.presets[position]
                        Button {
                            rule.style = preset.style
                            apply()
                        } label: {
                            Text(preset.name == "Bold" ? "B" : "A")
                                .font(.system(size: 10.5, weight: preset.style.bold ? .bold : .medium))
                                .foregroundStyle(GridColor.swiftUI(preset.style.color) ?? .primary)
                                .frame(width: 24, height: 18)
                                .background(GridColor.swiftUI(preset.style.fill) ?? .clear, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .strokeBorder(rule.style == preset.style ? Color.primary : Color.primary.opacity(0.15), lineWidth: rule.style == preset.style ? 1.5 : 0.5)
                                }
                        }
                        .buttonStyle(.plain)
                        .help(preset.name)
                    }
                }
            }
            if rule.kind == .formula {
                Text("Write it for the first cell, like =$C2=\"Overdue\". The $ keeps a column fixed as it moves down.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Apply", action: apply).keyboardShortcut(.defaultAction)
            }
        }
        .onAppear { range = rule.range.a1 }
        .onChange(of: rule.kind) { _, _ in apply() }
    }

    private var valueLabel: String {
        switch rule.kind {
        case .formula: return "When"
        case .top, .bottom: return "How many"
        default: return "Value"
        }
    }

    private var placeholder: String {
        switch rule.kind {
        case .top, .bottom: return "3, or 10%"
        case .formula: return "=$B2>$D$1"
        case .containsText: return "Overdue"
        default: return "1000, or =$D$1"
        }
    }

    private func colour(_ key: WritableKeyPath<ConditionalRule, String>) -> Binding<Color> {
        Binding(get: { GridColor.swiftUI(rule[keyPath: key]) ?? .white }, set: { color in
            rule[keyPath: key] = Self.hex(color)
            apply()
        })
    }

    static func hex(_ color: Color) -> String {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return "#FFFFFF" }
        return String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
    }

    private func apply() {
        if let typed = CellRange(range.trimmingCharacters(in: .whitespaces).uppercased().replacingOccurrences(of: "$", with: "")) { rule.range = typed }
        sheets.updateRule(rule)
        range = rule.range.a1
    }
}

// MARK: Validation

private struct ValidationPanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var sheets: SheetsModel
    @Environment(\.colorScheme) private var scheme
    @State private var open: UUID?

    var body: some View {
        Menu {
            ForEach(DataValidation.Kind.allCases) { kind in
                Button(kind.title) {
                    sheets.addValidation(kind)
                    open = sheets.validations.last?.id
                }
            }
        } label: {
            Label("Add for \(sheets.targetRange.a1)", systemImage: "plus")
        }
        .menuStyle(.button)
        .fixedSize()
        if let active = sheets.activeValidation {
            PanelHint(text: "\(sheets.active.a1) takes \(active.kind.title.lowercased())\(active.help.isEmpty ? "" : ": \(active.help)").")
        }
        if sheets.validations.isEmpty {
            PanelHint(text: "Keep a column tidy: a list to pick from (a status, a category), tick boxes, numbers or dates within limits. Anything else is marked with a red corner, or refused.")
        }
        ForEach(sheets.validations) { rule in
            PanelCard(selected: open == rule.id) {
                HStack(spacing: 6) {
                    Image(systemName: icon(rule.kind))
                        .font(.system(size: 11))
                        .foregroundStyle(theme.inkSecondary(scheme))
                        .frame(width: 18)
                    Button {
                        open = open == rule.id ? nil : rule.id
                        sheets.select(rule.range)
                    } label: {
                        Text(rule.summary)
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.ink(scheme))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    Button {
                        sheets.deleteValidation(rule.id)
                    } label: {
                        Image(systemName: "trash").font(.system(size: 10.5))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .help("Remove the rule (the values stay)")
                }
                if open == rule.id { ValidationEditor(rule: rule) }
            }
        }
        let invalid = sheets.decorations.invalid.count
        if invalid > 0 {
            PanelHint(text: "\(invalid) \(invalid == 1 ? "cell breaks" : "cells break") its rule, marked with a red corner.")
        }
    }

    private func icon(_ kind: DataValidation.Kind) -> String {
        switch kind {
        case .list: return "list.bullet"
        case .checkbox: return "checkmark.square"
        case .wholeNumber, .decimal: return "number"
        case .date: return "calendar"
        case .textLength: return "textformat.size"
        }
    }
}

private struct ValidationEditor: View {
    @EnvironmentObject private var sheets: SheetsModel
    @State var rule: DataValidation
    @State private var range = ""
    @State private var choices = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: $rule.kind) {
                ForEach(DataValidation.Kind.allCases) { kind in Text(kind.title).tag(kind) }
            }
            .labelsHidden()
            HStack {
                Text("Cells").font(.system(size: 11)).frame(width: 52, alignment: .leading)
                TextField("C2:C40", text: $range)
            }
            switch rule.kind {
            case .list:
                HStack(alignment: .top) {
                    Text("Choices").font(.system(size: 11)).frame(width: 52, alignment: .leading)
                    TextField("Todo, Doing, Done", text: $choices, axis: .vertical).lineLimit(1...4)
                }
                HStack {
                    Text("Or from").font(.system(size: 11)).frame(width: 52, alignment: .leading)
                    TextField("Lists!A2:A9", text: $rule.source)
                }
            case .checkbox:
                Text("Ticked is TRUE, empty is FALSE, so =COUNTIF(range,TRUE) counts the ticks.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            default:
                HStack {
                    Text(rule.kind == .textLength ? "Length" : "From").font(.system(size: 11)).frame(width: 52, alignment: .leading)
                    TextField(rule.kind == .date ? "1/7/2026" : "0", text: $rule.minimum)
                    Text("to").font(.system(size: 11))
                    TextField(rule.kind == .date ? "30/6/2027" : "", text: $rule.maximum)
                }
            }
            if rule.kind != .checkbox {
                Toggle("Refuse anything else (otherwise it's marked)", isOn: $rule.reject).font(.system(size: 11))
                HStack {
                    Text("Note").font(.system(size: 11)).frame(width: 52, alignment: .leading)
                    TextField("Shown when the cell's selected", text: $rule.help)
                }
            }
            HStack {
                Spacer()
                Button("Apply", action: apply).keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            range = rule.range.a1
            choices = rule.choices.joined(separator: ", ")
        }
    }

    private func apply() {
        if let typed = CellRange(range.trimmingCharacters(in: .whitespaces).uppercased().replacingOccurrences(of: "$", with: "")) { rule.range = typed }
        rule.choices = choices.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        sheets.updateValidation(rule)
        range = rule.range.a1
    }
}

// MARK: Cleaning a column

private struct CleanPanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var sheets: SheetsModel
    @Environment(\.colorScheme) private var scheme
    @State private var separator = " "

    var body: some View {
        let issues = sheets.columnIssues
        Text(sheets.cleaningTitle)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(theme.ink(scheme))
        PanelHint(text: "George checks the column you're in. Click another column to check that one.")
        if issues.isEmpty {
            PanelCard {
                Label("Nothing to clean here.", systemImage: "checkmark")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkSecondary(scheme))
            }
        }
        ForEach(issues) { issue in
            PanelCard {
                Text(issue.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(theme.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                if !issue.example.isEmpty {
                    Text("Like \(issue.example)")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .lineLimit(1)
                }
                HStack {
                    Button("Show") { show(issue) }
                    Spacer()
                    Button(issue.kind.fix) { sheets.fix(issue.kind) }
                        .buttonStyle(.vellumPrimary)
                }
            }
        }
        SectionLabel(text: "Tidy")
            .padding(.top, 4)
        HStack {
            Text("Capitals").font(.system(size: 11.5))
            Spacer()
            Menu("Change…") {
                ForEach(ColumnDoctor.CaseStyle.allCases) { style in
                    Button(style.title) { sheets.setCase(style) }
                }
            }
            .menuStyle(.button)
            .fixedSize()
        }
        HStack {
            Text("Split at").font(.system(size: 11.5))
            Picker("", selection: $separator) {
                Text("Spaces").tag(" ")
                Text("Commas").tag(",")
                Text("Hyphens").tag("-")
                Text("Slashes").tag("/")
                Text("@ (emails)").tag("@")
            }
            .labelsHidden()
            .fixedSize()
            Spacer()
            Button("Split") { sheets.split(by: separator) }
        }
        PanelHint(text: "Every fix is one step to undo (⌘Z).")
    }

    private func show(_ issue: ColumnIssue) {
        guard let first = issue.rows.first, let last = issue.rows.last else { return }
        let column = sheets.active.column
        sheets.select(CellRange(CellAddress(row: first, column: column), CellAddress(row: last, column: column)))
    }
}

// MARK: Comments

private struct CommentThread: Identifiable {
    var address: CellAddress
    var comments: [GridComment]
    var id: CellAddress { address }
}

private struct CommentsPanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var sheets: SheetsModel
    @Environment(\.colorScheme) private var scheme
    @State private var draft = ""
    @State private var replies: [CellAddress: String] = [:]

    var body: some View {
        let threads = sheets.threads
        PanelCard(selected: true) {
            Text("Comment on \(sheets.active.a1)")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(theme.ink(scheme))
            TextField("Say something, or ask @George", text: $draft, axis: .vertical)
                .lineLimit(2...5)
            HStack {
                if sheets.commentRun != nil {
                    ProgressView().controlSize(.small)
                    Text("George is reading the sheet…").font(.system(size: 11)).foregroundStyle(theme.inkTertiary(scheme))
                }
                Spacer()
                Button("Comment") {
                    sheets.addComment(draft, at: sheets.active)
                    draft = ""
                }
                .buttonStyle(.vellumPrimary)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        if threads.isEmpty {
            PanelHint(text: "No comments on this sheet. Ask George about a number with @George and he answers from the sheet.")
        }
        ForEach(threads.map { CommentThread(address: $0.address, comments: $0.comments) }) { thread in
            PanelCard(selected: thread.address == sheets.active) {
                HStack {
                    Button(thread.address.a1) { sheets.select(thread.address) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    Text(sheets.display(thread.address))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .lineLimit(1)
                    Spacer()
                    Button("Resolve") { sheets.resolveThread(thread.address) }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                }
                ForEach(thread.comments) { comment in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            if comment.author == "George" {
                                AgentLogo(code: "ge", size: 12, color: theme.inkSecondary(scheme))
                            }
                            Text(comment.author).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.ink(scheme))
                            Text(comment.date.formatted(.relative(presentation: .named)))
                                .font(.system(size: 10.5))
                                .foregroundStyle(theme.inkTertiary(scheme))
                        }
                        Text(comment.text)
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.ink(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .contextMenu {
                        Button("Delete comment", role: .destructive) { sheets.deleteComment(comment.id) }
                    }
                }
                HStack {
                    TextField("Reply", text: Binding(get: { replies[thread.address] ?? "" }, set: { replies[thread.address] = $0 }))
                        .onSubmit { reply(thread.address) }
                    Button {
                        reply(thread.address)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .disabled((replies[thread.address] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func reply(_ address: CellAddress) {
        sheets.addComment(replies[address] ?? "", at: address)
        replies[address] = ""
    }
}

// MARK: Versions

struct SheetsVersionsView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var sheets: SheetsModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let versions = sheets.versions()
        VStack(alignment: .leading, spacing: 12) {
            Text("Earlier versions")
                .font(theme.display(22))
                .foregroundStyle(theme.ink(scheme))
            Text("Sheets keeps a copy every ten minutes while you work: everything from the last day, then one a day for a month.")
                .font(.system(size: 12))
                .foregroundStyle(theme.inkSecondary(scheme))
                .fixedSize(horizontal: false, vertical: true)
            if versions.isEmpty {
                Text("No earlier versions yet. The first is kept as soon as you make a change.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(versions) { version in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(version.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(theme.ink(scheme))
                                    Text(version.date.formatted(.relative(presentation: .named)))
                                        .font(.system(size: 11))
                                        .foregroundStyle(theme.inkTertiary(scheme))
                                }
                                Spacer()
                                Button("Restore") { sheets.restore(version) }
                                    .buttonStyle(.vellumSecondary)
                            }
                            .padding(.vertical, 7)
                            .overlay(alignment: .bottom) { Rectangle().fill(theme.edge(scheme)).frame(height: 0.5) }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
            HStack {
                Spacer()
                Button("Done") { sheets.showsVersions = false }
                    .buttonStyle(.vellumPrimary)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 440)
    }
}
