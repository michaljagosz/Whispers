import Foundation

class TempFileManager {
    static let shared = TempFileManager()
    
    // Nazwa naszego dedykowanego folderu, żeby nie usuwać plików innych apek
    private let cacheDirName = "com.whispers.files"
    
    private var cacheURL: URL {
        let base = FileManager.default.temporaryDirectory
        return base.appendingPathComponent(cacheDirName, isDirectory: true)
    }
    
    init() {
        createCacheDirectory()
    }
    
    // Tworzy folder przy starcie, jeśli nie istnieje
    private func createCacheDirectory() {
        if !FileManager.default.fileExists(atPath: cacheURL.path) {
            try? FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        }
    }
    
    // Zwraca bezpieczny URL do zapisu pliku
    func getUniqueFileURL(fileName: String) -> URL {
        // Sanityzacja nazwy (usuwamy dziwne znaki)
        let safeName = fileName.components(separatedBy: .init(charactersIn: "/\\?%*|\"<>:")).joined(separator: "_")
        return cacheURL.appendingPathComponent(safeName)
    }
    
    // 🔥 GLÓWNA FUNKCJA CZYSZCZĄCA
    func clearCache() {
        do {
            if FileManager.default.fileExists(atPath: cacheURL.path) {
                // Usuwamy cały folder
                try FileManager.default.removeItem(at: cacheURL)
                print("🧹 Wyczyszczono pamięć podręczną plików.")
                
                // Tworzymy go na nowo pusty
                createCacheDirectory()
            }
        } catch {
            print("⚠️ Błąd czyszczenia cache: \(error)")
        }
    }
}
