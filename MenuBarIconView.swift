import SwiftUI

struct MenuBarIconView: View {
    // Stany aplikacji
    @State private var hasUnread = false
    @State private var isTyping = false
    @State private var isReceivingFile = false
    
    var body: some View {
        ZStack {
            // 1. DOMYŚLNA IKONA (Baza)
            Image(systemName: "message.fill")
                .font(.system(size: 14))
                .opacity((hasUnread || isTyping || isReceivingFile) ? 0 : 1) // Ukryj, jeśli jest inny stan
            
            // 2. NIEPRZECZYTANA WIADOMOŚĆ (Czerwona kropka)
            // Pokazujemy tylko, jeśli nie ma ważniejszych stanów (pisanie/plik)
            if hasUnread && !isTyping && !isReceivingFile {
                Image(systemName: "message.badge.filled.fill")
                    .font(.system(size: 14))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.red, .primary) // Czerwona kropka, systemowy dymek
                    .symbolEffect(.pulse, options: .repeating, isActive: true)
            }
            
            // 3. KTOŚ PISZE (Fala - Variable Color)
            // Ma wyższy priorytet niż zwykła kropka
            if isTyping && !isReceivingFile {
                Image(systemName: "ellipsis.message.fill")
                    .font(.system(size: 14))
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: true)
            }
            
            // 4. PLIK OCZEKUJĄCY (Najwyższy priorytet - Pulse)
            if isReceivingFile {
                Image(systemName: "arrow.down.message.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .symbolEffect(.pulse, options: .repeating, isActive: true)
            }
        }
        // --- OBSŁUGA SYGNAŁÓW ---
        .onReceive(NotificationCenter.default.publisher(for: .unreadMessage)) { _ in
            withAnimation { hasUnread = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .messagesRead)) { _ in
            withAnimation {
                hasUnread = false
                isReceivingFile = false // Resetujemy też ikonę pliku po wejściu w czat
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .typingStarted)) { _ in
            withAnimation { isTyping = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .typingEnded)) { _ in
            withAnimation { isTyping = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .incomingFile)) { _ in
            withAnimation { isReceivingFile = true }
        }
    }
}
