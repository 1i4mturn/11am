import Foundation

// Checks Johnny's terminal engine: the screen a program draws (text, wrapping, cursor, erasing, colours, scrolling,
// the alternate screen, wide and combined characters), status answers, titles, links and shell marks, re-wrapping
// on resize, the keys and mouse sent back, and real shells in a pseudo-terminal.

var failures = 0
func check(_ condition: Bool, _ name: String) {
    print(condition ? "PASS" : "FAIL", name)
    if !condition { failures += 1 }
}

func terminal(_ columns: Int = 20, _ rows: Int = 5, _ text: String = "") -> TerminalEmulator {
    let emulator = TerminalEmulator(columns: columns, rows: rows)
    emulator.feed(text)
    return emulator
}

func row(_ emulator: TerminalEmulator, _ y: Int) -> String { emulator.screen[y].text }

/// Spins the main run loop until something is true, or gives up.
@discardableResult
func waitFor(_ seconds: Double = 10, until condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition() && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    return condition()
}

// Text, line breaks and wrapping
var t = terminal(20, 5, "hello\r\nworld")
check(row(t, 0) == "hello" && row(t, 1) == "world" && t.cursorX == 5 && t.cursorY == 1, "Text and line breaks")
t = terminal(10, 5, String(repeating: "a", count: 25))
check(t.screen[0].wrapped && t.screen[1].wrapped && !t.screen[2].wrapped && row(t, 2) == "aaaaa" && t.cursorX == 5 && t.cursorY == 2,
      "Long lines wrap and remember they did")
t = terminal(10, 5, String(repeating: "b", count: 10))
check(t.cursorX == 9 && t.cursorY == 0 && !t.screen[0].wrapped, "Filling a line exactly waits before wrapping")
t.feed("\r\nc")
check(t.cursorY == 1 && row(t, 1) == "c" && !t.screen[0].wrapped, "…so a line break after it doesn't leave a blank line")

