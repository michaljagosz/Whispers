import SwiftUI

struct MessageBubble: View {
    let message: Message
    let isMe: Bool
    var isPreviousFromSameSender: Bool = false
    var isNextFromSameSender: Bool = false
    var chatManager: ChatManager
    
    var onExpand: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    
    @State private var showDetails = false
    @State private var isDownloading = false
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMe { Spacer() }
            
            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                if message.is_deleted == true {
                    Text(Strings.msgDeleted)
                        .font(.system(size: 13, weight: .light).italic())
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .foregroundStyle(.white.opacity(0.6))
                        .background(Color.gray.opacity(0.2))
                        .clipShape(.rect(
                            topLeadingRadius: (!isMe && isPreviousFromSameSender) ? 4 : 16,
                            bottomLeadingRadius: (!isMe && isNextFromSameSender) ? 4 : 16,
                            bottomTrailingRadius: (isMe && isNextFromSameSender) ? 4 : 16,
                            topTrailingRadius: (isMe && isPreviousFromSameSender) ? 4 : 16
                        ))
                } else {
                    Group {
                        if message.type == "file", let fileName = message.file_name {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(Color.white.opacity(0.2)).frame(width: 40, height: 40)
                                        Image(systemName: "doc.fill").foregroundStyle(.white)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(fileName).font(.system(size: 14, weight: .medium)).lineLimit(1)
                                        if let size = message.file_size { Text(formatBytes(size)).font(.caption2).foregroundStyle(.white.opacity(0.7)) }
                                    }
                                }
                                
                                let status = message.file_status ?? "accepted"
                                
                                if status == "pending" {
                                    if isMe {
                                        Text(Strings.filePendingMe).font(.caption2).italic().foregroundStyle(.white.opacity(0.6))
                                    } else {
                                        HStack {
                                            Button(Strings.btnReject) {
                                                if let id = message.id { Task { await chatManager.respondToFile(messageID: id, accept: false) } }
                                            }
                                            .buttonStyle(.bordered).tint(.red).controlSize(.small)
                                            
                                            Button(Strings.btnAccept) {
                                                if let id = message.id { Task { await chatManager.respondToFile(messageID: id, accept: true) } }
                                            }
                                            .buttonStyle(.borderedProminent).tint(.green).controlSize(.small)
                                        }
                                    }
                                } else if status == "rejected" {
                                    Text(Strings.fileRejected).font(.caption).foregroundStyle(.red.opacity(0.8))
                                } else {
                                    Button(action: { downloadAndOpenFile() }) {
                                        HStack {
                                            if isDownloading { ProgressView().controlSize(.small) }
                                            else { Image(systemName: "arrow.down.circle.fill") }
                                            Text(Strings.btnOpenFile).font(.caption).fontWeight(.medium)
                                        }
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(Color.black.opacity(0.2)).cornerRadius(8)
                                    }.buttonStyle(.plain)
                                }
                            }
                            .padding(10)
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(message.content)
                            }.padding(.horizontal, 12).padding(.vertical, 8)
                        }
                    }
                    .foregroundStyle(isMe ? Color(nsColor: .selectedControlTextColor) : .white)
                    .background(isMe ? Color(nsColor: .controlAccentColor) : Color.white.opacity(0.15))
                    .brightness(showDetails ? -0.15 : 0)
                    .clipShape(.rect(
                        topLeadingRadius: (!isMe && isPreviousFromSameSender) ? 4 : 16,
                        bottomLeadingRadius: (!isMe && isNextFromSameSender) ? 4 : 16,
                        bottomTrailingRadius: (isMe && isNextFromSameSender) ? 4 : 16,
                        topTrailingRadius: (isMe && isPreviousFromSameSender) ? 4 : 16
                    ))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { showDetails.toggle() }
                        if showDetails { onExpand?() }
                    }
                    .contextMenu { if isMe { if message.type != "file" { Button { onEdit?() } label: { Label(Strings.edit, systemImage: "pencil") } }; Button(role: .destructive) { onDelete?() } label: { Label(Strings.delete, systemImage: "trash") } } }
                }
                
                if showDetails && message.is_deleted != true {
                    HStack(spacing: 4) {
                        if let d = message.created_at { Text(d.formatted(date: .omitted, time: .shortened)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5)) }
                        
                        if message.edited_at != nil {
                            Text(Strings.editedTag)
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        
                        if isMe { Image(systemName: message.is_read == true ? "checkmark.circle.fill" : "checkmark.circle").font(.system(size: 10)).foregroundStyle(.white.opacity(message.is_read == true ? 0.8 : 0.4)) }
                    }
                    .padding(.horizontal, 4)
                }
            }
            if !isMe { Spacer() }
        }.padding(.bottom, isNextFromSameSender ? 2 : 10)
    }
    
    // ✅ BEZPIECZNE POBIERANIE PLIKU
    func downloadAndOpenFile() {
        guard let path = message.file_path, let originalName = message.file_name else { return }
        isDownloading = true
        Task {
            if let data = await chatManager.downloadFile(path: path) {
                await MainActor.run {
                    // 1. Sanityzacja nazwy pliku (usuwanie znaków specjalnych ścieżki)
                    let safeName = originalName.components(separatedBy: .init(charactersIn: "/\\?%*|\"<>:")).joined(separator: "_")
                    
                    // 2. Użycie katalogu tymczasowego
                    let tempDir = FileManager.default.temporaryDirectory
                    let fileURL = tempDir.appendingPathComponent(safeName)
                    
                    do {
                        try data.write(to: fileURL)
                        NSWorkspace.shared.open(fileURL)
                    } catch {
                        print("Błąd zapisu: \(error)")
                    }
                    isDownloading = false
                }
            } else { await MainActor.run { isDownloading = false } }
        }
    }
    
    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter(); formatter.allowedUnits = [.useKB, .useMB]; formatter.countStyle = .file; return formatter.string(fromByteCount: bytes)
    }
}
