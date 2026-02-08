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

// MARK: - Main Application Delegate
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    var recordingWindow: NSWindow?
    var accessibilityTimer: Timer?  // 权限监控定时器
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        checkAccessibilityPermissions()
        HotkeyManager.shared.registerHotkey()
        setupEventTap()
        
        // 允许 App Nap - 热键事件会自动唤醒应用，无需禁用
        // 睡眠/唤醒监听
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }
    
    @objc func didWake() {
        print("System Woke Up: Resetting Event Tap...")
        // Re-initialize event tap after a short delay to ensure system is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.setupEventTap()
        }
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
        let recordItem = NSMenuItem(title: "Change Hotkey...", action: #selector(openRecorder), keyEquivalent: "k")
        menu.addItem(recordItem)

        let autoStartItem = NSMenuItem(title: "Start at Login", action: #selector(toggleAutoStart), keyEquivalent: "")
        autoStartItem.state = AutoStartManager.shared.isEnabled ? .on : .off
        menu.addItem(autoStartItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 3. Restart & Quit
        menu.addItem(NSMenuItem(title: "Restart", action: #selector(restartApp), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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
    
    @objc func openRecorder() {
        if let w = recordingWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let window = HotkeyRecorderWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Set Global Hotkey"
        window.isReleasedWhenClosed = false
        
        let label = NSTextField(labelWithString: "Press new key combination...")
        label.font = NSFont.systemFont(ofSize: 16)
        label.alignment = .center
        label.frame = NSRect(x: 20, y: 80, width: 260, height: 30)
        window.contentView?.addSubview(label)
        
        let subLabel = NSTextField(labelWithString: "Press 'Esc' to cancel")
        subLabel.font = NSFont.systemFont(ofSize: 12)
        subLabel.textColor = .secondaryLabelColor
        subLabel.alignment = .center
        subLabel.frame = NSRect(x: 20, y: 50, width: 260, height: 20)
        window.contentView?.addSubview(subLabel)
        
        self.recordingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        let trusted = AXIsProcessTrusted()
        
        if !trusted {
            // 弹出系统权限请求对话框
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
            
            // 启动定时器监控权限变化
            accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    self?.accessibilityTimer = nil
                    print("Accessibility granted, restarting...")
                    self?.restartApp()
                }
            }
        }
    }
}

// MARK: - Hotkey Recorder Window
class HotkeyRecorderWindow: NSWindow {
    override var canBecomeKey: Bool { return true }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { self.close(); return } 
        if event.modifierFlags.contains(.command) && event.keyCode == 55 { return }
        if event.modifierFlags.contains(.control) && event.keyCode == 59 { return }
        if event.modifierFlags.contains(.option) && event.keyCode == 58 { return }
        if event.modifierFlags.contains(.capsLock) { return }
        
        var carbonMods: UInt32 = 0
        if event.modifierFlags.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.control) { carbonMods |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option)  { carbonMods |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift)   { carbonMods |= UInt32(shiftKey) }
        
        HotkeyManager.shared.currentKeyCode = Int(event.keyCode)
        HotkeyManager.shared.currentModifiers = Int(carbonMods)
        HotkeyManager.shared.registerHotkey()
        
        self.close()
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.recordingWindow = nil
        }
    }
}

// MARK: - Logic & Helpers

func minimizeAllWindows() {
    print("Action: Minimizing all windows...")
    let workspace = NSWorkspace.shared
    for app in workspace.runningApplications {
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { continue }
        if app.activationPolicy == .regular {
            let appRef = AXUIElementCreateApplication(app.processIdentifier)
            minimizeAppWindows(appRef)
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

func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    // 处理 tap 被系统禁用的情况
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        // 延迟重建 eventTap（通过主线程）
        DispatchQueue.main.async {
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.setupEventTap()
            }
        }
        return Unmanaged.passUnretained(event)
    }
    
    if type != .leftMouseDown { return Unmanaged.passUnretained(event) }
    
    // 快速检查：点击位置是否在 Dock 区域（屏幕底部 80px）
    let location = event.location
    let screenHeight = NSScreen.main?.frame.height ?? 0
    if location.y < (screenHeight - 80) { return Unmanaged.passUnretained(event) }
    
    // 仅当点击在 Dock 区域时才进行 AX 查询（减少 CPU 开销）
    let systemWide = AXUIElementCreateSystemWide()
    var element: AXUIElement?
    let result = AXUIElementCopyElementAtPosition(systemWide, Float(location.x), Float(location.y), &element)
    
    if result == .success, let target = element, isDockIcon(element: target) {
        if handleDockIconClick(element: target) {
            return nil  // 拦截事件，阻止 Dock 的默认激活行为
        }
    }
    return Unmanaged.passUnretained(event)
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

func handleDockIconClick(element: AXUIElement) -> Bool {
    var title: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
    guard let appName = title as? String else { return false }
    
    let workspace = NSWorkspace.shared
    guard let runningApp = workspace.runningApplications.first(where: { $0.localizedName == appName }) else { return false }
    
    if runningApp.isActive {
        let appRef = AXUIElementCreateApplication(runningApp.processIdentifier)
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            var didMinimize = false
            for window in windows {
                var minVal: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minVal)
                if let m = minVal as? Bool, !m {
                    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, true as CFTypeRef)
                    didMinimize = true
                }
            }
            return didMinimize
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
