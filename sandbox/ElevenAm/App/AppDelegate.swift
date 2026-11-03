import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var notch: NotchController?
    private var askHotKey: HotKey?
    private var noteHotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        FontRegistry.registerBundledFonts()

        let notch = NotchController(model: model)
        notch.show()
        self.notch = notch

        // ⌥Space opens Ask in the notch from anywhere.
        askHotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) { [weak self] in
            self?.openAsk()
        }
        // ⌥⇧N jots a note from anywhere.
        noteHotKey = HotKey(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(optionKey | shiftKey)) { [weak self] in
            self?.quickNote()
        }

        model.start()
        applyLaunchArguments(notch: notch)
    }

    /// Developer flags for screenshots and quick checks, e.g.
    /// `ElevenAm -startSection lab -forceAppearance dark -openNotch YES -activate YES`
    private func applyLaunchArguments(notch: NotchController) {
        let arguments = UserDefaults.standard
        if let start = arguments.string(forKey: "startSection"), let section = AppSection(rawValue: start) {
            model.section = section
        }
        if let appearance = arguments.string(forKey: "forceAppearance"), let value = Appearance(rawValue: appearance) {
            model.theme.values.appearance = value
        }
        if arguments.bool(forKey: "openNotch") {
            notch.openPreview()
        }
        if let tool = arguments.string(forKey: "photoTool"), let value = PhotoTool(rawValue: tool) {
            model.photo.tool = value
        }
        // -photoLook and -videoLook take a built-in look's name, e.g. "Teal & orange".
        if let name = arguments.string(forKey: "photoLook"), let look = LookLibrary.builtIns.first(where: { $0.name == name }) {
            model.photo.settings = look.settings
        }
        if arguments.bool(forKey: "videoSample") {
            let look = arguments.string(forKey: "videoLook").flatMap { name in LookLibrary.builtIns.first { $0.name == name } }
            model.video.loadSamples(grade: look?.settings)
        }
        // -calendarMode month, -calendarEvent kickoff (selects a sample event), -calendarNew YES (opens the editor).
        if let mode = arguments.string(forKey: "calendarMode").flatMap(CalendarMode.init(rawValue:)) {
            model.calendar.mode = mode
        }
        if let event = arguments.string(forKey: "calendarEvent") {
            model.calendar.selectedID = "sample:\(event)"
        }
        if arguments.bool(forKey: "calendarNew") {
            model.calendar.newEvent(at: CalendarView.suggestedStart(for: model.calendar))
        }
        // -pdfSample YES opens the sample agreement; -pdfMode pages; -pdfTool redact.
        if arguments.bool(forKey: "pdfSample") {
            model.pdf.loadSample()
        }
        if let mode = arguments.string(forKey: "pdfMode").flatMap(PDFMode.init(rawValue:)) {
            model.pdf.mode = mode
        }
        if let tool = arguments.string(forKey: "pdfTool").flatMap(PDFTool.init(rawValue:)) {
            model.pdf.tool = tool
        }
        // -writeDoc 1 opens the second sample document; -writePageSetup YES opens page setup.
        if arguments.object(forKey: "writeDoc") != nil {
            let index = arguments.integer(forKey: "writeDoc")
            if index < model.write.documents.count { model.write.selectedID = model.write.documents[index].id }
        }
        // -notesFolder Work picks a folder; -notesNote "Acme pilot" opens a note.
        if let folder = arguments.string(forKey: "notesFolder") {
            model.notes.scope = .folder(folder)
        }
        if let title = arguments.string(forKey: "notesNote"), let note = model.notes.note(titled: title) {
            model.notes.selectedID = note.id
        }
        // -sheetsBook "Japan trip" opens a workbook; -sheetsSheet 1 a sheet; -sheetsSelect A1:E7 a range.
        if let name = arguments.string(forKey: "sheetsBook") {
            model.sheets.open(named: name)
        }
        if arguments.object(forKey: "sheetsSheet") != nil {
            model.sheets.showSheet(arguments.integer(forKey: "sheetsSheet"))
        }
        if let text = arguments.string(forKey: "sheetsSelect"), let range = CellRange(text) {
            model.sheets.select(range)
        }
        // -moneyTab bank opens a Money tab; -moneyInvoice INV-0004 selects one; -moneyEditor YES starts a new invoice.
        if let tab = arguments.string(forKey: "moneyTab").flatMap(MoneyTab.init(rawValue:)) {
            model.ledger.tab = tab
        }
        if let number = arguments.string(forKey: "moneyInvoice"), let invoice = model.ledger.book.invoices.first(where: { $0.number == number }) {
            model.ledger.selectedInvoice = invoice.id
        }
        if arguments.bool(forKey: "moneyEditor") {
            model.ledger.newInvoice(.sale)
            if var draft = model.ledger.editing, let contact = model.ledger.book.contacts.first {
                draft.contact = contact.id
                draft.lines[0].description = "Brand refresh, phase 1"
                draft.lines[0].quantity = 1
                draft.lines[0].unitPrice = 480_000
                draft.lines.append(InvoiceLine(description: "Workshop facilitation", quantity: 6, unitPrice: 18_000, account: "200", gst: .gst))
                model.ledger.editing = draft
            }
        }
        // -designName Founder opens a design; -designTab graphic picks a Design tab; -designSelect 2 selects a layer.
        if let name = arguments.string(forKey: "designName") {
            model.studio.open(named: name)
        }
        if let tab = arguments.string(forKey: "designTab").flatMap(DesignView.DesignTab.init(rawValue:)) {
            model.studio.tab = tab
        }
        if arguments.object(forKey: "designSelect") != nil {
            let index = arguments.integer(forKey: "designSelect")
            let layers = model.studio.controller.document.layers
            if layers.indices.contains(index) { model.studio.controller.select(layers[index].id) }
        }
        // -decksSlide 3 shows a slide; -decksPresent YES starts presenting.
        if arguments.object(forKey: "decksSlide") != nil {
            model.decks.showSlide(arguments.integer(forKey: "decksSlide"))
        }
        if arguments.bool(forKey: "decksPresent") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.model.decks.present() }
        }
        // -audioProject Founders opens a project; -audioClip YES selects the first clip; -audioTab 2 picks a panel.
        if let name = arguments.string(forKey: "audioProject") {
            model.audio.open(named: name)
        }
        if arguments.bool(forKey: "audioClip") {
            model.audio.selectFirstClip = true
            model.audio.selectFirstClipIfAsked()
        }
        if arguments.object(forKey: "audioTab") != nil {
            model.audio.panelTab = arguments.integer(forKey: "audioTab")
        }
        if arguments.bool(forKey: "activate") {
            NSApp.activate()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.sheets.flushSave()
        model.studio.flushSave()
        model.decks.flushSave()
        model.audio.flushSave()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 11am keeps living in the notch when its windows are closed.
        false
    }

    func openAsk() {
        notch?.openAsk()
    }

    /// A new note, ready to type into, from anywhere.
    func quickNote() {
        NSApp.activate()
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        model.go(to: .notes)
        model.notes.scope = .all
        model.notes.newNote()
        model.notes.wantsFocus = true
    }
}
