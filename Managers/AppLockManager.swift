import Foundation
import SwiftUI
import Security
import LocalAuthentication // ✅ 1. Importujemy framework

@Observable
class AppLockManager {
    static let shared = AppLockManager()
    
    var isLocked: Bool = false
    var isEnabled: Bool = false
    
    // ✅ 2. Nowa flaga: Czy biometria jest dostępna na tym Macu?
    var isBiometricAvailable: Bool = false
    
    private let keychainService = "com.whispers.applock"
    private let keychainAccount = "userPIN"
    
    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "isAppLockEnabled")
        if isEnabled { isLocked = true }
        checkBiometricAvailability() // Sprawdzamy przy starcie
    }
    // --- Zarządzanie Stanem ---
    
    func lock() {
        if isEnabled {
            withAnimation { isLocked = true }
        }
    }
    
    func unlock(with pin: String) -> Bool {
        guard let storedPin = getPINFromKeychain() else { return false }
        if pin == storedPin {
            withAnimation { isLocked = false }
            return true
        }
        return false
    }
    
    // ✅ 3. NOWA FUNKCJA: Sprawdzanie dostępności TouchID
    private func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?
        // Sprawdza czy sprzęt ma TouchID i czy jest skonfigurowane
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            self.isBiometricAvailable = true
        } else {
            self.isBiometricAvailable = false
        }
    }
        
        // ✅ 4. NOWA FUNKCJA: Wywołanie TouchID
        func unlockWithBiometrics(completion: @escaping (Bool) -> Void) {
            let context = LAContext()
            context.localizedCancelTitle = "Anuluj"
            
            var error: NSError?
            if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
                let reason = "Odblokuj Whispers, aby uzyskać dostęp do wiadomości."
                
                context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authenticationError in
                    DispatchQueue.main.async {
                        if success {
                            withAnimation { self.isLocked = false }
                            completion(true)
                        } else {
                            completion(false)
                        }
                    }
                }
            } else {
                completion(false)
            }
        }
    
    // Sprawdza, czy PIN istnieje w Keychain (niezależnie czy funkcja jest włączona)
    func hasSavedPIN() -> Bool {
        return getPINFromKeychain() != nil
    }
    
    // --- Zarządzanie Ustawieniami ---
    
    func setPIN(_ pin: String) {
        savePINToKeychain(pin)
        enableLock() // Automatycznie włącza przy ustawieniu
    }
    
    func enableLock() {
        UserDefaults.standard.set(true, forKey: "isAppLockEnabled")
        self.isEnabled = true
    }
    
    func disableLock() {
        // ZMIANA: Nie usuwamy PIN-u, tylko wyłączamy flagę
        UserDefaults.standard.set(false, forKey: "isAppLockEnabled")
        self.isEnabled = false
        self.isLocked = false
    }
    
    // --- Keychain Helpers ---
    
    private func savePINToKeychain(_ pin: String) {
        guard let data = pin.data(using: .utf8) else { return }
        deletePINFromKeychain() // Nadpisz stary
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func getPINFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    private func deletePINFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}

