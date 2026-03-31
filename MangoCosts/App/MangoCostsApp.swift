import SwiftUI
import AppKit

@main
struct MangoCostsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var floatingPanel: FloatingPanel?
    let costModel = CostModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenuBar()
        setupFloatingPanel()
        NotificationManager.shared.requestPermission()
    }

    // MARK: Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.title = "🥭"
        button.action = #selector(statusBarButtonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show / Hide", action: #selector(togglePanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Mango Costs", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc func togglePanel() {
        guard let panel = floatingPanel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFront(nil)
        }
    }

    @objc private func refreshNow() {
        costModel.loadSessionData()
    }

    // MARK: Floating Panel

    private func setupFloatingPanel() {
        let panel = FloatingPanel(costModel: costModel)
        panel.positionTopRight()
        panel.orderFront(nil)
        floatingPanel = panel
    }
}

// MARK: - FloatingPanel

final class FloatingPanel: NSPanel {
    init(costModel: CostModel) {
        // Use borderless panel — we draw our own header in SwiftUI for full layout control
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 260),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true



        let contentView = ContentView(costModel: costModel, onClose: {
            NSApp.terminate(nil)
        })
        let hosting = NSHostingView(rootView: contentView)
        hosting.frame = self.contentView!.bounds
        hosting.autoresizingMask = [.width, .height]
        self.contentView?.addSubview(hosting)

        // Rounded corners at window level
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.cornerRadius = 12
        self.contentView?.layer?.masksToBounds = true
    }

    func positionTopRight() {
        guard let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        let w: CGFloat = 320
        let h: CGFloat = 260
        setFrameOrigin(NSPoint(x: sf.maxX - w - 20, y: sf.maxY - h - 20))
    }
}
