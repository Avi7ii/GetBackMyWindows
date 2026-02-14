import Cocoa
import CoreGraphics

// Get Finder PID
let workspace = NSWorkspace.shared
guard let finder = workspace.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.finder" }) else {
    print("Finder not running")
    exit(1)
}

print("Finder PID: \(finder.processIdentifier)")

let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as! [[String: Any]]

print("--- Visible Windows (Finder) ---")
for entry in infoList {
    if let ownerPID = entry[kCGWindowOwnerPID as String] as? Int32, ownerPID == finder.processIdentifier {
        let name = entry[kCGWindowName as String] as? String ?? ""
        let layer = entry[kCGWindowLayer as String] as? Int ?? 0
        let bounds = entry[kCGWindowBounds as String] as? [String: Any] ?? [:]
        print("Name: '\(name)', Layer: \(layer), Bounds: \(bounds)")
    }
}
