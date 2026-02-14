
import Cocoa
import Carbon

// MARK: - Auto-Hide Manager (Preserved)
class AutoHideManager {
    static let shared = AutoHideManager()
    private var hideTimer: Timer?
    
    private init() {
        setupObservers()
    }
    
    private func setupObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(appDidResignActive), name: NSApplication.didResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: NSApplication.didBecomeActiveNotification, object: nil)
    }
    
    @objc private func appDidResignActive() {
        print("AutoHideManager: App Resigned Active -> Scheduling Hide")
        scheduleHide()
    }
    
    @objc private func appDidBecomeActive() {
        print("AutoHideManager: App Became Active -> Canceling Hide")
        cancelHide()
        
        // Ensure Policy is Regular so it shows in Dock
        if NSApp.activationPolicy() != .regular {
             NSApp.setActivationPolicy(.regular)
        }
    }
    
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "AutoHideDock") }
        set { UserDefaults.standard.set(newValue, forKey: "AutoHideDock") }
    }
    
    var delay: TimeInterval {
        get { 
            let val = UserDefaults.standard.double(forKey: "AutoHideDelay")
            return val <= 0 ? 5.0 : val 
        }
        set { UserDefaults.standard.set(newValue, forKey: "AutoHideDelay") }
    }
    
    func scheduleHide() {
        cancelHide()
        guard isEnabled else { return }
        print("AutoHideManager: Scheduled hide in \(delay) seconds")
        
        hideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            print("AutoHideManager: Hiding Dock Icon")
            // Check for visible windows (excluding minimized ones)
            // Note: NSWindow.isVisible is true even if miniaturized in some contexts, so check isMiniaturized explicitly.
            let hasVisibleWindow = NSApp.windows.contains { $0.isVisible && !$0.isMiniaturized }
            
            if NSApp.isActive && hasVisibleWindow {
                 print("AutoHideManager: App is active with visible windows, skipping hide")
                 return
            }
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    func cancelHide() {
        hideTimer?.invalidate()
        hideTimer = nil
    }
    
    func show() {
        cancelHide()
        if NSApp.activationPolicy() != .regular {
             NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Modern Window Controller
class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()
    
    // We need to keep a reference to splitVC to control tabs
    private var mainSplitVC: MainSplitViewController!
    
    init() {
        // 1. Create a Modern Panel-style Window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), // Larger, fixed size
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        
        // 2. Translucency & Glass Effect
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear 
        window.isReleasedWhenClosed = false
        
        super.init(window: window)
        window.delegate = self
        
        // 3. Setup Root View Controller (The Container)
        let rootVC = RootViewController()
        
        // 4. Setup Split View Layout
        mainSplitVC = MainSplitViewController()
        
        // 5. Install RootVC as Content
        window.contentViewController = rootVC
        
        // 6. Embed SplitVC into RootVC (Safe to do after view load)
        rootVC.embed(child: mainSplitVC)
        
        window.center()
        
        // Adjust standard window buttons (Traffic Lights)
        if let closeButton = window.standardWindowButton(.closeButton),
           let minimizeButton = window.standardWindowButton(.miniaturizeButton),
           let zoomButton = window.standardWindowButton(.zoomButton) {
            
            let yOffset: CGFloat = -16
            let xOffset: CGFloat = 8
            
            closeButton.translatesAutoresizingMaskIntoConstraints = false
            minimizeButton.translatesAutoresizingMaskIntoConstraints = false
            zoomButton.translatesAutoresizingMaskIntoConstraints = false
            
            if let titlebarView = closeButton.superview {
                NSLayoutConstraint.activate([
                    closeButton.leadingAnchor.constraint(equalTo: titlebarView.leadingAnchor, constant: 16 + xOffset),
                    closeButton.centerYAnchor.constraint(equalTo: titlebarView.centerYAnchor, constant: 16 + yOffset),
                    
                    minimizeButton.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 8),
                    minimizeButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
                    
                    zoomButton.leadingAnchor.constraint(equalTo: minimizeButton.trailingAnchor, constant: 8),
                    zoomButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor)
                ])
            }
        }
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    // Lifecycle hooks for AutoHide
    func windowDidMiniaturize(_ notification: Notification) { AutoHideManager.shared.scheduleHide() }
    func windowWillClose(_ notification: Notification) { AutoHideManager.shared.scheduleHide() }
    func windowDidDeminiaturize(_ notification: Notification) { AutoHideManager.shared.cancelHide() }
    
    func show(tab: String = "General") {
        AutoHideManager.shared.show()
        window?.makeKeyAndOrderFront(nil)
        mainSplitVC.selectTab(named: tab)
    }
}

// ... (RootViewController, MainSplitViewController etc remain same)

// MARK: - Modern Tutorial VC (Redesigned)
class ModernTutorialViewController: ModernBaseViewController {
    init() { super.init(title: "Tutorial") }
    required init?(coder: NSCoder) { fatalError() }
    
    override func setupContent(in stack: NSStackView) {
        // Use NSGridView for pixel-perfect alignment
        let grid = NSGridView(views: [])
        grid.columnSpacing = 20
        grid.rowSpacing = 24
        grid.yPlacement = .top // Align content to top of row
        
        // Define Rows
        addRow(to: grid, icon: "cursorarrow.click.2", title: "Click to Minimize", desc: "Click the Dock icon to minimize all windows of the current app. Click again to restore.")
        addDivider(to: grid)
        addRow(to: grid, icon: "message.fill", title: "WeChat Smart Assistant", desc: "Reading an article? Click the Dock icon to return to the chat list.\nClick on the main window to minimize.")
        addDivider(to: grid)
        addRow(to: grid, icon: "keyboard", title: "Boss Key", desc: "Press the global shortcut (Default: Control+A) to instantly hide all windows.")
        
        stack.addArrangedSubview(grid)
    }
    
    func addRow(to grid: NSGridView, icon: String, title: String, desc: String) {
        // Icon Column
        let iconImg = NSImageView(image: NSImage(systemSymbolName: icon, accessibilityDescription: nil)!)
        iconImg.symbolConfiguration = .init(pointSize: 24, weight: .semibold)
        iconImg.contentTintColor = .controlAccentColor
        iconImg.translatesAutoresizingMaskIntoConstraints = false
        iconImg.widthAnchor.constraint(equalToConstant: 32).isActive = true
        iconImg.heightAnchor.constraint(equalToConstant: 32).isActive = true
        
        // Text Column
        let textCol = NSStackView()
        textCol.orientation = .vertical
        textCol.alignment = .leading
        textCol.spacing = 6
        
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = .labelColor
        
        let descLabel = NSTextField(labelWithString: desc)
        descLabel.font = .systemFont(ofSize: 13, weight: .regular)
        descLabel.textColor = .secondaryLabelColor
        descLabel.usesSingleLineMode = false
        descLabel.lineBreakMode = .byWordWrapping
        descLabel.preferredMaxLayoutWidth = 450
        
        textCol.addArrangedSubview(titleLabel)
        textCol.addArrangedSubview(descLabel)
        
        grid.addRow(with: [iconImg, textCol])
    }
    
    func addDivider(to grid: NSGridView) {
        let div = NSBox()
        div.boxType = .separator
        div.alphaValue = 0.3
        
        // Spanning divider
        let row = grid.addRow(with: [div])
        row.mergeCells(in: NSRange(location: 0, length: 2))
    }
}

class RootViewController: NSViewController {
    private var contentViewController: NSViewController?
    
    init() { super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    
    override func loadView() {
        // 1. Transparent Container Root (Absolute Corner Kill)
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.layer?.cornerRadius = 20
        container.layer?.cornerCurve = .continuous
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = false // ALLOW SHADOWS TO SPILL OVER
        self.view = container
        
        // 2. Liquid Glass Backdrop (Clipped Subview)
        let visualEffect = NSVisualEffectView()
        visualEffect.blendingMode = .behindWindow
        visualEffect.material = .fullScreenUI
        visualEffect.state = .active
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 20
        visualEffect.layer?.cornerCurve = .continuous
        visualEffect.layer?.masksToBounds = false // ALLOW INNER SHADOWS TO BREATHE
        
        container.addSubview(visualEffect)
        
        // 3. GLOBAL SHADOW LAYER (BREAKS SPLITVIEW BOUNDARIES)
        let globalShadowView = NSView()
        globalShadowView.wantsLayer = true
        globalShadowView.translatesAutoresizingMaskIntoConstraints = false
        
        // Multi-layered Soft Gaussian Shadows WITH AGGRESSIVE X-OFFSET (Right Spillover)
        let shadowColors = [0.45, 0.28, 0.15, 0.08] // Deepened opacity
        let shadowRadii: [CGFloat] = [15, 35, 70, 110] // Massive expansion
        let shadowXOffsets: [CGFloat] = [12, 28, 48, 70] // AGGRESSIVE RIGHT PUSH
        let shadowYOffsets: [CGFloat] = [-4, -8, -14, -20] // Reduced bottom shadow
        
        for i in 0..<4 {
            let sLayer = CALayer()
            sLayer.shadowColor = NSColor.black.cgColor
            sLayer.shadowOpacity = Float(shadowColors[i])
            sLayer.shadowOffset = CGSize(width: shadowXOffsets[i], height: shadowYOffsets[i])
            sLayer.shadowRadius = shadowRadii[i]
            sLayer.name = "global_s_\(i)"
            globalShadowView.layer?.addSublayer(sLayer)
        }
        
        visualEffect.addSubview(globalShadowView)
        
        // 4. Constraints
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 900),
            container.heightAnchor.constraint(equalToConstant: 600),
            
            visualEffect.topAnchor.constraint(equalTo: container.topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            visualEffect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            
            globalShadowView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            globalShadowView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            globalShadowView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            globalShadowView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor)
        ])
        
        // 5. Update Path Logic
        let sidebarCardWidth: CGFloat = 240 - 16 - 4
        let cardRect = NSRect(x: 16, y: 16, width: sidebarCardWidth, height: 600 - 52 - 16)
        let shadowPath = NSBezierPath(roundedRect: cardRect, xRadius: 18, yRadius: 18).cgPath
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            globalShadowView.layer?.sublayers?.forEach { 
                $0.frame = globalShadowView.bounds
                $0.shadowPath = shadowPath
            }
        }
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        // Window Level Clipping
        if let window = self.view.window {
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            
            // Force content view rounding as a second safety net
            if let contentView = window.contentView {
                contentView.wantsLayer = true
                contentView.layer?.cornerRadius = 20
                contentView.layer?.cornerCurve = .continuous
                contentView.layer?.cornerRadius = 20
                contentView.layer?.cornerCurve = .continuous
                contentView.layer?.masksToBounds = false // CRITICAL FIX: Allow shadows to extend beyond window bounds
            }
            
            window.invalidateShadow()
        }
    }
    
    override func viewDidLayout() {
        super.viewDidLayout()
        self.view.window?.invalidateShadow()
    }
    
    func embed(child: NSViewController) {
        self.contentViewController = child
        self.addChild(child)
        child.view.frame = self.view.bounds
        child.view.autoresizingMask = [.width, .height]
        self.view.addSubview(child.view)
    }
}

