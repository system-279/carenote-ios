import FirebaseFirestore
import Foundation
import os.log

// MARK: - FirestoreError

enum FirestoreError: Error, Sendable {
    case encodingFailed(Error)
    case decodingFailed(Error)
    case documentNotFound(String)
    /// Firestore security rules 等によるアクセス拒否 (`FirestoreErrorCode.permissionDenied` = 7)。
    /// メンバー権限では削除できない legacy document (例: `createdBy=""`) を検知するのに使う。
    case permissionDenied
    /// 対象 document が Firestore 側で既に存在しない (`FirestoreErrorCode.notFound` = 5)。
    /// 他端末での先行削除など、idempotent success として扱うのが望ましい。
    case notFound
    case operationFailed(Error)

    /// エラーが transient (自動リトライで回復しうる) かを判定する。
    ///
    /// `operationFailed` が `FirestoreErrorDomain` 内の以下コードを包む場合のみ transient:
    /// - `deadlineExceeded`: ネットワーク timeout
    /// - `resourceExhausted`: quota / rate limit
    /// - `unavailable`: Firestore backend 一時障害
    ///
    /// それ以外 (`encodingFailed` / `decodingFailed` / `documentNotFound`、及び
    /// permissionDenied / unauthenticated / notFound 等のコード) はすべて permanent 扱い。
    ///
    /// 分類基準はグローバル `~/.claude/rules/error-handling.md` §3 の
    /// transient/permanent プロトコルに準拠。
    var isTransient: Bool {
        guard case let .operationFailed(underlying) = self else { return false }
        let nsError = underlying as NSError
        guard nsError.domain == FirestoreErrorDomain else { return false }
        switch nsError.code {
        case FirestoreErrorCode.deadlineExceeded.rawValue,
             FirestoreErrorCode.resourceExhausted.rawValue,
             FirestoreErrorCode.unavailable.rawValue:
            return true
        default:
            return false
        }
    }

    /// Firestore SDK が throw した NSError を `FirestoreError` にマップする。
    ///
    /// - `FirestoreErrorDomain` + `permissionDenied` (code 7) → `.permissionDenied`
    /// - `FirestoreErrorDomain` + `notFound` (code 5) → `.notFound`
    /// - その他 (transient / 未分類 / 異なる domain) → `.operationFailed(error)` で保持
    ///
    /// transient 判定は `.operationFailed` の `isTransient` プロパティで確認する。
    /// 基準はグローバル `~/.claude/rules/error-handling.md` §3 の
    /// transient/permanent プロトコルに準拠。
    static func map(_ error: Error) -> FirestoreError {
        let nsError = error as NSError
        guard nsError.domain == FirestoreErrorDomain else {
            return .operationFailed(error)
        }
        switch nsError.code {
        case FirestoreErrorCode.permissionDenied.rawValue:
            return .permissionDenied
        case FirestoreErrorCode.notFound.rawValue:
            return .notFound
        default:
            return .operationFailed(error)
        }
    }
}

// MARK: - RecordingStoring

protocol RecordingStoring: Sendable {
    func createRecording(tenantId: String, recording: FirestoreRecording) async throws -> String
    func updateTranscription(tenantId: String, recordingId: String, transcription: String, status: TranscriptionStatus) async throws
    func deleteRecording(tenantId: String, recordingId: String) async throws
}

// MARK: - ClientManaging

protocol ClientManaging: Sendable {
    func fetchClients(tenantId: String) async throws -> [FirestoreClient]
    func addClient(tenantId: String, name: String, furigana: String) async throws
    func updateClient(tenantId: String, clientId: String, name: String, furigana: String) async throws
    func deleteClient(tenantId: String, clientId: String) async throws
}

// MARK: - TemplateManaging

protocol TemplateManaging: Sendable {
    func fetchTemplates(tenantId: String) async throws -> [FirestoreTemplate]
    func createTemplate(tenantId: String, name: String, prompt: String, outputType: OutputType, createdBy: String, createdByName: String) async throws -> String
    func updateTemplate(tenantId: String, templateId: String, name: String, prompt: String, outputType: OutputType) async throws
    func deleteTemplate(tenantId: String, templateId: String) async throws
}

// MARK: - FirestoreService

