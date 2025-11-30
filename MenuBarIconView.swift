import SwiftUI

struct MenuBarIconView: View {
    // Stany aplikacji
    @State private var hasUnread = false
    @State private var isTyping = false
    
    var body: some View {
        ZStack {
            // 1. ZWYKŁA IKONA (Gdy nic się nie dzieje)
            if !hasUnread && !isTyping {
                Image(systemName: "message.fill")
                    .font(.system(size: 14)) // Rozmiar pasujący do paska
            }
            
            // 2. KTOŚ PISZE (Fala + Variable Color)
            if isTyping && !hasUnread {
                Image(systemName: "ellipsis.message.fill")
                    .font(.system(size: 14))
                    // Animacja: Zmieniające się kolory warstw (fala)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: true)
                    .foregroundStyle(.white) // Możemy zaszaleć z kolorem fali
            }
            
            // 3. NOWA WIADOMOŚĆ (Kropka + Pulse)
            if hasUnread {
                Image(systemName: "message.badge.filled.fill")
                    .font(.system(size: 14))
                    // Animacja: Pulsowanie całego dymku
                    .symbolEffect(.pulse, options: .repeating, isActive: true)
                    .foregroundStyle(.red, .white) // Biały dymek, czerwona kropka
            }
        }
        // Nasłuchiwanie na sygnały z ChatManager/AppDelegate
        .onReceive(NotificationCenter.default.publisher(for: .unreadMessage)) { _ in
            withAnimation { hasUnread = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .messagesRead)) { _ in
            withAnimation { hasUnread = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .typingStarted)) { _ in
            // Pokaż falę tylko jeśli nie ma ważniejszego statusu (nieprzeczytanej wiadomości)
            if !hasUnread {
                withAnimation { isTyping = true }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .typingEnded)) { _ in
            withAnimation { isTyping = false }
        }
    }
}