// MARK: - Split View Controller
class MainSplitViewController: NSSplitViewController {
    private let sidebarVC = SidebarViewController()
    private let contentVC = ContainerViewController()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Transparency and Layer Setup
        self.view.wantsLayer = true
        self.view.layer?.backgroundColor = NSColor.clear.cgColor
        self.splitView.wantsLayer = true
        self.splitView.layer?.backgroundColor = NSColor.clear.cgColor
        self.splitView.dividerStyle = .thin
        
        // Use a regular NSSplitViewItem instead of .sidebar to avoid forced opaque square backgrounds
        let sidebarItem = NSSplitViewItem(viewController: sidebarVC)
        sidebarItem.minimumThickness = 240 // Slightly wider to account for margins
        sidebarItem.maximumThickness = 240
        sidebarItem.canCollapse = false
        
        // Final Nuclear Transparency for Divider
        if #available(macOS 10.14, *) {
            self.splitView.setValue(NSColor.clear, forKey: "dividerColor")
        }
        
        let contentItem = NSSplitViewItem(viewController: contentVC)
        
        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
        
        // Link action
        sidebarVC.delegate = contentVC
    }
    
    func selectTab(named name: String) {
        sidebarVC.selectItem(named: name)
    }
}

// MARK: - Sidebar Implementation
protocol SidebarDelegate: AnyObject {
    func didSelectSection(_ name: String)
}

