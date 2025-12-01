import SwiftUI
import UserNotifications

// --- CENTRALNA DEFINICJA POWIADOMIEŃ ---
extension Notification.Name {
    static let unreadMessage = Notification.Name("unreadMessage")
    static let messagesRead = Notification.Name("messagesRead")
    static let typingStarted = Notification.Name("typingStarted")
    static let typingEnded = Notification.Name("typingEnded")
    static let incomingFile = Notification.Name("incomingFile")
}

@main
struct MenuBarChatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem?
    var popover = NSPopover()
    var eventMonitor: Any?
    
    // Tworzymy instancję managera tutaj, aby żyła przez cały czas działania aplikacji
    var chatManager = ChatManager()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Przekazujemy chatManager do ContentView
        let contentView = ContentView(chatManager: chatManager)
        
        popover.contentSize = NSSize(width: 340, height: 550)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)
        
        // Setup Ikony
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            let iconView = NSHostingView(rootView: MenuBarIconView())
            
            // Poprawione marginesy (38px)
            iconView.frame = NSRect(x: 0, y: 0, width: 38, height: 22)
            
            button.subviews.forEach { $0.removeFromSuperview() }
            button.addSubview(iconView)
            
            iconView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                iconView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor)
            ])
            
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        // Powiadomienia Systemowe
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        
        // Globalny Skrót
        setupGlobalShortcut()
    }
    
    // NOWE: Obsługa zamykania aplikacji
    func applicationWillTerminate(_ notification: Notification) {
        print("🛑 Zamykanie aplikacji... Ustawianie statusu offline.")
        chatManager.setOfflineStatus()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
    
    func setupGlobalShortcut() {
        let shortcutKey = UserDefaults.standard.string(forKey: "globalShortcut") ?? "ctrl_opt_w"
        var modifierMask: NSEvent.ModifierFlags = []
        var keyCode: UInt16 = 0
        
        switch shortcutKey {
        case "ctrl_opt_w": modifierMask = [.control, .option]; keyCode = 13
        case "ctrl_opt_s": modifierMask = [.control, .option]; keyCode = 1
        case "cmd_ctrl_dot": modifierMask = [.command, .control]; keyCode = 47
        default: modifierMask = [.control, .option]; keyCode = 13
        }
        
        if let monitor = eventMonitor { NSEvent.removeMonitor(monitor) }
        
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(modifierMask) && event.keyCode == keyCode {
                self?.togglePopover(nil)
            }
        }
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        if let button = statusItem?.button {
            if popover.isShown {
                popover.performClose(sender)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .messagesRead, object: nil)
            }
        }
    }
}
