import Foundation
import Supabase
import SwiftUI
import UserNotifications

// --- MODELE ---

struct Message: Codable, Identifiable, Equatable {
    var id: Int?
    let sender_id: UUID
    let receiver_id: UUID
    let content: String
    let created_at: Date?
    var is_read: Bool?
}

// Model profilu z bazy (rozszerzony o status)
struct Profile: Codable {
    let id: UUID
    var status: String? // online, away, busy
}

// Nasz lokalny enum do łatwej obsługi statusów
enum UserStatus: String, CaseIterable, Codable {
    case online = "online"
    case away = "away"
    case busy = "busy"
    
    // Pomocnicze właściwości do UI
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
    // ⚠️ WPISZ SWOJE DANE
    private let client = SupabaseClient(
        supabaseURL: URL(string: "https://TWOJ-PROJEKT.supabase.co")!,
        supabaseKey: "TWOJ-KLUCZ",
        options: SupabaseClientOptions(
            auth: .init(storage: FileStorage(), flowType: .pkce, emitLocalSessionAsInitialSession: true)
        )
    )
    
    var myID: UUID = UUID()
    var messages: [Message] = []
    var contacts: [Contact] = []
    var currentContact: Contact?
    
    // STATUSY
    var myStatus: UserStatus = .online
    var friendStatuses: [UUID: UserStatus] = [:] // Pamięć podręczna statusów znajomych
    
    var typingUserID: UUID? = nil
    private var typingTimeoutTimer: Timer?
    private var channel: RealtimeChannelV2?
    
    // Debounce dla typing
    private var lastTypingSentAt: Date = .distantPast
    private let typingDebounceInterval: TimeInterval = 1.0
    
    init() {
        loadContacts()
        Task { await initializeSession() }
    }
    
    // --- AUTH & INIT ---
    
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
            
            // Pobierz początkowe statusy znajomych
            await fetchFriendStatuses()
            