class SidebarViewController: NSViewController {
    weak var delegate: SidebarDelegate?
    private var stackView: NSStackView!
    private var buttons: [SidebarButton] = []
    
    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 400))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        self.view = view
        
        // SIDEBAR CONTAINER (Clipped Backdrop)
        let cardContainer = NSView()
        cardContainer.wantsLayer = true
        cardContainer.translatesAutoresizingMaskIntoConstraints = false
        
        // NO SHADOW HERE ANYMORE - IT'S ON THE WINDOW LEVEL
        
        view.addSubview(cardContainer)
        
        // FLOATING CARD BACKDROP (Responsible for Blur, Clipping, and Borders)
        let backdrop = NSVisualEffectView()
        backdrop.material = .sidebar
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = 18
        backdrop.layer?.cornerCurve = .continuous
        backdrop.layer?.masksToBounds = true
        
        // Premium Double Border (ENHANCED RIM PROMINENCE)
        backdrop.layer?.borderWidth = 0.8 // Thicker
        backdrop.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor // Brighter
        
        cardContainer.addSubview(backdrop)
        
        // Physical Interior Glow/Glint (TOP)
        let glint = NSView()
        glint.wantsLayer = true
        glint.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        glint.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(glint)

        
        NSLayoutConstraint.activate([
            cardContainer.topAnchor.constraint(equalTo: view.topAnchor, constant: 52),
            cardContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -36),
            cardContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            cardContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            
            backdrop.topAnchor.constraint(equalTo: cardContainer.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor),
            backdrop.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor),
            
            glint.topAnchor.constraint(equalTo: backdrop.topAnchor),
            glint.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
            glint.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
            glint.heightAnchor.constraint(equalToConstant: 0.5)
        ])
        
        // Layout
        stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 10
        stackView.edgeInsets = NSEdgeInsets(top: 20, left: 12, bottom: 20, right: 12)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        backdrop.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: backdrop.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor)
        ])
        
        // Removed manual background layer to let window vibrancy show through

        
        // Add Items with Groups (Keychain Access Style)
        addLabel("Settings")
        addButton(icon: "gearshape.fill", title: "General", color: .systemGray)
        addButton(icon: "keyboard.fill", title: "Controls", color: .systemBlue)
        
        stackView.setCustomSpacing(20, after: stackView.arrangedSubviews.last!)
        
        addLabel("Information")
        addButton(icon: "book.closed.fill", title: "Tutorial", color: .systemOrange)
        addButton(icon: "info.circle.fill", title: "About", color: .systemPink)
        
        // Select first by default
        buttons.first?.isSelected = true
    }
    
    private func addButton(icon: String, title: String, color: NSColor) {
        let btn = SidebarButton(title: title, iconName: icon, iconColor: color)
        btn.target = self
        btn.action = #selector(buttonClicked(_:))
        stackView.addArrangedSubview(btn)
        
        // Fix width collapse issue
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        
        buttons.append(btn)
    }
    
    private func addLabel(_ text: String) {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = .secondaryLabelColor.withAlphaComponent(0.6)
        stackView.addArrangedSubview(label)
    }
    
    @objc func buttonClicked(_ sender: SidebarButton) {
        // Update UI
        buttons.forEach { $0.isSelected = false }
        sender.isSelected = true
        
        // Notify Delegate
        delegate?.didSelectSection(sender.sectionTitle)
        
        // Haptic Feedback

    }
    
    func selectItem(named name: String) {
        if let btn = buttons.first(where: { $0.sectionTitle == name }) {
            buttonClicked(btn)
        }
    }
}

