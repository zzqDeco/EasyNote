import SwiftData

enum EasyNoteSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        // These top-level storage types define V1 and must remain unchanged.
        // Persisted layout changes require a new VersionedSchema and migration stage.
        [
            DiaryEntry.self,
            TodoItem.self,
            ChatSession.self,
            SessionMessage.self
        ]
    }

    static var schema: Schema {
        Schema(versionedSchema: self)
    }
}

enum EasyNoteMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [EasyNoteSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
