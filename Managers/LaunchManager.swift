import Foundation
import ServiceManagement

@Observable
class LaunchManager {
    var isLaunchAtLoginEnabled: Bool {
        didSet {
            updateLaunchState()
        }
    }
    
    init() {
        // Sprawdzamy aktualny stan przy uruchomieniu
        self.isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }
    
    private func updateLaunchState() {
        do {
            if isLaunchAtLoginEnabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                    print("🚀 Autostart włączony")
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                    print("🛑 Autostart wyłączony")
                }
            }
        } catch {
            print("Błąd zmiany autostartu: \(error)")
        }
    }
}
