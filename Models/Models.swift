import Foundation
import SwiftUI

struct Message: Codable, Identifiable, Equatable {
    var id: Int?
    let sender_id: UUID
    let receiver_id: UUID
    var content: String
    let created_at: Date?
    var is_read: Bool?
    var is_deleted: Bool?
    var edited_at: Date?
    var type: String?
    var file_path: String?
    var file_name: String?
    var file_size: Int64?
    var file_status: String?
}

struct Profile: Codable {
    let id: UUID
    var status: String?
    var public_key: String?
    var username: String?
}
enum UserStatus: String, CaseIterable, Codable {
    case online = "online"
    case away = "away"
    case busy = "busy"
    case offline = "offline"
    
    var color: Color {
        switch self {
        case .online: return .green
        case .away: return .orange
        case .busy: return .red
        case .offline: return .gray
        }
    }
    
    var title: String {
        switch self {
        case .online: return Strings.statusOnline
        case .away: return Strings.statusAway
        case .busy: return Strings.statusBusy
        case .offline: return Strings.statusOffline
        }
    }
}

struct Contact: Codable, Identifiable {
    var id: UUID
    var name: String
}

struct TypingEvent: Codable { let sender_id: UUID }
