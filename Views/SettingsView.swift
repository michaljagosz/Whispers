import SwiftUI

struct SettingsView: View {
    var chatManager: ChatManager // 🆕 Odbieramy managera
    
    @State private var launchManager = LaunchManager()
    @AppStorage("globalShortcut") private var selectedShortcut: String = "ctrl_opt_w"
    
    // Lokalne stany dla edycji profilu
    @State private var editedName: String = ""
    @State private var isSaving: Bool = false
    
    var body: some View {
        TabView {
            Form {
                // --- SEKCJA 1: PROFIL ---
                Section {
                    HStack {
                        TextField("Twoja nazwa", text: $editedName)
                            .textFieldStyle(.roundedBorder)
                        
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Zapisz") {
                                saveName()
                            }
                            // Przycisk aktywny tylko gdy nazwa nie jest pusta i jest inna niż obecna
                            .disabled(editedName.isEmpty || editedName == chatManager.myUsername)
                        }
                    }
                    Text("Ta nazwa będzie widoczna dla Twoich kontaktów.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                } header: {
                    Text("Profil")
                }
                
                // --- SEKCJA 2: SYSTEM ---
                Section {
                    Toggle("Uruchamiaj przy starcie systemu", isOn: $launchManager.isLaunchAtLoginEnabled)
                        .toggleStyle(.switch)
                } header: {
                    Text("System")
                }
                
                // --- SEKCJA 3: KLAWIATURA ---
                Section {
                    Picker("Skrót wywołania:", selection: $selectedShortcut) {
                        Text("⌃ + ⌥ + W").tag("ctrl_opt_w")
                        Text("⌃ + ⌥ + S").tag("ctrl_opt_s")
                        Text("⌘ + ⌃ + .").tag("cmd_ctrl_dot")
                    }
                    
                    Text("Zmiana skrótu wymaga restartu aplikacji.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Klawiatura")
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Ogólne", systemImage: "gear")
            }
            .padding()
        }
        .frame(width: 450, height: 350) // Nieco większe okno, żeby wszystko się zmieściło
        .onAppear {
            // Wczytaj obecną nazwę z managera przy otwarciu okna
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
