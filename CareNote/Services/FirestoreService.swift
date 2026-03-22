import FirebaseFirestore
import Foundation

// MARK: - FirestoreError

enum FirestoreError: Error, Sendable {
    case encodingFailed(Error)
    case decodingFailed(Error)
    case documentNotFound(String)
    case operationFailed(Error)
}

// MARK: - RecordingStoring

protocol RecordingStoring: Sendable {
    func createRecording(tenantId: String, recording: FirestoreRecording) async throws -> String
    func updateTranscription(tenantId: String, recordingId: String, transcription: String, status: TranscriptionStatus) async throws
}

// MARK: - WhitelistManaging

protocol WhitelistManaging: Sendable {
    func fetchWhitelist(tenantId: String) async throws -> [FirestoreWhitelistEntry]
    func addToWhitelist(tenantId: String, email: String, role: String, addedBy: String) async throws
    func removeFromWhitelist(tenantId: String, entryId: String) async throws
    func updateRole(tenantId: String, entryId: String, role: String) async throws
    func isEmailWhitelisted(tenantId: String, email: String) async throws -> Bool
    func fetchRoleForEmail(tenantId: String, email: String) async throws -> String?
}

// MARK: - FirestoreService

/// Firestore CRUD service with multi-tenant structure: `tenants/{tenantId}/...`
actor FirestoreService: RecordingStoring, WhitelistManaging {

    // MARK: - Properties

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

    private func whitelistCollection(tenantId: String) -> CollectionReference {
        db.collection("tenants").document(tenantId).collection("whitelist")
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

    // MARK: - Whitelist

    func fetchWhitelist(tenantId: String) async throws -> [FirestoreWhitelistEntry] {
        do {
            let snapshot = try await whitelistCollection(tenantId: tenantId)
                .order(by: "addedAt", descending: true)
                .getDocuments()

            return snapshot.documents.compactMap { document in
                let data = document.data()
                let addedAt = (data["addedAt"] as? Timestamp)?.dateValue() ?? Date()

                return FirestoreWhitelistEntry(
                    id: document.documentID,
                    email: data["email"] as? String ?? "",
                    role: data["role"] as? String ?? "user",
                    addedBy: data["addedBy"] as? String ?? "",
                    addedAt: addedAt
                )
            }
        } catch {
            throw FirestoreError.operationFailed(error)
        }
    }

    func addToWhitelist(tenantId: String, email: String, role: String, addedBy: String) async throws {
        do {
            try await whitelistCollection(tenantId: tenantId).addDocument(data: [
                "email": email.normalizedEmail,
                "role": role,
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

    func updateRole(tenantId: String, entryId: String, role: String) async throws {
        do {
            try await whitelistCollection(tenantId: tenantId).document(entryId).updateData([
                "role": role,
            ])
        } catch {
            throw FirestoreError.operationFailed(error)
        }
    }

    func isEmailWhitelisted(tenantId: String, email: String) async throws -> Bool {
        do {
            let snapshot = try await whitelistCollection(tenantId: tenantId)
                .whereField("email", isEqualTo: email.normalizedEmail)
                .limit(to: 1)
                .getDocuments()
            return !snapshot.documents.isEmpty
        } catch {
            throw FirestoreError.operationFailed(error)
        }
    }

    func fetchRoleForEmail(tenantId: String, email: String) async throws -> String? {
        do {
            let snapshot = try await whitelistCollection(tenantId: tenantId)
                .whereField("email", isEqualTo: email.normalizedEmail)
                .limit(to: 1)
                .getDocuments()
            return snapshot.documents.first?.data()["role"] as? String
        } catch {
            throw FirestoreError.operationFailed(error)
        }
    }
}
