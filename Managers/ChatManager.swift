import Foundation
import Supabase
import SwiftUI
import UserNotifications
import Network

@Observable
class ChatManager {
    // 🔐 BEZPIECZEŃSTWO: Pobieranie kluczy z Config (Secrets.plist)
    private let client = SupabaseClient(
        supabaseURL: Config.supabaseURL,
        supabaseKey: Config.supabaseKey,
        options: SupabaseClientOptions(
            auth: .init(storage: FileStorage(), flowType: .pkce, emitLocalSessionAsInitialSession: true)
        )
    )
    
    // Zmienne stanu
    var myID: UUID = UUID()
    var messages: [Message] = []
    var contacts: [Contact] = []
    var currentContact: Contact?
    var myStatus: UserStatus = .online
    var myUsername: String = ""
    
    // Statusy i Klucze znajomych
    var friendStatuses: [UUID: UserStatus] = [:]
    var friendPublicKeys: [UUID: String] = [:] // 🔐 Klucze do szyfrowania
    
    var unreadCounts: [UUID: Int] = [:]
    
    // Pisanie
    var typingUserID: UUID? = nil
    private var typingTask: Task<Void, Never>?
    
    // Sieć
    var isConnected: Bool = true
    private let monitor = NWPathMonitor()
    private var channel: RealtimeChannelV2?
    private var listenerTask: Task<Void, Never>?
    
    // UI & Błędy
    var isLoading: Bool = false
    var errorMessage: String = ""
    var showError: Bool = false
    
    private var lastTypingSentAt: Date = .distantPast
    private let typingDebounceInterval: TimeInterval = 1.0
    
    init() {
        startNetworkMonitoring()
        loadContacts()
        Task { await initializeSession() }
    }
    
