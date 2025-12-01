import SwiftUI

struct ContentView: View {
    @State private var chatManager = ChatManager()
    
    // UI State
    @State private var isAddingContact = false
    @State private var newContactName = ""
    @State private var newContactToken = ""
    
    @State private var messageInput = ""
    @FocusState private var isInputFocused: Bool
    
    // Wyszukiwanie
    @State private var searchText = ""
    
    // Edycja wiadomości
    @State private var messageToEdit: Message?
    @State private var editContent = ""
    @State private var showEditAlert = false
    
    // --- BODY ---
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // --- HEADER (Nagłówek) ---
                headerView
                    .padding()
                    .background(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.05), radius: 5, y: 5)
                    .zIndex(1)
                
                // --- CONTENT (Treść) ---
                if let contact = chatManager.currentContact {
                    chatView(contact: contact)
                        .transition(.move(edge: .trailing))
                } else {
                    contactListView
                        .transition(.move(edge: .leading))
                }
                
                // --- PASEK OFFLINE (Status połączenia) ---
                if !chatManager.isConnected {
                    HStack(spacing: 6) {
                        Image(systemName: "wifi.slash")
                        Text("Brak połączenia")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.8))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .frame(width: 340, height: 550)
        .background(Color(.windowBackgroundColor)) // Jeśli nie masz tego koloru w Assets, użyje domyślnego
        .background(.ultraThinMaterial)
        .animation(.default, value: chatManager.isConnected)
        // Alert do edycji wiadomości
        .alert("Edytuj wiadomość", isPresented: $showEditAlert) {
            TextField("Treść", text: $editContent)
            Button("Zapisz") {
                if let msg = messageToEdit, let id = msg.id {
                    Task { await chatManager.editMessage(messageID: id, newContent: editContent) }
                }
            }
            Button("Anuluj", role: .cancel) { }
        }
    } // <--- KONIEC BODY
    
    // --- LOGIKA FILTROWANIA (Teraz poprawnie poza body) ---
    var filteredContacts: [Contact] {
        if searchText.isEmpty {
            return chatManager.contacts
        } else {
            return chatManager.contacts.filter { contact in
                contact.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    // --- KOMPONENTY ---
    
    var headerView: some View {
        HStack {
            if chatManager.currentContact != nil {
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        chatManager.currentContact = nil
                        searchText = "" // Czyścimy szukanie przy powrocie
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .bold()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                
                VStack(alignment: .leading) {
                    Text(chatManager.currentContact?.name ?? "Czat")
                        .font(.headline)
                    // Tutaj można dodać status online/offline znajomego
                }
            } else {
                Text("Wiadomości")
                    .font(.title3)
                    .fontWeight(.bold)
            }
            
            Spacer()
            
            // PRAWA STRONA (Profil)
            Menu {
                Text("ID: ...\(chatManager.myID.uuidString.suffix(4))")
                    .font(.caption)
                Button("Skopiuj moje ID") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(chatManager.myID.uuidString, forType: .string)
                }
                Divider()
                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("Zakończ aplikację")
                }
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
    
    var contactListView: some View {
        VStack(spacing: 0) {
            // 1. PASEK WYSZUKIWANIA
            if !chatManager.contacts.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("Szukaj kontaktu...", text: $searchText)
                        .textFieldStyle(.plain)
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.top, 10)
            }
            
            // 2. LISTA KONTAKTÓW
            ScrollView {
                VStack(spacing: 10) {
                    if filteredContacts.isEmpty && !searchText.isEmpty {
                        Text("Nie znaleziono \"\(searchText)\"")
                            .foregroundStyle(.secondary)
                            .padding(.top, 20)
                    }
                    else if chatManager.contacts.isEmpty {
                        VStack(spacing: 15) {
                            Image(systemName: "paperplane")
                                .font(.system(size: 40))
                                .foregroundStyle(.gray.opacity(0.3))
                            Text("Nikogo tu jeszcze nie ma")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 50)
                    }
                    else {
                        ForEach(filteredContacts) { contact in
                            HStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.1))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Text(String(contact.name.prefix(1)))
                                            .bold()
                                            .foregroundStyle(Color.accentColor)
                                    )
                                
                                VStack(alignment: .leading) {
                                    Text(contact.name)
                                        .font(.system(.body, design: .rounded))
                                        .bold()
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(12)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3)) {
                                    chatManager.currentContact = contact
                                    searchText = ""
                                }
                                // Dodajemy Task { }
                                Task {
                                    await chatManager.fetchMessages()
                                }
                            }
                            .contextMenu {
                                Button("Usuń", role: .destructive) {
                                    if let index = chatManager.contacts.firstIndex(where: { $0.id == contact.id }) {
                                        chatManager.removeContact(at: IndexSet(integer: index))
                                    }
                                }
                            }
                        }
                    }
                    
                    // 3. SEKCJA DODAWANIA
                    VStack(spacing: 12) {
                        if isAddingContact {
                            TextField("Nazwa (np. Kasia)", text: $newContactName)
                                .textFieldStyle(.roundedBorder)
                            TextField("Token ID", text: $newContactToken)
                                .textFieldStyle(.roundedBorder)
                            
                            HStack {
                                Button("Anuluj") { withAnimation { isAddingContact = false } }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.red)
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
                            }
                        } else {
                            Button(action: { withAnimation { isAddingContact = true } }) {
                                Label("Dodaj nowy kontakt", systemImage: "plus")
                                    .frame(maxWidth: .infinity)
                                    .padding(8)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                    .padding(.top, 10)
                }
                .padding()
            }
        }
    }
    
    func chatView(contact: Contact) -> some View {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        // --- 1. SPINNER (Jeśli ładujemy i pusto) ---
                        if chatManager.isLoading && chatManager.messages.isEmpty {
                            VStack(spacing: 15) {
                                Spacer().frame(height: 100) // Odstęp od góry
                                ProgressView()
                                    .controlSize(.large) // Większe kółko
                                Text("Wczytywanie historii...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        
                        // --- 2. LISTA WIADOMOŚCI (Jeśli są dane) ---
                        else {
                            LazyVStack(spacing: 0) { // Spacing 0, bo odstępy są w MessageBubble
                                Color.clear.frame(height: 10)
                                
                                ForEach(Array(chatManager.messages.enumerated()), id: \.element.id) { index, msg in
                                    
                                    // A. LOGIKA DATY (Nagłówki "Dzisiaj", "Wczoraj")
                                    let showDateHeader: Bool = {
                                        if index == 0 { return true }
                                        guard let currDate = msg.created_at,
                                              let prevDate = chatManager.messages[index - 1].created_at else { return false }
                                        return !Calendar.current.isDate(currDate, inSameDayAs: prevDate)
                                    }()
                                    
                                    if showDateHeader, let date = msg.created_at {
                                        DateHeader(date: date)
                                    }
                                    
                                    // B. LOGIKA GRUPOWANIA (Inteligentne rogi)
                                    let isPreviousSame: Bool = {
                                        if index == 0 { return false }
                                        if showDateHeader { return false } // Nowy dzień przerywa grupę
                                        return chatManager.messages[index - 1].sender_id == msg.sender_id
                                    }()
                                    
                                    let isNextSame: Bool = {
                                        if index >= chatManager.messages.count - 1 { return false }
                                        guard let currDate = msg.created_at,
                                              let nextDate = chatManager.messages[index + 1].created_at else { return false }
                                        if !Calendar.current.isDate(currDate, inSameDayAs: nextDate) { return false }
                                        return chatManager.messages[index + 1].sender_id == msg.sender_id
                                    }()
                                    
                                    // C. DYMEK WIADOMOŚCI
                                    MessageBubble(
                                        message: msg,
                                        isMe: msg.sender_id == chatManager.myID,
                                        isPreviousFromSameSender: isPreviousSame,
                                        isNextFromSameSender: isNextSame,
                                        onExpand: {
                                            // Scrolluj na dół przy rozwinięciu ostatniej wiadomości
                                            if msg.id == chatManager.messages.last?.id {
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                                        proxy.scrollTo(msg.id, anchor: .bottom)
                                                    }
                                                }
                                            }
                                        },
                                        onEdit: {
                                            messageToEdit = msg
                                            editContent = msg.content
                                            showEditAlert = true
                                        },
                                        onDelete: {
                                            if let id = msg.id { Task { await chatManager.deleteMessage(messageID: id) } }
                                        }
                                    )
                                    .id(msg.id)
                                }
                                
                                Color.clear.frame(height: 20)
                            }
                            .padding(.horizontal)
                        }
                    }
                    // Automatyczne przewijanie na dół przy nowej wiadomości
                    .onChange(of: chatManager.messages) {
                        if let lastMsg = chatManager.messages.last {
                            withAnimation { proxy.scrollTo(lastMsg.id, anchor: .bottom) }
                        }
                    }
                    .onAppear {
                        if let lastMsg = chatManager.messages.last {
                            proxy.scrollTo(lastMsg.id, anchor: .bottom)
                        }
                        isInputFocused = true
                    }
                }
                
                // --- 3. WSKAŹNIK PISANIA ---
                if chatManager.typingUserID == contact.id {
                    HStack {
                        TypingIndicatorView()
                        Text("\(contact.name) pisze...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
                    .transition(.opacity.animation(.easeInOut))
                }
                
                // --- 4. PASEK WPROWADZANIA (Input Bar) ---
                HStack(spacing: 10) {
                    TextField("Napisz wiadomość...", text: $messageInput)
                        .textFieldStyle(.plain)
                        .focused($isInputFocused)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .onSubmit(sendMessage)
                        .onChange(of: messageInput) {
                            if !messageInput.isEmpty {
                                chatManager.sendTypingSignal()
                            }
                        }
                    
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .resizable()
                            .frame(width: 30, height: 30)
                            .foregroundStyle(messageInput.isEmpty ? Color.white.opacity(0.2) : Color.blue)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(messageInput.isEmpty)
                }
                .padding(12)
                .background(.ultraThinMaterial)
            }
        }
    
    func sendMessage() {
        guard !messageInput.isEmpty else { return }
        let text = messageInput
        messageInput = ""
        Task { await chatManager.sendMessage(text) }
    }
}