// Cursor and erasing
t = terminal(20, 5, "\u{1B}[2;3HX")
check(t.screen[1].cells[2].text == "X", "Move the cursor (CUP)")
t.feed("\u{1B}[1;1H\u{1B}[2J")
check(t.screenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Clear the screen")
t = terminal(20, 5, "abcdef\u{1B}[3D\u{1B}[K")
check(row(t, 0) == "abc", "Erase to the end of the line")
t = terminal(20, 5, "abcdef\r\u{1B}[2P")
check(row(t, 0) == "cdef", "Delete characters")
t.feed("\r\u{1B}[2@")
check(row(t, 0) == "  cdef", "Insert blanks")
t = terminal(20, 5, "a\tb")
check(t.screen[0].cells[8].text == "b", "Tabs stop every eight columns")
t = terminal(20, 5, "a\u{1B}[3b")
check(row(t, 0) == "aaaa", "Repeat the last character")
t = terminal(20, 4, "1\r\n2\r\n3\r\n4\u{1B}[2;1H\u{1B}[L")
check(row(t, 0) == "1" && row(t, 1) == "" && row(t, 2) == "2" && row(t, 3) == "3", "Insert a line")
t.feed("\u{1B}[M")
check(row(t, 1) == "2" && row(t, 3) == "", "Delete a line")

// Colour and style
t = terminal(20, 5, "\u{1B}[1;31mR\u{1B}[38;5;208mO\u{1B}[38;2;1;2;3mT\u{1B}[38:2::4:5:6mC\u{1B}[0mN\u{1B}[97;44mB")
let cells = t.screen[0].cells
check(cells[0].style.flags.contains(.bold) && cells[0].style.foreground == .indexed(1), "Bold red")
check(cells[1].style.foreground == .indexed(208) && cells[1].style.flags.contains(.bold), "256 colours keep the bold")
check(cells[2].style.foreground == .rgb(1, 2, 3) && cells[3].style.foreground == .rgb(4, 5, 6), "True colour, both spellings")
check(cells[4].style == TermStyle(), "Reset")
check(cells[5].style.foreground == .indexed(15) && cells[5].style.background == .indexed(4), "Bright text on a background")
t = terminal(10, 3, "\u{1B}[44m\u{1B}[2K")
check(t.screen[0].cells.allSatisfy { $0.style.background == .indexed(4) }, "Erasing keeps the background colour")

// Scrolling, regions, the alternate screen
t = terminal(10, 3, (1...10).map(String.init).joined(separator: "\r\n"))
check(t.scrollback.count == 7 && row(t, 0) == "8" && row(t, 2) == "10" && t.line(t.firstLine)?.text == "1", "Lines scroll into the scrollback")
t = terminal(10, 5, "top\u{1B}[5;1Hbottom\u{1B}[2;4r\u{1B}[4;1Hx\n")
check(row(t, 0) == "top" && row(t, 4) == "bottom" && row(t, 2) == "x" && t.scrollback.isEmpty, "A scroll region scrolls only inside itself")
t = terminal(20, 5, "main\u{1B}[?1049h\u{1B}[Halt screen")
check(t.isAlternateScreen && row(t, 0) == "alt screen", "Full-screen programs get their own screen")
t.feed("\u{1B}[?1049l")
check(!t.isAlternateScreen && row(t, 0) == "main" && t.cursorX == 4 && t.cursorY == 0, "…and leave the shell as it was")
t = terminal(10, 3, "\u{1B}[?1049h" + (1...10).map(String.init).joined(separator: "\r\n"))
check(t.scrollback.isEmpty, "The alternate screen keeps nothing in the scrollback")

// Characters
t = terminal(10, 3, "日本")
check(t.screen[0].cells[0].width == 2 && t.screen[0].cells[1].width == 0 && t.screen[0].cells[2].text == "本" && t.cursorX == 4,
      "Wide characters take two cells")
t.feed("\u{1B}[1;2HX")
check(t.screen[0].cells[0].text.isEmpty && t.screen[0].cells[1].text == "X", "Writing over half a wide character clears it")
t = terminal(10, 3, "👍 👨\u{200D}👩\u{200D}👧 🇦🇺 e\u{301}")
let line = t.screen[0].cells
check(line[0].width == 2 && line[3].text == "👨\u{200D}👩\u{200D}👧" && line[3].width == 2 && line[6].text == "🇦🇺",
      "Emoji, joined emoji and flags each take one wide cell")
check(line[9].text == "e\u{301}" && t.cursorX == 9 && t.screen[0].wrapped == false, "Accents join the letter before them")
t = terminal(10, 3)
t.feed([0xE6])
t.feed([0x97, 0xA5])
check(t.screen[0].cells[0].text == "日", "UTF-8 split between reads")
t = terminal(10, 3, "\u{1B}(0qx\u{1B}(Bq")
check(row(t, 0) == "─│q", "Line-drawing characters")
t = terminal(10, 3, "12345678\u{1B}[1;10H日")
check(t.screen[0].wrapped && t.screen[1].cells[0].text == "日", "A wide character that doesn't fit wraps whole")

// Answers, titles, folders, links, marks
var answers: [String] = []
t = terminal(20, 5)
t.onResponse = { answers.append(String(decoding: $0, as: UTF8.self)) }
t.feed("\u{1B}[3;4H\u{1B}[6n\u{1B}[c\u{1B}[5n")
check(answers.count == 3 && answers[0] == "\u{1B}[3;4R" && answers[1].hasPrefix("\u{1B}[?") && answers[2] == "\u{1B}[0n", "Answers status queries")
t.feed("\u{1B}]0;Build server\u{07}\u{1B}]7;file://mac/Users/me/My%20Folder\u{1B}\\")
check(t.title == "Build server" && t.directory == "/Users/me/My Folder", "Titles and the shell's folder")
t = terminal(30, 3, "\u{1B}]8;;https://11am.app\u{07}Link\u{1B}]8;;\u{07} after")
check(t.screen[0].cells[0].style.link != 0 && t.links[t.screen[0].cells[0].style.link] == "https://11am.app" && t.screen[0].cells[5].style.link == 0,
      "Hyperlinks")
t = terminal(40, 10, "\u{1B}]133;A\u{07}$ \u{1B}]133;B\u{07}ls -la\r\n\u{1B}]133;C\u{07}one\r\ntwo\r\n\u{1B}]133;D;0\u{07}"
    + "\u{1B}]133;A\u{07}$ \u{1B}]133;B\u{07}false\r\n\u{1B}]133;C\u{07}\u{1B}]133;D;1\u{07}\u{1B}]133;A\u{07}$ ")
let commands = t.commands()
check(commands.count == 2 && commands[0].command == "ls -la" && commands[0].exitStatus == 0 && commands[1].command == "false" && commands[1].exitStatus == 1,
      "Shell marks give each command and its exit status (\(commands.map(\.command)))")
check(commands.first.map { t.output(of: $0) } == "one\ntwo", "…and what it printed")

// Searching
t = terminal(20, 5, "hello world\r\nsay HELLO")
let matches = t.find("hello")
check(matches.count == 2 && matches[0].columns == 0..<5 && matches[1].columns == 4..<9, "Search the screen and scrollback")

// Resizing re-wraps
t = terminal(10, 5, String(repeating: "x", count: 25) + "\r\n$ ")
t.resize(columns: 20, rows: 5)
check(row(t, 0).count == 20 && row(t, 1).count == 5 && row(t, 2) == "$" && t.cursorX == 2 && t.cursorY == 2, "Wider: long lines re-wrap")
t.resize(columns: 30, rows: 5)
check(row(t, 0).count == 25 && !t.screen[0].wrapped && row(t, 1) == "$" && t.cursorY == 1, "…into one line when it fits")
t.resize(columns: 5, rows: 5)
check(t.scrollback.count == 1 && row(t, 4) == "$" && t.cursorX == 2 && t.cursorY == 4, "Narrower: more rows, the top goes to the scrollback")
t = terminal(10, 5, "\u{1B}]133;A\u{07}$ \u{1B}]133;B\u{07}echo hi\r\n\u{1B}]133;C\u{07}hi\r\n\u{1B}]133;D;0\u{07}")
t.resize(columns: 7, rows: 8)
check(t.commands().first?.command == "echo hi" && t.commands().first?.exitStatus == 0, "Marks move with their lines when re-wrapping")

// Keys, mouse and paste
func text(_ bytes: [UInt8]) -> String { String(decoding: bytes, as: UTF8.self) }
check(text(TerminalKeys.encode(.up)) == "\u{1B}[A" && text(TerminalKeys.encode(.up, applicationCursor: true)) == "\u{1B}OA", "Arrow keys, both cursor modes")
check(text(TerminalKeys.encode(.left, modifiers: .control)) == "\u{1B}[1;5D" && text(TerminalKeys.encode(.function(5))) == "\u{1B}[15~"
      && text(TerminalKeys.encode(.function(1))) == "\u{1B}OP" && text(TerminalKeys.encode(.tab, modifiers: .shift)) == "\u{1B}[Z", "Modified and function keys")
check(TerminalKeys.encode(text: "c", modifiers: .control) == [3] && TerminalKeys.encode(text: "b", modifiers: .option) == [0x1B, 0x62]
      && TerminalKeys.encode(.backspace) == [0x7F], "Control and Option keys")
check(text(TerminalKeys.mouse(.left, column: 4, row: 2, pressed: true, sgr: true)) == "\u{1B}[<0;5;3M"
      && text(TerminalKeys.mouse(.left, column: 4, row: 2, pressed: false, sgr: true)) == "\u{1B}[<0;5;3m", "Mouse clicks for full-screen programs")
check(text(TerminalKeys.paste("a\nb", bracketed: true)) == "\u{1B}[200~a\rb\u{1B}[201~", "Bracketed paste")

// A real pseudo-terminal
var environment = ProcessInfo.processInfo.environment
environment["TERM"] = "xterm-256color"
environment["BASH_SILENCE_DEPRECATION_WARNING"] = "1"
do {
    let screen = TerminalEmulator(columns: 100, rows: 30)
    let process = try TerminalProcess.start(executable: "/bin/sh", arguments: ["-c", "stty size; printf 'hi\\033[1mthere\\n'"],
                                            environment: environment, directory: NSTemporaryDirectory(), columns: 100, rows: 30)
    var exited: Int32?
    process.onData = { screen.feed($0) }
    process.onExit = { exited = $0 }
    waitFor { exited != nil }
    check(exited == 0 && row(screen, 0) == "30 100" && row(screen, 1) == "hithere" && screen.screen[1].cells[2].style.flags.contains(.bold),
          "A program runs in a pseudo-terminal of the right size (\(screen.screenText.prefix(40)))")

    let resized = TerminalEmulator(columns: 80, rows: 24)
    let sleeper = try TerminalProcess.start(executable: "/bin/sh", arguments: ["-c", "sleep 0.5; stty size"],
                                            environment: environment, directory: NSTemporaryDirectory(), columns: 80, rows: 24)
    var done = false
    sleeper.onData = { resized.feed($0) }
    sleeper.onExit = { _ in done = true }
    sleeper.resize(columns: 120, rows: 40)
    waitFor { done }
    check(row(resized, 0) == "40 120", "Resizing tells the program")
} catch {
    check(false, "Pseudo-terminal: \(error.localizedDescription)")
}

/// Runs an interactive shell with the integration, types commands at each prompt, and returns what the screen saw.
func session(_ shell: String, typing lines: [String]) -> TerminalEmulator? {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("11am-shell-\(UUID().uuidString)", isDirectory: true)
    let prepared = ShellIntegration.prepare(shell: shell, in: folder, environment: environment)
    let screen = TerminalEmulator(columns: 100, rows: 40)
    guard let process = try? TerminalProcess.start(executable: shell, arguments: prepared.arguments, environment: prepared.environment,
                                                   directory: NSTemporaryDirectory(), columns: 100, rows: 40, loginName: shell.hasSuffix("zsh")) else { return nil }
    screen.onResponse = { process.write($0) }
    process.onData = { screen.feed($0) }
    var exited = false
    process.onExit = { _ in exited = true }
    func prompts() -> Int {
        (0..<screen.lineCount).reduce(0) { total, index in
            total + (screen.line(screen.firstLine + index)?.marks.filter { $0.kind == .commandStart }.count ?? 0)
        }
    }
    for (index, line) in lines.enumerated() {
        guard waitFor(15, until: { prompts() > index }) else { break }
        process.write(Array((line + "\r").utf8))
    }
    waitFor(15) { prompts() > lines.count }
    process.write(Array("exit\r".utf8))
    waitFor(10) { exited }
    if !exited { process.terminate() }
    return screen
}

if let zsh = session("/bin/zsh", typing: ["echo hello-11am", "false", "cd /usr"]) {
    let ran = zsh.commands()
    check(ran.count >= 3 && ran[0].command.hasSuffix("echo hello-11am") && ran[0].exitStatus == 0 && zsh.output(of: ran[0]) == "hello-11am"
          && ran[1].command.hasSuffix("false") && ran[1].exitStatus == 1,
          "zsh marks prompts, commands and exit statuses (\(ran.map { "\($0.command)=\($0.exitStatus.map(String.init) ?? "?")" }))")
    check(zsh.directory == "/usr", "zsh says which folder it's in (\(zsh.directory ?? "none"))")
} else {
    check(false, "zsh starts")
}
if let bash = session("/bin/bash", typing: ["echo hello-bash", "false"]) {
    let ran = bash.commands()
    check(ran.count >= 2 && ran[0].command.hasSuffix("echo hello-bash") && ran[0].exitStatus == 0 && ran[1].exitStatus == 1,
          "bash marks prompts, commands and exit statuses (\(ran.map { "\($0.command)=\($0.exitStatus.map(String.init) ?? "?")" }))")
} else {
    check(false, "bash starts")
}

// MARK: Scripts

/// Runs something async from these synchronous tests.
final class Box<T> { var value: T? }
func blocking<T>(_ seconds: Double = 60, _ work: @escaping () async -> T) -> T? {
    let box = Box<T>()
    Task { box.value = await work() }
    waitFor(seconds) { box.value != nil }
    return box.value
}

check(ScriptLanguage.from(extension: "scpt") == .appleScript && ScriptLanguage.from(extension: "js") == .javaScript
      && ScriptLanguage.from(extension: "zsh") == .shell && ScriptLanguage.from(extension: "py") == .python, "Script languages from file names")
let controlling = "tell application \"Mail\"\n  get name\nend tell\ntell app \"Finder\" to activate\nlog (application \"Mail\")"
check(ScriptApps.controlled(by: controlling, language: .appleScript) == ["Mail", "Finder"], "Finds the apps an AppleScript controls")
check(ScriptApps.controlled(by: "const s = Application('Safari'); const me = Application.currentApplication();", language: .javaScript) == ["Safari"],
      "…and a JavaScript one")
var allowed = ScriptDocument(name: "x", language: .appleScript, source: controlling)
allowed.approvedApps = ["mail"]
check(ScriptApps.needingApproval(allowed) == ["Finder"], "Only apps not yet allowed need asking")
let colours = ScriptHighlighter.tokens("-- note\nset x to \"hi\" & 42", language: .appleScript)
check(colours.first?.kind == .comment && colours.contains { $0.kind == .keyword } && colours.contains { $0.kind == .string } && colours.contains { $0.kind == .number },
      "Colours comments, keywords, text and numbers")
check(!ScriptHighlighter.tokens("say \"set to\"", language: .appleScript).contains { $0.kind == .keyword && $0.range.location > 4 },
      "Keywords inside text stay plain")

if let apple = blocking({ try? await ScriptRun.run("log \"hello from the log\"\nreturn 1 + 2", language: .appleScript) }) ?? nil {
    check(apple.output.trimmingCharacters(in: .whitespacesAndNewlines) == "3" && apple.log.contains("hello from the log") && apple.status == 0,
          "AppleScript runs, with its result and log (\(apple.output.trimmingCharacters(in: .newlines)))")
} else { check(false, "AppleScript runs") }
if let jxa = blocking({ try? await ScriptRun.run("[1, 2, 3].map(x => x * 2).join(',')", language: .javaScript) }) ?? nil {
    check(jxa.output.trimmingCharacters(in: .whitespacesAndNewlines) == "2,4,6", "JavaScript for Automation runs (\(jxa.output.trimmingCharacters(in: .newlines)))")
} else { check(false, "JavaScript runs") }
if let shell = blocking({ try? await ScriptRun.run("tr a-z A-Z", language: .shell, input: "quiet") }) ?? nil {
    check(shell.output.trimmingCharacters(in: .newlines) == "QUIET", "Shell scripts get their input")
} else { check(false, "Shell scripts run") }
if let python = blocking({ try? await ScriptRun.run("import sys\nprint(sys.stdin.read()[::-1])", language: .python, input: "abc") }) ?? nil {
    check(python.output.trimmingCharacters(in: .newlines) == "cba", "Python runs (\(python.output.trimmingCharacters(in: .newlines)) \(python.log.prefix(80)))")
} else { check(false, "Python runs") }
let failing = blocking { try? await ScriptRun.run("error \"Nope\" number 42", language: .appleScript) } ?? nil
check(failing.map { $0.status != 0 && $0.log.contains("Nope") } ?? false, "A failing script says why")

check((blocking { await ScriptCompiler.check("tell application \"Finder\" to get name", language: .appleScript) } ?? "x") == nil, "A good script checks out")
let broken = blocking { await ScriptCompiler.check("tell application \"Finder\" to", language: .appleScript) } ?? nil
check(broken != nil && !(broken ?? "").isEmpty, "A broken script is caught without running (\((broken ?? "").prefix(60)))")
check((blocking { await ScriptCompiler.check("function (", language: .javaScript) } ?? nil) != nil, "…in JavaScript too")
check((blocking { await ScriptCompiler.check("if then fi", language: .shell) } ?? nil) != nil
      && (blocking { await ScriptCompiler.check("echo ok", language: .shell) } ?? "x") == nil, "Shell scripts are parsed, not run, to check them")
let built = FileManager.default.temporaryDirectory.appendingPathComponent("11am-test-\(UUID().uuidString)", isDirectory: true)
try? FileManager.default.createDirectory(at: built, withIntermediateDirectories: true)
let appMade = blocking { await ScriptCompiler.compile("display notification \"hi\"\nreturn \"made\"", language: .appleScript, to: built.appendingPathComponent("Made.app")) } ?? "x"
check(appMade == nil && FileManager.default.fileExists(atPath: built.appendingPathComponent("Made.app/Contents/Resources/Scripts/main.scpt").path),
      "Exports a double-clickable app")
let compiled = built.appendingPathComponent("Saved.scpt")
_ = blocking { await ScriptCompiler.compile("return \"round trip\"", language: .appleScript, to: compiled) }
let decompiled = blocking { await ScriptCompiler.decompile(compiled) } ?? nil
check(decompiled?.contains("round trip") == true, "Compiled scripts open again as text")

let sdef = """
<?xml version="1.0" encoding="UTF-8"?>
<dictionary title="Test">
  <suite name="Standard Suite" code="core" description="Common things">
    <command name="open" code="aevtodoc" description="Open something.">
      <direct-parameter type="file"/>
      <parameter name="using" code="usin" type="text" description="With what"/>
    </command>
    <class name="window" code="cwin" description="A window.">
      <property name="name" code="pnam" type="text" description="Its title"/>
      <element type="tab"/>
    </class>
    <enumeration name="saveable" code="savo"><enumerator name="yes" code="yes "/></enumeration>
  </suite>
</dictionary>
"""
let parsed = ScriptDictionary.parse(Data(sdef.utf8))
check(parsed.suites == ["Standard Suite"] && parsed.commands.first?.name == "open" && parsed.commands.first?.details.count == 2
      && parsed.classes.first?.name == "window" && parsed.classes.first?.details.contains { $0.name == "name" } == true,
      "Reads scripting dictionaries")
let finder = blocking { await ScriptDictionary.load(app: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")) } ?? nil
check(finder?.commands.contains { $0.name == "open" } == true && finder?.classes.contains { $0.name == "file" } == true,
      "Loads Finder's dictionary (\(finder?.items.count ?? 0) entries)")
check(ScriptDictionary.scriptableApps().contains { $0.lastPathComponent == "Finder.app" }, "Lists the Mac's scriptable apps")

// MARK: Automations

var sydney = Calendar(identifier: .gregorian)
sydney.timeZone = TimeZone(identifier: "Australia/Sydney")!
func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    sydney.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}
let nineDaily = AutomationSchedule(kind: .daily, hour: 9, minute: 0)
check(nineDaily.next(after: at(4, 8), calendar: sydney) == at(4, 9) && nineDaily.next(after: at(4, 10), calendar: sydney) == at(5, 9),
      "Daily: later today, or tomorrow")
check(AutomationSchedule(kind: .weekdays, hour: 9).next(after: at(6, 10), calendar: sydney) == at(9, 9), "Weekdays skip the weekend (Friday to Monday)")
check(AutomationSchedule(kind: .weekly, hour: 17, minute: 30, weekday: 6).next(after: at(4, 12), calendar: sydney) == at(6, 17, 30), "Weekly on a Friday")
check(AutomationSchedule(kind: .every, minutes: 15).next(after: at(4, 12), calendar: sydney) == at(4, 12, 15), "Every 15 minutes")

check(AutomationTemplate.fill("{{input}} · {{trigger}} · {{item}}", input: " result\n", trigger: "file.pdf", item: "x") == "result · file.pdf · x",
      "Fills in the blanks")
let awkward = "it's a \"file\"; rm -rf ~.pdf"
let quoted = AutomationTemplate.fillShell("printf %s {{item}}", input: "", trigger: "", item: awkward)
if let echoed = blocking({ await AutomationServices.runShell(quoted, input: "") }) {
    check(echoed.output == awkward && echoed.ok, "Values go into shell commands quoted, so they can't change the command")
} else { check(false, "Quoted shell values") }
check(AutomationTemplate.fillShell("echo '{{input}}'", input: "a'b", trigger: "") == "echo 'a'\\''b'", "…even when the command already quoted them")
check(AutomationCondition(test: .contains, text: "error").passes(result: "An ERROR here", succeeded: true)
      && !AutomationCondition(test: .isNotEmpty).passes(result: "  \n", succeeded: true)
      && AutomationCondition(test: .lacks, text: "x").passes(result: "abc", succeeded: true), "Conditions")

let watched = FileManager.default.temporaryDirectory.appendingPathComponent("11am-watch-\(UUID().uuidString)", isDirectory: true)
try? FileManager.default.createDirectory(at: watched, withIntermediateDirectories: true)
FileManager.default.createFile(atPath: watched.appendingPathComponent("old.pdf").path, contents: Data())
var snapshot = FolderSnapshot(path: watched.path)
for name in ["new.pdf", "notes.txt", ".hidden.pdf", "big.pdf.download", "Scan.PDF"] {
    FileManager.default.createFile(atPath: watched.appendingPathComponent(name).path, contents: Data())
}
let arrived = snapshot.newFiles(in: watched.path, matching: "*.pdf").map { ($0 as NSString).lastPathComponent }
check(arrived == ["Scan.PDF", "new.pdf"], "Spots new files in a folder, by pattern (\(arrived))")
check(snapshot.newFiles(in: watched.path, matching: "").isEmpty, "…and only once")
check(FolderSnapshot.matches("photo.png", "*.pdf, *.png") && !FolderSnapshot.matches("photo.jpg", "*.pdf, *.png"), "Several patterns")

var notified: [String] = []
var noted: [String] = []
var approvals = true
let readable = watched.appendingPathComponent("letter.txt")
try? "Dear Sam, the invoice is attached.".write(to: readable, atomically: true, encoding: .utf8)
let services = AutomationServices(
    shell: { command, input in await AutomationServices.runShell(command, input: input) },
    script: { _, input in ("script saw \(input)", true) },
    agent: { prompt in prompt.uppercased() },
    notify: { title, body in notified.append("\(title): \(body)") },
    appendNote: { title, text in noted.append("\(title)|\(text)") },
    approve: { _ in approvals },
    shortcut: { name, input in ("\(name) got \(input)", true) },
    readText: { path in try? String(contentsOfFile: path, encoding: .utf8) }
)
func runAutomation(_ steps: [AutomationStep], trigger: String = "manual") -> (status: AutomationRun.Status, output: String, log: [String])? {
    let automation = Automation(name: "Test", trigger: .button, steps: steps)
    let lines = Box<[String]>()
    lines.value = []
    guard let outcome = blocking({ await AutomationRunner.run(automation, trigger: trigger, services: services, log: { lines.value?.append($0) }) }) else { return nil }
    return (outcome.status, outcome.output, lines.value ?? [])
}
let full = runAutomation([
    .shell("printf 'one\\ntwo\\n'"),
    .forEach("echo item-{{item}}"),
    .condition(AutomationCondition(test: .contains, text: "item-two")),
    .agent("shout {{input}}"),
    .approval("ok?"),
    .appendNote(title: "Log {{date}}", text: "{{input}}"),
    .notify(title: "Done", body: "{{input}}"),
])
check(full?.status == .succeeded && full?.output == "SHOUT ITEM-ONE\nITEM-TWO" && noted.count == 1 && noted[0].hasSuffix("SHOUT ITEM-ONE\nITEM-TWO")
      && notified == ["Done: SHOUT ITEM-ONE\nITEM-TWO"], "Steps pass their results along (\(full?.output ?? "nil"))")
check(runAutomation([.shell("echo nothing to see"), .condition(AutomationCondition(test: .contains, text: "error")), .notify(title: "x", body: "")])?.status == .skipped
      && notified.count == 1, "A condition that fails stops the run as skipped")
check(runAutomation([.shell("echo partway; exit 3"), .notify(title: "never", body: "")])?.status == .failed && notified.count == 1, "A failing step stops the run")
approvals = false
check(runAutomation([.approval("May I?"), .notify(title: "never", body: "")])?.status == .stopped, "Saying no stops it")
let documentRun = runAutomation([.readText("{{trigger}}"), .script(UUID())], trigger: readable.path)
check(documentRun?.status == .succeeded && documentRun?.output == "script saw Dear Sam, the invoice is attached.", "Reads a document, then hands it to a script")
check(runAutomation([.readText("/nowhere/at/all.pdf")])?.status == .failed, "A missing document fails clearly")
let everything = Automation(name: "All", trigger: .folder(path: "/tmp", pattern: "*.pdf"), steps: [
    .shell("a"), .script(UUID()), .agent("b"), .notify(title: "c", body: "d"), .condition(AutomationCondition(test: .lacks, text: "e")),
    .forEach("f"), .approval("g"), .appendNote(title: "h", text: "i"), .shortcut("j"), .readText("k"),
])
let roundTrip = try? JSONDecoder().decode(Automation.self, from: JSONEncoder().encode(everything))
check(roundTrip == everything, "Automations save and load, every step kind")
check(AutomationTemplates.all().count >= 4 && AutomationTemplates.all().allSatisfy { !$0.enabled }, "Ready-made automations start switched off")

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
