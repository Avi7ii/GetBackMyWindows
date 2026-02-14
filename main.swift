import Cocoa
import Carbon

// MARK: - Constants & Defaults
let kGlobalEvents: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue)

struct AppDefaults {
    static let hotKeyCode = "GlobalHotKeyCode"
    static let hotKeyModifiers = "GlobalHotKeyModifiers"
    
    // Default: Control + A (kVK_ANSI_A = 0x00)
    static let defaultKeyCode = kVK_ANSI_A
    static let defaultModifiers = controlKey
}

// MARK: - Auto Start Manager
class AutoStartManager {
    static let shared = AutoStartManager()
    
    private var launchAgentURL: URL? {
        guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return nil }
        return library.appendingPathComponent("LaunchAgents/com.user.GetBackMyWindows.plist")
    }
    
    var isEnabled: Bool {
        guard let url = launchAgentURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    func toggle(_ enable: Bool) {
        guard let url = launchAgentURL, let execPath = Bundle.main.executablePath else { return }
        
        if enable {
            // Create plist
            let dict: [String: Any] = [
                "Label": "com.user.GetBackMyWindows",
                "ProgramArguments": [execPath],
                "RunAtLoad": true,
                "ProcessType": "Interactive"
            ]
            let plistContent = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
            
            // Ensure directory exists
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? plistContent?.write(to: url)
        } else {
            // Remove plist
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - Hotkey Manager
class HotkeyManager {
    static let shared = HotkeyManager()
    
    var hotKeyRef: EventHotKeyRef?
    var eventHandlerRef: EventHandlerRef?
    
    var currentKeyCode: Int {
        get { UserDefaults.standard.object(forKey: AppDefaults.hotKeyCode) as? Int ?? AppDefaults.defaultKeyCode }
        set { UserDefaults.standard.set(newValue, forKey: AppDefaults.hotKeyCode) }
    }
    
    var currentModifiers: Int {
        get { UserDefaults.standard.object(forKey: AppDefaults.hotKeyModifiers) as? Int ?? AppDefaults.defaultModifiers }
        set { UserDefaults.standard.set(newValue, forKey: AppDefaults.hotKeyModifiers) }
    }
    
    func registerHotkey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        
        let hotKeyID = EventHotKeyID(signature: OSType(0x11223344), id: 1)
        
        let status = RegisterEventHotKey(UInt32(currentKeyCode),
                                         UInt32(currentModifiers),
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &hotKeyRef)
        
        if status != noErr {
            print("Hotkey: Failed to register (Error \(status))")
            return
        }
        
        if eventHandlerRef == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { (_, _, _) -> OSStatus in
                minimizeAllWindows()
                return noErr
            }, 1, &eventType, nil, &eventHandlerRef)
        }
        
        print("Hotkey: Registered Code: \(currentKeyCode), Mods: \(currentModifiers)")
    }
    
    func stringRepresentation() -> String {
        return getKeyString(keyCode: UInt16(currentKeyCode), modifiers: UInt32(currentModifiers))
    }
}

// MARK: - Update Checker
class UpdateChecker {
    static let shared = UpdateChecker()
    static let currentVersion = "2.0.0"
    
    private let defaults = UserDefaults.standard
    private let keyLastCheck = "LastUpdateCheckDate"
    private let keyLatestVersion = "LatestVersionAvailable"
    private let keyAutoCheck = "AutoCheckUpdates"
    
    var isAutoCheckEnabled: Bool {
        get { defaults.object(forKey: keyAutoCheck) as? Bool ?? true } // Default to true
        set { defaults.set(newValue, forKey: keyAutoCheck) }
    }
    
    var latestVersionAvailable: String? {
        get { defaults.string(forKey: keyLatestVersion) }
        set { defaults.set(newValue, forKey: keyLatestVersion) }
    }
    
