import Foundation
import SwiftData

@Model
final class DiaryEntry {
    var id: UUID
    var title: String
    var content: String
    var mood: String?
    var tags: [String]
    var creationDate: Date
    var lastModified: Date
    var isFavorite: Bool
    var audioURL: URL?
    var aiSummary: String?
    
    init(id: UUID = UUID(), title: String, content: String = "", mood: String? = nil, tags: [String] = [], isFavorite: Bool = false) {
        self.id = id
        self.title = title
        self.content = content
        self.mood = mood
        self.tags = tags
        self.creationDate = Date()
        self.lastModified = Date()
        self.isFavorite = isFavorite
    }
} 