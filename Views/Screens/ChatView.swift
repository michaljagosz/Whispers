import SwiftUI

// Pomocniczy klucz do wykrywania pozycji scrolla
struct ViewOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
    }
}

struct ChatView: View {
    var contact: Contact
    var chatManager: ChatManager
    
    @Binding var messageInput: String
    @Binding var isSendingFile: Bool
    @Binding var pendingFileData: Data?
    @Binding var pendingFileName: String?
    
    @State private var previousMessageCount = 0
    @FocusState private var isInputFocused: Bool
    @State private var messageToEdit: Message?
    @State private var editContent = ""
    @State private var showEditAlert = false
    
    // ✅ NOWE STANY DLP
    @State private var showDLPAlert = false
    @State private var dlpWarningMessage = ""
    
    var body: some View {
        VStack(spacing: 0) {
            messagesList
            
            if chatManager.typingUserID == contact.id {
                HStack {
                    TypingIndicatorView()
                    Text("\(contact.name) \(Strings.typingSuffix)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.bottom, 4).transition(.opacity)
            }
            
            if let fileName = pendingFileName {
                filePreviewBar(fileName: fileName)
            }
            
            inputBar
        }
        // Alert edycji (bez zmian)
        .alert(Strings.editMsgTitle, isPresented: $showEditAlert) {
            TextField(Strings.msgContent, text: $editContent)
            Button(Strings.save) {
                if let msg = messageToEdit, let id = msg.id {
                    Task { await chatManager.editMessage(messageID: id, newContent: editContent) }
                }
            }
            Button(Strings.cancel, role: .cancel) { }
        }
        // ✅ NOWY ALERT: DLP
        .alert("Wykryto dane wrażliwe", isPresented: $showDLPAlert) {
            Button("Wyślij mimo to", role: .destructive) {
                performSend() // Wymuszenie wysłania
            }
            Button("Anuluj", role: .cancel) { }
        } message: {
            Text(dlpWarningMessage)
        }
    }
    
    var messagesList: some View {
        // ... (Cała sekcja messagesList BEZ ZMIAN - skopiuj z poprzedniej wersji)
        ScrollViewReader { proxy in
            ScrollView {
                if chatManager.canLoadMoreMessages {
                    GeometryReader { geo in
                        Color.clear.preference(key: ViewOffsetKey.self, value: geo.frame(in: .global).minY)
                    }
                    .frame(height: 20)
                    .onPreferenceChange(ViewOffsetKey.self) { value in
                        if value > 0 { Task { await chatManager.loadOlderMessages() } }
                    }
                    if chatManager.isLoading { ProgressView().controlSize(.small).padding(5) }
                }
                
                if chatManager.isLoading && chatManager.messages.isEmpty {
                    VStack(spacing: 15) { Spacer().frame(height: 100); ProgressView().controlSize(.large); Text(Strings.loadingHistory).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity)
                } else {
                    LazyVStack(spacing: 0) {
                        Color.clear.frame(height: 10)
                        ForEach(Array(chatManager.messages.enumerated()), id: \.element.id) { index, msg in
                            let showDateHeader: Bool = {
                                if index == 0 { return true }
                                guard let current = msg.created_at,
                                      let previous = chatManager.messages[index-1].created_at else { return false }
                                return !Calendar.current.isDate(current, inSameDayAs: previous)
                            }()
                            
                            if showDateHeader, let date = msg.created_at { DateHeader(date: date) }
                            
                            let isPrevSame: Bool = {
                                if index == 0 || showDateHeader { return false }
                                return chatManager.messages[index-1].sender_id == msg.sender_id
                            }()
                            
                            let isNextSame: Bool = {
                                if index >= chatManager.messages.count - 1 { return false }
                                guard let current = msg.created_at,
                                      let next = chatManager.messages[index+1].created_at else { return false }
                                if !Calendar.current.isDate(current, inSameDayAs: next) { return false }
                                return chatManager.messages[index+1].sender_id == msg.sender_id
                            }()
                            
                            MessageBubble(
                                message: msg,
                                isMe: msg.sender_id == chatManager.myID,
                                isPreviousFromSameSender: isPrevSame,
                                isNextFromSameSender: isNextSame,
                                chatManager: chatManager,
                                onExpand: { },
                                onEdit: { messageToEdit = msg; editContent = msg.content; showEditAlert = true },
                                onDelete: { if let id = msg.id { Task { await chatManager.deleteMessage(messageID: id) } } }
                            )
                            .id(msg.id ?? 0)
                        }
                    }.padding(.horizontal)
                    Color.clear.frame(height: 15).id("bottomID")
                }
            }
            .onChange(of: chatManager.messages) {
                let count = chatManager.messages.count
                guard let last = chatManager.messages.last else { return }
                if previousMessageCount == 0 || (count - previousMessageCount) > 1 {
                     if previousMessageCount == 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { proxy.scrollTo("bottomID", anchor: .bottom) } }
                } else if count > previousMessageCount {
                    if last.sender_id == chatManager.myID { withAnimation { proxy.scrollTo("bottomID", anchor: .bottom) } }
                }
                previousMessageCount = count
            }
            .onAppear {
                previousMessageCount = chatManager.messages.count
                DispatchQueue.main.async { proxy.scrollTo("bottomID", anchor: .bottom) }
                isInputFocused = true
            }
        }
    }
    
    func filePreviewBar(fileName: String) -> some View {
        HStack {
            Image(systemName: "doc.fill").foregroundStyle(Color.accentColor).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(Strings.fileReady).font(.caption2).foregroundStyle(.secondary)
                Text(fileName).font(.subheadline).fontWeight(.medium).lineLimit(1)
            }
            Spacer()
            Button(action: { withAnimation { pendingFileData = nil; pendingFileName = nil } }) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.gray).font(.title3)
            }.buttonStyle(.plain)
        }
        .padding(10).background(Color.accentColor.opacity(0.1)).cornerRadius(10).padding(.horizontal).padding(.bottom, 4)
    }
    
    var inputBar: some View {
        HStack(spacing: 10) {
            TextField(Strings.inputPlaceholder, text: $messageInput)
                .textFieldStyle(.plain)
                .focused($isInputFocused)
                .padding(10)
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())
                .onSubmit(sendMessage)
                .onChange(of: messageInput) { if !messageInput.isEmpty { chatManager.sendTypingSignal() } }
            
            Button(action: sendMessage) {
                if isSendingFile { ProgressView().controlSize(.small).frame(width: 30, height: 30) }
                else {
                    Image(systemName: pendingFileData != nil ? "square.and.arrow.up.circle.fill" : "arrow.up.circle.fill")
                        .resizable().frame(width: 30, height: 30)
                        .foregroundStyle((messageInput.isEmpty && pendingFileData == nil) ? Color.white.opacity(0.2) : Color.accentColor)
                }
            }.buttonStyle(.plain).disabled((messageInput.isEmpty && pendingFileData == nil) || isSendingFile)
        }.padding(12).background(.ultraThinMaterial)
    }
    
    // ✅ ZMODYFIKOWANA FUNKCJA SEND
    func sendMessage() {
        // 1. Obsługa plików (mają priorytet, nie sprawdzamy DLP dla nazw plików)
        if let data = pendingFileData, let name = pendingFileName {
            isSendingFile = true
            Task {
                await chatManager.sendFile(data: data, fileName: name)
                await MainActor.run { pendingFileData = nil; pendingFileName = nil; isSendingFile = false }
            }
            return
        }
        
        guard !messageInput.isEmpty else { return }
        
        // 2. SPRAWDZENIE DLP
        if let risk = DLPHelper.shared.analyze(messageInput) {
            // Ryzyko wykryte! Pokaż alert.
            dlpWarningMessage = risk.warningMessage
            showDLPAlert = true
            return
        }
        
        // 3. Jeśli czysto -> wyślij
        performSend()
    }
    
    // Funkcja pomocnicza, wywoływana "po dobroci" lub "na siłę" (z alertu)
    func performSend() {
        let text = messageInput
        messageInput = ""
        Task { await chatManager.sendMessage(text) }
    }
}
