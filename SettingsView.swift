import SwiftUI

struct SettingsView: View {
    @State private var launchManager = LaunchManager()
    @AppStorage("globalShortcut") private var selectedShortcut: String = "ctrl_opt_w"
    
    var body: some View {
        TabView { // TabView w Settings tworzy pasek narzędzi na górze (jak w Safari)
            Form {
                Section {
                    Toggle("Uruchamiaj przy starcie systemu", isOn: $launchManager.isLaunchAtLoginEnabled)
                        .toggleStyle(.switch)
                } header: {
                    Text("System")
                }
                
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
        }
        .frame(width: 400, height: 300) // Stały rozmiar okna ustawień
    }
}
