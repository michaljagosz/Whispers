import Foundation
import CryptoKit
import Security

class CryptoManager {
    static let shared = CryptoManager()
    
    private var myPrivateKey: Curve25519.KeyAgreement.PrivateKey?
    private let keychainTag = "com.whispers.keys.private"
    
    init() {
        loadPrivateKey()
    }
    
    // 1. Zwraca mój klucz publiczny (do wysłania do Supabase)
    var myPublicKeyBase64: String? {
        guard let key = myPrivateKey else { return nil }
        return key.publicKey.rawRepresentation.base64EncodedString()
    }
    
    // 2. Szyfrowanie wiadomości dla konkretnego odbiorcy
    func encrypt(text: String, receiverPublicKeyBase64: String) -> String? {
        guard let myPrivateKey = myPrivateKey,
              let receiverKeyData = Data(base64Encoded: receiverPublicKeyBase64),
              let receiverPublicKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: receiverKeyData) else {
            return nil
        }
        
        // Magia: Tworzymy wspólny sekret (Shared Secret)
        let sharedSecret = try? myPrivateKey.sharedSecretFromKeyAgreement(with: receiverPublicKey)
        let symmetricKey = sharedSecret?.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data(),
            outputByteCount: 32
        )
        
        guard let key = symmetricKey, let data = text.data(using: .utf8) else { return nil }
        
        // Szyfrujemy AES-GCM
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            return sealedBox.combined?.base64EncodedString()
        } catch {
            print("❌ Błąd szyfrowania: \(error)")
            return nil
        }
    }
    
    // 3. Odszyfrowywanie wiadomości od nadawcy
    func decrypt(base64Cipher: String, senderPublicKeyBase64: String) -> String? {
        guard let myPrivateKey = myPrivateKey,
              let senderKeyData = Data(base64Encoded: senderPublicKeyBase64),
              let senderPublicKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: senderKeyData),
              let sealedData = Data(base64Encoded: base64Cipher) else {
            return nil
        }
        
        let sharedSecret = try? myPrivateKey.sharedSecretFromKeyAgreement(with: senderPublicKey)
        let symmetricKey = sharedSecret?.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data(),
            outputByteCount: 32
        )
        
        guard let key = symmetricKey else { return nil }
        
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: sealedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            return String(data: decryptedData, encoding: .utf8)
        } catch {
            // Jeśli błąd -> zwracamy nil (może to stara, nieszyfrowana wiadomość?)
            return nil
        }
    }
    
    // --- Zarządzanie Kluczami (Keychain) ---
    
    private func loadPrivateKey() {
        if let data = readKeyFromKeychain() {
            try? myPrivateKey = Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        } else {
            // Generuj nowy, jeśli nie istnieje
            let newKey = Curve25519.KeyAgreement.PrivateKey()
            myPrivateKey = newKey
            saveKeyToKeychain(key: newKey)
        }
    }
    
    private func saveKeyToKeychain(key: Curve25519.KeyAgreement.PrivateKey) {
        let data = key.rawRepresentation
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainTag,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary) // Usuń stary, jeśli jest
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func readKeyFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainTag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        return status == errSecSuccess ? (dataTypeRef as? Data) : nil
    }
}
