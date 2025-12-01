import SwiftUI
import UserNotifications

extension Notification.Name {
    static let unreadMessage = Notification.Name("unreadMessage")
    static let messagesRead = Notification.Name("messagesRead")
    static let typingStarted = Notification.Name("typingStarted")
    static let typingEnded = Notification.Name("typingEnded")
}

@main
struct MenuBarChatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 1. To definiuje oficjalne okno ustawień (Cmd+,)
        Settings {
            SettingsView()
        }
    }
}
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem?
    var popover = NSPopover()
    
    // Monitor klawiatury
    var eventMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A. Setup Widoku
        let contentView = ContentView()
        popover.contentSize = NSSize(width: 340, height: 550)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)
        
        // B. Setup Ikony (bez zmian)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            let iconView = NSHostingView(rootView: MenuBarIconView())
            iconView.frame = NSRect(x: 0, y: 0, width: 22, height: 22)
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
        
        // C. Powiadomienia (bez zmian)
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        
        // D. SKRÓT KLAWIATUROWY (Global Hotkey)
        setupGlobalShortcut()
    }
    
    func setupGlobalShortcut() {
            // Pobieramy wybraną opcję (domyślnie teraz ctrl_opt_w)
            let shortcutKey = UserDefaults.standard.string(forKey: "globalShortcut") ?? "ctrl_opt_w"
            
            var modifierMask: NSEvent.ModifierFlags = []
            var keyCode: UInt16 = 0
            
            switch shortcutKey {
            case "ctrl_opt_w": // Control + Option + W
                modifierMask = [.control, .option]
                keyCode = 13
                
            case "ctrl_opt_s": // Control + Option + S
                modifierMask = [.control, .option]
                keyCode = 1
                
            case "cmd_ctrl_dot": // Command + Control + .
                modifierMask = [.command, .control]
                keyCode = 47
                
            default: // Fallback (ctrl + opt + w)
                modifierMask = [.control, .option]
                keyCode = 13
            }
            
            // Rejestracja monitora globalnego
            // Najpierw usuwamy stary monitor, jeśli istnieje (dla bezpieczeństwa)
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
            }
            
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.modifierFlags.contains(modifierMask) && event.keyCode == keyCode {
                    self?.togglePopover(nil)
                }
            }
        }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
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
