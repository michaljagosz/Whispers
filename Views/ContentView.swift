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
    
    // App Lock Manager (do nakładki blokady)
    @State private var lockManager = AppLockManager.shared

    var body: some View {
        @Bindable var chatManager = chatManager
        NavigationStack {
            VStack(spacing: 0) {
                // HEADER
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
        .background(Color.clear) // Ważne dla WindowAccessor
        .background(.ultraThinMaterial)
        // ✅ 1. STEALTH MODE: Ukrywanie okna przed nagrywaniem ekranu
        .background(WindowAccessor { window in
            window?.sharingType = .none
        })
        .animation(.default, value: chatManager.isConnected)
        .animation(.easeInOut, value: isDropTargeted)
        .alert(Strings.fileTooLargeTitle, isPresented: $showFileAlert) {
            Button(Strings.ok, role: .cancel) { }
        } message: {
            Text(Strings.fileTooLargeMsg)
        }
        .alert(Strings.errorOccurred, isPresented: $chatManager.showError) {
            Button(Strings.ok, role: .cancel) { }
        } message: {
            Text(chatManager.errorMessage)
        }
        // ✅ 2. APP LOCK OVERLAY
        .overlay {
            if lockManager.isLocked {
                LockScreenView()
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            lockManager.lock()
        }
    }
    
    var offlineBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash")
            Text(Strings.offlineBar)
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
                Text(Strings.dropZone).font(.title2).bold()
            }.foregroundStyle(Color.accentColor)
        }
        .allowsHitTesting(false)
    }
    
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
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

// ✅ 3. POMOCNICZY STRUCT: Dostęp do NSWindow
struct WindowAccessor: NSViewRepresentable {
    var callback: (NSWindow?) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.callback(view.window)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}