// Custom Sidebar Button with "Modern" Feel
class SidebarButton: NSButton {
    let sectionTitle: String
    var isSelected: Bool = false {
        didSet { needsDisplay = true }
    }
    
    private let iconColor: NSColor
    private let iconName: String
    private var isHovering: Bool = false {
        didSet { needsDisplay = true }
    }
    
    init(title: String, iconName: String, iconColor: NSColor) {
        self.sectionTitle = title
        self.iconName = iconName
        self.iconColor = iconColor
        super.init(frame: .zero)
        self.title = ""
        self.bezelStyle = .inline
        self.isBordered = false
        self.SetConstraints()
        
        // Hover Tracking
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        self.addTrackingArea(area)
    }
    
    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }
    
    required init?(coder: NSCoder) { fatalError() }
    
    private func SetConstraints() {
        self.translatesAutoresizingMaskIntoConstraints = false
        self.heightAnchor.constraint(equalToConstant: 34).isActive = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        // 1. Draw Hover/Selection Background
        if isSelected || isHovering {
            // Shortened selection width (more padding on right)
            let path = NSBezierPath(roundedRect: NSRect(x: 8, y: 0, width: bounds.width - 24, height: bounds.height), xRadius: 10, yRadius: 10)
            
            if isSelected {
                // Rich Gradient for Selection
                let startColor = NSColor.controlAccentColor.withAlphaComponent(0.25)
                let endColor = NSColor.controlAccentColor.withAlphaComponent(0.15)
                let gradient = NSGradient(starting: startColor, ending: endColor)
                gradient?.draw(in: path, angle: 90)
                
                // Subtle Inner Stroke
                NSColor.white.withAlphaComponent(0.1).setStroke()
                path.lineWidth = 0.5
                path.stroke()
            } else {
                NSColor.labelColor.withAlphaComponent(0.05).setFill()
                path.fill()
            }
        }
        
        // 2. Draw Icon
        let iconSize = NSSize(width: 18, height: 18) // Slightly larger
        let iconRect = NSRect(x: 12, y: (bounds.height - iconSize.height)/2, width: iconSize.width, height: iconSize.height)
        
        if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
            // Active: Accent Color; Inactive: Gray
            let color = isSelected ? NSColor.controlAccentColor : NSColor.secondaryLabelColor
            let config = NSImage.SymbolConfiguration(paletteColors: [color])
            let coloredImg = image.withSymbolConfiguration(config)
            coloredImg?.draw(in: iconRect)
        }
        
        // 3. Draw Text
        let textRect = NSRect(x: 40, y: (bounds.height - 16)/2, width: bounds.width - 44, height: 16)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: isSelected ? .semibold : .medium),
            .foregroundColor: isSelected ? NSColor.labelColor : NSColor.secondaryLabelColor
        ]
        (sectionTitle as NSString).draw(in: textRect, withAttributes: attrs)
    }
}

// MARK: - Container Content View
class ContainerViewController: NSViewController, SidebarDelegate {
    private var currentVC: NSViewController?
    
    // Cache view controllers
    private lazy var generalVC = ModernGeneralViewController()
    private lazy var controlsVC = ModernControlsViewController()
    private lazy var tutorialVC = ModernTutorialViewController()
    private lazy var aboutVC = ModernAboutViewController()
    
    override func loadView() {
        self.view = NSView(frame: .zero)
        self.view.wantsLayer = true
        self.view.layer?.backgroundColor = .clear
        // Default to General
        switchChild(to: generalVC)
    }
    
    func didSelectSection(_ name: String) {
        switch name {
        case "General": switchChild(to: generalVC)
        case "Controls": switchChild(to: controlsVC)
        case "Tutorial": switchChild(to: tutorialVC)
        case "About": switchChild(to: aboutVC)
        default: break
        }
    }
    
