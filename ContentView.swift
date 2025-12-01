import SwiftUI
import UniformTypeIdentifiers

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
    
    // Edycja
    @State private var messageToEdit: Message?
    @State private var editContent = ""
    @State private var showEditAlert = false
    
    // Pliki
    @State private var pendingFileData: Data?
    @State private var pendingFileName: String?
    @State private var isDropTargeted = false
    @State private var isSendingFile = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // HEADER
                headerView
                    .padding().background(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.05), radius: 5, y: 5).zIndex(1)
                
                // CONTENT
                if let contact = chatManager.currentContact {
                    chatView(contact: contact).transition(.move(edge: .trailing))
                } else {
                    contactListView.transition(.move(edge: .leading))
                }
                
                // OFFLINE BAR
                if !chatManager.isConnected {
                    HStack(spacing: 6) {
                        Image(systemName: "wifi.slash")
                        Text("Brak połączenia")
                    }
                    .font(.caption).fontWeight(.medium).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(Color.red.opacity(0.8))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            // OBSŁUGA DRAG & DROP (POPRAWIONA)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                return handleDrop(providers: providers)
            }
            .overlay {
                if isDropTargeted {
                    ZStack {
                        Color.blue.opacity(0.2)
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.blue, style: StrokeStyle(lineWidth: 3, dash: [10]))
                        VStack {
                            Image(systemName: "arrow.down.doc.fill").font(.system(size: 50))
                            Text("Upuść plik tutaj").font(.title2).bold()
                        }.foregroundStyle(.blue)
                    }.ignoresSafeArea().allowsHitTesting(false)
                }
            }
        }
        .frame(width: 340, height: 550)
        .background(Color(.windowBackgroundColor))
        .background(.ultraThinMaterial)
        .animation(.default, value: chatManager.isConnected)
        .animation(.easeInOut, value: isDropTargeted)
        .alert("Edytuj wiadomość", isPresented: $showEditAlert) {
            TextField("Treść", text: $editContent)
            Button("Zapisz") {
                if let msg = messageToEdit, let id = msg.id { Task { await chatManager.editMessage(messageID: id, newContent: editContent) } }
            }
            Button("Anuluj", role: .cancel) { }
        }
    }
    
    // --- POPRAWIONA OBSŁUGA PLIKÓW (FIX 0 BYTES) ---
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        // Zamiast loadDataRepresentation, używamy loadItem z fileURL, żeby dostać ścieżkę do pliku na dysku.
        // To naprawia problem "nieznanego pliku" i "0 bajtów".
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                // URL może być bezpośrednio URL-em lub Data
                var fileURL: URL? = nil
                
                if let url = item as? URL {
                    fileURL = url
                } else if let data = item as? Data {
                    fileURL = URL(dataRepresentation: data, relativeTo: nil)
                }
                
                if let url = fileURL {
                    // Mamy prawdziwą ścieżkę do pliku!
                    do {
                        // Wczytujemy dane bezpośrednio z dysku
                        let data = try Data(contentsOf: url)
                        let fileName = url.lastPathComponent
                        
                        DispatchQueue.main.async {
                            self.pendingFileData = data
                            self.pendingFileName = fileName
                        }
                    } catch {
                        print("Błąd odczytu pliku: \(error)")
                    }
                }
            }
            return true
        }
        return false
    }
    
    var filteredContacts: [Contact] {
        if searchText.isEmpty { return chatManager.contacts }
        else { return chatManager.contacts.filter { $0.name.localizedCaseInsensitiveContains(searchText) } }
    }
    
    // --- WIDOKI ---
    
    var headerView: some View {
        HStack {
            if chatManager.currentContact != nil {
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        chatManager.currentContact = nil; searchText = ""; pendingFileData = nil; pendingFileName = nil
                    }
                }) { Image(systemName: "chevron.left").bold() }.buttonStyle(.plain).foregroundStyle(.secondary)
                VStack(alignment: .leading) { Text(chatManager.currentContact?.name ?? "Czat").font(.headline) }
            } else { Text("Wiadomości").font(.title3).fontWeight(.bold) }
            Spacer()
            Menu {
                Text("ID: ...\(chatManager.myID.uuidString.suffix(4))").font(.caption)
                Button("Skopiuj moje ID") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(chatManager.myID.uuidString, forType: .string) }
                Divider()
                Button(role: .destructive) { NSApplication.shared.terminate(nil) } label: { Text("Zakończ aplikację") }
            } label: { Image(systemName: "person.crop.circle").font(.system(size: 22)).foregroundStyle(.secondary) }.menuStyle(.borderlessButton).fixedSize()
        }
    }
    
    var contactListView: some View {
        VStack(spacing: 0) {
            if !chatManager.contacts.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Szukaj kontaktu...", text: $searchText).textFieldStyle(.plain)
                    if !searchText.isEmpty { Button(action: { searchText = "" }) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain) }
                }.padding(10).background(Color.white.opacity(0.1)).cornerRadius(8).padding(.horizontal).padding(.top, 10)
            }
            ScrollView {
                VStack(spacing: 10) {
                    if filteredContacts.isEmpty && !searchText.isEmpty { Text("Nie znaleziono \"\(searchText)\"").foregroundStyle(.secondary).padding(.top, 20) }
                    else if chatManager.contacts.isEmpty {
                        VStack(spacing: 15) { Image(systemName: "paperplane").font(.system(size: 40)).foregroundStyle(.gray.opacity(0.3)); Text("Nikogo tu jeszcze nie ma").foregroundStyle(.secondary) }.padding(.top, 50)
                    } else {
                        ForEach(filteredContacts) { contact in
                            HStack {
                                Circle().fill(Color.accentColor.opacity(0.1)).frame(width: 40, height: 40)
                                    .overlay(Text(String(contact.name.prefix(1))).bold().foregroundStyle(Color.accentColor))
                                VStack(alignment: .leading) { Text(contact.name).font(.system(.body, design: .rounded)).bold() }
                                Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(10).background(Color.white.opacity(0.05)).cornerRadius(12).contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3)) { chatManager.currentContact = contact; searchText = "" }
                                Task { await chatManager.fetchMessages() }
                            }
                            .contextMenu { Button("Usuń", role: .destructive) { if let idx = chatManager.contacts.firstIndex(where: { $0.id == contact.id }) { chatManager.removeContact(at: IndexSet(integer: idx)) } } }
                        }
                    }
                    VStack(spacing: 12) {
                        if isAddingContact {
                            TextField("Nazwa", text: $newContactName).textFieldStyle(.roundedBorder)
                            TextField("Token ID", text: $newContactToken).textFieldStyle(.roundedBorder)
                            HStack {
                                Button("Anuluj") { withAnimation { isAddingContact = false } }.buttonStyle(.plain).foregroundStyle(.red)
                                Spacer(); Button("Zapisz") { if !newContactName.isEmpty && !newContactToken.isEmpty { chatManager.addContact(name: newContactName, tokenString: newContactToken); newContactName=""; newContactToken=""; withAnimation { isAddingContact = false } } }.buttonStyle(.borderedProminent)
                            }
                        } else {
                            Button(action: { withAnimation { isAddingContact = true } }) { Label("Dodaj nowy kontakt", systemImage: "plus").frame(maxWidth: .infinity).padding(8).background(Color.gray.opacity(0.1)).cornerRadius(8) }.buttonStyle(.plain)
                        }
                    }.padding().background(Color.white.opacity(0.05)).cornerRadius(12).padding(.top, 10)
                }.padding()
            }
        }
    }
    
    func chatView(contact: Contact) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    if chatManager.isLoading && chatManager.messages.isEmpty {
                        VStack(spacing: 15) { Spacer().frame(height: 100); ProgressView().controlSize(.large); Text("Wczytywanie historii...").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity)
                    } else {
                        LazyVStack(spacing: 0) {
                            Color.clear.frame(height: 10)
                            ForEach(Array(chatManager.messages.enumerated()), id: \.element.id) { index, msg in
                                let showDateHeader: Bool = {
                                    if index == 0 { return true }
                                    guard let c = msg.created_at, let p = chatManager.messages[index-1].created_at else { return false }
                                    return !Calendar.current.isDate(c, inSameDayAs: p)
                                }()
                                if showDateHeader, let d = msg.created_at { DateHeader(date: d) }
                                
                                let isPrevSame: Bool = { if index == 0 || showDateHeader { return false }; return chatManager.messages[index-1].sender_id == msg.sender_id }()
                                let isNextSame: Bool = { if index >= chatManager.messages.count-1 { return false }; guard let c=msg.created_at, let n=chatManager.messages[index+1].created_at else{return false}; if !Calendar.current.isDate(c, inSameDayAs: n){return false}; return chatManager.messages[index+1].sender_id == msg.sender_id }()
                                
                                MessageBubble(
                                    message: msg, isMe: msg.sender_id == chatManager.myID, isPreviousFromSameSender: isPrevSame, isNextFromSameSender: isNextSame, chatManager: chatManager,
                                    onExpand: { if msg.id == chatManager.messages.last?.id { DispatchQueue.main.asyncAfter(deadline: .now()+0.1) { withAnimation { proxy.scrollTo(msg.id, anchor: .bottom) } } } },
                                    onEdit: { messageToEdit=msg; editContent=msg.content; showEditAlert=true },
                                    onDelete: { if let id=msg.id { Task{await chatManager.deleteMessage(messageID: id)} } }
                                ).id(msg.id)
                            }
                            Color.clear.frame(height: 20)
                        }.padding(.horizontal)
                    }
                }
                .onChange(of: chatManager.messages) { if let last = chatManager.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } } }
                .onAppear { if let last = chatManager.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }; isInputFocused = true }
            }
            if chatManager.typingUserID == contact.id { HStack { TypingIndicatorView(); Text("\(contact.name) pisze...").font(.caption).foregroundStyle(.secondary); Spacer() }.padding(.horizontal, 20).padding(.bottom, 4).transition(.opacity) }
            
            // BRUDNOPIS
            if let fileName = pendingFileName {
                HStack {
                    Image(systemName: "doc.fill").foregroundStyle(.blue).font(.title2)
                    VStack(alignment: .leading, spacing: 2) { Text("Plik gotowy do wysłania").font(.caption2).foregroundStyle(.secondary); Text(fileName).font(.subheadline).fontWeight(.medium).lineLimit(1) }
                    Spacer()
                    Button(action: { withAnimation { pendingFileData = nil; pendingFileName = nil } }) { Image(systemName: "xmark.circle.fill").foregroundStyle(.gray).font(.title3) }.buttonStyle(.plain)
                }.padding(10).background(Color.blue.opacity(0.1)).cornerRadius(10).padding(.horizontal).padding(.bottom, 4).transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // INPUT
            HStack(spacing: 10) {
                TextField("Napisz wiadomość...", text: $messageInput).textFieldStyle(.plain).focused($isInputFocused).foregroundStyle(.white).padding(10).background(Color.white.opacity(0.1)).clipShape(Capsule()).overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
                    .onSubmit(sendMessage)
                    .onChange(of: messageInput) { if !messageInput.isEmpty { chatManager.sendTypingSignal() } }
                Button(action: sendMessage) {
                    if isSendingFile { ProgressView().controlSize(.small).frame(width: 30, height: 30) }
                    else { Image(systemName: pendingFileData != nil ? "arrow.up.doc.fill" : "arrow.up.circle.fill").resizable().frame(width: 30, height: 30).foregroundStyle((messageInput.isEmpty && pendingFileData == nil) ? Color.white.opacity(0.2) : Color.blue).background(Color.white.opacity(0.1)).clipShape(Circle()) }
                }.buttonStyle(.plain).disabled((messageInput.isEmpty && pendingFileData == nil) || isSendingFile)
            }.padding(12).background(.ultraThinMaterial)
        }
    }
    
    func sendMessage() {
        if let data = pendingFileData, let name = pendingFileName {
            isSendingFile = true
            Task {
                await chatManager.sendFile(data: data, fileName: name)
                await MainActor.run { pendingFileData = nil; pendingFileName = nil; isSendingFile = false }
            }
            return
        }
        guard !messageInput.isEmpty else { return }
        let text = messageInput; messageInput = ""
        Task { await chatManager.sendMessage(text) }
    }
}

