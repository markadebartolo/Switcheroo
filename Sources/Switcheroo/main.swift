import AppKit

let application = NSApplication.shared
if CommandLine.arguments.contains("--self-test") {
    do { try SelfTest.run(); exit(0) }
    catch { fputs("Switcheroo self-test failed: \(error)\n", stderr); exit(1) }
}
let delegate = AppDelegate()
application.delegate = delegate
application.run()
