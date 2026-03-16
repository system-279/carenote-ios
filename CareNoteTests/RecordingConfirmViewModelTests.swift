@testable import CareNote
import Foundation
import SwiftData
import Testing

@Suite("RecordingConfirmViewModel Tests")
struct RecordingConfirmViewModelTests {

    private static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: RecordingRecord.self, OutboxItem.self, ClientCache.self, OutputTemplate.self,
            configurations: config
        )
    }

    @Test @MainActor
    func loadTemplatesでプリセットが自動seedされる() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        let vm = RecordingConfirmViewModel(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            clientId: "c1",
            clientName: "テスト",
            scene: .visit,
            duration: 60,
            modelContext: context,
            tenantId: "t1"
        )

        // テンプレートが0件の状態でloadTemplatesを呼ぶ
        vm.loadTemplates()

        // プリセット4件がseedされて読み込まれる
        #expect(vm.templates.count == 4)
        #expect(vm.selectedTemplate != nil)
        #expect(vm.templates.allSatisfy { $0.isPreset })
    }

    @Test @MainActor
    func loadTemplatesで既存テンプレートがある場合は再seedしない() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        // 事前にseed
        PresetTemplates.seedIfNeeded(modelContext: context)

        let vm = RecordingConfirmViewModel(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            clientId: "c1",
            clientName: "テスト",
            scene: .visit,
            duration: 60,
            modelContext: context,
            tenantId: "t1"
        )

        vm.loadTemplates()

        // 4件のまま（重複seedされない）
        #expect(vm.templates.count == 4)
    }

    @Test @MainActor
    func loadTemplatesでプリセットが先頭にソートされる() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        // カスタムテンプレートを先に追加
        let custom = OutputTemplate(
            name: "カスタム1",
            prompt: "テスト",
            outputType: OutputType.custom.rawValue,
            isPreset: false
        )
        context.insert(custom)
        try context.save()

        let vm = RecordingConfirmViewModel(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            clientId: "c1",
            clientName: "テスト",
            scene: .visit,
            duration: 60,
            modelContext: context,
            tenantId: "t1"
        )

        vm.loadTemplates()

        // 4プリセット + 1カスタム = 5件
        #expect(vm.templates.count == 5)
        // プリセットが先頭
        #expect(vm.templates.first?.isPreset == true)
        // カスタムが末尾
        #expect(vm.templates.last?.isPreset == false)
        #expect(vm.templates.last?.name == "カスタム1")
    }

    @Test @MainActor
    func デフォルト選択は最初のプリセット() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        let vm = RecordingConfirmViewModel(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            clientId: "c1",
            clientName: "テスト",
            scene: .visit,
            duration: 60,
            modelContext: context,
            tenantId: "t1"
        )

        vm.loadTemplates()

        #expect(vm.selectedTemplate?.name == "文字起こし（デフォルト）")
    }
}