    func checkForUpdates(force: Bool = false, completion: ((Bool) -> Void)? = nil) {
        if !force {
            if !isAutoCheckEnabled {
                print("UpdateChecker: Auto-check disabled by user.")
                completion?(false)
                return
            }
            
            if let lastCheck = defaults.object(forKey: keyLastCheck) as? Date {
                // Check if 24 hours have passed (86400 seconds)
                if Date().timeIntervalSince(lastCheck) < 86400 {
                    print("UpdateChecker: Check skipped (Last check: \(lastCheck))")
                    completion?(false)
                    return
                }
            }
        }
        
        print("UpdateChecker: Checking for updates...")
        guard let url = URL(string: "https://api.github.com/repos/Avi7ii/GetBackMyWindows/releases/latest") else {
            completion?(false)
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            
            // Record check time even if it fails, to prevent spamming
            self.defaults.set(Date(), forKey: self.keyLastCheck)
            
            guard let data = data, error == nil else {
                print("UpdateChecker: Network error - \(error?.localizedDescription ?? "Unknown")")
                completion?(false)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let tagName = json["tag_name"] as? String {
                    
                    let cleanTag = tagName.replacingOccurrences(of: "v", with: "")
                    print("UpdateChecker: Latest version found: \(cleanTag)")
                    
                    self.latestVersionAvailable = cleanTag
                    
                    // Simple string comparison for now. Ideally should parse semver.
                    // Assuming format "1.2.0" vs "1.2.1"
                    let hasNew = cleanTag != UpdateChecker.currentVersion
                    completion?(hasNew)
                    
                    if hasNew {
                        DispatchQueue.main.async {
                            if let delegate = NSApp.delegate as? AppDelegate {
                                delegate.updateMenu()
                            }
                        }
                    }
                } else {
                    completion?(false)
                }
            } catch {
                print("UpdateChecker: JSON Parse Error")
                completion?(false)
            }
        }
        task.resume()
    }
}