            setupRealtime()
        } catch {
            print("❌ Błąd autoryzacji: \(error)")
        }
    }
    
    func ensureProfileExists(id: UUID) async {
        // Domyślnie tworzymy profil jako 'online'
        let profile = Profile(id: id, status: "online")
        try? await client.database.from("profiles").upsert(profile).execute()
    }
    
    // --- STATUSY ---
    
    func changeMyStatus(to status: UserStatus) {
        self.myStatus = status
        Task {
            do {
                try await client.database
                    .from("profiles")
                    .update(["status": status.rawValue])
                    .eq("id", value: myID)
                    .execute()
            } catch {
                print("Błąd zmiany statusu: \(error)")
            }
        }
    }
    
    func fetchFriendStatuses() async {
        // Pobieramy statusy wszystkich profili (można by filtrować tylko do kontaktów, ale tak prościej)
        guard !contacts.isEmpty else { return }
        let ids = contacts.map { $0.id }
        
        do {
            let profiles: [Profile] = try await client.database
                .from("profiles")
                .select()
                .in("id", value: ids)
                .execute()
                .value
            
            await MainActor.run {
                for profile in profiles {
                    if let statusString = profile.status, let status = UserStatus(rawValue: statusString) {
                        self.friendStatuses[profile.id] = status
                    }
                }
            }
        } catch {
            print("Błąd pobierania statusów: \(error)")
        }
    }
    
    // --- REALTIME ---
    
    func setupRealtime() {
        self.channel = client.channel("public:chat") // Zmieniłem nazwę kanału na ogólną
        guard let channel = channel else { return }
        
        // 1. Wiadomości (Insert, Update)
        let messageStream = channel.postgresChange(AnyAction.self, schema: "public", table: "messages")
        
        // 2. Profile (Update - zmiany statusów)
        let profileStream = channel.postgresChange(UpdateAction.self, schema: "public", table: "profiles")
        
        // 3. Typing
        let broadcastStream = channel.broadcastStream(event: "typing")
        
        struct BroadcastWrapper: Decodable { let payload: TypingEvent }
        
        Task {
            await channel.subscribe()
            
            await withTaskGroup(of: Void.self) { group in
                
                // Wątek A: Wiadomości
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
                                    if !self.messages.contains(where: { $0.id == message.id }) {
                                        if message.sender_id == self.typingUserID {
                                            self.typingUserID = nil
                                            self.typingTimeoutTimer?.invalidate()
                                            NotificationCenter.default.post(name: .typingEnded, object: nil)
                                        }
                                        
                                        if self.currentContact?.id == message.sender_id || self.currentContact?.id == message.receiver_id {
                                            self.messages.append(message)
                                            if self.currentContact?.id == message.sender_id {
                                                self.markMessagesAsRead(from: message.sender_id)
                                            }
                                        }
                                        
                                        if message.sender_id != self.myID {
                                            NotificationCenter.default.post(name: .unreadMessage, object: nil)
                                            let senderName = self.contacts.first(where: { $0.id == message.sender_id })?.name ?? "Nowa wiadomość"
                                            self.sendSystemNotification(title: senderName, body: message.content)
                                        }
                                    } else if let index = self.messages.firstIndex(where: { $0.id == message.id }) {
                                        self.messages[index] = message
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Wątek B: Zmiany Statusów (Profile)
                group.addTask {
                    for await change in profileStream {
                        if let profile = try? change.record.decode(as: Profile.self),
                           let statusStr = profile.status,
                           let newStatus = UserStatus(rawValue: statusStr) {
                            
                            DispatchQueue.main.async {
                                // Aktualizujemy lokalną mapę statusów
                                self.friendStatuses[profile.id] = newStatus
                            }
                        }
                    }
                }
                
                // Wątek C: Broadcast
                group.addTask {
                    for await event in broadcastStream {
                        do {
                            let data = try JSONEncoder().encode(event)
                            let wrapper = try JSONDecoder().decode(BroadcastWrapper.self, from: data)
                            self.handleTypingEvent(senderID: wrapper.payload.sender_id)
                        } catch { }
                    }
                }
            }
        }
    }
    
    // --- POZOSTAŁE FUNKCJE (CRUD) ---
    
    private func handleTypingEvent(senderID: UUID) {
        if senderID == myID { return }
        if contacts.contains(where: { $0.id == senderID }) {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .typingStarted, object: nil)
                Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                    NotificationCenter.default.post(name: .typingEnded, object: nil)
                }
            }
        }
        if currentContact?.id == senderID {
            DispatchQueue.main.async {
                self.typingUserID = senderID
                self.typingTimeoutTimer?.invalidate()
                self.typingTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                    self.typingUserID = nil
                    NotificationCenter.default.post(name: .typingEnded, object: nil)
                }
            }
        }
    }

    func fetchMessages() async {
        guard let friendID = currentContact?.id else { return }
        do {
            let response: [Message] = try await client.database.from("messages").select().or("and(sender_id.eq.\(myID),receiver_id.eq.\(friendID)),and(sender_id.eq.\(friendID),receiver_id.eq.\(myID))").order("created_at", ascending: true).execute().value
            DispatchQueue.main.async { self.messages = response }
        } catch { print("Błąd pobierania: \(error)") }
    }
    
    func sendMessage(_ text: String) async {
        guard let friendID = currentContact?.id else { return }
        let msg = Message(id: nil, sender_id: myID, receiver_id: friendID, content: text, created_at: nil, is_read: false)
        do { try await client.database.from("messages").insert(msg).execute() } catch { print("Błąd wysyłania: \(error)") }
    }
    
    func markMessagesAsRead(from friendID: UUID) {
        Task { try? await client.database.from("messages").update(["is_read": true]).eq("sender_id", value: friendID).eq("receiver_id", value: myID).eq("is_read", value: false).execute() }
    }
    
    func addContact(name: String, tokenString: String) {
        guard let uuid = UUID(uuidString: tokenString) else { return }
        let newContact = Contact(id: uuid, name: name)
        contacts.append(newContact)
        saveContacts()
        // Po dodaniu od razu pobierz jego status
        Task { await fetchFriendStatuses() }
    }
    
    func removeContact(at offsets: IndexSet) { contacts.remove(atOffsets: offsets); saveContacts() }
    private func saveContacts() { if let encoded = try? JSONEncoder().encode(contacts) { UserDefaults.standard.set(encoded, forKey: "savedContacts") } }
    private func loadContacts() { if let data = UserDefaults.standard.data(forKey: "savedContacts"), let decoded = try? JSONDecoder().decode([Contact].self, from: data) { self.contacts = decoded } }
    
    private func sendSystemNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
    
    // --- TYPING BROADCAST ---
    func sendTypingSignal() async {
        // Debounce to once per typingDebounceInterval
        let now = Date()
        guard now.timeIntervalSince(lastTypingSentAt) >= typingDebounceInterval else { return }
        lastTypingSentAt = now
        
        guard let channel else { return }
        do {
            try await channel.broadcast(event: "typing", message: TypingEvent(sender_id: myID))
        } catch {
            // Optional: silently ignore or log
            // print("Typing broadcast failed: \(error)")
        }
    }
}
struct FileStorage: AuthLocalStorage {
    func store(key: String, value: Data) throws { UserDefaults.standard.set(value, forKey: key) }
    func retrieve(key: String) throws -> Data? { UserDefaults.standard.data(forKey: key) }
    func remove(key: String) throws { UserDefaults.standard.removeObject(forKey: key) }
}
