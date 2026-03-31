import Foundation
import SwiftData
import os.log

// MARK: - ClientCacheError

enum ClientCacheError: Error, Sendable {
    case modelContainerNotAvailable
    case fetchFailed(Error)
    case refreshFailed(Error)
    case saveFailed(Error)
}

// MARK: - ClientCacheService

/// Client master data cache management.
/// Fetches from Firestore and caches in SwiftData (ClientCache) with a 24-hour TTL.
/// Uses @MainActor because all SwiftData operations require mainContext.
@MainActor
final class ClientCacheService {

    // MARK: - Constants

    private static let cacheExpirationInterval: TimeInterval = 24 * 60 * 60 // 24 hours
    private static let logger = Logger(subsystem: "jp.carenote.app", category: "ClientCacheService")

    // MARK: - Properties

    private let clientManager: any ClientManaging
    private let modelContainer: ModelContainer

    // MARK: - Initialization

    init(clientManager: any ClientManaging, modelContainer: ModelContainer) {
        self.clientManager = clientManager
        self.modelContainer = modelContainer
    }

    // MARK: - Public Methods

    /// Check if the cache needs to be refreshed.
    /// Returns `true` if the cache is empty or older than 24 hours.
    func needsRefresh() -> Bool {
        let context = modelContainer.mainContext

        let descriptor = FetchDescriptor<ClientCache>(
            sortBy: [SortDescriptor(\.cachedAt, order: .reverse)]
        )

        do {
            let cached = try context.fetch(descriptor)
            guard let newest = cached.first else { return true }
            let elapsed = Date().timeIntervalSince(newest.cachedAt)
            return elapsed > Self.cacheExpirationInterval
        } catch {
            Self.logger.error("needsRefresh: SwiftData fetch failed: \(error.localizedDescription)")
            return true
        }
    }

    /// Refresh the cache if it is stale or empty.
    /// - Parameter tenantId: The tenant identifier to fetch clients for.
    func refreshIfNeeded(tenantId: String) async throws {
        guard needsRefresh() else { return }
        try await forceRefresh(tenantId: tenantId)
    }

    /// Force refresh the cache regardless of staleness.
    /// - Parameter tenantId: The tenant identifier to fetch clients for.
    func forceRefresh(tenantId: String) async throws {
        // Fetch from Firestore
        let clients: [FirestoreClient]
        do {
            clients = try await clientManager.fetchClients(tenantId: tenantId)
        } catch {
            throw ClientCacheError.refreshFailed(error)
        }

        let context = modelContainer.mainContext

        // Delete existing cache
        do {
            let existing = try context.fetch(FetchDescriptor<ClientCache>())
            for item in existing {
                context.delete(item)
            }
        } catch {
            throw ClientCacheError.fetchFailed(error)
        }

        // Insert new cache entries
        let now = Date()
        for client in clients {
            let cached = ClientCache(
                id: client.id,
                name: client.name,
                furigana: client.furigana,
                cachedAt: now
            )
            context.insert(cached)
        }

        // Save
        do {
            try context.save()
        } catch {
            throw ClientCacheError.saveFailed(error)
        }
    }

    /// Get cached clients from SwiftData.
    /// - Returns: An array of cached `ClientCache` entries.
    func getCachedClients() throws -> [ClientCache] {
        let context = modelContainer.mainContext

        let descriptor = FetchDescriptor<ClientCache>(
            sortBy: [SortDescriptor(\.furigana)]
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            throw ClientCacheError.fetchFailed(error)
        }
    }
}