// --- POMOCNICZE STRUKTURY ---

struct MessageBubble: View {
    let message: Message
    let isMe: Bool
    var isPreviousFromSameSender: Bool = false
    var isNextFromSameSender: Bool = false
    
    var onExpand: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    
    @State private var showDetails = false
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMe { Spacer() }
            
            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                
                if message.is_deleted == true {
                    Text("🚫 Wiadomość usunięta")
                        .font(.system(size: 13, weight: .light).italic())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(.white.opacity(0.6))
                        .background(Color.gray.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.content)
                        if message.edited_at != nil {
                            Text("(edytowano)")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(.white)
                    .background(isMe ? Color.blue : Color.white.opacity(0.15))
                    .brightness(showDetails ? -0.15 : 0)
                    .clipShape(
                        .rect(
                            topLeadingRadius: (!isMe && isPreviousFromSameSender) ? 4 : 16,
                            bottomLeadingRadius: (!isMe && isNextFromSameSender) ? 4 : (isMe ? 16 : 4),
                            bottomTrailingRadius: (isMe && isNextFromSameSender) ? 4 : (isMe ? 4 : 16),
                            topTrailingRadius: (isMe && isPreviousFromSameSender) ? 4 : 16
                        )
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showDetails.toggle()
                        }
                        if showDetails { onExpand?() }
                    }
                    .contextMenu {
                        if isMe {
                            Button { onEdit?() } label: { Label("Edytuj", systemImage: "pencil") }
                            Button(role: .destructive) { onDelete?() } label: { Label("Usuń", systemImage: "trash") }
                        } else {
                            Button("Kopiuj") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(message.content, forType: .string)
                            }
                        }
                    }
                }
                
                if showDetails && message.is_deleted != true {
                    HStack(spacing: 4) {
                        if let date = message.created_at {
                            Text(date.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        if isMe {
                            Image(systemName: message.is_read == true ? "checkmark.circle.fill" : "checkmark.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(message.is_read == true ? 0.8 : 0.4))
                        }
                    }
                    .padding(.horizontal, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            if !isMe { Spacer() }
        }
        .padding(.bottom, isNextFromSameSender ? 2 : 10)
    }
}

struct DateHeader: View {
    let date: Date
    var body: some View {
        Text(formatDate(date))
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(.white.opacity(0.6))
            .padding(.vertical, 4)
            .padding(.horizontal, 12)
            .background(Color.black.opacity(0.2))
            .clipShape(Capsule())
            .padding(.vertical, 4)
    }
    
    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Dzisiaj" }
        else if calendar.isDateInYesterday(date) { return "Wczoraj" }
        else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            formatter.locale = Locale(identifier: "pl_PL")
            return formatter.string(from: date)
        }
    }
}

struct TypingIndicatorView: View {
    @State private var numberOfDots = 3
    @State private var isAnimating = false
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<numberOfDots, id: \.self) { index in
                Circle()
                    .frame(width: 6, height: 6)
                    .foregroundStyle(.secondary)
                    .opacity(isAnimating ? 0.3 : 1.0)
                    .scaleEffect(isAnimating ? 0.8 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(0.2 * Double(index)), value: isAnimating)
            }
        }
        .onAppear { isAnimating = true }
    }
}