// MARK: - Main Application Delegate
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    var accessibilityTimer: Timer?  // 权限监控定时器
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        UpdateChecker.shared.checkForUpdates() // Check on launch (debounced)
        
        // Ensure AutoHideManager is active (observers)
        _ = AutoHideManager.shared
        
        // Show Settings if it's likely the first run (no permission)
        // or just always checking permissions.
        checkAccessibilityPermissions()
        
        HotkeyManager.shared.registerHotkey()
        setupEventTap()
        
        // 防止 App Nap (关键修复)
        ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Global Event Listener")
        
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        
        if !AXIsProcessTrusted() {
             SettingsWindowController.shared.show(tab: "General")
        }
    }
    
    @objc func didWake() {
        print("System Woke Up: Resetting Event Tap...")
        // 延迟重置，给系统一点缓冲时间
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.setupEventTap()
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            SettingsWindowController.shared.show()
        }
        return true
    }
    
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "dock.arrow.down.rectangle", accessibilityDescription: "GetBackMyWindows")
        }
        
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateMenu()
    }
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        updateMenu()
    }
    
    func updateMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()
        
        // 0. Version Info
        let versionItem = NSMenuItem(title: "Current Version: \(UpdateChecker.currentVersion)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        
        if let newVersion = UpdateChecker.shared.latestVersionAvailable, 
           newVersion != UpdateChecker.currentVersion {
            let updateItem = NSMenuItem(title: "🚀 New Version Available: \(newVersion)", action: #selector(openUpdatePage), keyEquivalent: "")
            updateItem.target = self
            menu.addItem(updateItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // 1. Info Items
        let info1 = NSMenuItem(title: "🖱️ Click Dock Icon → Minimize", action: nil, keyEquivalent: "")
        info1.isEnabled = false
        menu.addItem(info1)
        
        let hotkeyString = HotkeyManager.shared.stringRepresentation()
        let info2 = NSMenuItem(title: "⌨️ \(hotkeyString) → Minimize All", action: nil, keyEquivalent: "")
        info2.isEnabled = false
        menu.addItem(info2)
        
        menu.addItem(NSMenuItem.separator())
        
        // 2. Settings
        let recordItem = NSMenuItem(title: "Preferences...", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(recordItem)

        let autoStartItem = NSMenuItem(title: "Start at Login", action: #selector(toggleAutoStart), keyEquivalent: "")
        autoStartItem.state = AutoStartManager.shared.isEnabled ? .on : .off
        menu.addItem(autoStartItem)
        
        menu.addItem(NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdatesManually), keyEquivalent: ""))
        
        menu.addItem(NSMenuItem.separator())
        
        // 3. Restart & Quit
        menu.addItem(NSMenuItem(title: "Restart", action: #selector(restartApp), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }
    
    @objc func checkForUpdatesManually() {
        UpdateChecker.shared.checkForUpdates(force: true) { [weak self] hasUpdate in
            DispatchQueue.main.async {
                self?.updateMenu()
                if !hasUpdate {
                    let alert = NSAlert()
                    alert.messageText = "You're up to date!"
                    alert.informativeText = "GetBackMyWindows \(UpdateChecker.currentVersion) is currently the newest version available."
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }
    
    @objc func openUpdatePage() {
        if let url = URL(string: "https://github.com/Avi7ii/GetBackMyWindows/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func restartApp() {
        guard let execPath = Bundle.main.executablePath else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: execPath)
        try? task.run()
        NSApp.terminate(nil)
    }
    
    @objc func toggleAutoStart(_ sender: NSMenuItem) {
        let newState = sender.state == .off
        AutoStartManager.shared.toggle(newState)
        // State update happens in menu refresh, but we can update immediately for UI responsiveness
        sender.state = newState ? .on : .off
    }
    
    @objc func openSettings() {
        SettingsWindowController.shared.show()
    }
    
    // MARK: - Event Tap
    func setupEventTap() {
        // Cleanup existing tap
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
                runLoopSource = nil
            }
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,  // 需要拦截事件以阻止 Dock 默认行为
                                          eventsOfInterest: kGlobalEvents,
                                          callback: eventTapCallback,
                                          userInfo: nil) else {
            print("EventTap: Failed")
            return
        }
        
        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("EventTap: Setup Complete")
    }
    
    func checkAccessibilityPermissions() {
        // Now handled by SettingsWindowController -> GeneralViewController
    }
}

// MARK: - Native Settings GUI

// GUI implementation moved to SettingsUI.swift

func minimizeAllWindows() {
    print("Action: Minimizing all windows...")
    DispatchQueue.global(qos: .userInteractive).async {
        let workspace = NSWorkspace.shared
        // 获取自身进程 ID
        let myPID = NSRunningApplication.current.processIdentifier
        
        for app in workspace.runningApplications {
            if app.activationPolicy == .regular {
                if app.processIdentifier == myPID {
                    // CASE: Self (Must be on Main Thread to avoid crash)
                    DispatchQueue.main.async {
                        // 使用原生 AppKit API 安全最小化
                        for window in NSApp.windows {
                            if window.isVisible && !window.isMiniaturized {
                                window.miniaturize(nil)
                            }
                        }
                    }
                } else {
                    // CASE: Other Apps (Use Accessibility / AX API)
                    let appRef = AXUIElementCreateApplication(app.processIdentifier)
                    minimizeAppWindows(appRef)
                }
            }
        }
    }
}

func minimizeAppWindows(_ appRef: AXUIElement) {
    var windowsRef: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
    if result == .success, let windows = windowsRef as? [AXUIElement] {
        for window in windows {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, true as CFTypeRef)
        }
    }
}

// Event Tap Circuit Breaker
var tapRestartCount = 0
var lastTapRestartTime: TimeInterval = 0

func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    // 处理 tap 被系统禁用的情况（App Nap、超时等）
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        let now = Date().timeIntervalSince1970
        if now - lastTapRestartTime < 10 {
            tapRestartCount += 1
        } else {
            tapRestartCount = 1
        }
        lastTapRestartTime = now
        
        if tapRestartCount > 5 {
            print("EventTap: ⚠️ Circuit Breaker Triggered (Too many restarts). Stopping Event Tap.")
            // Do not restart. Let it die to save system resources.
            // Optionally notify user via UI in future updates.
            return Unmanaged.passUnretained(event)
        }
        
        print("EventTap: Disabled by System (\(type.rawValue)). Restarting... (Attempt \(tapRestartCount)/5)")
        DispatchQueue.main.async {
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.setupEventTap()
            }
        }
        return Unmanaged.passUnretained(event)
    }
    
    // Check for re-posted event to avoid infinite loops (Scheme A)
    if event.getIntegerValueField(.eventSourceUserData) == kUserDataMagic {
        return Unmanaged.passUnretained(event)
    }

    guard type == .leftMouseDown else { return Unmanaged.passUnretained(event) }
    
    // 直接使用 Accessibility API 判断点击目标
    let location = event.location
    
    // Performance Optimization (V7): Geometric Pre-check
    // AXUIElementCopyElementAtPosition is expensive (IPC). 
    // Only perform it if the mouse is likely over the Dock (outside visible frame).
    if !isMouseInDockRegion(location) {
        return Unmanaged.passUnretained(event)
    }
    
    let systemWide = AXUIElementCreateSystemWide()
    var element: AXUIElement?
    let result = AXUIElementCopyElementAtPosition(systemWide, Float(location.x), Float(location.y), &element)
    
    if result == .success, let target = element, isDockIcon(element: target) {
        // Optimization (Hybrid): Conditional Interception & Async Execution
        // Only intercept if we actually intend to minimize windows.
        // Otherwise, let the system handle drag, long press, etc.
        if handleDockIconClick(element: target) {
            return nil // Swallow event only if we minimized
        }
    }
    return Unmanaged.passUnretained(event)
}

func isMouseInDockRegion(_ location: CGPoint) -> Bool {
    // Check if the point is within any screen's "safe area" (visibleFrame).
    // If it is inside visibleFrame, it's NOT on the Dock (Dock is excluded from visibleFrame).
    // If it is OUTSIDE visibleFrame but INSIDE frame, it's potentially on the Dock (or Menu Bar).
    
    for screen in NSScreen.screens {
        // Convert CoreGraphics geometric point (top-left 0,0) to Cocoa (bottom-left 0,0)
        // Note: location is CGEvent location (top-left origin).
        // NSScreen.frame is bottom-left origin? 
        // Actually simplest is: Check if point is outside the "User Space".
        
        // Let's stick to CG coordinates for simplicity if possible, but NSScreen uses Cocoa coords.
        // We need to flip Y.
        guard let primaryScreenHeight = NSScreen.screens.first?.frame.height else { return true }
        let cocoaY = primaryScreenHeight - location.y
        let cocoaPoint = NSPoint(x: location.x, y: cocoaY)
        
        if NSPointInRect(cocoaPoint, screen.frame) {
            // Point is on this screen.
            // Check if it is inside the usable area (excluding Dock/Menu)
            if NSPointInRect(cocoaPoint, screen.visibleFrame) {
                return false // It's in the content area, definitively NOT the Dock.
            }
            // It's on screen but outside visible area -> Dock or Menu Bar.
            // Heuristic: Menu Bar is usually at top (high Cocoa Y). Dock is at bottom/side.
            // We assume Dock if it's not the top menu bar.
            // Simple check: Is it the Menu Bar?
            // Menu bar is usually height ~24.
            if cocoaY > (screen.frame.maxY - 25) {
                return false // It's the Menu Bar
            }
            return true // It's likely the Dock
        }
    }
    return false // Fallback: If off-screen or undetected, let's be safe and say No (or True? False is safer for perfs)
}

func isDockIcon(element: AXUIElement) -> Bool {
    var role: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
    if let r = role as? String {
        if r == "AXDockItem" { return true }
        var parent: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent)
        if let p = parent {
            var pr: CFTypeRef?
            AXUIElementCopyAttributeValue(p as! AXUIElement, kAXRoleAttribute as CFString, &pr)
            if let prs = pr as? String, prs == "AXDockItem" { return true }
        }
    }
    return false
}

// MARK: - App Cache Manager
class AppCache {
    static let shared = AppCache()
    private var apps: [String: NSRunningApplication] = [:]
    private let queue = DispatchQueue(label: "com.user.GetBackMyWindows.AppCache", qos: .userInteractive)
    
    // Lazy load: No init observers needed
    
    private func refreshSync() {
        let running = NSWorkspace.shared.runningApplications
        var newCache: [String: NSRunningApplication] = [:]
        for app in running {
            if let name = app.localizedName {
                newCache[name] = app
            }
        }
        self.apps = newCache
    }
    
    func getApp(named name: String) -> NSRunningApplication? {
        return queue.sync {
            if let cached = apps[name], !cached.isTerminated {
                return cached
            }
            // Not found or terminated, refresh cache
            refreshSync()
            return apps[name]
        }
    }
}

// Global serial queue for click processing to prevent race conditions
let clickProcessingQueue = DispatchQueue(label: "com.user.GetBackMyWindows.ClickQueue", qos: .userInteractive)
let kUserDataMagic: Int64 = 0x55AA

// Global variable for debounce (accessed only within clickProcessingQueue)
var lastClickTime: TimeInterval = 0
var lastClickedAppPID: pid_t = 0

// ... (existing code)

func handleDockIconClick(element: AXUIElement) -> Bool {
    return autoreleasepool {
        // Strategy 1: Identify by URL
    var urlRef: CFTypeRef?
    let urlResult = AXUIElementCopyAttributeValue(element, "AXURL" as CFString, &urlRef)
    
    var candidates: [NSRunningApplication] = []
    var isWeChatHelper = false
    
    if urlResult == .success, let url = urlRef as? URL {
        // Special Handling for WeChat Helper
        if url.absoluteString.contains("WeChatAppEx.app") {
            isWeChatHelper = true
        }
        
        let apps = NSWorkspace.shared.runningApplications
        candidates = apps.filter { app in
            app.bundleURL == url || app.executableURL == url
        }
        
        // Handle Self-Click (Minimize if visible, otherwise let system restore)
        if let selfApp = candidates.first(where: { $0.bundleIdentifier == Bundle.main.bundleIdentifier }) {
            if hasVisibleWindows(selfApp) {
                DispatchQueue.main.async {
                    for window in NSApp.windows {
                        if window.isVisible && !window.isMiniaturized {
                            window.miniaturize(nil)
                        }
                    }
                }
                return true // Swallow event to prevent system from interfering
            }
            return false // Let system handle restore/activate
        }
    }
    
    // Debug log
    if isWeChatHelper {
        print("Detected WeChat Helper click")
    }
    
    if isWeChatHelper {
        // WeChat Logic V4: Fully Async & Full State Management
        // 1. Intercept immediately to prevent blocking/timeout
        // 2. Determine state (Minimized? Active? Background?)
        // 3. Perform Action (Restore, Minimize, Raise)
        
        clickProcessingQueue.async {
            // Find Main WeChat App (PID 3477)
            guard let mainApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.tencent.xinWeChat" }) else { return }
            
            let appRef = AXUIElementCreateApplication(mainApp.processIdentifier)
            var windowsRef: CFTypeRef?
            
            // Get ALL windows
            guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let windows = windowsRef as? [AXUIElement] else {
                // Fallback: Activate app if we can't get windows
                mainApp.activate(options: .activateIgnoringOtherApps)
                return
            }
            
            var targetWindow: AXUIElement?
            
            // Find the "Green Window" (Heuristic: Title != "微信" && Title != "WeChat")
            // Iterate to find the first matching window
            for window in windows {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
                let title = titleRef as? String ?? ""
                
                if !title.isEmpty && title != "微信" && title != "WeChat" {
                    targetWindow = window
                    break
                }
            }
            
            if let win = targetWindow {
                // Check Is Minimized
                var minRef: CFTypeRef?
                let _ = AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &minRef)
                let isMinimized = (minRef as? Bool) ?? false
                
                if isMinimized {
                    // CASE 1: Restore
                    AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, false as CFTypeRef)
                    AXUIElementPerformAction(win, kAXRaiseAction as CFString)
                    mainApp.activate(options: .activateIgnoringOtherApps)
                } else {
                    // Check if it is the KEY window
                    var focusedRef: CFTypeRef?
                    var isKey = false
                    if mainApp.isActive {
                        if AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success {
                            // Compare AXUIElement equality (CFEqual)
                            if CFEqual(focusedRef as! AXUIElement, win) {
                                isKey = true
                            }
                        }
                    }
                    
                    if isKey {
                        // CASE 2: Minimize (Already frontmost)
                        AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, true as CFTypeRef)
                    } else {
                        // CASE 3: Activate (Visible but background/inactive)
                        AXUIElementPerformAction(win, kAXRaiseAction as CFString)
                        mainApp.activate(options: .activateIgnoringOtherApps)
                    }
                }
            } else {
                // No specific window found, just bring main app to front
                mainApp.activate(options: .activateIgnoringOtherApps)
            }
        }
        return true
    }

    // Standard Logic for other apps
    if candidates.isEmpty {
        var title: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
        
        if titleResult == .success, let appName = title as? String {
             if let app = AppCache.shared.getApp(named: appName) {
                 candidates.append(app)
             }
        }
    }
    
    // Standard Minimize Logic
    for app in candidates {
        if app.isActive {
            // Special Logic for WeChat Main Icon
            if app.bundleIdentifier == "com.tencent.xinWeChat" {
                if hasVisibleWindows(app) {
                     // Debounce logic
                     let now = Date().timeIntervalSince1970
                     if app.processIdentifier == lastClickedAppPID && (now - lastClickTime) < 0.1 {
                         return true
                     }
                     lastClickTime = now
                     lastClickedAppPID = app.processIdentifier
                     
                     clickProcessingQueue.async {
                         handleWeChatMainClick(app)
                     }
                     return true
                }
            }
            
            if hasVisibleWindows(app) {
                let now = Date().timeIntervalSince1970
                if app.processIdentifier == lastClickedAppPID && (now - lastClickTime) < 0.1 {
                    return true
                }
                lastClickTime = now
                lastClickedAppPID = app.processIdentifier
                
                clickProcessingQueue.async {
                    minimizeAppWindows(app)
                }
                return true
            }
        }
    }
    
        return false
    }
}

