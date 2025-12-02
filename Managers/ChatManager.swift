import Foundation
import Supabase
import SwiftUI
import UserNotifications
import Network

// Modele zostały przeniesione do Models/Models.swift - tutaj zostaje tylko klasa managera

@Observable
class ChatManager {
    // ✅ TERAZ JEST BEZPIECZNIE:
    private let client = SupabaseClient(
        supabaseURL: Config.supabaseURL,
        supabaseKey: Config.supabaseKey,
        options: SupabaseClientOptions(
            auth: .init(storage: FileStorage(), flowType: .pkce, emitLocalSessionAsInitialSession: true)
        )
    )
    
    var myID: UUID = UUID()
    var messages: [Message] = []
    var contacts: [Contact] = []
    var currentContact: Contact?
    var myStatus: UserStatus = .online
    var friendStatuses: [UUID: UserStatus] = [:]
    
    var unreadCounts: [UUID: Int] = [:]
    
    var typingUserID: UUID? = nil
    private var typingTimeoutTimer: Timer?
    var isConnected: Bool = true
    private let monitor = NWPathMonitor()
    private var channel: RealtimeChannelV2?
    
    private var listenerTask: Task<Void, Never>?
    
    var errorMessage: String = ""
    var showError: Bool = false
    
    var isLoading: Bool = false
    private var lastTypingSentAt: Date = .distantPast
    private let typingDebounceInterval: TimeInterval = 1.0
    
    init() {
        startNetworkMonitoring()
        loadContacts()
        Task { await initializeSession() }
    }
    
