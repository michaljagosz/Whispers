import SwiftUI

struct ContentView: View {
    @State private var chatManager = ChatManager()
    
    // UI State
    @State private var isAddingContact = false
    @State private var newContactName = ""
    @State private var newContactToken = ""
    @State private var messageInput = ""
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // --- HEADER (Nagłówek) ---
                headerView
                    .background(.ultraThinMaterial)
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundStyle(Color.white.opacity(0.1)),
                        alignment: .bottom
                    )
                    .zIndex(1)
                
                // --- CONTENT (Treść) ---
                ZStack {
                    // Ciemne tło
                    Color(nsColor: .windowBackgroundColor).opacity(0.5)
                        .ignoresSafeArea()
                    
                    if let contact = chatManager.currentContact {
                        chatView(contact: contact)
                            .transition(.move(edge: .trailing))
                    } else {
                        contactListView
                            .transition(.move(edge: .leading))
                    }
                }
            }
        }
        .frame(width: 340, height: 550)
        .background(Color.black.opacity(0.8))
        .background(.ultraThinMaterial)
    }
    
    // --- KOMPONENTY ---
    
    var headerView: some View {
        HStack {
            // LEWA STRONA
            HStack {
                if let contact = chatManager.currentContact {
                    // WIDOK CZATU: Przycisk powrotu + Status Rozmówcy
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            chatManager.currentContact = nil
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.name)
                            .font(.headline)
                            .foregroundStyle(.white)
                        
                        // Wyświetlanie statusu rozmówcy
                        let status = chatManager.friendStatuses[contact.id] ?? .online
                        HStack(spacing: 4) {
                            Circle()
                                .fill(status.color)
                                .frame(width: 6, height: 6)
                            Text(status.title)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                } else {
                    // WIDOK LISTY: Ustawienia + Mój Status
                    SettingsLink {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(",", modifiers: .command)
                    .help("Ustawienia (⌘,)")
                    
                    // Menu wyboru mojego statusu
                    Menu {
                        // Tutaj używamy Binding z logiką
                        Picker("Mój status", selection: Binding(
                            get: { chatManager.myStatus },
                            set: { chatManager.changeMyStatus(to: $0) }
                        )) {
                            ForEach(UserStatus.allCases, id: \.self) { status in
                                Label(status.title, systemImage: "circle.fill")
                                    // .foregroundStyle nie działa wewnątrz Pickera w starszych macOS, ale zostawiamy dla nowszych
                                    .tag(status)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Wiadomości")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                            
                            // Kropka mojego statusu
                            Circle()
                                .fill(chatManager.myStatus.color)
                                .frame(width: 8, height: 8)
                                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .padding(.leading, 4)
                }
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
                    .foregroundStyle(.white.opacity(0.8))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
    }
    
    var contactListView: some View {
            ScrollView {
                VStack(spacing: 10) {
                    // Przycisk Dodawania
                    if !isAddingContact {
                        Button(action: { withAnimation { isAddingContact = true } }) {
                            HStack {
                                Image(systemName: "plus")
                                Text("Dodaj nowy kontakt")
                            }
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 10)
                    }
                    
                    // Formularz dodawania
                    if isAddingContact {
                        VStack(spacing: 12) {
                            TextField("Nazwa", text: $newContactName)
                                .textFieldStyle(.plain)
                                .padding(8)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(6)
                                .foregroundStyle(.white)
                            
                            TextField("Token ID", text: $newContactToken)
                                .textFieldStyle(.plain)
                                .padding(8)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(6)
                                .foregroundStyle(.white)
                            
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
                        }
                        .padding()
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(12)
                    }
                    
                    // Lista kontaktów
                    if chatManager.contacts.isEmpty && !isAddingContact {
                        VStack(spacing: 15) {
                            Spacer().frame(height: 30)
                            Image(systemName: "person.2.slash")
                                .font(.system(size: 40))
                                .foregroundStyle(.white.opacity(0.2))
                            Text("Brak kontaktów")
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    } else {
                        ForEach(chatManager.contacts) { contact in
                            HStack {
                                // AWATAR Z KROPKĄ STATUSU
                                ZStack(alignment: .bottomTrailing) {
                                    Circle()
                                        .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Text(String(contact.name.prefix(1)).uppercased())
                                                .bold()
                                                .foregroundStyle(.white)
                                        )
                                    
                                    let status = chatManager.friendStatuses[contact.id] ?? .online
                                    Circle()
                                        .fill(status.color)
                                        .frame(width: 12, height: 12)
                                        .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 2))
                                }
                                
                                Text(contact.name)
                                    .font(.system(.body, design: .rounded))
                                    .bold()
                                    .foregroundStyle(.white)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(12)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3)) {
                                    chatManager.currentContact = contact
                                }
                                // --- TU BYŁ BŁĄD: Musi być Task { ... } ---
                                Task {
                                    await chatManager.fetchMessages()
                                    chatManager.markMessagesAsRead(from: contact.id)
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
                }
                .padding()
            }
        }
    
    func chatView(contact: Contact) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        Color.clear.frame(height: 10)
                        
                        ForEach(chatManager.messages) { msg in
                            MessageBubble(
                                message: msg,
                                isMe: msg.sender_id == chatManager.myID,
                                onExpand: {
                                    if msg.id == chatManager.messages.last?.id {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                                proxy.scrollTo("bottomID", anchor: .bottom)
                                            }
                                        }
                                    }
                                }
                            )
                            .id(msg.id)
                        }
                        
                        Color.clear
                            .frame(height: 50)
                            .id("bottomID")
                    }
                    .padding(.horizontal)
                }
                .onChange(of: chatManager.messages) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            proxy.scrollTo("bottomID", anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    proxy.scrollTo("bottomID", anchor: .bottom)
                    isInputFocused = true
                }
            }
            
            // Wskaźnik pisania
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
            
            // Input Bar
            HStack(spacing: 10) {
                TextField("Napisz wiadomość…", text: $messageInput)
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
                            // Wyślij sygnał "typing" w kontekście asynchronicznym
                            Task { await chatManager.sendTypingSignal() }
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

// Struktura MessageBubble (z poprzedniego kroku, dla pewności że jest)
struct MessageBubble: View {
    let message: Message
    let isMe: Bool
    var onExpand: (() -> Void)? = nil
    
    @State private var showDetails = false
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMe { Spacer() }
            
            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(.white)
                    .background(isMe ? Color.blue : Color.white.opacity(0.15))
                    .brightness(showDetails ? -0.15 : 0)
                    .clipShape(
                        .rect(
                            topLeadingRadius: 16,
                            bottomLeadingRadius: isMe ? 16 : 4,
                            bottomTrailingRadius: isMe ? 4 : 16,
                            topTrailingRadius: 16
                        )
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showDetails.toggle()
                        }
                        if showDetails { onExpand?() }
                    }
                
                if showDetails {
                    HStack(spacing: 4) {
                        if let date = message.created_at {
                            Text(date.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        
                        if isMe {
                            if message.is_read == true {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.8))
                            } else {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            
            if !isMe { Spacer() }
        }
    }
}

// Struktura TypingIndicatorView (też dla pewności)
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
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(0.2 * Double(index)),
                        value: isAnimating
                    )
            }
        }
        .onAppear { isAnimating = true }
    }
}

