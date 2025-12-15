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
            SettingsView(chatManager: appDelegate.chatManager)
        }
    }
}

// ✅ ZMIANA 1: Dodajemy NSPopoverDelegate do listy protokołów
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem?
    var popover = NSPopover()
    var eventMonitor: Any?
    
    // ChatManager żyje tutaj przez cały czas działania aplikacji
    var chatManager = ChatManager()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        TempFileManager.shared.clearCache()
        
        let contentView = ContentView(chatManager: chatManager)
        
        popover.contentSize = NSSize(width: 340, height: 550)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)
        
        // ✅ ZMIANA 2: Ustawiamy delegata, aby wykrywać zamknięcie okna
        popover.delegate = self
        
        // Setup Ikony
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            let iconView = NSHostingView(rootView: MenuBarIconView())
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
        
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        
        setupGlobalShortcut()
    }
    
    // ✅ ZMIANA 3: Ta funkcja wywoła się AUTOMATYCZNIE, gdy popover zniknie (kliknięcie poza okno)
    func popoverDidClose(_ notification: Notification) {
        // Natychmiast zablokuj aplikację po zamknięciu okienka
        AppLockManager.shared.lock()
        print("🔒 Popover zamknięty – aplikacja zablokowana.")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        print("🛑 Zamykanie aplikacji... Ustawianie statusu offline.")
        TempFileManager.shared.clearCache()
        chatManager.setOfflineStatus()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
            
            // 1. Pobieramy ukryte ID z powiadomienia
            let userInfo = response.notification.request.content.userInfo
            
            if let senderIDString = userInfo["senderID"] as? String,
               let senderID = UUID(uuidString: senderIDString) {
                
                // 2. Przełączamy wątek na główny, bo będziemy zmieniać UI
                DispatchQueue.main.async {
                    // 3. Otwieramy okno aplikacji (jeśli zamknięte)
                    self.togglePopover(nil)
                    
                    // 4. Szukamy kontaktu w załadowanej liście
                    if let contact = self.chatManager.contacts.first(where: { $0.id == senderID }) {
                        // 5. Ustawiamy go jako aktywnego -> SwiftUI automatycznie przełączy widok na ChatView
                        self.chatManager.currentContact = contact
                        
                        // Opcjonalnie: Czyścimy status "nieprzeczytane"
                        self.chatManager.markMessagesAsRead(from: senderID)
                        
                        // Pobieramy historię rozmowy
                        Task { await self.chatManager.fetchMessages() }
                    }
                }
            }
            
            completionHandler()
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
                // performClose wyzwoli popoverDidClose, więc blokada zadziała
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .messagesRead, object: nil)
            }
        }
    }
}