    private func switchChild(to newVC: NSViewController) {
        if let current = currentVC {
            current.view.removeFromSuperview()
            current.removeFromParent()
        }
        
        addChild(newVC)
        newVC.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(newVC.view)
        
        NSLayoutConstraint.activate([
            newVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            newVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            newVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            newVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        // Fade Animation can be added to view.layer
        newVC.view.wantsLayer = true
        let transition = CATransition()
        transition.type = .fade
        transition.duration = 0.2
        view.layer?.add(transition, forKey: nil)
        
        currentVC = newVC
    }
}

// MARK: - Modern Base Child Controller (Large Title + Card)
class ModernBaseViewController: NSViewController {
    let pageTitle: String
    private var cardContainer: NSView! // Property for layout updates
    
    init(title: String) {
        self.pageTitle = title
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func loadView() {
        self.view = NSView(frame: .zero)
        self.view.wantsLayer = true
        self.view.layer?.backgroundColor = .clear
        
        // 1. Large Header Title (Thicker, Larger)
        let headerLabel = NSTextField(labelWithString: pageTitle)
        headerLabel.font = NSFont.systemFont(ofSize: 32, weight: .heavy) // Increased Size & Weight
        headerLabel.textColor = .labelColor
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(headerLabel)
        
        // 2. Card Container (Unified 3D Floating Card)
        cardContainer = NSView()
        cardContainer.wantsLayer = true
        cardContainer.layer?.name = "cardContainer" // Tag for debug
        cardContainer.translatesAutoresizingMaskIntoConstraints = false
        
        // Multi-layered Deep 3D Shadow (Aligned with Sidebar)
        // Multi-layered Deep 3D Shadow (Tweaked for less truncation)
        let shadowColors = [0.4, 0.22, 0.1, 0.05]
        let shadowRadii: [CGFloat] = [10, 25, 50, 90]
        let shadowXOffsets: [CGFloat] = [6, 12, 24, 40] // Reduced X Offset for safety (was 48)
        let shadowYOffsets: [CGFloat] = [-5, -10, -20, -35]
        
        for i in 0..<4 {
            let sLayer = CALayer()
            sLayer.shadowColor = NSColor.black.cgColor
            sLayer.shadowOpacity = Float(shadowColors[i])
            sLayer.shadowOffset = CGSize(width: shadowXOffsets[i], height: shadowYOffsets[i])
            sLayer.shadowRadius = shadowRadii[i]
            sLayer.name = "content_s_\(i)"
            cardContainer.layer?.addSublayer(sLayer)
        }
        
        // Update paths on layout or after delay
        // Async shadow update moved to viewDidLayout to prevent race conditions
        
        view.addSubview(cardContainer)
        
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(white: 0.16, alpha: 0.45).cgColor // Refined for better transparency while maintaining depth
        card.layer?.cornerRadius = 20
        card.layer?.cornerCurve = .continuous
        card.layer?.masksToBounds = true
        
        // Premium Double Border (ENHANCED RIM)
        card.layer?.borderWidth = 0.8
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.addSubview(card)
        
        // Physical Interior Glow/Glint (TOP)
        let glint = NSView()
        glint.wantsLayer = true
        glint.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        glint.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(glint)
        
        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 40),
            headerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            
            cardContainer.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 20),
            cardContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            cardContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -60), // Increased margin (was -52)
            cardContainer.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -40),
            
            card.topAnchor.constraint(equalTo: cardContainer.topAnchor),
            card.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor),
            
            glint.topAnchor.constraint(equalTo: card.topAnchor),
            glint.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            glint.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            glint.heightAnchor.constraint(equalToConstant: 0.5)
        ])
        
        // Let subclasses populate the card using a simple stack
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 24
        stack.edgeInsets = NSEdgeInsets(top: 32, left: 32, bottom: 32, right: 32) // Maximized padding
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])
        
        setupContent(in: stack)
    }
    
    override func viewDidLayout() {
        super.viewDidLayout()
        // Reliable Shadow Update
        if let card = cardContainer, let layer = card.layer {
            let path = NSBezierPath(roundedRect: card.bounds, xRadius: 20, yRadius: 20).cgPath
            layer.sublayers?.forEach { 
                if $0.name?.starts(with: "content_s_") == true {
                     $0.frame = card.bounds
                     $0.shadowPath = path
                }
            }
        }
    }
    
    // Subclasses override this
    func setupContent(in stack: NSStackView) {}
    
    func createRow(label: String, control: NSView) -> NSStackView {
        let row = NSStackView()
        row.spacing = 10
        row.alignment = .firstBaseline
        
        let lbl = NSTextField(labelWithString: label)
        lbl.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        
        row.addArrangedSubview(lbl)
        row.addArrangedSubview(control)
        return row
    }
}

// MARK: - Modern General VC
class ModernGeneralViewController: ModernBaseViewController {
    init() { super.init(title: "General") }
    required init?(coder: NSCoder) { fatalError() }
    
    private var statusLabel: NSTextField!
    private var permissionIcon: NSImageView!
    
    override func setupContent(in stack: NSStackView) {
        // Permissions Section
        let permRow = NSStackView()
        permRow.spacing = 10
        
        permissionIcon = NSImageView(image: NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)!)
        permissionIcon.contentTintColor = .systemGray
        
        statusLabel = NSTextField(labelWithString: "Checking Permissions...")
        statusLabel.font = NSFont.systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabelColor
        
        permRow.addArrangedSubview(permissionIcon)
        permRow.addArrangedSubview(statusLabel)
        
