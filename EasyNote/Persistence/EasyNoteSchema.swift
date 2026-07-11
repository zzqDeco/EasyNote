import SwiftData

enum EasyNoteSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            EasyNoteSchemaV1.DiaryEntry.self,
            EasyNoteSchemaV1.TodoItem.self,
            EasyNoteSchemaV1.ChatSession.self,
            EasyNoteSchemaV1.SessionMessage.self
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
