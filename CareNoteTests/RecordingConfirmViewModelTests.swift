@testable import CareNote
import Foundation
import SwiftData
import Testing

@Suite("RecordingConfirmViewModel Tests", .serialized)
struct RecordingConfirmViewModelTests {

    // tenantId を空にしてFirestore呼び出しをスキップ（テスト環境ではFirebaseApp未初期化）
    @Test @MainActor
    func loadTemplatesでプリセットが自動seedされる() async throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext

        let vm = RecordingConfirmViewModel(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            clientId: "c1",
            clientName: "テスト",
            scene: .visit,
            duration: 60,
            modelContext: context,
            tenantId: ""
        )

        await vm.loadTemplates()

        let presets = vm.templateItems.filter { $0.source == .preset }
        #expect(presets.count == 4)
        #expect(vm.selectedItem != nil)
    }

    @Test @MainActor
    func loadTemplatesで既存テンプレートがある場合は再seedしない() async throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext

        PresetTemplates.seedIfNeeded(modelContext: context)

        let vm = RecordingConfirmViewModel(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            clientId: "c1",
            clientName: "テスト",
            scene: .visit,
            duration: 60,
            modelContext: context,
            tenantId: ""
        )

        await vm.loadTemplates()

        let presets = vm.templateItems.filter { $0.source == .preset }
        #expect(presets.count == 4)
    }

    @Test @MainActor
    func loadTemplatesでプリセットが先頭にソートされる() async throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext

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
            tenantId: ""
        )

        await vm.loadTemplates()

        #expect(vm.templateItems.count >= 5)
        #expect(vm.templateItems.first?.source == .preset)
    }

    @Test @MainActor
    func デフォルト選択は最初のプリセット() async throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext

        let vm = RecordingConfirmViewModel(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            clientId: "c1",
            clientName: "テスト",
            scene: .visit,
            duration: 60,
            modelContext: context,
            tenantId: ""
        )

        await vm.loadTemplates()

        #expect(vm.selectedItem?.name == "文字起こし（デフォルト）")
    }

    @Test @MainActor
    func テナントテンプレート取得失敗時にerrorMessageが設定されプリセットは残る() async throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let mock = MockTemplateService()
        mock.fetchError = NSError(domain: "test", code: 1)

        let vm = RecordingConfirmViewModel(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            clientId: "c1",
            clientName: "テスト",
            scene: .visit,
            duration: 60,
            modelContext: context,
            tenantId: "tenant-1",
            firestoreService: mock
        )

        await vm.loadTemplates()

        #expect(vm.errorMessage?.contains("共有テンプレートの読み込みに失敗しました") == true)
        let presets = vm.templateItems.filter { $0.source == .preset }
        #expect(presets.count == 4)
        let tenantItems = vm.templateItems.filter { $0.source == .tenant }
        #expect(tenantItems.isEmpty)
    }
}
