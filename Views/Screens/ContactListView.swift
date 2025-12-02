import SwiftUI

struct ContactListView: View {
    var chatManager: ChatManager
    @Binding var searchText: String
    @Binding var isAddingContact: Bool
    
    // Lokalne stany dla formularza
    @State private var newContactName = ""
    @State private var newContactToken = ""
    
    var filteredContacts: [Contact] {
        if searchText.isEmpty { return chatManager.contacts }
        else { return chatManager.contacts.filter { $0.name.localizedCaseInsensitiveContains(searchText) } }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Pasek wyszukiwania
            searchAndAddBar
            
            // Formularz dodawania
            if isAddingContact {
                addContactForm
            }
            
            // Lista kontaktów
            ScrollView {
                VStack(spacing: 10) {
                    if filteredContacts.isEmpty && !searchText.isEmpty {
                        Text("Nie znaleziono \"\(searchText)\"").foregroundStyle(.secondary).padding(.top, 20)
                    } else if chatManager.contacts.isEmpty && !isAddingContact {
                        emptyStateView
                    } else {
                        contactsList
                    }
                }.padding()
            }
        }
    }
    
    var searchAndAddBar: some View {
        // Skopiuj kod "HStack { Image(systemName: "magnifyingglass")... }" z Twojego ContentView
        // Zastąp lokalne zmienne odpowiednimi bindingami
        HStack(spacing: 8) {
             Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
             TextField("Szukaj kontaktu...", text: $searchText).textFieldStyle(.plain)
             if !searchText.isEmpty {
                 Button(action: { searchText = "" }) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
             }
             
             Button(action: { withAnimation { isAddingContact.toggle() } }) {
                 Image(systemName: isAddingContact ? "minus.circle.fill" : "plus.circle.fill")
                     .font(.title3)
                     .foregroundStyle(isAddingContact ? .gray : .blue)
             }
             .buttonStyle(.plain)
             .help("Dodaj nowy kontakt")
             
         }.padding(10).background(Color.white.opacity(0.1)).cornerRadius(8).padding(.horizontal).padding(.top, 10)
    }
    
    var addContactForm: some View {
        VStack(spacing: 10) {
            TextField("Nazwa", text: $newContactName).textFieldStyle(.roundedBorder)
            TextField("Token ID", text: $newContactToken).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Zapisz") {
                    if !newContactName.isEmpty && !newContactToken.isEmpty {
                        chatManager.addContact(name: newContactName, tokenString: newContactToken)
                        newContactName = ""
                        newContactToken = ""
                        withAnimation { isAddingContact = false }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
        .padding(.horizontal)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    var emptyStateView: some View {
        VStack(spacing: 15) {
            Image(systemName: "paperplane").font(.system(size: 40)).foregroundStyle(.gray.opacity(0.3))
            Text("Nikogo tu jeszcze nie ma").foregroundStyle(.secondary)
            Button("Dodaj kontakt") { withAnimation { isAddingContact = true } }
        }.padding(.top, 50)
    }
    
    var contactsList: some View {
        ForEach(filteredContacts) { contact in
            ContactRow(contact: contact, chatManager: chatManager) {
                withAnimation(.spring(response: 0.3)) { chatManager.currentContact = contact; searchText = "" }
                Task {
                    await chatManager.fetchMessages()
                    chatManager.markMessagesAsRead(from: contact.id)
                }
            }
        }
    }
}

// Pomocniczy widok pojedynczego wiersza kontaktu (warto go też wyodrębnić)
struct ContactRow: View {
    let contact: Contact
    var chatManager: ChatManager
    let action: () -> Void
    
    var body: some View {
        HStack {
            ZStack(alignment: .bottomTrailing) {
                Circle().fill(Color.accentColor.opacity(0.1)).frame(width: 40, height: 40)
                    .overlay(Text(String(contact.name.prefix(1))).bold().foregroundStyle(Color.accentColor))
                
                if let status = chatManager.friendStatuses[contact.id] {
                    Circle()
                        .fill(status.color)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color(.windowBackgroundColor), lineWidth: 2))
                }
            }
            
            VStack(alignment: .leading) { Text(contact.name).font(.system(.body, design: .rounded)).bold() }
            Spacer()
            
            if let unreadCount = chatManager.unreadCounts[contact.id], unreadCount > 0 {
                Text("\(unreadCount)")
                    .font(.caption2).fontWeight(.bold).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.red).clipShape(Capsule())
            }
            
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(10).background(Color.white.opacity(0.05)).cornerRadius(12).contentShape(Rectangle())
        .onTapGesture(perform: action)
        .contextMenu { Button("Usuń", role: .destructive) { if let idx = chatManager.contacts.firstIndex(where: { $0.id == contact.id }) { chatManager.removeContact(at: IndexSet(integer: idx)) } } }
    }
}
