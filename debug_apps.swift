import Cocoa

let workspace = NSWorkspace.shared
let apps = workspace.runningApplications

print("--- Running Applications ---")
for app in apps {
    if app.activationPolicy == .regular {
        print("Name: \(app.localizedName ?? "N/A")")
        print("  Bundle ID: \(app.bundleIdentifier ?? "N/A")")
        print("  PID: \(app.processIdentifier)")
        print("  Executable URL: \(app.executableURL?.path ?? "N/A")")
        print("---------------------------")
    }
}