// --- MESSAGE BUBBLE (POPRAWIONY STATUS) ---

struct MessageBubble: View {
    let message: Message
    let isMe: Bool
    var isPreviousFromSameSender: Bool = false
    var isNextFromSameSender: Bool = false
    var chatManager: ChatManager
    
    var onExpand: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    
    @State private var showDetails = false
    @State private var isDownloading = false
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMe { Spacer() }
            
            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                if message.is_deleted == true {
                    Text("🚫 Wiadomość usunięta")
                        .font(.system(size: 13, weight: .light).italic())
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .foregroundStyle(.white.opacity(0.6)).background(Color.gray.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Group {
                        if message.type == "file", let fileName = message.file_name {
                            // WIDOK PLIKU
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(Color.white.opacity(0.2)).frame(width: 40, height: 40)
                                        Image(systemName: "doc.fill").foregroundStyle(.white)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(fileName).font(.system(size: 14, weight: .medium)).lineLimit(1)
                                        if let size = message.file_size { Text(formatBytes(size)).font(.caption2).foregroundStyle(.white.opacity(0.7)) }
                                    }
                                }
                                
                                // LOGIKA AKCEPTACJI
                                let status = message.file_status ?? "accepted" // Fallback dla starych
                                
                                if status == "pending" {
                                    if isMe {
                                        Text("Oczekuje na akceptację...").font(.caption2).italic().foregroundStyle(.white.opacity(0.6))
                                    } else {
                                        // Odbiorca ma przyciski
                                        HStack {
                                            Button("Odrzuć") {
                                                if let id = message.id { Task { await chatManager.respondToFile(messageID: id, accept: false) } }
                                            }
                                            .buttonStyle(.bordered).tint(.red).controlSize(.small)
                                            
                                            Button("Akceptuj") {
                                                if let id = message.id { Task { await chatManager.respondToFile(messageID: id, accept: true) } }
                                            }
                                            .buttonStyle(.borderedProminent).tint(.green).controlSize(.small)
                                        }
                                    }
                                } else if status == "rejected" {
                                    Text("Transfer odrzucony").font(.caption).foregroundStyle(.red.opacity(0.8))
                                } else {
                                    // ACCEPTED -> Pokaż przycisk pobierania
                                    Button(action: { downloadAndOpenFile() }) {
                                        HStack {
                                            if isDownloading { ProgressView().controlSize(.small) }
                                            else { Image(systemName: "arrow.down.circle.fill") }
                                            Text("Otwórz plik").font(.caption).fontWeight(.medium)
                                        }
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(Color.black.opacity(0.2)).cornerRadius(8)
                                    }.buttonStyle(.plain)
                                }
                            }
                            .padding(10)
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(message.content)
                                if message.edited_at != nil { Text("(edytowano)").font(.caption2).foregroundStyle(.white.opacity(0.6)).padding(.top, 2) }
                            }.padding(.horizontal, 12).padding(.vertical, 8)
                        }
                    }
                    .foregroundStyle(.white)
                    .background(isMe ? Color.blue : Color.white.opacity(0.15))
                    .brightness(showDetails ? -0.15 : 0)
                    .clipShape(.rect(
                        topLeadingRadius: (!isMe && isPreviousFromSameSender) ? 4 : 16,
                        bottomLeadingRadius: (!isMe && isNextFromSameSender) ? 4 : (isMe ? 16 : 4),
                        bottomTrailingRadius: (isMe && isNextFromSameSender) ? 4 : (isMe ? 4 : 16),
                        topTrailingRadius: (isMe && isPreviousFromSameSender) ? 4 : 16
                    ))
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.spring(response: 0.3)) { showDetails.toggle() }; if showDetails { onExpand?() } }
                    .contextMenu { if isMe { if message.type != "file" { Button { onEdit?() } label: { Label("Edytuj", systemImage: "pencil") } }; Button(role: .destructive) { onDelete?() } label: { Label("Usuń", systemImage: "trash") } } }
                }
                
                if showDetails && message.is_deleted != true {
                    HStack(spacing: 4) {
                        if let d = message.created_at { Text(d.formatted(date: .omitted, time: .shortened)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5)) }
                        if isMe { Image(systemName: message.is_read == true ? "checkmark.circle.fill" : "checkmark.circle").font(.system(size: 10)).foregroundStyle(.white.opacity(message.is_read == true ? 0.8 : 0.4)) }
                    }
                    .padding(.horizontal, 4).transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            if !isMe { Spacer() }
        }.padding(.bottom, isNextFromSameSender ? 2 : 10)
    }
    
    func downloadAndOpenFile() {
        guard let path = message.file_path, let name = message.file_name else { return }
        isDownloading = true
        Task {
            if let data = await chatManager.downloadFile(path: path) {
                await MainActor.run {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                    do { try data.write(to: tempURL); NSWorkspace.shared.open(tempURL) } catch { print("Błąd zapisu: \(error)") }
                    isDownloading = false
                }
            } else { await MainActor.run { isDownloading = false } }
        }
    }
    
    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter(); formatter.allowedUnits = [.useKB, .useMB]; formatter.countStyle = .file; return formatter.string(fromByteCount: bytes)
    }
}

// Helpers DateHeader i TypingIndicator bez zmian...
struct DateHeader: View { let date: Date; var body: some View { Text(formatDate(date)).font(.caption2).fontWeight(.medium).foregroundStyle(.white.opacity(0.6)).padding(.vertical, 4).padding(.horizontal, 12).background(Color.black.opacity(0.2)).clipShape(Capsule()).padding(.vertical, 4) }; private func formatDate(_ d: Date) -> String { let cal = Calendar.current; if cal.isDateInToday(d) { return "Dzisiaj" } else if cal.isDateInYesterday(d) { return "Wczoraj" } else { let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; f.locale = Locale(identifier: "pl_PL"); return f.string(from: d) } } }
struct TypingIndicatorView: View { @State private var dots = 3; @State private var anim = false; var body: some View { HStack(spacing: 4) { ForEach(0..<dots, id: \.self) { i in Circle().frame(width: 6, height: 6).foregroundStyle(.secondary).opacity(anim ? 0.3 : 1).scaleEffect(anim ? 0.8 : 1).animation(.easeInOut(duration: 0.6).repeatForever().delay(0.2 * Double(i)), value: anim) } }.onAppear { anim = true } } }
