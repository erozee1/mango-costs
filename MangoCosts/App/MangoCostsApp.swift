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

final class FloatingPanel: NSPanel, NSWindowDelegate {
    init(costModel: CostModel) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "🥭 Mango Costs"
        titlebarAppearsTransparent = true
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        self.delegate = self

        let contentView = ContentView(costModel: costModel)
        let hosting = NSHostingView(rootView: contentView)
        hosting.frame = self.contentView!.bounds
        hosting.autoresizingMask = [.width, .height]
        self.contentView?.addSubview(hosting)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }

    func positionTopRight() {
        guard let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        setFrameOrigin(NSPoint(x: sf.maxX - frame.width - 20, y: sf.maxY - frame.height - 20))
    }
}
