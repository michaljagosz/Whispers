import SwiftUI

struct SettingsView: View {
    var chatManager: ChatManager
    
    @State private var launchManager = LaunchManager()
    @AppStorage("globalShortcut") private var selectedShortcut: String = "ctrl_opt_w"
    
    @State private var editedName: String = ""
    @State private var isSaving: Bool = false
    
    @State private var showCopyAlert = false
    @State private var keyToImport: String = ""
    @State private var showImportAlert = false
    
    // --- App Lock ---
    @State private var appLockManager = AppLockManager.shared
    
    // Arkusz ustawiania nowego PINu
    @State private var showSetPinSheet = false
    @State private var newPin = ""
    
    // Arkusz weryfikacji (używany przy wyłączaniu ORAZ zmianie)
    @State private var showVerifySheet = false
    @State private var verifyPinInput = ""
    @State private var verifyError = false
    
    // Flaga, żeby wiedzieć, co robimy po udanej weryfikacji
    // false = wyłączamy blokadę, true = zmieniamy PIN
    @State private var isChangingPin = false
    
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
                            Button(Strings.save) { saveName() }
                                .disabled(editedName.isEmpty || editedName == chatManager.myUsername)
                        }
                    }
                    Text(Strings.nameHint).font(.caption).foregroundStyle(.secondary)
                } header: { Text(Strings.profileSection) }
                
                // --- SEKCJA 2: SYSTEM ---
                Section {
                    Toggle(Strings.launchAtLogin, isOn: $launchManager.isLaunchAtLoginEnabled)
                        .toggleStyle(.switch)
                } header: { Text(Strings.systemSection) }
                
                // --- SEKCJA 3: KLAWIATURA ---
                Section {
                    Picker(Strings.shortcutLabel, selection: $selectedShortcut) {
                        Text("⌃ + ⌥ + W").tag("ctrl_opt_w")
                        Text("⌃ + ⌥ + S").tag("ctrl_opt_s")
                        Text("⌘ + ⌃ + .").tag("cmd_ctrl_dot")
                    }
                    Text(Strings.shortcutHint).font(.caption).foregroundStyle(.secondary)
                } header: { Text(Strings.keyboardSection) }
                
                // --- SEKCJA 4: BEZPIECZEŃSTWO ---
                Section {
                    // EKSPORT / IMPORT
                    Button(Strings.exportKeyBtn) {
                        if let key = CryptoManager.shared.exportPrivateKeyBase64() {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(key, forType: .string)
                            showCopyAlert = true
                        }
                    }
                    .foregroundStyle(.red)
                    .alert(Strings.keyCopiedTitle, isPresented: $showCopyAlert) {
                        Button(Strings.ok, role: .cancel) { }
                    } message: { Text(Strings.keyCopiedMsg) }
                                        
                    VStack(alignment: .leading) {
                        Text(Strings.importKeyTitle).font(.caption).fontWeight(.bold)
                        HStack {
                            TextField(Strings.pasteKeyPlaceholder, text: $keyToImport).textFieldStyle(.roundedBorder)
                            Button(Strings.loadBtn) {
                                if CryptoManager.shared.importPrivateKey(base64: keyToImport) {
                                    showImportAlert = true
                                    keyToImport = ""
                                    Task { await chatManager.initializeSession() }
                                }
                            }.disabled(keyToImport.isEmpty)
                        }
                    }
                    .padding(.vertical, 4)
                    .alert(Strings.importSuccessTitle, isPresented: $showImportAlert) {
                        Button(Strings.ok, role: .cancel) { }
                    } message: { Text(Strings.importSuccessMsg) }

                    Divider().padding(.vertical, 8)
                    
                    // --- APP LOCK ---
                    Toggle("Blokada aplikacji kodem PIN", isOn: Binding(
                        get: { appLockManager.isEnabled },
                        set: { newValue in
                            if newValue {
                                // Włączanie:
                                if appLockManager.hasSavedPIN() {
                                    appLockManager.enableLock()
                                } else {
                                    // Pierwsze ustawienie - nie wymaga weryfikacji starego PINu (bo go nie ma)
                                    newPin = ""
                                    showSetPinSheet = true
                                }
                            } else {
                                // Wyłączanie: Wymaga weryfikacji
                                startVerification(forChange: false)
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    // Sheet 1: Ustawianie nowego PINu
                    .sheet(isPresented: $showSetPinSheet) {
                        pinSettingSheet
                    }
                    // Sheet 2: Weryfikacja
                    .sheet(isPresented: $showVerifySheet) {
                        pinVerificationSheet
                    }
                    
                    if appLockManager.isEnabled {
                        HStack {
                            Image(systemName: "lock.fill")
                            Text("Aplikacja chroniona kodem PIN.")
                            Spacer()
                            // ✅ ZMIANA: Teraz ten przycisk też wymaga weryfikacji
                            Button("Zmień PIN") {
                                startVerification(forChange: true)
                            }
                            .font(.caption)
                            .buttonStyle(.link)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    
                } header: { Text(Strings.securitySection) }
            }
            .formStyle(.grouped)
            .tabItem { Label(Strings.settingsGeneral, systemImage: "gear") }
            .padding()
        }
        .frame(width: 450, height: 520)
        .onAppear { editedName = chatManager.myUsername }
    }
    
    // --- UI: Arkusz ustawiania PIN ---
    var pinSettingSheet: some View {
        VStack(spacing: 20) {
            Text("Ustaw kod PIN").font(.headline)
            Text("Ten kod będzie wymagany po każdym powrocie do aplikacji.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            
            SecureField("Nowy PIN", text: $newPin)
                .textFieldStyle(.roundedBorder).frame(width: 200)
                .onSubmit { savePinAction() }
            
            HStack(spacing: 15) {
                Button(Strings.cancel) {
                    showSetPinSheet = false
                    newPin = ""
                    // Jeśli anulowano przy pierwszym włączaniu, cofamy toggle
                    if !appLockManager.hasSavedPIN() { appLockManager.disableLock() }
                }.keyboardShortcut(.cancelAction)
                
                Button(Strings.save) { savePinAction() }
                    .buttonStyle(.borderedProminent)
                    .disabled(newPin.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding().frame(width: 300, height: 220)
    }
    
    // --- UI: Arkusz weryfikacji ---
    var pinVerificationSheet: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 40))
                .foregroundStyle(verifyError ? .red : .blue)
                .symbolEffect(.bounce, value: verifyError)
            
            Text("Wymagana autoryzacja")
                .font(.headline)
            
            Text(isChangingPin ? "Podaj obecny PIN, aby ustawić nowy." : "Podaj obecny PIN, aby wyłączyć blokadę.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            SecureField("Twój PIN", text: $verifyPinInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit { verifyAndProceed() }
            
            HStack(spacing: 15) {
                Button(Strings.cancel) {
                    showVerifySheet = false
                    verifyPinInput = ""
                    isChangingPin = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Dalej") {
                    verifyAndProceed()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 300, height: 250)
    }
    
    // --- LOGIKA ---
    
    func startVerification(forChange: Bool) {
        isChangingPin = forChange
        verifyPinInput = ""
        verifyError = false
        showVerifySheet = true
    }
    
    func verifyAndProceed() {
        if appLockManager.unlock(with: verifyPinInput) {
            // Weryfikacja udana
            showVerifySheet = false
            verifyPinInput = ""
            
            if isChangingPin {
                // Scenariusz: Zmiana PIN-u
                // Małe opóźnienie, aby jeden arkusz zniknął zanim pojawi się drugi
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    newPin = ""
                    showSetPinSheet = true
                    // Resetujemy flagę po otwarciu okna
                    isChangingPin = false
                }
            } else {
                // Scenariusz: Wyłączenie blokady
                appLockManager.disableLock()
            }
        } else {
            // Błąd
            verifyError = true
            verifyPinInput = ""
        }
    }
    
    func savePinAction() {
        if !newPin.isEmpty {
            appLockManager.setPIN(newPin)
            showSetPinSheet = false
            newPin = ""
        }
    }
    
    func saveName() {
        isSaving = true
        Task {
            await chatManager.updateMyName(to: editedName)
            await MainActor.run { isSaving = false }
        }
    }
}
