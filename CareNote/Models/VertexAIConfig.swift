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
    /// 拒否対象は (a) 文字種・長さが不正な値（`TranscriptionService` の URL 組み立てで
    /// force-unwrap クラッシュを起こすため）、(b) 無印「Gemini 3 Flash」ベースモデル
    /// (`gemini-3-flash` / `gemini-3.0-flash` とそれぞれの `-` 付き派生。`gemini-3.5-flash`
    /// 等マイナーバージョン付きは対象外)、(c) preview/experimental系のみ。
    static func isModelAllowed(_ modelId: String) -> Bool {
        let lower = modelId.lowercased()
        guard !lower.isEmpty, lower.count <= 64 else { return false }

        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        guard lower.unicodeScalars.allSatisfy(allowedCharacters.contains) else { return false }
        guard let first = lower.first, first.isASCII, first.isLetter || first.isNumber else { return false }

        let bareFlashPatterns = ["gemini-3-flash", "gemini-3.0-flash"]
        if bareFlashPatterns.contains(where: { lower == $0 || lower.hasPrefix("\($0)-") }) {
            return false
        }

        return !lower.split(separator: "-").contains(where: isProhibitedSegment)
    }

    /// ハイフン区切りの1セグメント単位で preview/experimental 系かどうかを判定する。
    /// "preview" は部分一致（`gemini-3-flashpreview` や `preview001` のような
    /// ハイフン省略・サフィックス付きのバイパスも拒否するため）、"exp" は完全一致または
    /// 「exp」の直後が英字ではない場合のみ拒否（`expansion` 等の偶発一致を誤検知しないため）。
    private static func isProhibitedSegment(_ segment: Substring) -> Bool {
        if segment.contains("preview") || segment == "experimental" || segment == "exp" {
            return true
        }
        if segment.hasPrefix("exp") {
            let rest = segment.dropFirst(3)
            return rest.first.map { !$0.isLetter } ?? true
        }
        return false
    }

    /// modelId が denylist を通過し、thinkingLevel が allowlist と完全一致する場合のみ有効とみなす。
    var isValid: Bool {
        Self.isModelAllowed(modelId) && Self.allowedThinkingLevels.contains(thinkingLevel)
    }
}
