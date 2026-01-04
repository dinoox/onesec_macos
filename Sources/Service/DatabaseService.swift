//
//  DatabaseService.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/12/15.
//

import Foundation
import SQLite

// MARK: - Database Error

enum DatabaseError: Error {
    case notInitialized
    case operationFailed(String)
}

// MARK: - Database Service

final class DatabaseService {
    static let shared = DatabaseService()

    private var db: Connection?
    private let queue = DispatchQueue(label: "com.onesec.database", qos: .userInitiated)

    // Tables
    private let audios = Table("audios")
    private let personas = Table("personas")

    // Columns - audios
    private let id = Expression<String>("id")
    private let sessionID = Expression<String>("session_id")
    private let userID = Expression<Int>("user_id")
    private let createdAt = Expression<Int64>("created_at")
    private let filename = Expression<String>("filename")
    private let error = Expression<String?>("error")
    private let content = Expression<String?>("content")
    private let version = Expression<String?>("version")

    // Columns - personas
    private let personaId = Expression<Int>("id")
    private let personaUserId = Expression<Int?>("user_id")
    private let personaName = Expression<String>("name")
    private let personaDescription = Expression<String?>("description")
    private let personaIcon = Expression<String>("icon")
    private let personaIconSvg = Expression<String?>("icon_svg")
    private let personaContent = Expression<String>("content")
    private let personaIsExample = Expression<Bool>("is_example")
    private let personaCreatedAt = Expression<Int?>("created_at")
    private let personaUpdatedAt = Expression<Int?>("updated_at")


    func initialize() throws {
        guard let dbURL = UserConfigService.shared.databaseDirectory else {
            throw DatabaseError.operationFailed("Database directory not available")
        }

        try queue.sync {
            db = try Connection(dbURL.path)
            try createTables()
            log.info("Database initialized")
        }
    }

