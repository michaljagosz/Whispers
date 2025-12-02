import Foundation

struct Config {
    // Pobieranie URL
    static var supabaseURL: URL {
        guard let urlString = string(for: "SupabaseURL"),
              let url = URL(string: urlString) else {
            fatalError("🛑 BŁĄD KONFIGURACJI: Nie znaleziono klucza 'SupabaseURL' w Secrets.plist lub jest nieprawidłowy.")
        }
        return url
    }
    
    // Pobieranie Klucza
    static var supabaseKey: String {
        guard let key = string(for: "SupabaseKey") else {
            fatalError("🛑 BŁĄD KONFIGURACJI: Nie znaleziono klucza 'SupabaseKey' w Secrets.plist.")
        }
        return key
    }
    
    // Prywatna funkcja pomocnicza do czytania pliku plist
    private static func string(for key: String) -> String? {
        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            print("⚠️ Ostrzeżenie: Nie znaleziono pliku Secrets.plist")
            return nil
        }
        return dict[key] as? String
    }
}