        let openSettingsBtn = NSButton(title: "Open Settings", target: self, action: #selector(openPrivacySettings))
        openSettingsBtn.bezelStyle = .rounded
        permRow.addArrangedSubview(openSettingsBtn)
        
        stack.addArrangedSubview(createHeader("Permissions"))
        stack.addArrangedSubview(permRow)
        
        // Add troubleshooting hint
        let hintLabel = NSTextField(labelWithString: "If checked but red, remove app (-) and re-add (+).")
        hintLabel.font = NSFont.systemFont(ofSize: 10)
        hintLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(hintLabel)
        
        stack.addArrangedSubview(NSBox.createSeparator())
        
        // Launch on Login
        let launchSwitch = NSSwitch()
        launchSwitch.state = AutoStartManager.shared.isEnabled ? .on : .off
        launchSwitch.target = self
        launchSwitch.action = #selector(toggleLaunch)
        
        stack.addArrangedSubview(createRow(label: "Start at Login", control: launchSwitch))
        
        // Auto Updates
        let updateSwitch = NSSwitch()
        updateSwitch.state = UpdateChecker.shared.isAutoCheckEnabled ? .on : .off
        updateSwitch.target = self
        updateSwitch.action = #selector(toggleUpdates)
        
        stack.addArrangedSubview(createRow(label: "Auto Check Updates", control: updateSwitch))
        
        stack.addArrangedSubview(NSBox.createSeparator())
        
        // Auto Hide
        stack.addArrangedSubview(createHeader("Dock Behaviour"))
        
        let hideRow = NSStackView()
        hideRow.spacing = 12
        hideRow.alignment = .firstBaseline
        
        let hideLabel = NSTextField(labelWithString: "Auto Hide Delay")
        
        let hidePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        let options = [
            ("Never", 0.0),
            ("3 Seconds", 3.0),
            ("5 Seconds", 5.0),
            ("10 Seconds", 10.0),
            ("15 Seconds", 15.0),
            ("30 Seconds", 30.0),
            ("1 Minute", 60.0)
        ]
        
        for (title, val) in options {
            hidePopup.addItem(withTitle: title)
            hidePopup.lastItem?.representedObject = val
        }
        
        // Restore state
        let currentDelay = AutoHideManager.shared.isEnabled ? AutoHideManager.shared.delay : 0.0
        // Find closest match or select Never if disabled
        if !AutoHideManager.shared.isEnabled {
            hidePopup.selectItem(withTitle: "Never")
        } else {
            // Find item with closest double value
            if let item = hidePopup.itemArray.first(where: { ($0.representedObject as? Double) == currentDelay }) {
                hidePopup.select(item)
            } else {
                // Fallback to 5s default if custom value
                hidePopup.selectItem(withTitle: "5 Seconds")
            }
        }
        
        hidePopup.target = self
        hidePopup.action = #selector(changeAutoHideDelay(_:))
        
        hideRow.addArrangedSubview(hideLabel)
        hideRow.addArrangedSubview(hidePopup)
        
        stack.addArrangedSubview(hideRow)
        
        updatePermission()
        // Start timer
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in self?.updatePermission() }
    }
    
    @objc func changeAutoHideDelay(_ sender: NSPopUpButton) {
        guard let val = sender.selectedItem?.representedObject as? Double else { return }
        
        if val <= 0 {
            AutoHideManager.shared.isEnabled = false
        } else {
            AutoHideManager.shared.isEnabled = true
            AutoHideManager.shared.delay = val
        }
    }
    
    func createHeader(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        l.textColor = .tertiaryLabelColor
        return l
    }
    
    func updatePermission() {
        if AXIsProcessTrusted() {
            permissionIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            permissionIcon.contentTintColor = .systemGreen
            statusLabel.stringValue = "Accessibility Granted"
        } else {
            permissionIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            permissionIcon.contentTintColor = .systemRed
            statusLabel.stringValue = "Not Granted"
        }
    }
    
    @objc func openPrivacySettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    @objc func toggleLaunch(_ sender: NSSwitch) { AutoStartManager.shared.toggle(sender.state == .on) }
    @objc func toggleUpdates(_ sender: NSSwitch) { UpdateChecker.shared.isAutoCheckEnabled = (sender.state == .on) }
}

// MARK: - Modern Controls VC
// MARK: - Modern Controls VC
// MARK: - Modern Controls VC (V3 Redesign)
class ModernControlsViewController: ModernBaseViewController {
    init() { super.init(title: "Controls") }
    required init?(coder: NSCoder) { fatalError() }
    
    // UI Elements
    private var recorderView: NSView!
    private var keyLabel: NSTextField!
    private var statusIcon: NSImageView!
    private var hintLabel: NSTextField!
    private var isRecording = false
    
    override func setupContent(in stack: NSStackView) {
        // 1. Adjust Stack for Centering
        stack.alignment = .centerX
        stack.distribution = .fill
        stack.spacing = 24
        
        // Push content down to vertical center (Spacer)
        let topSpacer = NSView()
        stack.addArrangedSubview(topSpacer)
        topSpacer.heightAnchor.constraint(equalToConstant: 40).isActive = true
        
        // 2. Hero Section
        let heroIcon = NSImageView(image: NSImage(systemSymbolName: "command", accessibilityDescription: nil)!)
        heroIcon.symbolConfiguration = .init(pointSize: 64, weight: .ultraLight)
        heroIcon.contentTintColor = .secondaryLabelColor
        
        let heroTitle = NSTextField(labelWithString: "Global Boss Key")
        heroTitle.font = .systemFont(ofSize: 24, weight: .bold)
        heroTitle.textColor = .labelColor
        
        let loopDesc = NSTextField(labelWithString: "Instantly hide all windows when panic strikes.")
        loopDesc.font = .systemFont(ofSize: 14)
        loopDesc.textColor = .secondaryLabelColor
        
        stack.addArrangedSubview(heroIcon)
        stack.addArrangedSubview(heroTitle)
        stack.addArrangedSubview(loopDesc)
        
        // 3. Giant Recorder View
        recorderView = NSView()
        recorderView.wantsLayer = true
        recorderView.layer?.backgroundColor = NSColor(white: 0, alpha: 0.3).cgColor
        recorderView.layer?.cornerRadius = 20
        recorderView.layer?.borderWidth = 1.5
        recorderView.layer?.borderColor = NSColor(white: 1, alpha: 0.1).cgColor
        recorderView.translatesAutoresizingMaskIntoConstraints = false
        
        // Size Constraints
        recorderView.widthAnchor.constraint(equalToConstant: 300).isActive = true
        recorderView.heightAnchor.constraint(equalToConstant: 80).isActive = true
        
        // Content inside Recorder
        keyLabel = NSTextField(labelWithString: HotkeyManager.shared.stringRepresentation())
        keyLabel.font = .monospacedSystemFont(ofSize: 32, weight: .bold)
        keyLabel.textColor = .white
        keyLabel.alignment = .center
        keyLabel.translatesAutoresizingMaskIntoConstraints = false
        
        statusIcon = NSImageView(image: NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)!)
        statusIcon.symbolConfiguration = .init(pointSize: 24, weight: .bold)
        statusIcon.contentTintColor = .systemGreen
        statusIcon.isHidden = true
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        
        recorderView.addSubview(keyLabel)
        recorderView.addSubview(statusIcon)
        
