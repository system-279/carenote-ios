import Foundation
import os.log
import SwiftData

// MARK: - PresetTemplates

enum PresetTemplates {
    static let all: [(name: String, prompt: String, outputType: OutputType)] = [
        (
            name: "文字起こし（デフォルト）",
            prompt: """
                以下の音声を日本語で文字起こししてください。

                指示:
                - 句読点（。、）を適切に付与してください
                - 「えー」「あのー」などのフィラー（つなぎ言葉）は省略してください
                - 介護用語は正確に記載してください（例: 要介護度、ADL、IADL、ケアプラン、サービス担当者会議 等）
                - 話者の区別がつく場合は話者を明示してください
                - 音声が不明瞭な箇所は [不明瞭] と記載してください
                """,
            outputType: .transcription
        ),
        (
            name: "訪問記録",
            prompt: """
                以下の音声から訪問記録を作成してください。

                出力形式:
                【訪問日時】（音声内容から推定）
                【利用者の状態】
                - バイタル・体調の変化
                - 精神面・表情・意欲
                【実施内容】
                - 実施したケア・支援の内容
                【特記事項】
                - 家族からの伝達事項
                - 環境変化
                - ヒヤリハット
                【次回訪問時の留意点】

                指示:
                - 介護用語は正確に記載してください
                - 客観的な事実と主観的な所見を区別してください
                - 音声が不明瞭な箇所は [不明瞭] と記載してください
                """,
            outputType: .visitRecord
        ),
        (
            name: "会議録",
            prompt: """
                以下の音声から会議録を作成してください。

                出力形式:
                【議題】
                【出席者】（音声から判別できる範囲）
                【協議内容】
                1. （議題ごとに整理）
                   - 発言要旨
                   - 決定事項
                【今後の対応】
                - 担当者・期限を含めて記載
                【次回予定】

                指示:
                - 発言者が区別できる場合は明示してください
                - 決定事項と検討事項を明確に区別してください
                - 介護用語は正確に記載してください
                - 音声が不明瞭な箇所は [不明瞭] と記載してください
                """,
            outputType: .meetingMinutes
        ),
        (
            name: "要約",
            prompt: """
                以下の音声の内容を要約してください。

                出力形式:
                【要約】（3〜5文で全体をまとめる）
                【重要ポイント】
                - 箇条書きで要点を列挙
                【アクションアイテム】
                - 対応が必要な事項を列挙

                指示:
                - 簡潔かつ正確に要約してください
                - 介護用語は正確に記載してください
                - 音声が不明瞭な箇所は [不明瞭] と記載してください
                """,
            outputType: .summary
        ),
    ]

    private static let logger = Logger(subsystem: "jp.carenote.app", category: "PresetTemplates")

    /// プリセットテンプレートを ModelContext に挿入する（既に存在する場合はスキップ）
    @MainActor
    static func seedIfNeeded(modelContext: ModelContext) {
        logger.info("seedIfNeeded called")

        let descriptor = FetchDescriptor<OutputTemplate>(
            predicate: #Predicate<OutputTemplate> { $0.isPreset }
        )

        var existingCount = 0
        do {
            existingCount = try modelContext.fetchCount(descriptor)
        } catch {
            logger.error("fetchCount failed: \(error.localizedDescription)")
            existingCount = -1
        }

        logger.info("Existing preset count: \(existingCount)")
        guard existingCount == 0 || existingCount == -1 else { return }

        for preset in all {
            let template = OutputTemplate(
                name: preset.name,
                prompt: preset.prompt,
                outputType: preset.outputType.rawValue,
                isPreset: true
            )
            modelContext.insert(template)
        }

        do {
            try modelContext.save()
            logger.info("Seeded \(self.all.count) preset templates successfully")
        } catch {
            logger.error("Failed to save seeded templates: \(error.localizedDescription)")
        }
    }
}