    // 📢 Obsługa błędów dla UI
    func handleError(_ error: Error, title: String) {
        print("❌ \(title): \(error)")
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
            
            // 🔐 PUBLIKACJA MOJEGO KLUCZA PUBLICZNEGO
            if let myKey = CryptoManager.shared.myPublicKeyBase64 {
                let updateData = ["public_key": myKey, "status": "online"]
                // Upsert zapewnia, że profil istnieje
                try? await client.database.from("profiles").upsert(["id": myID.uuidString]).execute()
                try? await client.database.from("profiles").update(updateData).eq("id", value: myID).execute()
                print("🔐 Klucz publiczny opublikowany.")
            } else {
                await ensureProfileExists(id: authID)
            }
            
            await fetchMyProfile()
            await fetchFriendStatuses()
            await fetchUnreadCounts()
            setupRealtime()
            await checkInitialAlerts()
        } catch {
            handleError(error, title: "Błąd autoryzacji")
        }
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
        let profile = Profile(id: id, status: "online", public_key: nil)
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
        } catch {
            handleError(error, title: "Nie udało się wysłać pliku")
        }
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
            let profiles: [Profile] = try await client.database.from("profiles")
                .select()
                .in("id", value: ids)
                .execute()
                .value
            
            await MainActor.run {
                for profile in profiles {
                    // 1. Status
                    if let s = profile.status, let st = UserStatus(rawValue: s) {
                        self.friendStatuses[profile.id] = st
                    }
                    // 2. Klucz publiczny
                    if let key = profile.public_key {
                        self.friendPublicKeys[profile.id] = key
                    }
                    
                    // 3. 🆕 SYNCHRONIZACJA NAZWY
                    // Jeśli użytkownik ma ustawioną nazwę na serwerze...
                    if let serverName = profile.username, !serverName.isEmpty {
                        // ...szukamy go w naszych lokalnych kontaktach
                        if let idx = self.contacts.firstIndex(where: { $0.id == profile.id }) {
                            // Jeśli nazwa lokalna jest STARA (inna niż serwerowa) -> aktualizujemy
                            if self.contacts[idx].name != serverName {
                                print("🔄 Aktualizacja nazwy kontaktu: \(self.contacts[idx].name) -> \(serverName)")
                                self.contacts[idx].name = serverName
                                self.saveContacts() // Zapisujemy zmianę w UserDefaults
                            }
                        }
                    }
                }
            }
        } catch {
            print("Błąd fetchFriendStatuses: \(error)")
        }
    }
    
    // 🆕 Pobieranie mojego profilu z bazy
    func fetchMyProfile() async {
        do {
            let profile: Profile = try await client.database.from("profiles")
                .select()
                .eq("id", value: myID)
                .single()
                .execute()
                .value
            
            await MainActor.run {
                self.myUsername = profile.username ?? ""
                if let s = profile.status, let st = UserStatus(rawValue: s) {
                    self.myStatus = st
                }
            }
        } catch {
            print("Błąd pobierania mojego profilu: \(error)")
        }
    }

    // 🆕 Aktualizacja nazwy w bazie
    func updateMyName(to newName: String) async {
        do {
            try await client.database.from("profiles")
                .update(["username": newName])
                .eq("id", value: myID)
                .execute()
            
            await MainActor.run {
                self.myUsername = newName
            }
            print("✅ Zaktualizowano nazwę na: \(newName)")
        } catch {
            handleError(error, title: "Nie udało się zmienić nazwy")
        }
    }
    
    // 🔐 FUNKCJA ODSZYFROWUJĄCA (CZYSTA WERSJA)
    private func processIncomingMessage(_ msg: Message) -> Message {
        var processed = msg
        // Próbujemy odszyfrować tylko wiadomości tekstowe
        if processed.type == "text" {
            let otherUserID = (processed.sender_id == myID) ? processed.receiver_id : processed.sender_id
            
            if let key = friendPublicKeys[otherUserID],
               let decrypted = CryptoManager.shared.decrypt(base64Cipher: processed.content, senderPublicKeyBase64: key) {
                processed.content = decrypted
            }
            // W przeciwnym razie zostawiamy oryginał (dla starych wiadomości plain-text)
        }
        return processed
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
                        
                        if let rawMessage = incomingMessage {
                            // 🔐 ODSZYFROWANIE W LOCIE
                            let message = self.processIncomingMessage(rawMessage)
                            
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
                                        if message.sender_id == self.typingUserID {
                                            self.typingUserID = nil
                                            self.typingTask?.cancel()
                                            NotificationCenter.default.post(name: .typingEnded, object: nil)
                                        }
                                        
                                        if self.currentContact?.id == message.sender_id || self.currentContact?.id == message.receiver_id {
                                            self.messages.append(message)
                                            if self.currentContact?.id == message.sender_id { self.markMessagesAsRead(from: message.sender_id) }
                                        }
                                        
                                        if message.sender_id != self.myID {
                                            // 🎵 DŹWIĘK POWIADOMIENIA (Lokalny)
                                            NSSound(named: "Glass")?.play()
                                            
                                            if message.type == "file" && message.file_status == "pending" {
                                                NotificationCenter.default.post(name: .incomingFile, object: nil)
                                            } else {
                                                NotificationCenter.default.post(name: .unreadMessage, object: nil)
                                            }
                                            
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
                
                // WĄTEK B: STATUSY I PROFILE
                group.addTask {
                    for await change in profileStream {
                        if let profile = try? change.record.decode(as: Profile.self) {
                            await MainActor.run {
                                // 1. Status
                                if let s = profile.status, let ns = UserStatus(rawValue: s) {
                                    self.friendStatuses[profile.id] = ns
                                }
                                // 2. Klucz
                                if let key = profile.public_key {
                                    self.friendPublicKeys[profile.id] = key
                                }
                                
                                // 3. 🆕 NAZWA NA ŻYWO
                                if let newName = profile.username, !newName.isEmpty {
                                    if let idx = self.contacts.firstIndex(where: { $0.id == profile.id }) {
                                        if self.contacts[idx].name != newName {
                                            self.contacts[idx].name = newName
                                            self.saveContacts()
                                            print("⚡️ Realtime: Zmieniono nazwę kontaktu na \(newName)")
                                        }
                                    }
                                }
                            }
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
        // Ignorujemy własne sygnały (dla pewności)
        if senderID == myID { return }
        
        // Wszystkie zmiany UI muszą być na głównym wątku
        Task { @MainActor in
            // 1. Ustawiamy, że ktoś pisze
            self.typingUserID = senderID
            NotificationCenter.default.post(name: .typingStarted, object: nil)
            
            // 2. Anulujemy poprzednie zadanie "czyszczenia" (jeśli istnieje)
            // To zapobiega sytuacji, gdzie stary timer wyłącza status, gdy ktoś wciąż pisze
            self.typingTask?.cancel()
            
            // 3. Uruchamiamy nowe zadanie z opóźnieniem (Debounce)
            self.typingTask = Task {
                try? await Task.sleep(nanoseconds: 3 * 1_000_000_000) // Czekaj 3 sekundy
                
                // Jeśli zadanie nie zostało anulowane (czyli nie przyszedł nowy sygnał), czyścimy status
                if !Task.isCancelled {
                    self.typingUserID = nil
                    NotificationCenter.default.post(name: .typingEnded, object: nil)
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
    
    func fetchMessages() async {
        guard let friendID = currentContact?.id else { return }
        await MainActor.run { self.isLoading = true }
        do {
            let response: [Message] = try await client.database.from("messages")
                .select()
                .or("and(sender_id.eq.\(myID),receiver_id.eq.\(friendID)),and(sender_id.eq.\(friendID),receiver_id.eq.\(myID))")
                .order("created_at", ascending: true)
                .execute()
                .value
            
            // 🔐 ODSZYFROWANIE HISTORII
            let decryptedMessages = response.map { self.processIncomingMessage($0) }
            
            await MainActor.run { self.messages = decryptedMessages; self.isLoading = false }
        } catch {
            await MainActor.run { self.isLoading = false }
            handleError(error, title: "Błąd pobierania wiadomości")
        }
    }
    
    func sendMessage(_ text: String) async {
        guard let friendID = currentContact?.id else { return }
        
        var contentToSend = text
        // 🔐 SZYFROWANIE
        if let friendKey = friendPublicKeys[friendID],
           let encrypted = CryptoManager.shared.encrypt(text: text, receiverPublicKeyBase64: friendKey) {
            contentToSend = encrypted
            print("🔒 Wiadomość zaszyfrowana przed wysłaniem.")
        } else {
            print("⚠️ Brak klucza znajomego - wysyłam jawnym tekstem.")
        }
        
        let msg = Message(id: nil, sender_id: myID, receiver_id: friendID, content: contentToSend, created_at: Date(), is_read: false, is_deleted: false, edited_at: nil, type: "text")
        
        do {
            try await client.database.from("messages").insert(msg).execute()
        } catch {
            handleError(error, title: "Błąd wysyłania")
        }
    }
    
    func deleteMessage(messageID: Int) async {
        do {
            try await client.database.from("messages").update(["is_deleted": true]).eq("id", value: messageID).execute()
            await MainActor.run { if let idx = messages.firstIndex(where: { $0.id == messageID }) { messages[idx].is_deleted = true } }
        } catch {
            handleError(error, title: "Błąd usuwania wiadomości")
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
            handleError(error, title: "Błąd edycji wiadomości")
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
    
    // 🆕 INTELIGENTNE DODAWANIE KONTAKTU
    func addContact(tokenString: String) async {
        // 1. Walidacja formatu UUID
        guard let uuid = UUID(uuidString: tokenString) else {
            handleError(NSError(domain: "App", code: 1, userInfo: [NSLocalizedDescriptionKey: "Nieprawidłowy format Tokena ID"]), title: "Błąd dodawania")
            return
        }
        
        // 2. Walidacja: Czy nie dodajemy siebie?
        if uuid == myID {
            handleError(NSError(domain: "App", code: 2, userInfo: [NSLocalizedDescriptionKey: "Nie możesz dodać samego siebie"]), title: "Błąd dodawania")
            return
        }
        
        // 3. Walidacja: Czy kontakt już istnieje?
        if contacts.contains(where: { $0.id == uuid }) {
            handleError(NSError(domain: "App", code: 3, userInfo: [NSLocalizedDescriptionKey: "Ten kontakt jest już na liście"]), title: "Info")
            return
        }
        
        // 4. Pobranie danych z serwera
        do {
            let profile: Profile = try await client.database.from("profiles")
                .select()
                .eq("id", value: uuid)
                .single()
                .execute()
                .value
            
            // Używamy nazwy z profilu, a jeśli jej nie ma - domyślnej "Użytkownik"
            let remoteName = profile.username ?? "Użytkownik"
            
            await MainActor.run {
                // Dodajemy kontakt z nazwą pobraną z bazy
                self.contacts.append(Contact(id: uuid, name: remoteName))
                self.saveContacts()
                
                // Od razu pobieramy jego klucz publiczny i status
                Task {
                    await self.fetchFriendStatuses()
                }
            }
            print("✅ Dodano kontakt: \(remoteName)")
            
        } catch {
            handleError(error, title: "Nie znaleziono użytkownika")
        }
    }
    
    func removeContact(at offsets: IndexSet) { contacts.remove(atOffsets: offsets); saveContacts() }
    private func saveContacts() { if let encoded = try? JSONEncoder().encode(contacts) { UserDefaults.standard.set(encoded, forKey: "savedContacts") } }
    private func loadContacts() { if let data = UserDefaults.standard.data(forKey: "savedContacts"), let decoded = try? JSONDecoder().decode([Contact].self, from: data) { self.contacts = decoded } }
    
    private func sendSystemNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // 🔇 WYCISZAMY SYSTEMOWY DŹWIĘK (używamy własnego "Glass")
        // content.sound = .default
        
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

struct FileStorage: AuthLocalStorage {
    func store(key: String, value: Data) throws { UserDefaults.standard.set(value, forKey: key) }
    func retrieve(key: String) throws -> Data? { UserDefaults.standard.data(forKey: key) }
    func remove(key: String) throws { UserDefaults.standard.removeObject(forKey: key) }
}
