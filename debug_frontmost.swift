import Cocoa
import CoreGraphics

print("--- Frontmost Application ---")
if let front = NSWorkspace.shared.frontmostApplication {
    print("Name: \(front.localizedName ?? "N/A")")
    print("PID: \(front.processIdentifier)")
    print("Bundle: \(front.bundleIdentifier ?? "N/A")")
}

print("\n--- Top 5 Visible Windows (Z-Order) ---")
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
if let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
    for (i, win) in infoList.prefix(5).enumerated() {
        let name = win[kCGWindowName as String] as? String ?? "N/A"
        let owner = win[kCGWindowOwnerName as String] as? String ?? "N/A"
        let pid = win[kCGWindowOwnerPID as String] as? Int32 ?? 0
        let layer = win[kCGWindowLayer as String] as? Int ?? 0
        print("[\(i)] \(name) (Owner: \(owner), PID: \(pid), Layer: \(layer))")
    }
}
