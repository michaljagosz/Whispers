import Foundation

enum DLPRiskType {
    case creditCard
    case privateKey
    case passwordContext
    case highEntropy
    
    var warningMessage: String {
        switch self {
        case .creditCard: return "Wykryto numer karty kredytowej."
        case .privateKey: return "Tekst wygląda jak klucz prywatny lub token."
        case .passwordContext: return "Wykryto słowo wskazujące na przesyłanie hasła."
        case .highEntropy: return "Wykryto silne hasło lub losowy ciąg znaków."
        }
    }
}

class DLPHelper {
    static let shared = DLPHelper()
    
    // ✅ ROZSZERZONA LISTA SŁÓW KLUCZOWYCH (PL, EN, DE, FR, ES, IT)
    private let sensitiveKeywords = [
        // Polski
        "hasło", "tajne", "klucz",
        // Angielski
        "password", "secret", "key", "token", "pin",
        // Niemiecki
        "passwort", "schlüssel", "geheim", "kennwort",
        // Francuski
        "passe", "clé", "secret",
        // Hiszpański
        "contraseña", "clave", "secreto",
        // Włoski
        "chiave", "segreto"
    ]
    
    func analyze(_ text: String) -> DLPRiskType? {
        let lowerText = text.lowercased()
        
        // 1. Karty Kredytowe
        let cardPattern = "\\b(?:\\d[ -]*?){13,19}\\b"
        if let regex = try? NSRegularExpression(pattern: cardPattern),
           regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
            if !text.contains("+") { return .creditCard }
        }
        
        // 2. Klucze Prywatne
        let keyPattern = "\\b[A-Za-z0-9+/]{30,}\\={0,2}\\b"
        if let regex = try? NSRegularExpression(pattern: keyPattern),
           regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
            if !lowerText.contains("http") && !lowerText.contains("www") { return .privateKey }
        }
        
        // 3. DETEKCJA HASEŁ (HYBRYDOWA + UNICODE)
        // Działa dla każdego języka (polski, niemiecki, francuski itd.)
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        
        for word in words {
            if word.count >= 6 && word.count < 60 && !word.lowercased().hasPrefix("http") {
                
                let entropy = calculateShannonEntropy(word)
                let complexity = calculateComplexity(word)
                
                // Przypadek A: Złożone hasło
                // Entropia > 2.5 ORAZ Złożoność >= 3
                // (Słowa z diakrytykami jak "München" mają Złożoność 2, więc są bezpieczne)
                if entropy > 2.5 && complexity >= 3 {
                    print("🚨 DLP: Wykryto złożone hasło: \(word)")
                    return .highEntropy
                }
                
                // Przypadek B: Bardzo wysoka entropia
                // Próg 4.3 bezpiecznie przepuszcza długie słowa w językach naturalnych
                if entropy > 4.3 {
                    print("🚨 DLP: Wykryto wysoką entropię: \(word)")
                    return .highEntropy
                }
            }
        }
        
        // 4. Kontekst słów kluczowych (Wielojęzyczny)
        for keyword in sensitiveKeywords {
            if lowerText.contains(keyword) { return .passwordContext }
        }
        
        return nil
    }
    
    private func calculateShannonEntropy(_ string: String) -> Double {
        let length = Double(string.count)
        guard length > 0 else { return 0 }
        
        var frequencies = [Character: Int]()
        for char in string { frequencies[char, default: 0] += 1 }
        
        return frequencies.values.reduce(0.0) { result, count in
            let probability = Double(count) / length
            return result - (probability * log2(probability))
        }
    }
    
    // ✅ OBLICZANIE ZŁOŻONOŚCI (UNICODE)
    // \p{L} oznacza "Any Unicode Letter" (w tym ą, ü, é, ñ, ö)
    private func calculateComplexity(_ string: String) -> Int {
        var score = 0
        
        // 1. Małe litery (Unicode: a-z, ą, ü, é...)
        if string.range(of: "\\p{Ll}", options: .regularExpression) != nil { score += 1 }
        
        // 2. Duże litery (Unicode: A-Z, Ż, Ü, Ñ...)
        if string.range(of: "\\p{Lu}", options: .regularExpression) != nil { score += 1 }
        
        // 3. Cyfry
        if string.range(of: "[0-9]", options: .regularExpression) != nil { score += 1 }
        
        // 4. Symbole specjalne
        // Wszystko co NIE jest literą Unicode (\p{L}) ani cyfrą
        if string.range(of: "[^\\p{L}0-9]", options: .regularExpression) != nil { score += 1 }
        
        return score
    }
}
