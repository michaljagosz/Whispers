import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    var chatManager: ChatManager
    
    // UI State
    @State private var isAddingContact = false
    @State private var searchText = ""
    @State private var messageInput = ""
    
    // Pliki (Drag & Drop)
    @State private var pendingFileData: Data?
    @State private var pendingFileName: String?
    @State private var isDropTargeted = false
    @State private var isSendingFile = false
    @State private var showFileAlert = false
    let maxFileSize: Int64 = 50 * 1024 * 1024
    
    var body: some View {
        @Bindable var chatManager = chatManager
        NavigationStack {
            VStack(spacing: 0) {
                // HEADER (z nowego pliku)
                HeaderView(
                    chatManager: chatManager,
                    searchText: $searchText,
                    pendingFileData: $pendingFileData,
                    pendingFileName: $pendingFileName
                )
                
                // CONTENT
                if let contact = chatManager.currentContact {
                    ChatView(
                        contact: contact,
                        chatManager: chatManager,
                        messageInput: $messageInput,
                        isSendingFile: $isSendingFile,
                        pendingFileData: $pendingFileData,
                        pendingFileName: $pendingFileName
                    )
                    .transition(.move(edge: .trailing))
                } else {
                    ContactListView(
                        chatManager: chatManager,
                        searchText: $searchText,
                        isAddingContact: $isAddingContact
                    )
                    .transition(.move(edge: .leading))
                }
                
                // OFFLINE BAR
                if !chatManager.isConnected {
                    offlineBar
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                return handleDrop(providers: providers)
            }
            .overlay {
                if isDropTargeted {
                    dropZoneOverlay
                }
            }
        }
        .frame(width: 340, height: 550)
        .background(Color(.windowBackgroundColor)) // Sprawdź czy masz ten kolor w Assets, jeśli nie użyj systemowego
        .background(.ultraThinMaterial)
        .animation(.default, value: chatManager.isConnected)
        .animation(.easeInOut, value: isDropTargeted)
        .alert("Plik jest za duży", isPresented: $showFileAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Maksymalny rozmiar pliku to 50 MB.")
        }
        // 🆕 NOWY ALERT BŁĘDÓW OGÓLNYCH:
        .alert("Wystąpił błąd", isPresented: $chatManager.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(chatManager.errorMessage)
        }
    }
    
    var offlineBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash")
            Text("Brak połączenia")
        }
        .font(.caption).fontWeight(.medium).foregroundStyle(.white)
        .frame(maxWidth: .infinity).padding(.vertical, 6)
        .background(Color.red.opacity(0.8))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    var dropZoneOverlay: some View {
        ZStack {
            Color.blue.opacity(0.2).ignoresSafeArea()
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10]))
                .padding(12)
            VStack {
                Image(systemName: "arrow.down.doc.fill").font(.system(size: 50))
                Text("Upuść plik tutaj").font(.title2).bold()
            }.foregroundStyle(Color.accentColor)
        }
        .allowsHitTesting(false)
    }
    
    // Funkcja handleDrop pozostaje tutaj, bo dotyczy całego okna
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                // ... (Twoja logika ładowania pliku z oryginalnego pliku)
                // Pamiętaj o ustawianiu pendingFileData i pendingFileName
                var fileURL: URL? = nil
                if let url = item as? URL {
                    fileURL = url
                } else if let data = item as? Data {
                    fileURL = URL(dataRepresentation: data, relativeTo: nil)
                }
                
                if let url = fileURL {
                    do {
                        let resources = try url.resourceValues(forKeys: [.fileSizeKey])
                        if let fileSize = resources.fileSize, Int64(fileSize) > maxFileSize {
                            DispatchQueue.main.async { self.showFileAlert = true }
                            return
                        }
                        
                        let data = try Data(contentsOf: url)
                        let fileName = url.lastPathComponent
                        DispatchQueue.main.async {
                            self.pendingFileData = data
                            self.pendingFileName = fileName
                        }
                    } catch { print("Błąd odczytu pliku: \(error)") }
                }
            }
            return true
        }
        return false
    }
}
