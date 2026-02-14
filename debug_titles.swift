import Cocoa
import CoreGraphics

// Get PID
let workspace = NSWorkspace.shared
guard let app = workspace.runningApplications.first(where: { $0.bundleIdentifier == "com.tencent.xinWeChat" }) else {
    print("WeChat not running")
    exit(1)
}
let pid = app.processIdentifier
print("WeChat PID: \(pid)")

let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as! [[String: Any]]

print("--- WeChat Windows ---")
for entry in infoList {
    if let ownerPID = entry[kCGWindowOwnerPID as String] as? Int32, ownerPID == pid {
        print("ID: \(entry[kCGWindowNumber as String] ?? 0)")
        print("Title: '\(entry[kCGWindowName as String] ?? "")'")
        print("Layer: \(entry[kCGWindowLayer as String] ?? -1)")
        print("Bounds: \(entry[kCGWindowBounds as String] ?? "")")
        print("Alpha: \(entry[kCGWindowAlpha as String] ?? 0)")
        print("IsOnScreen: \(entry[kCGWindowIsOnscreen as String] ?? false)")
        print("---------------------------")
    }
}
