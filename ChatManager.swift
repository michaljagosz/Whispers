import Foundation
import Supabase
import SwiftUI
import UserNotifications
import Network

// --- MODELE ---

struct Message: Codable, Identifiable, Equatable {
    var id: Int?
    let sender_id: UUID
    let receiver_id: UUID
    var content: String
    let created_at: Date?
    var is_read: Bool?
    var is_deleted: Bool?
    var edited_at: Date?
}

struct Profile: Codable {
    let id: UUID
    var status: String?
}

enum UserStatus: String, CaseIterable, Codable {
    case online = "online"
    case away = "away"
    case busy = "busy"
    
    var color: Color {
        switch self {
        case .online: return .green
        case .away: return .orange
        case .busy: return .red
        }
    }
    
    var title: String {
        switch self {
        case .online: return "Dostępny"
        case .away: return "Zaraz wracam"
        case .busy: return "Zajęty"
        }
    }
}

struct Contact: Codable, Identifiable {
    var id: UUID
    var name: String
}

struct TypingEvent: Codable { let sender_id: UUID }

// --- MENEDŻER ---

@Observable
class ChatManager {
    // ⚠️⚠️⚠️ TU WPISZ SWOJE DANE Z SUPABASE ⚠️⚠️⚠️
    private let client = SupabaseClient(
        supabaseURL: URL(string: "https://sfyhkqkxlwoigpmfevop.supabase.co")!,
        supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNmeWhrcWt4bHdvaWdwbWZldm9wIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQzOTAxOTUsImV4cCI6MjA3OTk2NjE5NX0._JqoDJ4H3wXdlfOBGtDqzNrWo3tJq0Fx80aMEyToxrk",
        options: SupabaseClientOptions(
            auth: .init(storage: FileStorage(), flowType: .pkce, emitLocalSessionAsInitialSession: true)
        )
    )
    
    var myID: UUID = UUID()
    var messages: [Message] = []
    var contacts: [Contact] = []
    var currentContact: Contact?
    
    // Statusy
    var myStatus: UserStatus = .online
    var friendStatuses: [UUID: UserStatus] = [:]
    
    // Pisanie
    var typingUserID: UUID? = nil
    private var typingTimeoutTimer: Timer?
    
    // Połączenie
    var isConnected: Bool = true
    private let monitor = NWPathMonitor()
    private var channel: RealtimeChannelV2? // Poprawny typ V2
    
    // NOWE: Zmienna ładowania (To naprawi błąd w ContentView)
    var isLoading: Bool = false
    
    // Debounce
    private var lastTypingSentAt: Date = .distantPast
    private let typingDebounceInterval: TimeInterval = 1.0
    
    init() {
        startNetworkMonitoring()
        loadContacts()
        Task { await initializeSession() }
    }
    
