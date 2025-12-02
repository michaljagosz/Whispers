import SwiftUI

struct SettingsView: View {
    var chatManager: ChatManager
    
    @State private var launchManager = LaunchManager()
    @AppStorage("globalShortcut") private var selectedShortcut: String = "ctrl_opt_w"
    
    // Lokalne stany dla edycji profilu
    @State private var editedName: String = ""
    @State private var isSaving: Bool = false
    @State private var showCopyAlert = false
    @State private var keyToImport: String = ""
    @State private var showImportAlert = false
    
    var body: some View {
        TabView {
            Form {
                // --- SEKCJA 1: PROFIL ---
                Section {
                    HStack {
                        TextField(Strings.yourName, text: $editedName)
                            .textFieldStyle(.roundedBorder)
                        
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Button(Strings.save) {
                                saveName()
                            }
                            // Przycisk aktywny tylko gdy nazwa nie jest pusta i jest inna niż obecna
                            .disabled(editedName.isEmpty || editedName == chatManager.myUsername)
                        }
                    }
                    Text(Strings.nameHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                } header: {
                    Text(Strings.profileSection)
                }
                
                // --- SEKCJA 2: SYSTEM ---
                Section {
                    Toggle(Strings.launchAtLogin, isOn: $launchManager.isLaunchAtLoginEnabled)
                        .toggleStyle(.switch)
                } header: {
                    Text(Strings.systemSection)
                }
                
                // --- SEKCJA 3: KLAWIATURA ---
                Section {
                    Picker(Strings.shortcutLabel, selection: $selectedShortcut) {
                        Text("⌃ + ⌥ + W").tag("ctrl_opt_w")
                        Text("⌃ + ⌥ + S").tag("ctrl_opt_s")
                        Text("⌘ + ⌃ + .").tag("cmd_ctrl_dot")
                    }
                    
                    Text(Strings.shortcutHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(Strings.keyboardSection)
                }
                
                // --- SEKCJA 4: BEZPIECZEŃSTWO ---
                Section {
                    Button(Strings.exportKeyBtn) {
                        if let key = CryptoManager.shared.exportPrivateKeyBase64() {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(key, forType: .string)
                            showCopyAlert = true
                        }
                    }
                    .foregroundStyle(.red) // Ostrzegawczy kolor
                    .alert(Strings.keyCopiedTitle, isPresented: $showCopyAlert) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        Text(Strings.keyCopiedMsg)
                    }
                    
//                    Text(Strings.keyWarning)
//                        .font(.caption)
//                        .foregroundStyle(.secondary)
                    
//                    Divider()
                                        
                    // 2. IMPORT (Nowość)
                    VStack(alignment: .leading) {
                        Text(Strings.importKeyTitle)
                            .font(.caption).fontWeight(.bold)
                        
                        HStack {
                            TextField(Strings.pasteKeyPlaceholder, text: $keyToImport)
                                .textFieldStyle(.roundedBorder)
                            
                            Button(Strings.loadBtn) {
                                if CryptoManager.shared.importPrivateKey(base64: keyToImport) {
                                    showImportAlert = true
                                    keyToImport = "" // Czyścimy pole dla bezpieczeństwa
                                    
                                    // Ważne: Po imporcie warto opublikować "nowy-stary" klucz publiczny ponownie,
                                    // żeby upewnić się, że serwer ma aktualne dane.
                                    Task {
                                        await chatManager.initializeSession()
                                    }
                                }
                            }
                            .disabled(keyToImport.isEmpty)
                        }
                    }
                    .padding(.vertical, 4)
                    .alert(Strings.importSuccessTitle, isPresented: $showImportAlert) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        Text(Strings.importSuccessMsg)
                    }

                    Text(Strings.keyWarning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(Strings.securitySection)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label(Strings.settingsGeneral, systemImage: "gear")
            }
            .padding()
        }
        .frame(width: 450, height: 400) // Zwiększono wysokość, żeby zmieściła się sekcja bezpieczeństwa
        .onAppear {
            editedName = chatManager.myUsername
        }
    }
    
    func saveName() {
        isSaving = true
        Task {
            await chatManager.updateMyName(to: editedName)
            await MainActor.run {
                isSaving = false
            }
        }
    }
}
