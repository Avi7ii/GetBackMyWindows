import Cocoa
import CoreGraphics

// Helper to print window info
func printWindowInfo() {
    let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
    guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        print("Failed to get window list")
        return
    }
    
    print("--- Scanning WeChat Windows ---")
    
    // Find all running apps with "WeChat" in name or bundle
    let apps = NSWorkspace.shared.runningApplications.filter {
        ($0.localizedName?.contains("微信") == true) || 
        ($0.bundleIdentifier?.contains("WeChat") == true) ||
        ($0.bundleURL?.path.contains("WeChat") == true)
    }
    
    for app in apps {
        print("App: \(app.localizedName ?? "N/A") (PID: \(app.processIdentifier))")
        print("    Bundle: \(app.bundleIdentifier ?? "N/A")")
        print("    IsActive: \(app.isActive)")
        
        // Find windows for this PID
        let appWindows = infoList.filter {
            ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier
        }
        
        if appWindows.isEmpty {
            print("    [No Windows Found in CGWindowList]")
        } else {
            for win in appWindows {
                let name = win[kCGWindowName as String] as? String ?? ""
                let number = win[kCGWindowNumber as String] as? Int ?? -1
                let layer = win[kCGWindowLayer as String] as? Int ?? -1
                let bounds = win[kCGWindowBounds as String] as? [String: Any] ?? [:]
                let alpha = win[kCGWindowAlpha as String] as? Double ?? 1.0
                
                print("    - WinID: \(number)")
                print("      Name: '\(name)'")
                print("      Layer: \(layer)")
                print("      Bounds: \(bounds)")
                print("      Alpha: \(alpha)")
            }
        }
        print("--------------------------------------------------")
    }
}

printWindowInfo()