func handleWeChatMainClick(_ app: NSRunningApplication) {
    let appRef = AXUIElementCreateApplication(app.processIdentifier)
    
    // 1. Get Focused Window
    var focusedWindow: CFTypeRef?
    if AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success {
        let window = focusedWindow as! AXUIElement
        
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
        let title = titleRef as? String ?? ""
        
        // 2. Decide Action
        // If Title IS "微信" or "WeChat" -> Minimize it (User is on main screen, wants to hide app)
        if title == "微信" || title == "WeChat" {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, true as CFTypeRef)
        } else {
            // User is on a Helper Window (Article/MiniProgram) but clicked Main Icon.
            // They likely want to Go Back to Main Chat.
            // Action: Activate the "微信" window
            activateWeChatMainWindow(appRef, app)
        }
    } else {
        // Fallback: Just minimize if we can't determine focus
        minimizeAppWindows(app)
    }
}

func activateWeChatMainWindow(_ appRef: AXUIElement, _ app: NSRunningApplication) {
    var windowsRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success,
       let windows = windowsRef as? [AXUIElement] {
        for window in windows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            let title = titleRef as? String ?? ""
            
            if title == "微信" || title == "WeChat" {
                // Found Main Window -> Raise it
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                app.activate(options: .activateIgnoringOtherApps)
                return
            }
        }
    }
    // If not found, just activate the app
    app.activate(options: .activateIgnoringOtherApps)
}