    // --- MONITOROWANIE SIECI ---
    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let hasConnection = (path.status == .satisfied)
                if self?.isConnected != hasConnection {
                    self?.isConnected = hasConnection
                    if hasConnection {
                        print("🌐 Połączenie przywrócone")
                        Task { [weak self] in
                            await self?.fetchMessages()
                            await self?.fetchFriendStatuses()
                        }
                    } else {
                        print("🚫 Utracono połączenie")
                    }
                }
            }
        }
        let queue = DispatchQueue(label: "NetworkMonitor")
        monitor.start(queue: queue)
    }
    
    // --- AUTH ---
    func initializeSession() async {
        do {
            let session: Session
            if let currentSession = try? await client.auth.session {
                session = currentSession
            } else {
                session = try await client.auth.signInAnonymously()
            }
            
            let authID = session.user.id
            await MainActor.run { self.myID = authID }
            await ensureProfileExists(id: authID)
            await fetchFriendStatuses()
            setupRealtime()
        } catch {
            print("❌ Błąd autoryzacji: \(error)")
        }
    }
    
    func ensureProfileExists(id: UUID) async {
        let profile = Profile(id: id, status: "online")
        try? await client.database.from("profiles").upsert(profile).execute()
    }
    
    // --- STATUSY ---
    func changeMyStatus(to status: UserStatus) {
        self.myStatus = status
        Task {
            try? await client.database.from("profiles").update(["status": status.rawValue]).eq("id", value: myID).execute()
        }
    }
    
    func fetchFriendStatuses() async {
        guard !contacts.isEmpty else { return }
        let ids = contacts.map { $0.id }
        do {
            let profiles: [Profile] = try await client.database.from("profiles").select().in("id", value: ids).execute().value
            await MainActor.run {
                for profile in profiles {
                    if let statusString = profile.status, let status = UserStatus(rawValue: statusString) {
                        self.friendStatuses[profile.id] = status
                    }
                }
            }
        } catch { print("Błąd pobierania statusów: \(error)") }
    }
    
    // --- REALTIME ---
    func setupRealtime() {
        self.channel = client.channel("public:chat")
        guard let channel = channel else { return }
        
        let messageStream = channel.postgresChange(AnyAction.self, schema: "public", table: "messages")
        let profileStream = channel.postgresChange(UpdateAction.self, schema: "public", table: "profiles")
        let broadcastStream = channel.broadcastStream(event: "typing")
        
        Task {
            await channel.subscribe()
            await MainActor.run { self.isConnected = true }
            
            await withTaskGroup(of: Void.self) { group in
                // A. Wiadomości
                group.addTask {
                    for await change in messageStream {
                        var incomingMessage: Message? = nil
                        switch change {
                        case .insert(let action): incomingMessage = try? action.record.decode(as: Message.self)
                        case .update(let action): incomingMessage = try? action.record.decode(as: Message.self)
                        default: break
                        }
                        
                        if let message = incomingMessage {
                            if (message.receiver_id == self.myID || message.sender_id == self.myID) {
                                DispatchQueue.main.async {
                                    if let index = self.messages.firstIndex(where: { $0.id == message.id }) {
                                        self.messages[index] = message
                                    } else if !self.messages.contains(where: { $0.id == message.id }) {
                                        if message.sender_id == self.typingUserID {
                                            self.typingUserID = nil
                                            self.typingTimeoutTimer?.invalidate()
                                        }
                                        if self.currentContact?.id == message.sender_id || self.currentContact?.id == message.receiver_id {
                                            self.messages.append(message)
                                            if self.currentContact?.id == message.sender_id {
                                                self.markMessagesAsRead(from: message.sender_id)
                                            }
                                        }
                                        if message.sender_id != self.myID {
                                            NotificationCenter.default.post(name: .unreadMessage, object: nil)
                                            NSSound(named: "Glass")?.play()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                // B. Profile
                group.addTask {
                    for await change in profileStream {
                        if let profile = try? change.record.decode(as: Profile.self),
                           let statusStr = profile.status,
                           let newStatus = UserStatus(rawValue: statusStr) {
                            DispatchQueue.main.async { self.friendStatuses[profile.id] = newStatus }
                        }
                    }
                }
                // C. Typing
                group.addTask {
                    for await event in broadcastStream {
                        if let data = try? JSONSerialization.data(withJSONObject: event),
                           let typingEvent = try? JSONDecoder().decode(TypingEvent.self, from: data) {
                            self.handleTypingEvent(senderID: typingEvent.sender_id)
                        }
                    }
                }
            }
        }
    }
    
    // --- TYPING ---
    private func handleTypingEvent(senderID: UUID) {
        if senderID == myID { return }
        if currentContact?.id == senderID {
            DispatchQueue.main.async {
                self.typingUserID = senderID
                self.typingTimeoutTimer?.invalidate()
                self.typingTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                    self.typingUserID = nil
                }
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

    // --- MESSAGES CRUD (Zaktualizowane o isLoading) ---
    
    func fetchMessages() async {
        guard let friendID = currentContact?.id else { return }
        
        // 1. START ŁADOWANIA
        await MainActor.run { self.isLoading = true }
        
        do {
            let response: [Message] = try await client.database
                .from("messages")
                .select()
                .or("and(sender_id.eq.\(myID),receiver_id.eq.\(friendID)),and(sender_id.eq.\(friendID),receiver_id.eq.\(myID))")
                .order("created_at", ascending: true)
                .execute()
                .value
            
            // 2. STOP ŁADOWANIA
            await MainActor.run {
                self.messages = response
                self.isLoading = false
            }
        } catch {
            print("Błąd pobierania: \(error)")
            await MainActor.run { self.isLoading = false }
        }
    }
    
    func sendMessage(_ text: String) async {
        guard let friendID = currentContact?.id else { return }
        let msg = Message(id: nil, sender_id: myID, receiver_id: friendID, content: text, created_at: nil, is_read: false, is_deleted: false, edited_at: nil)
        do { try await client.database.from("messages").insert(msg).execute() } catch { print("Błąd wysyłania: \(error)") }
    }
    
    func deleteMessage(messageID: Int) async {
        do {
            try await client.database.from("messages").update(["is_deleted": true]).eq("id", value: messageID).execute()
            await MainActor.run {
                if let index = messages.firstIndex(where: { $0.id == messageID }) {
                    messages[index].is_deleted = true
                }
            }
        } catch { print("Błąd usuwania: \(error)") }
    }
    
    func editMessage(messageID: Int, newContent: String) async {
        do {
            let updateData: [String: String] = [
                "content": newContent,
                "edited_at": ISO8601DateFormatter().string(from: Date())
            ]
            try await client.database.from("messages").update(updateData).eq("id", value: messageID).execute()
            await MainActor.run {
                if let index = messages.firstIndex(where: { $0.id == messageID }) {
                    messages[index].content = newContent
                    messages[index].edited_at = Date()
                }
            }
        } catch { print("Błąd edycji: \(error)") }
    }
    
    func markMessagesAsRead(from friendID: UUID) {
        Task { try? await client.database.from("messages").update(["is_read": true]).eq("sender_id", value: friendID).eq("receiver_id", value: myID).eq("is_read", value: false).execute() }
    }
    
    // --- KONTAKTY ---
    func addContact(name: String, tokenString: String) {
        guard let uuid = UUID(uuidString: tokenString) else { return }
        let newContact = Contact(id: uuid, name: name)
        contacts.append(newContact)
        saveContacts()
        Task { await fetchFriendStatuses() }
    }
    
    func removeContact(at offsets: IndexSet) { contacts.remove(atOffsets: offsets); saveContacts() }
    private func saveContacts() { if let encoded = try? JSONEncoder().encode(contacts) { UserDefaults.standard.set(encoded, forKey: "savedContacts") } }
    private func loadContacts() { if let data = UserDefaults.standard.data(forKey: "savedContacts"), let decoded = try? JSONDecoder().decode([Contact].self, from: data) { self.contacts = decoded } }
}

struct FileStorage: AuthLocalStorage {
    func store(key: String, value: Data) throws { UserDefaults.standard.set(value, forKey: key) }
    func retrieve(key: String) throws -> Data? { UserDefaults.standard.data(forKey: key) }
    func remove(key: String) throws { UserDefaults.standard.removeObject(forKey: key) }
}
