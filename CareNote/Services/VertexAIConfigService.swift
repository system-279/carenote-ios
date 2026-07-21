import Foundation
import os.log

// MARK: - VertexAIConfigService

/// `platformConfig/vertexAi` から Vertex AI モデル設定を解決する共有サービス（ADR-012）。
///
/// - allowlist 検証を通った設定のみ採用し、失敗時や不正値はハードコードデフォルト
///   (`VertexAIConfig.default`) へソフトフェイルする。例外は一切伝播しない。
/// - `OutboxSyncService` はオンライン時のみ動作するため永続キャッシュは持たず、
///   プロセス生存中のみ有効なメモリキャッシュで十分とする。
/// - `defaultSyncServiceFactory` (`RecordingConfirmViewModel`) が呼ばれるたびに
///   新規サービスインスタンスを構築する現状の構造上、`shared` を共有しないと
///   メモリキャッシュが機能しない点に注意。
actor VertexAIConfigService {
    static let shared = VertexAIConfigService(configFetcher: FirestoreService())

    private static let logger = Logger(subsystem: "jp.carenote.app", category: "VertexAIConfigService")

    private let configFetcher: any VertexAIConfigFetching
    private var cachedConfig: VertexAIConfig?

    init(configFetcher: any VertexAIConfigFetching) {
        self.configFetcher = configFetcher
    }

    /// 有効な `VertexAIConfig` を返す。fetch 失敗・不正値・未シードの場合は
    /// `VertexAIConfig.default` にフォールバックする（例外は伝播させない）。
    ///
    /// 成功して allowlist 検証を通った値のみキャッシュする。fetch 失敗や
    /// allowlist 不正値はキャッシュしない — 次回呼び出しで再度 fetch を試みる
    /// ことで、一時的な障害でプロセス生存中ずっと `.default` に固定されるのを防ぐ。
    func resolveConfig() async -> VertexAIConfig {
        if let cachedConfig {
            return cachedConfig
        }

        do {
            if let fetched = try await configFetcher.fetchVertexAIConfig() {
                if fetched.isValid {
                    cachedConfig = fetched
                    return fetched
                }
                Self.logger.error("fetchVertexAIConfig returned an invalid config (modelId=\(fetched.modelId, privacy: .public), thinkingLevel=\(fetched.thinkingLevel, privacy: .public)), falling back to default")
            }
        } catch {
            Self.logger.error("fetchVertexAIConfig failed, falling back to default: \(error.localizedDescription, privacy: .public)")
        }

        return .default
    }
}
