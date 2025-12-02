import SwiftUI

struct ContactListView: View {
    var chatManager: ChatManager
    @Binding var searchText: String
    @Binding var isAddingContact: Bool
    
    // 🆕 USUNIĘTO: @State private var newContactName = ""
    // Zostało tylko to:
    @State private var newContactToken = ""
    @State private var isAdding = false // Do pokazania kręciołka
    
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
                        Text(Strings.notFound(searchText)).foregroundStyle(.secondary).padding(.top, 20)
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
        HStack(spacing: 8) {
             Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(Strings.searchPlaceholder, text: $searchText).textFieldStyle(.plain)
             if !searchText.isEmpty {
                 Button(action: { searchText = "" }) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
             }
             
             Button(action: { withAnimation { isAddingContact.toggle() } }) {
                 Image(systemName: isAddingContact ? "minus.circle.fill" : "plus.circle.fill")
                     .font(.title3)
                     .foregroundStyle(isAddingContact ? .gray : .blue)
             }
             .buttonStyle(.plain)
             .help(Strings.addContactTooltip)
             
         }.padding(10).background(Color.white.opacity(0.1)).cornerRadius(8).padding(.horizontal).padding(.top, 10)
    }
    
    // 🆕 ZMODYFIKOWANY FORMULARZ (Tylko Token)
    var addContactForm: some View {
        VStack(spacing: 10) {
            // Usunięto pole "Nazwa"
            
            HStack {
                TextField(Strings.pasteTokenPlaceholder, text: $newContactToken)
                    .textFieldStyle(.roundedBorder)
                
                if isAdding {
                    ProgressView().controlSize(.small)
                } else {
                    Button(Strings.addBtn) {
                        if !newContactToken.isEmpty {
                            isAdding = true
                            Task {
                                await chatManager.addContact(tokenString: newContactToken)
                                await MainActor.run {
                                    newContactToken = ""
                                    isAdding = false
                                    withAnimation { isAddingContact = false }
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(newContactToken.isEmpty)
                }
            }
            Text(Strings.contactAutoName)
                .font(.caption2)
                .foregroundStyle(.secondary)
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
            Text(Strings.noContactsTitle).foregroundStyle(.secondary)
            Button(Strings.noContactsBtn) { withAnimation { isAddingContact = true } }
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

// ContactRow (bez zmian - skopiowany z poprzedniej wersji dla kompletności)
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
        .contextMenu { Button(Strings.delete, role: .destructive) { if let idx = chatManager.contacts.firstIndex(where: { $0.id == contact.id }) { chatManager.removeContact(at: IndexSet(integer: idx)) } } }
    }
}
