import Foundation

// MARK: - VertexAIConfig

/// Vertex AI 文字起こし呼び出しに使うモデル設定（ADR-012）。
/// `platformConfig/vertexAi` (Firestore) から解決するが、値は必ず allowlist 検証を通す。
struct VertexAIConfig: Sendable, Equatable {
    let modelId: String
    let thinkingLevel: String

    /// アプリビルド時点でハードコードされたフォールバック値（ADR-011 準拠）。
    static let `default` = VertexAIConfig(modelId: "gemini-3.5-flash", thinkingLevel: "minimal")

    /// CLAUDE.md Prohibited を満たすと確認済みの modelId。
    /// 完全一致のみ許容し、部分一致・prefix 一致は行わない。
    static let allowedModelIds: Set<String> = ["gemini-3.5-flash"]

    /// CLAUDE.md Prohibited（`thinkingLevel` を `minimal` 以外に設定禁止）を満たす thinkingLevel。
    static let allowedThinkingLevels: Set<String> = ["minimal"]

    /// modelId・thinkingLevel の両方が allowlist と完全一致する場合のみ有効とみなす。
    var isValid: Bool {
        Self.allowedModelIds.contains(modelId) && Self.allowedThinkingLevels.contains(thinkingLevel)
    }
}
