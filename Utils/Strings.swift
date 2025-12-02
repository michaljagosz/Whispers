import Foundation
import SwiftUI

struct Strings {
    // General
    static let appName = String(localized: "app_name")
    static let cancel = String(localized: "cancel")
    static let save = String(localized: "save")
    static let ok = String(localized: "ok")
    static let delete = String(localized: "delete")
    static let edit = String(localized: "edit")
    static let error = String(localized: "error")
    static let loading = String(localized: "loading")
    
    // Status
    static let statusOnline = String(localized: "status_online")
    static let statusAway = String(localized: "status_away")
    static let statusBusy = String(localized: "status_busy")
    static let statusOffline = String(localized: "status_offline")
    
    // Content View
    static let offlineBar = String(localized: "offline_bar")
    static let dropZone = String(localized: "drop_zone")
    static let fileTooLargeTitle = String(localized: "file_too_large_title")
    static let fileTooLargeMsg = String(localized: "file_too_large_msg")
    static let errorOccurred = String(localized: "error_occurred")
    
    // Contact List
    static let searchPlaceholder = String(localized: "search_placeholder")
    static let addContactTooltip = String(localized: "add_contact_tooltip")
    static let pasteTokenPlaceholder = String(localized: "paste_token_placeholder")
    static let addBtn = String(localized: "add_btn")
    static let contactAutoName = String(localized: "contact_auto_name")
    static let noContactsTitle = String(localized: "no_contacts_title")
    static let noContactsBtn = String(localized: "no_contacts_btn")
    static func notFound(_ text: String) -> String { String(format: String(localized: "not_found") + " \"%@\"", text) }
    
    // Chat View
    static let typingSuffix = String(localized: "typing_suffix")
    static let fileReady = String(localized: "file_ready")
    static let inputPlaceholder = String(localized: "input_placeholder")
    static let editMsgTitle = String(localized: "edit_msg_title")
    static let msgContent = String(localized: "msg_content")
    static let loadingHistory = String(localized: "loading_history")
    
    // Message Bubble
    static let msgDeleted = String(localized: "msg_deleted")
    static let filePendingMe = String(localized: "file_pending_me")
    static let btnReject = String(localized: "btn_reject")
    static let btnAccept = String(localized: "btn_accept")
    static let fileRejected = String(localized: "file_rejected")
    static let btnOpenFile = String(localized: "btn_open_file")
    static let editedTag = String(localized: "edited_tag")
    static func fileSentInfo(_ name: String) -> String { String(format: String(localized: "file_sent_info"), name) }
    
    // Header & Menu
    static let messagesTitle = String(localized: "messages_title")
    static let myStatus = String(localized: "my_status")
    static let copyId = String(localized: "copy_id")
    static let quitApp = String(localized: "quit_app")
    static let verifyContact = String(localized: "verify_contact")
    static let safetyNumber = String(localized: "safety_number")
    static func safetyAlertBody(_ number: String) -> String { String(format: String(localized: "safety_alert_body"), number) }
    
    // Settings
    static let settingsGeneral = String(localized: "settings_general")
    static let profileSection = String(localized: "profile_section")
    static let yourName = String(localized: "your_name")
    static let nameHint = String(localized: "name_hint")
    static let systemSection = String(localized: "system_section")
    static let launchAtLogin = String(localized: "launch_at_login")
    static let keyboardSection = String(localized: "keyboard_section")
    static let shortcutLabel = String(localized: "shortcut_label")
    static let shortcutHint = String(localized: "shortcut_hint")
    static let securitySection = String(localized: "security_section")
    static let exportKeyBtn = String(localized: "export_key_btn")
    static let importKeyTitle = String(localized: "import_key_title")
    static let pasteKeyPlaceholder = String(localized: "paste_key_placeholder")
    static let loadBtn = String(localized: "load_btn")
    static let importSuccessTitle = String(localized: "import_success_title")
    static let importSuccessMsg = String(localized: "import_success_msg")
    static let keyWarning = String(localized: "key_warning")
    static let keyCopiedTitle = String(localized: "key_copied_title")
    static let keyCopiedMsg = String(localized: "key_copied_msg")

    // Logic Errors
    static let authError = String(localized: "auth_error")
    static let sendFileError = String(localized: "send_file_error")
    static let userNotFound = String(localized: "user_not_found")
    static let invalidToken = String(localized: "invalid_token")
    static let selfAddError = String(localized: "self_add_error")
    static let contactExists = String(localized: "contact_exists")
    static let someone = String(localized: "someone")
    static let fetchError = String(localized: "fetch_error")
    static let sendError = String(localized: "send_error")
    static let defaultDocName = String(localized: "default_doc_name")
    
    // Date
    static let today = String(localized: "today")
    static let yesterday = String(localized: "yesterday")
}
