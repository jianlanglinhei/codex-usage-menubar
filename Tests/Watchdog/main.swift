import AppKit
precondition(!SleepKeeper.shouldSleep(for: .nominal))
precondition(!SleepKeeper.shouldSleep(for: .fair))
precondition(SleepKeeper.shouldSleep(for: .serious))
precondition(SleepKeeper.shouldSleep(for: .critical))
let script = SleepKeeper.watchdogScript(pid: Int32(CommandLine.arguments[1])!, marker: CommandLine.arguments[2], seconds: Int(CommandLine.arguments[3])!)
let command = "/usr/bin/nohup /bin/sh -c \(SleepKeeper.quote(script)) </dev/null >/dev/null 2>&1 &"
var error: NSDictionary?
guard NSAppleScript(source: SleepKeeper.appleScriptSource(command: command))!.compileAndReturnError(&error) else {
    fputs("AppleScript compile failed: \(String(describing: error))", stderr)
    exit(1)
}
print(script)