        NSLayoutConstraint.activate([
            keyLabel.centerXAnchor.constraint(equalTo: recorderView.centerXAnchor),
            keyLabel.centerYAnchor.constraint(equalTo: recorderView.centerYAnchor),
            
            statusIcon.trailingAnchor.constraint(equalTo: recorderView.trailingAnchor, constant: -20),
            statusIcon.centerYAnchor.constraint(equalTo: recorderView.centerYAnchor)
        ])
        
        // Click Gesture
        let click = NSClickGestureRecognizer(target: self, action: #selector(startRecording))
        recorderView.addGestureRecognizer(click)
        
        // Cursor
        recorderView.addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeInActiveApp, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil))
        
        stack.addArrangedSubview(recorderView)
        
        // 4. Bottom Hint
        hintLabel = NSTextField(labelWithString: "Click to set new shortcut")
        hintLabel.font = .systemFont(ofSize: 12, weight: .medium)
        hintLabel.textColor = .tertiaryLabelColor
        startBlinkingHint()
        
        stack.addArrangedSubview(hintLabel)
        
        
        // Monitor key events locally when recording
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.isRecording == true {
                self?.handleKey(event)
                return nil
            }
            return event
        }
    }
    
    // Hover Effects
    override func mouseEntered(with event: NSEvent) {
        if !isRecording {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                recorderView.animator().layer?.backgroundColor = NSColor(white: 0, alpha: 0.5).cgColor
                recorderView.animator().layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
            }
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        if !isRecording {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                recorderView.animator().layer?.backgroundColor = NSColor(white: 0, alpha: 0.3).cgColor
                recorderView.animator().layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
            }
        }
    }
    
    @objc func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        
        // Update UI for Recording
        keyLabel.stringValue = "Press Keys..."
        keyLabel.textColor = .systemBlue
        keyLabel.font = .systemFont(ofSize: 24, weight: .medium) // Smaller for instruction
        
        recorderView.layer?.borderColor = NSColor.systemBlue.cgColor
        recorderView.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.15).cgColor
        
        hintLabel.stringValue = "Press ESC to cancel"
        statusIcon.isHidden = true
    }
    
    func handleKey(_ event: NSEvent) {
        if event.keyCode == 53 { // ESC
            cancelRecording()
            return
        }
        
        var carbonMods: UInt32 = 0
        if event.modifierFlags.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.control) { carbonMods |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option)  { carbonMods |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift)   { carbonMods |= UInt32(shiftKey) }
        
        // Validate: Don't allow single keys without modifiers (optional, but good practice)
        // For now allowing any combo
        
        HotkeyManager.shared.currentKeyCode = Int(event.keyCode)
        HotkeyManager.shared.currentModifiers = Int(carbonMods)
        HotkeyManager.shared.registerHotkey()
        
        finishRecordingSuccess()
    }
    
    func cancelRecording() {
        isRecording = false
        resetUI(animate: true)
    }
    
    func finishRecordingSuccess() {
        isRecording = false
        
        // Show Success State
        keyLabel.stringValue = "Saved!"
        keyLabel.textColor = .systemGreen
        
        recorderView.layer?.borderColor = NSColor.systemGreen.cgColor
        recorderView.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.1).cgColor
        
        statusIcon.isHidden = false
        statusIcon.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            statusIcon.animator().alphaValue = 1
        }
        
        // Revert to Key Display after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.resetUI(animate: true)
        }
    }
    
    func resetUI(animate: Bool) {
        let updates = {
            self.keyLabel.stringValue = HotkeyManager.shared.stringRepresentation()
            self.keyLabel.font = .monospacedSystemFont(ofSize: 32, weight: .bold)
            self.keyLabel.textColor = .white
            
            self.recorderView.layer?.borderColor = NSColor(white: 1, alpha: 0.1).cgColor
            self.recorderView.layer?.backgroundColor = NSColor(white: 0, alpha: 0.3).cgColor
            
            self.statusIcon.isHidden = true
            self.hintLabel.stringValue = "Click to set new shortcut"
        }
        
        if animate {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                updates()
            }
        } else {
            updates()
        }
    }
    
    func startBlinkingHint() {
        // Just a subtle pulse
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 1.0
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.hintLabel.animator().alphaValue = 0.6
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 1.0
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.hintLabel.animator().alphaValue = 1.0
            }, completionHandler: {
                if self.view.window != nil { self.startBlinkingHint() }
            })
        })
    }
}