    private func createTables() throws {
        guard let db = db else {
            throw DatabaseError.notInitialized
        }

        try db.run(audios.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true)
            t.column(sessionID)
            t.column(userID)
            t.column(createdAt)
            t.column(filename)
            t.column(content)
            t.column(error)
            t.column(version)
        })

        try db.run(audios.createIndex(createdAt, ifNotExists: true))
        try db.run(audios.createIndex(sessionID, ifNotExists: true))
        try db.run(audios.createIndex(userID, ifNotExists: true))

        try db.run(personas.create(ifNotExists: true) { t in
            t.column(personaId, primaryKey: true)
            t.column(personaUserId)
            t.column(personaName)
            t.column(personaDescription)
            t.column(personaIcon)
            t.column(personaIconSvg)
            t.column(personaContent)
            t.column(personaIsExample)
            t.column(personaCreatedAt)
            t.column(personaUpdatedAt)
        })
    }

    // MARK: - Recording Operations

    func saveAudios(sessionID: String, filename: String, content: String? = nil, error: String? = nil, version: String? = nil, clearBeforeInsert: Bool = false) throws {
        guard let db = db else {
            throw DatabaseError.notInitialized
        }

        try queue.sync {
            if clearBeforeInsert {
                try db.run(audios.delete())
                log.info("Cleared all audios before insert")
            }

            let query = audios.filter(self.sessionID == sessionID)
            let count = try db.scalar(query.count)

            guard count == 0 else {
                log.info("Session \(sessionID) already has a record, skipping insert")
                return
            }

            let insert = audios.insert(
                self.id <- UUID().uuidString,
                self.sessionID <- sessionID,
                self.userID <- Config.shared.USER_CONFIG.user.userId,
                createdAt <- Int64(Date().timeIntervalSince1970),
                self.filename <- filename,
                self.content <- content,
                self.error <- error,
                self.version <- version
            )
            try db.run(insert)
        }
    }

    func getAudios(id: String) throws -> Audios? {
        guard let db = db else {
            throw DatabaseError.notInitialized
        }

        return try queue.sync {
            let query = audios.filter(self.id == id)
            guard let row = try db.pluck(query) else {
                return nil
            }

            return Audios(
                id: row[self.id],
                sessionID: row[self.sessionID],
                userID: row[self.userID],
                createdAt: Date(timeIntervalSince1970: TimeInterval(row[createdAt])),
                filename: row[filename],
                error: row[error],
                content: row[content],
                version: row[version]
            )
        }
    }

    func getAllAudios(limit: Int? = nil, offset: Int = 0) throws -> [Audios] {
        guard let db = db else {
            throw DatabaseError.notInitialized
        }

        return try queue.sync {
            var query = audios.order(createdAt.desc)

            if let limit = limit {
                query = query.limit(limit, offset: offset)
            }

            return try db.prepare(query).map { row in
                Audios(
                    id: row[self.id],
                    sessionID: row[self.sessionID],
                    userID: row[self.userID],
                    createdAt: Date(timeIntervalSince1970: TimeInterval(row[createdAt])),
                    filename: row[filename],
                    error: row[error],
                    content: row[content],
                    version: row[version]
                )
            }
        }
    }

    func deleteAudios(id: String) throws {
        guard let db = db else {
            throw DatabaseError.notInitialized
        }

        try queue.sync {
            let recording = audios.filter(self.id == id)
            let deleted = try db.run(recording.delete())

            if deleted > 0 {
                log.info("Recording deleted: \(id)")
            } else {
                log.warning("Recording not found: \(id)")
            }
        }
    }

    func updateAudios(id: String, error: String? = nil, content: String? = nil, version: String? = nil) throws {
        guard let db = db else {
            throw DatabaseError.notInitialized
        }

        try queue.sync {
            let recording = audios.filter(self.id == id)
            var setters: [Setter] = []

            if let error = error {
                setters.append(self.error <- error)
            }
            if let content = content {
                setters.append(self.content <- content)
            }
            if let version = version {
                setters.append(self.version <- version)
            }

            guard !setters.isEmpty else {
                log.warning("No fields to update for: \(id)")
                return
            }

            let updated = try db.run(recording.update(setters))

            if updated > 0 {
                log.info("Recording updated: \(id)")
            } else {
                log.warning("Recording not found: \(id)")
            }
        }
    }

    func getAudiosCount() throws -> Int {
        guard let db = db else {
            throw DatabaseError.notInitialized
        }

        return try queue.sync {
            try db.scalar(audios.count)
        }
    }

    func clearAllAudios() throws {
        guard let db = db else {
            throw DatabaseError.notInitialized
        }

        try queue.sync {
            try db.run(audios.delete())
            log.info("All recordings cleared")
        }
    }

    // MARK: - Query by SessionID

    func getAudiosBySession(sessionID: String) throws -> [Audios] {
        guard let db = db else {
            throw DatabaseError.notInitialized
        }

        return try queue.sync {
            let query = audios.filter(self.sessionID == sessionID).order(createdAt.desc)
            return try db.prepare(query).map { row in
                Audios(
                    id: row[self.id],
                    sessionID: row[self.sessionID],
                    userID: row[self.userID],
                    createdAt: Date(timeIntervalSince1970: TimeInterval(row[createdAt])),
                    filename: row[filename],
                    error: row[error],
                    content: row[content],
                    version: row[version]
                )
            }
        }
    }

    func deleteAudiosBySession(sessionID: String) throws {
        guard let db = db else {
            throw DatabaseError.notInitialized
        }

        try queue.sync {
            let recordings = audios.filter(self.sessionID == sessionID)
            let deleted = try db.run(recordings.delete())

            if deleted > 0 {
                log.info("Deleted \(deleted) recordings for session: \(sessionID)")
            } else {
                log.warning("No recordings found for session: \(sessionID)")
            }
        }
    }

    // MARK: - Persona Operations

    func savePersonas(_ personaList: [Persona]) throws {
        guard let db = db else {
            throw DatabaseError.notInitialized
        }

        try queue.sync {
            try db.run(personas.delete())

            for persona in personaList {
                let insert = personas.insert(or: .replace,
                                             personaId <- persona.id,
                                             personaUserId <- persona.userId,
                                             personaName <- persona.name,
                                             personaDescription <- persona.description,
                                             personaIcon <- persona.icon,
                                             personaIconSvg <- persona.iconSvg,
                                             personaContent <- persona.content,
                                             personaIsExample <- persona.isExample,
                                             personaCreatedAt <- persona.createdAt,
                                             personaUpdatedAt <- persona.updatedAt)
                try db.run(insert)
            }
            log.info("Saved \(personaList.count) personas")
        }
    }

    func getAllPersonas() throws -> [Persona] {
        guard let db = db else {
            throw DatabaseError.notInitialized
        }

        return try queue.sync {
            try db.prepare(personas).map { row in
                Persona(
                    id: row[personaId],
                    userId: row[personaUserId],
                    name: row[personaName],
                    description: row[personaDescription],
                    icon: row[personaIcon],
                    iconSvg: row[personaIconSvg],
                    content: row[personaContent],
                    isExample: row[personaIsExample],
                    createdAt: row[personaCreatedAt],
                    updatedAt: row[personaUpdatedAt]
                )
            }
        }
    }

    func getPersona(id: Int) throws -> Persona? {
        guard let db = db else {
            throw DatabaseError.notInitialized
        }

        return try queue.sync {
            let query = personas.filter(personaId == id)
            guard let row = try db.pluck(query) else {
                return nil
            }
            return Persona(
                id: row[personaId],
                userId: row[personaUserId],
                name: row[personaName],
                description: row[personaDescription],
                icon: row[personaIcon],
                iconSvg: row[personaIconSvg],
                content: row[personaContent],
                isExample: row[personaIsExample],
                createdAt: row[personaCreatedAt],
                updatedAt: row[personaUpdatedAt]
            )
        }
    }

    func clearAllPersonas() throws {
        guard let db = db else {
            throw DatabaseError.notInitialized
        }

        try queue.sync {
            try db.run(personas.delete())
            log.info("All personas cleared")
        }
    }

}

// MARK: - Data Models

struct Audios: Codable, Identifiable {
    let id: String
    let sessionID: String
    let userID: Int
    let createdAt: Date
    let filename: String
    let error: String?
    let content: String?
    let version: String?

    var asDictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "session_id": sessionID,
            "user_id": userID,
            "created_at": Int(createdAt.timeIntervalSince1970),
            "filename": filename,
        ]
        if let error = error {
            dict["error"] = error
        }
        if let content = content {
            dict["content"] = content
        }
        if let version = version {
            dict["version"] = version
        }
        return dict
    }
}
