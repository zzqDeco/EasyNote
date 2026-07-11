import SwiftData

enum EasyNoteSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        // SwiftData on Xcode 16.4 crashes when relationship-bearing nested
        // versioned models are rolled back. Keep these V1 storage types top-level
        // and enforce their immutable layout with the frozen contract tests.
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
