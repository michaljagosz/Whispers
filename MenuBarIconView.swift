import SwiftUI

struct MenuBarIconView: View {
    // Stany aplikacji
    @State private var hasUnread = false
    @State private var isTyping = false
    @State private var isReceivingFile = false
    
    // Zmienna do manualnej animacji pulsowania
    @State private var fileIconOpacity: Double = 1.0
    
    var body: some View {
        ZStack {
            // 1. DOMYŚLNA IKONA (Baza)
            Image(systemName: "message.fill")
                .font(.system(size: 14))
                .opacity((hasUnread || isTyping || isReceivingFile) ? 0 : 1) // Ukryj, jeśli jest inny stan
            
            // 2. NIEPRZECZYTANA WIADOMOŚĆ (Czerwona kropka)
            if hasUnread && !isTyping && !isReceivingFile {
                Image(systemName: "message.badge.filled.fill")
                    .font(.system(size: 14))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.red, .primary)
                    .symbolEffect(.pulse, options: .repeating, isActive: true)
            }
            
            // 3. KTOŚ PISZE (Fala)
            if isTyping && !isReceivingFile {
                Image(systemName: "ellipsis.message.fill")
                    .font(.system(size: 14))
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: true)
            }
            
            // 4. PLIK OCZEKUJĄCY (Naprawiona animacja pulsowania)
            if isReceivingFile {
                Image(systemName: "arrow.down.message.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .opacity(fileIconOpacity) // Podpinamy przezroczystość
                    .onAppear {
                        // Start animacji pulsowania po pojawieniu się ikony
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                            fileIconOpacity = 0.3 // Pulsujemy do 30% widoczności
                        }
                    }
            }
        }
        // --- OBSŁUGA SYGNAŁÓW ---
        .onReceive(NotificationCenter.default.publisher(for: .unreadMessage)) { _ in
            withAnimation { hasUnread = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .messagesRead)) { _ in
            withAnimation {
                hasUnread = false
                isReceivingFile = false
                fileIconOpacity = 1.0 // Resetujemy stan animacji
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .typingStarted)) { _ in
            withAnimation { isTyping = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .typingEnded)) { _ in
            withAnimation { isTyping = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .incomingFile)) { _ in
            // Resetujemy opacity przed startem, żeby animacja "zaskoczyła" od 1.0
            fileIconOpacity = 1.0
            withAnimation { isReceivingFile = true }
        }
    }
}
