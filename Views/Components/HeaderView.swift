import SwiftUI

struct HeaderView: View {
    var chatManager: ChatManager
    @Binding var searchText: String
    @Binding var pendingFileData: Data? // Potrzebne do resetu przy cofaniu
    @Binding var pendingFileName: String?
    
    // ✅ NOWE STANY dla Alertu Bezpieczeństwa
    @State private var showSafetyAlert = false
    @State private var safetyNumber: String = ""

    var body: some View {
        HStack {
            if chatManager.currentContact != nil {
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        chatManager.currentContact = nil
                        searchText = ""
                        pendingFileData = nil
                        pendingFileName = nil
                        chatManager.messages = []
                        // Reset licznika w ChatManager (opcjonalnie, jeśli dodasz tam taką funkcję)
                    }
                }) {
                    Image(systemName: "chevron.left").bold()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                
                VStack(alignment: .leading) {
                    Text(chatManager.currentContact?.name ?? Strings.messagesTitle).font(.headline)
                    if let contact = chatManager.currentContact, let status = chatManager.friendStatuses[contact.id] {
                        HStack(spacing: 4) {
                            Circle().fill(status.color).frame(width: 6, height: 6)
                            Text(status.title).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                
                // ✅ PRZYCISK WERYFIKACJI (Tylko gdy jesteśmy w czacie)
                Spacer()
                
                Menu {
                    Button(action: {
                        verifyContact()
                    }) {
                        Label(Strings.verifyContact, systemImage: "lock.shield")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                
            } else {
                Text(Strings.messagesTitle).font(.title3).fontWeight(.bold)
                
                Spacer()
                
                // Menu użytkownika
                Menu {
                    Picker(Strings.myStatus, selection: Binding(
                        get: { chatManager.myStatus },
                        set: { chatManager.changeMyStatus(to: $0) }
                    )) {
                        ForEach(UserStatus.allCases, id: \.self) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    .pickerStyle(.inline)
                    
                    Divider()
                    
                    Text("ID: ...\(chatManager.myID.uuidString.suffix(4))").font(.caption)
                    Button(Strings.copyId) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(chatManager.myID.uuidString, forType: .string)
                    }
                    Divider()
                    Button(role: .destructive) { NSApplication.shared.terminate(nil) } label: { Text(Strings.quitApp) }
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Image(systemName: "person.crop.circle").font(.system(size: 22))
                        Circle()
                            .fill(chatManager.myStatus.color)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
                    }
                    .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 5)
        .zIndex(1)
        // ✅ ALERT WERYFIKACJI
        .alert(Strings.safetyNumber, isPresented: $showSafetyAlert) {
            Button(Strings.ok, role: .cancel) { }
        } message: {
            Text(Strings.safetyAlertBody(safetyNumber))
        }
    }
    
    // ✅ FUNKCJA OBSŁUGUJĄCA LOGIKĘ
    func verifyContact() {
        guard let friendID = chatManager.currentContact?.id,
              let friendKey = chatManager.friendPublicKeys[friendID] else {
            return
        }
        
        if let number = CryptoManager.shared.generateSafetyNumber(friendPublicKeyBase64: friendKey) {
            self.safetyNumber = number
            self.showSafetyAlert = true
        }
    }
}