// MARK: - Modern About VC
// MARK: - Modern About VC
class ModernAboutViewController: ModernBaseViewController {
    init() { super.init(title: "About") }
    required init?(coder: NSCoder) { fatalError() }
    
    private var updateSpinner: NSProgressIndicator!
    private var checkUpdateBtn: NSButton!
    
    override func setupContent(in stack: NSStackView) {
        // 1. Header (Icon + Name + Version)
        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 20
        
        let icon = NSImageView(image: NSImage(named: NSImage.applicationIconName) ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 80).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 80).isActive = true
        
        let headerText = NSStackView()
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = 4
        
        let name = NSTextField(labelWithString: "GetBackMyWindows")
        name.font = .systemFont(ofSize: 24, weight: .heavy)
        
        let ver = NSTextField(labelWithString: "Version \(UpdateChecker.currentVersion)")
        ver.textColor = .secondaryLabelColor
        ver.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        
        let github = NSButton(title: "Visit GitHub", target: self, action: #selector(visitGitHub))
        github.bezelStyle = .inline
        
        headerText.addArrangedSubview(name)
        headerText.addArrangedSubview(ver)
        headerText.addArrangedSubview(github)
        
        header.addArrangedSubview(icon)
        header.addArrangedSubview(headerText)
        
        stack.addArrangedSubview(header)
        
        stack.addArrangedSubview(NSBox.createSeparator())
        
        // 2. Updates Section (Styled Card Row)
        let updateSection = NSStackView()
        updateSection.orientation = .vertical
        updateSection.alignment = .leading
        updateSection.spacing = 10
        
        let updateTitle = NSTextField(labelWithString: "Software Update")
        updateTitle.font = .systemFont(ofSize: 14, weight: .bold)
        
        let updateRow = NSStackView()
        updateRow.orientation = .horizontal
        updateRow.spacing = 16
        updateRow.alignment = .centerY
        
        let updateIcon = NSImageView(image: NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)!)
        updateIcon.contentTintColor = .systemBlue
        
        let updateDesc = NSTextField(labelWithString: "Check for new features and improvements.")
        updateDesc.textColor = .secondaryLabelColor
        updateDesc.font = .systemFont(ofSize: 13)
        
        checkUpdateBtn = NSButton(title: "Check Now", target: self, action: #selector(checkUpdate))
        checkUpdateBtn.bezelStyle = .rounded
        
        updateSpinner = NSProgressIndicator()
        updateSpinner.style = .spinning
        updateSpinner.controlSize = .small
        updateSpinner.isDisplayedWhenStopped = false
        
        updateRow.addArrangedSubview(updateIcon)
        updateRow.addArrangedSubview(updateDesc)
        updateRow.addArrangedSubview(updateSpinner)
        updateRow.addArrangedSubview(checkUpdateBtn)
        
        updateSection.addArrangedSubview(updateTitle)
        updateSection.addArrangedSubview(updateRow)
        
        stack.addArrangedSubview(updateSection)
        
        stack.addArrangedSubview(NSBox.createSeparator())
        
        // 3. Author Section
        let authorRow = NSStackView()
        authorRow.orientation = .horizontal
        authorRow.alignment = .centerY
        authorRow.spacing = 8
        
        let authorLabel = NSTextField(labelWithString: "Designed & Developed by")
        authorLabel.textColor = .secondaryLabelColor
        
        let authorName = NSTextField(labelWithString: "Zhixuan Zhao")
        authorName.font = .systemFont(ofSize: 13, weight: .semibold)
        
        authorRow.addArrangedSubview(authorLabel)
        authorRow.addArrangedSubview(authorName)
        
        stack.addArrangedSubview(authorRow)
    }
    
    @objc func visitGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/Avi7ii/GetBackMyWindows")!)
    }
    
    @objc func checkUpdate() {
        updateSpinner.startAnimation(nil)
        checkUpdateBtn.isEnabled = false
        
        UpdateChecker.shared.checkForUpdates(force: true) { [weak self] hasNew in
            DispatchQueue.main.async {
                self?.updateSpinner.stopAnimation(nil)
                self?.checkUpdateBtn.isEnabled = true
                self?.showUpdateResult(hasNew: hasNew)
            }
        }
    }
    
    func showUpdateResult(hasNew: Bool) {
        let alert = NSAlert()
        if hasNew {
            alert.messageText = "Update Available! 🎉"
            alert.informativeText = "Version \(UpdateChecker.shared.latestVersionAvailable ?? "New") is available on GitHub."
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Cancel")
            
            if alert.runModal() == .alertFirstButtonReturn {
                visitGitHub()
            }
        } else {
            alert.messageText = "Up to Date"
            alert.informativeText = "You are using the latest version (\(UpdateChecker.currentVersion))."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

// Helper Extensions
extension NSBox {
    static func createSeparator() -> NSBox {
        let b = NSBox()
        b.boxType = .separator
        return b
    }
}
