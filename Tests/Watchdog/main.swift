import AppKit
precondition(!SleepKeeper.shouldSleep(for: .nominal))
precondition(!SleepKeeper.shouldSleep(for: .fair))
precondition(SleepKeeper.shouldSleep(for: .serious))
precondition(SleepKeeper.shouldSleep(for: .critical))
let script = SleepKeeper.watchdogScript(pid: Int32(CommandLine.arguments[1])!, marker: CommandLine.arguments[2], seconds: Int(CommandLine.arguments[3])!)
precondition(SleepKeeper.startupFailure("CODEX_USAGE_READY\r") == nil)
precondition(SleepKeeper.startupFailure("") != nil)
precondition(SleepKeeper.startupFailure("CODEX_USAGE_ERROR:battery:1") != SleepKeeper.startupFailure("CODEX_USAGE_ERROR:pmset"))
let command = SleepKeeper.launchCommand(script: script)
// nohup exits without running anything under administrator privileges ("can't detach from console").
precondition(!command.contains("nohup"))
var error: NSDictionary?
guard NSAppleScript(source: SleepKeeper.appleScriptSource(command: command))!.compileAndReturnError(&error) else {
    fputs("AppleScript compile failed: \(String(describing: error))", stderr)
    exit(1)
}
print(CommandLine.arguments.contains("--launcher") ? command : script)