/// Firestore CRUD service with multi-tenant structure: `tenants/{tenantId}/...`
actor FirestoreService: RecordingStoring, ClientManaging, TemplateManaging {

    // MARK: - Properties

    private static let logger = Logger(subsystem: "jp.carenote.app", category: "FirestoreService")
    private let _firestore: Firestore?

    private var db: Firestore {
        _firestore ?? Firestore.firestore()
    }

    // MARK: - Initialization

    init(firestore: Firestore? = nil) {
        self._firestore = firestore
    }

    // MARK: - Collection References

    private func clientsCollection(tenantId: String) -> CollectionReference {
        db.collection("tenants").document(tenantId).collection("clients")
    }

    private func recordingsCollection(tenantId: String) -> CollectionReference {
        db.collection("tenants").document(tenantId).collection("recordings")
    }

    // MARK: - Clients

    /// Fetch all clients for a given tenant.
    /// - Parameter tenantId: The tenant identifier.
    /// - Returns: An array of `FirestoreClient` including document IDs.
    func fetchClients(tenantId: String) async throws -> [FirestoreClient] {
        do {
            let snapshot = try await clientsCollection(tenantId: tenantId)
                .order(by: "furigana")
                .getDocuments()

            return snapshot.documents.compactMap { document in
                let data = document.data()
                return FirestoreClient(
                    id: document.documentID,
                    name: data["name"] as? String ?? "",
                    furigana: data["furigana"] as? String ?? ""
                )
            }
        } catch {
            throw FirestoreError.operationFailed(error)
        }
    }

    func addClient(tenantId: String, name: String, furigana: String) async throws {
        do {
            try await clientsCollection(tenantId: tenantId).addDocument(data: [
                "name": name,
                "furigana": furigana,
                "createdAt": Timestamp(date: Date()),
            ])
        } catch {
            throw FirestoreError.operationFailed(error)
        }
    }

    func updateClient(tenantId: String, clientId: String, name: String, furigana: String) async throws {
        do {
            try await clientsCollection(tenantId: tenantId).document(clientId).updateData([
                "name": name,
                "furigana": furigana,
                "updatedAt": Timestamp(date: Date()),
            ])
        } catch {
            throw FirestoreError.operationFailed(error)
        }
    }

    func deleteClient(tenantId: String, clientId: String) async throws {
        do {
            try await clientsCollection(tenantId: tenantId).document(clientId).delete()
        } catch {
            throw FirestoreError.operationFailed(error)
        }
    }

    // MARK: - Whitelist

    private func whitelistCollection(tenantId: String) -> CollectionReference {
        db.collection("tenants").document(tenantId).collection("whitelist")
    }

    func fetchWhitelist(tenantId: String) async throws -> [WhitelistEntry] {
        do {
            let snapshot = try await whitelistCollection(tenantId: tenantId)
                .getDocuments()

            return snapshot.documents.compactMap { document in
                let data = document.data()
                let addedAt = (data["addedAt"] as? Timestamp)?.dateValue() ?? Date()
                return WhitelistEntry(
                    id: document.documentID,
                    email: data["email"] as? String ?? "",
                    role: UserRole.from(firestoreValue: data["role"] as? String),
                    addedBy: data["addedBy"] as? String ?? "",
                    addedAt: addedAt
                )
            }
        } catch {
            throw FirestoreError.operationFailed(error)
        }
    }

    func addToWhitelist(tenantId: String, email: String, role: UserRole, addedBy: String) async throws {
        do {
            try await whitelistCollection(tenantId: tenantId).addDocument(data: [
                "email": email.lowercased().trimmingCharacters(in: .whitespaces),
                "role": role.rawValue,
                "addedBy": addedBy,
                "addedAt": Timestamp(date: Date()),
            ])
        } catch {
            throw FirestoreError.operationFailed(error)
        }
    }

    func removeFromWhitelist(tenantId: String, entryId: String) async throws {
        do {
            try await whitelistCollection(tenantId: tenantId).document(entryId).delete()
        } catch {
            throw FirestoreError.operationFailed(error)
        }
    }

    func updateWhitelistRole(tenantId: String, entryId: String, role: UserRole) async throws {
        do {
            try await whitelistCollection(tenantId: tenantId).document(entryId).updateData([
                "role": role.rawValue,
            ])
        } catch {
            throw FirestoreError.operationFailed(error)
        }
    }

    // MARK: - Allowed Domains

    func fetchAllowedDomains(tenantId: String) async throws -> [String] {
        do {
            let document = try await db.collection("tenants").document(tenantId).getDocument()
            guard document.exists, let data = document.data() else { return [] }
            return data["allowedDomains"] as? [String] ?? []
        } catch {
            throw FirestoreError.operationFailed(error)
        }
    }

    func setAllowedDomains(tenantId: String, domains: [String]) async throws {
        do {
            try await db.collection("tenants").document(tenantId).setData([
                "allowedDomains": domains.map { $0.lowercased().trimmingCharacters(in: .whitespaces) },
            ], merge: true)
        } catch {
            throw FirestoreError.operationFailed(error)
        }
    }

    // MARK: - Templates

    private func templatesCollection(tenantId: String) -> CollectionReference {
        db.collection("tenants").document(tenantId).collection("templates")
    }

    func fetchTemplates(tenantId: String) async throws -> [FirestoreTemplate] {
        do {
            let snapshot = try await templatesCollection(tenantId: tenantId)
                .order(by: "createdAt")
                .getDocuments()

            return snapshot.documents.compactMap { document in
                let data = document.data()
                let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()

                return FirestoreTemplate(
                    id: document.documentID,
                    name: data["name"] as? String ?? "",
                    prompt: data["prompt"] as? String ?? "",
                    outputType: {
                        let raw = data["outputType"] as? String ?? ""
                        if let type = OutputType(rawValue: raw) ?? OutputType.fromLegacy(raw) {
                            return type
                        }
                        Self.logger.error("fetchTemplates: unrecognized outputType '\(raw)' in document \(document.documentID), falling back to .custom")
                        return .custom
                    }(),
                    createdBy: data["createdBy"] as? String ?? "",
                    createdByName: data["createdByName"] as? String ?? "",
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
            }
        } catch {
            throw FirestoreError.operationFailed(error)
        }
    }

    func createTemplate(tenantId: String, name: String, prompt: String, outputType: OutputType, createdBy: String, createdByName: String) async throws -> String {
        do {
            let now = Timestamp(date: Date())
            let docRef = try await templatesCollection(tenantId: tenantId).addDocument(data: [
                "name": name,
                "prompt": prompt,
                "outputType": outputType.rawValue,
                "createdBy": createdBy,
                "createdByName": createdByName,
                "createdAt": now,
                "updatedAt": now,
            ])
            return docRef.documentID
        } catch {
            throw FirestoreError.operationFailed(error)
        }
    }

    func updateTemplate(tenantId: String, templateId: String, name: String, prompt: String, outputType: OutputType) async throws {
        do {
            try await templatesCollection(tenantId: tenantId).document(templateId).updateData([
                "name": name,
                "prompt": prompt,
                "outputType": outputType.rawValue,
                "updatedAt": Timestamp(date: Date()),
            ])
        } catch {
            throw FirestoreError.operationFailed(error)
        }
    }

    func deleteTemplate(tenantId: String, templateId: String) async throws {
        do {
            try await templatesCollection(tenantId: tenantId).document(templateId).delete()
        } catch {
            throw FirestoreError.operationFailed(error)
        }
    }

    // MARK: - Recordings

    /// Create a new recording document.
    /// - Parameters:
    ///   - tenantId: The tenant identifier.
    ///   - recording: The recording data to store.
    /// - Returns: The generated Firestore document ID.
    func createRecording(tenantId: String, recording: FirestoreRecording) async throws -> String {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970

            let jsonData = try encoder.encode(recording)
            var dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] ?? [:]

            // Remove id field (let Firestore auto-generate)
            dict.removeValue(forKey: "id")

            // Convert date fields to Firestore Timestamp
            dict["recordedAt"] = Timestamp(date: recording.recordedAt)
            dict["createdAt"] = Timestamp(date: recording.createdAt)
            dict["updatedAt"] = Timestamp(date: recording.updatedAt)

            let docRef = try await recordingsCollection(tenantId: tenantId).addDocument(data: dict)
            return docRef.documentID
        } catch let error as FirestoreError {
            throw error
        } catch {
            throw FirestoreError.operationFailed(error)
        }
    }

    /// Update the transcription result for a recording.
    /// - Parameters:
    ///   - tenantId: The tenant identifier.
    ///   - recordingId: The Firestore document ID of the recording.
    ///   - transcription: The transcribed text.
    ///   - status: The new transcription status.
    func updateTranscription(
        tenantId: String,
        recordingId: String,
        transcription: String,
        status: TranscriptionStatus
    ) async throws {
        do {
            let docRef = recordingsCollection(tenantId: tenantId).document(recordingId)

            try await docRef.updateData([
                "transcription": transcription,
                "transcriptionStatus": status.rawValue,
                "updatedAt": Timestamp(date: Date()),
            ])
        } catch {
            throw FirestoreError.operationFailed(error)
        }
    }

    /// Delete a recording document at `tenants/{tenantId}/recordings/{recordingId}`.
    /// Audio files in Cloud Storage are intentionally left intact in this change —
    /// orphan cleanup is tracked as an Issue #182 follow-up and will be handled
    /// server-side (Cloud Function, TBD).
    func deleteRecording(tenantId: String, recordingId: String) async throws {
        do {
            try await recordingsCollection(tenantId: tenantId).document(recordingId).delete()
        } catch {
            // Issue #193: permissionDenied / notFound / transient を UI で区別できるよう分類する。
            // updateTranscription / deleteClient / deleteTemplate は本 Issue では YAGNI で見送り。
            throw FirestoreError.map(error)
        }
    }

    /// Fetch a single recording by Firestore document ID.
    /// - Parameters:
    ///   - tenantId: The tenant identifier.
    ///   - recordingId: The Firestore document ID.
    /// - Returns: The recording data, or nil if not found.
    func fetchRecording(tenantId: String, recordingId: String) async throws -> FirestoreRecording? {
        do {
            let document = try await recordingsCollection(tenantId: tenantId)
                .document(recordingId)
                .getDocument()

            guard document.exists, let data = document.data() else {
                return nil
            }

            let recordedAt = (data["recordedAt"] as? Timestamp)?.dateValue() ?? Date()
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()

            return FirestoreRecording(
                id: document.documentID,
                clientId: data["clientId"] as? String ?? "",
                clientName: data["clientName"] as? String ?? "",
                scene: data["scene"] as? String ?? "",
                recordedAt: recordedAt,
                durationSeconds: data["durationSeconds"] as? Double ?? 0,
                audioStoragePath: data["audioStoragePath"] as? String,
                transcription: data["transcription"] as? String,
                transcriptionStatus: data["transcriptionStatus"] as? String ?? TranscriptionStatus.pending.rawValue,
                createdBy: data["createdBy"] as? String ?? "",
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        } catch {
            throw FirestoreError.operationFailed(error)
        }
    }

    /// Fetch all recordings for a given tenant.
    /// - Parameter tenantId: The tenant identifier.
    /// - Returns: An array of `FirestoreRecording` including document IDs.
    func fetchRecordings(tenantId: String) async throws -> [FirestoreRecording] {
        do {
            let snapshot = try await recordingsCollection(tenantId: tenantId)
                .order(by: "recordedAt", descending: true)
                .getDocuments()

            return snapshot.documents.compactMap { document in
                let data = document.data()

                let recordedAt = (data["recordedAt"] as? Timestamp)?.dateValue() ?? Date()
                let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()

                return FirestoreRecording(
                    id: document.documentID,
                    clientId: data["clientId"] as? String ?? "",
                    clientName: data["clientName"] as? String ?? "",
                    scene: data["scene"] as? String ?? "",
                    recordedAt: recordedAt,
                    durationSeconds: data["durationSeconds"] as? Double ?? 0,
                    audioStoragePath: data["audioStoragePath"] as? String,
                    transcription: data["transcription"] as? String,
                    transcriptionStatus: data["transcriptionStatus"] as? String ?? TranscriptionStatus.pending.rawValue,
                    createdBy: data["createdBy"] as? String ?? "",
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
            }
        } catch {
            throw FirestoreError.operationFailed(error)
        }
    }
}