func minimizeAppWindows(_ app: NSRunningApplication) {
    let appRef = AXUIElementCreateApplication(app.processIdentifier)
    minimizeAppWindows(appRef)
}

func simulateClick(at point: CGPoint) {
    guard let downEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left) else { return }
    downEvent.setIntegerValueField(.eventSourceUserData, value: kUserDataMagic)
    downEvent.post(tap: .cghidEventTap)
    
    guard let upEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else { return }
    upEvent.setIntegerValueField(.eventSourceUserData, value: kUserDataMagic)
    upEvent.post(tap: .cghidEventTap)
}

func hasVisibleWindows(_ app: NSRunningApplication) -> Bool {
    let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
    guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return false }
    
    for entry in infoList {
        if let ownerPID = entry[kCGWindowOwnerPID as String] as? Int32, ownerPID == app.processIdentifier {
            // Check if window layer is normal (0)
            if let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 {
                return true
            }
        }
    }
    return false
}

func getKeyString(keyCode: UInt16, modifiers: UInt32) -> String {
    var modString = ""
    if (modifiers & UInt32(cmdKey)) != 0 { modString += "⌘" }
    if (modifiers & UInt32(controlKey)) != 0 { modString += "⌃" }
    if (modifiers & UInt32(optionKey)) != 0 { modString += "⌥" }
    if (modifiers & UInt32(shiftKey)) != 0 { modString += "⇧" }
    
    let keyStr: String
    switch keyCode {
    case 0: keyStr = "A"
    case 1: keyStr = "S"
    case 2: keyStr = "D"
    case 3: keyStr = "F"
    case 4: keyStr = "H"
    case 5: keyStr = "G"
    case 6: keyStr = "Z"
    case 7: keyStr = "X"
    case 8: keyStr = "C"
    case 9: keyStr = "V"
    case 11: keyStr = "B"
    case 12: keyStr = "Q"
    case 13: keyStr = "W"
    case 14: keyStr = "E"
    case 15: keyStr = "R"
    case 16: keyStr = "Y"
    case 17: keyStr = "T"
    case 18: keyStr = "1"
    case 19: keyStr = "2"
    case 20: keyStr = "3"
    case 21: keyStr = "4"
    case 22: keyStr = "6"
    case 23: keyStr = "5"
    case 24: keyStr = "="
    case 25: keyStr = "9"
    case 26: keyStr = "7"
    case 27: keyStr = "-"
    case 28: keyStr = "8"
    case 29: keyStr = "0"
    case 30: keyStr = "]"
    case 31: keyStr = "O"
    case 32: keyStr = "U"
    case 33: keyStr = "["
    case 34: keyStr = "I"
    case 35: keyStr = "P"
    case 37: keyStr = "L"
    case 38: keyStr = "J"
    case 39: keyStr = "'"
    case 40: keyStr = "K"
    case 41: keyStr = ";"
    case 42: keyStr = "\\"
    case 43: keyStr = ","
    case 44: keyStr = "/"
    case 45: keyStr = "N"
    case 46: keyStr = "M"
    case 47: keyStr = "."
    case 50: keyStr = "`"
    case 65: keyStr = "."
    default: keyStr = "?\(keyCode)"
    }
    return "\(modString)\(keyStr)"
}

// Entry Point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