    func handleError(_ error: Error, title: String) {
        print("❌ \(title): \(error)") // Zostawiamy print dla programisty
        Task {
            await MainActor.run {
                self.errorMessage = "\(title): \(error.localizedDescription)"
                self.showError = true
            }
        }
    }
    
    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let hasConnection = (path.status == .satisfied)
                if self?.isConnected != hasConnection {
                    self?.isConnected = hasConnection
                    if hasConnection {
                        Task { [weak self] in
                            await self?.fetchMessages()
                            await self?.fetchFriendStatuses()
                            await self?.fetchUnreadCounts()
                            self?.setupRealtime()
                            await self?.checkInitialAlerts()
                        }
                    }
                }
            }
        }
        let queue = DispatchQueue(label: "NetworkMonitor")
        monitor.start(queue: queue)
    }
    
    func initializeSession() async {
        do {
            let session: Session
            if let currentSession = try? await client.auth.session { session = currentSession }
            else { session = try await client.auth.signInAnonymously() }
            let authID = session.user.id
            await MainActor.run { self.myID = authID }
            await ensureProfileExists(id: authID)
            await fetchFriendStatuses()
            await fetchUnreadCounts()
            setupRealtime()
            await checkInitialAlerts()
        } catch { handleError(error, title: "Błąd autoryzacji") }
    }
    
    func checkInitialAlerts() async {
        do {
            let unreadCount = try await client.database.from("messages")
                .select("id", count: .exact)
                .eq("receiver_id", value: myID)
                .eq("is_read", value: false)
                .execute().count ?? 0
            
            let pendingFilesCount = try await client.database.from("messages")
                .select("id", count: .exact)
                .eq("receiver_id", value: myID)
                .eq("type", value: "file")
                .eq("file_status", value: "pending")
                .execute().count ?? 0
            
            await MainActor.run {
                if pendingFilesCount > 0 {
                    NotificationCenter.default.post(name: .incomingFile, object: nil)
                } else if unreadCount > 0 {
                    NotificationCenter.default.post(name: .unreadMessage, object: nil)
                }
            }
        } catch {
            print("Błąd sprawdzania statusu początkowego: \(error)")
        }
    }
    
    func fetchUnreadCounts() async {
        do {
            struct SenderID: Decodable { let sender_id: UUID }
            let records: [SenderID] = try await client.database.from("messages")
                .select("sender_id")
                .eq("receiver_id", value: myID)
                .eq("is_read", value: false)
                .execute()
                .value
            
            let counts = Dictionary(grouping: records, by: { $0.sender_id })
                .mapValues { $0.count }
            
            await MainActor.run {
                self.unreadCounts = counts
            }
        } catch {
            print("Błąd pobierania liczników: \(error)")
        }
    }
    
    func ensureProfileExists(id: UUID) async {
        let profile = Profile(id: id, status: "online")
        try? await client.database.from("profiles").upsert(profile).execute()
    }
    
    // --- PLIKI ---
    func sendFile(data: Data, fileName: String) async {
        guard let friendID = currentContact?.id else { return }
        let uniquePath = "\(myID)/\(UUID().uuidString)_\(fileName)"
        do {
            try await client.storage.from("files").upload(uniquePath, data: data, options: FileOptions(upsert: false))
            let msg = Message(id: nil, sender_id: myID, receiver_id: friendID, content: "Wysłano plik: \(fileName)", created_at: Date(), is_read: false, is_deleted: false, edited_at: nil, type: "file", file_path: uniquePath, file_name: fileName, file_size: Int64(data.count), file_status: "pending")
            try await client.database.from("messages").insert(msg).execute()
        } catch { handleError(error, title: "Nie udało się wysłać pliku") }
    }
    
    func downloadFile(path: String) async -> Data? {
        do {
            let data = try await client.storage.from("files").download(path: path)
            await deleteFileFromStorage(path: path)
            return data
        }
        catch { return nil }
    }
    
    private func deleteFileFromStorage(path: String) async {
        try? await client.storage.from("files").remove(paths: [path])
        print("🗑️ Plik usunięty z serwera: \(path)")
    }
    
    func respondToFile(messageID: Int, accept: Bool) async {
        let newStatus = accept ? "accepted" : "rejected"
        try? await client.database.from("messages").update(["file_status": newStatus]).eq("id", value: messageID).execute()
        
        if !accept {
            if let msg = messages.first(where: { $0.id == messageID }), let path = msg.file_path {
                await deleteFileFromStorage(path: path)
            }
        }
        
        await MainActor.run { if let index = messages.firstIndex(where: { $0.id == messageID }) { messages[index].file_status = newStatus } }
    }
    
    func changeMyStatus(to status: UserStatus) {
        self.myStatus = status
        Task { try? await client.database.from("profiles").update(["status": status.rawValue]).eq("id", value: myID).execute() }
    }
    
    func setOfflineStatus() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            try? await client.database.from("profiles")
                .update(["status": "offline"])
                .eq("id", value: myID)
                .execute()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2.0)
    }
    
    func fetchFriendStatuses() async {
        guard !contacts.isEmpty else { return }
        let ids = contacts.map { $0.id }
        do {
            let profiles: [Profile] = try await client.database.from("profiles").select().in("id", value: ids).execute().value
            await MainActor.run {
                for profile in profiles { if let s = profile.status, let st = UserStatus(rawValue: s) { self.friendStatuses[profile.id] = st } }
            }
        } catch { }
    }
    
    func setupRealtime() {
        listenerTask?.cancel()
        
        self.channel = client.channel("public:chat")
        guard let channel = channel else { return }
        let messageStream = channel.postgresChange(AnyAction.self, schema: "public", table: "messages")
        let profileStream = channel.postgresChange(UpdateAction.self, schema: "public", table: "profiles")
        let broadcastStream = channel.broadcastStream(event: "typing")
        
        listenerTask = Task {
            await channel.subscribe()
            await MainActor.run { self.isConnected = true }
            await withTaskGroup(of: Void.self) { group in
                
                // WĄTEK A: WIADOMOŚCI
                group.addTask {
                    for await change in messageStream {
                        var incomingMessage: Message? = nil
                        switch change {
                        case .insert(let action): incomingMessage = try? action.record.decode(as: Message.self)
                        case .update(let action): incomingMessage = try? action.record.decode(as: Message.self)
                        default: break
                        }
                        
                        if let message = incomingMessage {
                            if message.sender_id != self.myID && message.is_read == false {
                                await MainActor.run {
                                    self.unreadCounts[message.sender_id, default: 0] += 1
                                }
                            }
                            
                            if (message.receiver_id == self.myID || message.sender_id == self.myID) {
                                DispatchQueue.main.async {
                                    if let index = self.messages.firstIndex(where: { $0.id == message.id }) {
                                        self.messages[index] = message
                                    } else if !self.messages.contains(where: { $0.id == message.id }) {
                                        if message.sender_id == self.typingUserID { self.typingUserID = nil; self.typingTimeoutTimer?.invalidate() }
                                        
                                        if self.currentContact?.id == message.sender_id || self.currentContact?.id == message.receiver_id {
                                            self.messages.append(message)
                                            if self.currentContact?.id == message.sender_id { self.markMessagesAsRead(from: message.sender_id) }
                                        }
                                        
                                        if message.sender_id != self.myID {
                                            if message.type == "file" && message.file_status == "pending" {
                                                NotificationCenter.default.post(name: .incomingFile, object: nil)
                                            } else {
                                                NotificationCenter.default.post(name: .unreadMessage, object: nil)
                                            }
                                            NSSound(named: "Glass")?.play()
                                            
                                            let senderName = self.contacts.first(where: { $0.id == message.sender_id })?.name ?? "Ktoś"
                                            let body = (message.type == "file") ? "Przesłał plik: \(message.file_name ?? "Dokument")" : message.content
                                            self.sendSystemNotification(title: senderName, body: body)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                // WĄTEK B: STATUSY
                group.addTask {
                    for await change in profileStream {
                        if let profile = try? change.record.decode(as: Profile.self), let s = profile.status, let ns = UserStatus(rawValue: s) {
                            DispatchQueue.main.async { self.friendStatuses[profile.id] = ns }
                        }
                    }
                }
                
                // WĄTEK C: SYGNAŁY PISANIA
                group.addTask {
                    let encoder = JSONEncoder()
                    let decoder = JSONDecoder()
                    
                    struct BroadcastWrapper: Decodable {
                        let payload: TypingEvent
                    }
                    
                    for await event in broadcastStream {
                        if let data = try? encoder.encode(event) {
                            if let wrapper = try? decoder.decode(BroadcastWrapper.self, from: data) {
                                self.handleTypingEvent(senderID: wrapper.payload.sender_id)
                            }
                            else if let typingEvent = try? decoder.decode(TypingEvent.self, from: data) {
                                self.handleTypingEvent(senderID: typingEvent.sender_id)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func handleTypingEvent(senderID: UUID) {
        if senderID == myID { return }
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .typingStarted, object: nil)
            
            self.typingTimeoutTimer?.invalidate()
            self.typingTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                NotificationCenter.default.post(name: .typingEnded, object: nil)
            }
        }
        
        if currentContact?.id == senderID {
            DispatchQueue.main.async {
                self.typingUserID = senderID
            }
        }
    }
    
    func sendTypingSignal() {
        let now = Date()
        guard now.timeIntervalSince(lastTypingSentAt) >= typingDebounceInterval else { return }
        lastTypingSentAt = now
        guard let channel = channel else { return }
        Task {
            let event = TypingEvent(sender_id: myID)
            try? await channel.broadcast(event: "typing", message: event)
        }
    }
    
    func fetchMessages() async {
        guard let friendID = currentContact?.id else { return }
        await MainActor.run { self.isLoading = true }
        do {
            let response: [Message] = try await client.database.from("messages").select().or("and(sender_id.eq.\(myID),receiver_id.eq.\(friendID)),and(sender_id.eq.\(friendID),receiver_id.eq.\(myID))").order("created_at", ascending: true).execute().value
            await MainActor.run { self.messages = response; self.isLoading = false }
        } catch {
            await MainActor.run { self.isLoading = false }
            handleError(error, title: "Błąd pobierania wiadomości")
        }
    }
    
    func sendMessage(_ text: String) async {
        guard let friendID = currentContact?.id else { return }
        let msg = Message(id: nil, sender_id: myID, receiver_id: friendID, content: text, created_at: Date(), is_read: false, is_deleted: false, edited_at: nil, type: "text")
        try? await client.database.from("messages").insert(msg).execute()
    }
    
    func deleteMessage(messageID: Int) async {
        do {
            try await client.database.from("messages").update(["is_deleted": true]).eq("id", value: messageID).execute()
            await MainActor.run { if let idx = messages.firstIndex(where: { $0.id == messageID }) { messages[idx].is_deleted = true } }
        } catch {
            print("❌ Błąd usuwania wiadomości: \(error)")
        }
    }
    
    func editMessage(messageID: Int, newContent: String) async {
        let updateData: [String: String] = ["content": newContent, "edited_at": ISO8601DateFormatter().string(from: Date())]
        do {
            try await client.database.from("messages").update(updateData).eq("id", value: messageID).execute()
            await MainActor.run {
                if let idx = messages.firstIndex(where: { $0.id == messageID }) {
                    messages[idx].content = newContent; messages[idx].edited_at = Date()
                }
            }
        } catch {
            print("❌ Błąd edycji wiadomości: \(error)")
        }
    }
    
    func markMessagesAsRead(from friendID: UUID) {
        Task {
            try? await client.database.from("messages").update(["is_read": true]).eq("sender_id", value: friendID).eq("receiver_id", value: myID).eq("is_read", value: false).execute()
            await MainActor.run {
                self.unreadCounts[friendID] = 0
            }
        }
    }
    
    func addContact(name: String, tokenString: String) {
        guard let uuid = UUID(uuidString: tokenString) else { return }
        contacts.append(Contact(id: uuid, name: name)); saveContacts(); Task { await fetchFriendStatuses() }
    }
    
    func removeContact(at offsets: IndexSet) { contacts.remove(atOffsets: offsets); saveContacts() }
    private func saveContacts() { if let encoded = try? JSONEncoder().encode(contacts) { UserDefaults.standard.set(encoded, forKey: "savedContacts") } }
    private func loadContacts() { if let data = UserDefaults.standard.data(forKey: "savedContacts"), let decoded = try? JSONDecoder().decode([Contact].self, from: data) { self.contacts = decoded } }
    
    private func sendSystemNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        //content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

struct FileStorage: AuthLocalStorage {
    func store(key: String, value: Data) throws { UserDefaults.standard.set(value, forKey: key) }
    func retrieve(key: String) throws -> Data? { UserDefaults.standard.data(forKey: key) }
    func remove(key: String) throws { UserDefaults.standard.removeObject(forKey: key) }
}
