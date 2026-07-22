import Foundation

// MARK: - VertexAIConfig

/// Vertex AI 文字起こし呼び出しに使うモデル設定（ADR-012、ADR-014でmodelId検証方式を改訂）。
/// `platformConfig/vertexAi` (Firestore) から解決するが、値は必ず検証を通す。
struct VertexAIConfig: Sendable, Equatable {
    let modelId: String
    let thinkingLevel: String

    /// アプリビルド時点でハードコードされたフォールバック値（ADR-011 準拠。ADR-014により
    /// gemini-3.6-flashを評価したが日本データレジデンシー未対応のため据置、詳細はADR-014参照）。
    static let `default` = VertexAIConfig(modelId: "gemini-3.5-flash", thinkingLevel: "minimal")

    /// CLAUDE.md Prohibited（`thinkingLevel` を `minimal` 以外に設定禁止）を満たす thinkingLevel。
    static let allowedThinkingLevels: Set<String> = ["minimal"]

    /// CLAUDE.md Prohibited が禁止する modelId のみを拒否する denylist（ADR-014）。
    /// 完全一致allowlistと異なり、正しい将来モデル名を運営者が入力すればアプリ更新なしで通る。
    /// 拒否対象は (a) 無印「Gemini 3 Flash」ベースモデル (`gemini-3-flash` / `gemini-3-flash-*`。
    /// `gemini-3.5-flash` 等マイナーバージョン付きは対象外) と (b) preview/experimental系のみ。
    static func isModelAllowed(_ modelId: String) -> Bool {
        let lower = modelId.lowercased()
        guard !lower.isEmpty else { return false }

        if lower == "gemini-3-flash" || lower.hasPrefix("gemini-3-flash-") {
            return false
        }

        let segments = Set(lower.split(separator: "-"))
        let prohibitedSegments: Set<Substring> = ["preview", "exp", "experimental"]
        if !segments.isDisjoint(with: prohibitedSegments) {
            return false
        }

        return true
    }

    /// modelId が denylist を通過し、thinkingLevel が allowlist と完全一致する場合のみ有効とみなす。
    var isValid: Bool {
        Self.isModelAllowed(modelId) && Self.allowedThinkingLevels.contains(thinkingLevel)
    }
}
