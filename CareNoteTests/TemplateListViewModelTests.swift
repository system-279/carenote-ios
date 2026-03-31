@testable import CareNote
import Foundation
import SwiftData
import Testing

@Suite("TemplateListViewModel Tests")
struct TemplateListViewModelTests {

    private static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: RecordingRecord.self, OutboxItem.self, ClientCache.self, OutputTemplate.self,
            configurations: config
        )
    }

    // MARK: - loadTemplates

    @Test @MainActor
    func loadTemplatesでSwiftDataからテンプレートを読み込む() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        let t1 = OutputTemplate(name: "カスタム1", prompt: "p1", outputType: OutputType.custom.rawValue, isPreset: false)
        context.insert(t1)
        try context.save()

        let vm = TemplateListViewModel(
            modelContext: context,
            firestoreService: MockTemplateService()
        )
        vm.loadTemplates()

        #expect(vm.templates.count == 1)
        #expect(vm.customs.count == 1)
        #expect(vm.presets.count == 0)
    }

    @Test @MainActor
    func loadTemplatesでプリセットとカスタムが分類される() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        PresetTemplates.seedIfNeeded(modelContext: context)
        let custom = OutputTemplate(name: "カスタム", prompt: "p", outputType: OutputType.custom.rawValue, isPreset: false)
        context.insert(custom)
        try context.save()

        let vm = TemplateListViewModel(
            modelContext: context,
            firestoreService: MockTemplateService()
        )
        vm.loadTemplates()

        #expect(vm.presets.count == 4)
        #expect(vm.customs.count == 1)
    }

    // MARK: - loadTenantTemplates

    @Test @MainActor
    func tenantIdがnilの場合はテナントテンプレートをスキップ() async throws {
        let container = try Self.makeContainer()
        let mock = MockTemplateService()
        mock.fetchResult = [
            FirestoreTemplate(id: "1", name: "T", prompt: "P", outputType: .custom, createdBy: "u", createdByName: "U", createdAt: Date(), updatedAt: Date()),
        ]

        let vm = TemplateListViewModel(
            modelContext: container.mainContext,
            tenantId: nil,
            firestoreService: mock
        )

        await vm.loadTenantTemplates()

        #expect(vm.tenantTemplates.isEmpty)
    }

    @Test @MainActor
    func テナントテンプレート読み込み成功() async throws {
        let container = try Self.makeContainer()
        let mock = MockTemplateService()
        mock.fetchResult = [
            FirestoreTemplate(id: "1", name: "共有1", prompt: "P1", outputType: .custom, createdBy: "u1", createdByName: "User1", createdAt: Date(), updatedAt: Date()),
            FirestoreTemplate(id: "2", name: "共有2", prompt: "P2", outputType: .transcription, createdBy: "u2", createdByName: "User2", createdAt: Date(), updatedAt: Date()),
        ]

        let vm = TemplateListViewModel(
            modelContext: container.mainContext,
            tenantId: "tenant-1",
            firestoreService: mock
        )

        await vm.loadTenantTemplates()

        #expect(vm.tenantTemplates.count == 2)
        #expect(vm.errorMessage == nil)
    }

    @Test @MainActor
    func テナントテンプレート読み込み失敗でerrorMessage設定() async throws {
        let container = try Self.makeContainer()
        let mock = MockTemplateService()
        mock.fetchError = NSError(domain: "test", code: 1)

        let vm = TemplateListViewModel(
            modelContext: container.mainContext,
            tenantId: "tenant-1",
            firestoreService: mock
        )

        await vm.loadTenantTemplates()

        #expect(vm.tenantTemplates.isEmpty)
        #expect(vm.errorMessage != nil)
    }

    // MARK: - deleteTemplate

    @Test @MainActor
    func プリセットテンプレートは削除できない() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        PresetTemplates.seedIfNeeded(modelContext: context)
        let vm = TemplateListViewModel(
            modelContext: context,
            firestoreService: MockTemplateService()
        )
        vm.loadTemplates()
        let preset = vm.presets.first!

        vm.deleteTemplate(preset)

        vm.loadTemplates()
        #expect(vm.presets.count == 4)
    }

    @Test @MainActor
    func カスタムテンプレートを削除できる() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        let custom = OutputTemplate(name: "削除対象", prompt: "p", outputType: OutputType.custom.rawValue, isPreset: false)
        context.insert(custom)
        try context.save()

        let vm = TemplateListViewModel(
            modelContext: context,
            firestoreService: MockTemplateService()
        )
        vm.loadTemplates()
        #expect(vm.customs.count == 1)

        vm.deleteTemplate(vm.customs.first!)

        #expect(vm.templates.filter { !$0.isPreset }.isEmpty)
    }

    // MARK: - deleteTenantTemplate

    @Test @MainActor
    func admin権限ありでテナントテンプレート削除成功() async throws {
        let container = try Self.makeContainer()
        let mock = MockTemplateService()
        let tmpl = FirestoreTemplate(id: "tmpl-1", name: "共有", prompt: "P", outputType: .custom, createdBy: "u1", createdByName: "U1", createdAt: Date(), updatedAt: Date())

        let vm = TemplateListViewModel(
            modelContext: container.mainContext,
            tenantId: "tenant-1",
            isAdmin: true,
            firestoreService: mock
        )
        vm.tenantTemplates = [tmpl]

        await vm.deleteTenantTemplate(tmpl)

        #expect(vm.tenantTemplates.isEmpty)
        #expect(mock.deleteCalledWith?.templateId == "tmpl-1")
    }

    @Test @MainActor
    func admin権限なしではテナントテンプレート削除されない() async throws {
        let container = try Self.makeContainer()
        let mock = MockTemplateService()
        let tmpl = FirestoreTemplate(id: "tmpl-1", name: "共有", prompt: "P", outputType: .custom, createdBy: "u1", createdByName: "U1", createdAt: Date(), updatedAt: Date())

        let vm = TemplateListViewModel(
            modelContext: container.mainContext,
            tenantId: "tenant-1",
            isAdmin: false,
            firestoreService: mock
        )
        vm.tenantTemplates = [tmpl]

        await vm.deleteTenantTemplate(tmpl)

        #expect(vm.tenantTemplates.count == 1)
        #expect(mock.deleteCalledWith == nil)
    }

    @Test @MainActor
    func テナントテンプレート削除失敗でerrorMessage設定() async throws {
        let container = try Self.makeContainer()
        let mock = MockTemplateService()
        mock.deleteError = NSError(domain: "test", code: 1)
        let tmpl = FirestoreTemplate(id: "tmpl-1", name: "共有", prompt: "P", outputType: .custom, createdBy: "u1", createdByName: "U1", createdAt: Date(), updatedAt: Date())

        let vm = TemplateListViewModel(
            modelContext: container.mainContext,
            tenantId: "tenant-1",
            isAdmin: true,
            firestoreService: mock
        )
        vm.tenantTemplates = [tmpl]

        await vm.deleteTenantTemplate(tmpl)

        #expect(vm.tenantTemplates.count == 1)
        #expect(vm.errorMessage != nil)
    }

    // MARK: - OutputType Fallback

    @Test
    func 未知のoutputTypeはcustomにフォールバック() {
        let item = TemplateItem(from: OutputTemplate(
            name: "テスト",
            prompt: "p",
            outputType: "未知の値",
            isPreset: false
        ))
        #expect(item.outputType == .custom)
    }

    @Test
    func 既知のoutputTypeは正しくマッピング() {
        let item = TemplateItem(from: OutputTemplate(
            name: "テスト",
            prompt: "p",
            outputType: OutputType.transcription.rawValue,
            isPreset: false
        ))
        #expect(item.outputType == .transcription)
    }

    // MARK: - Legacy rawValue Fallback

    @Test
    func 旧日本語rawValueがfromLegacyで正しく変換される() {
        let item = TemplateItem(from: OutputTemplate(
            name: "テスト",
            prompt: "p",
            outputType: "文字起こし",
            isPreset: false
        ))
        #expect(item.outputType == .transcription)
    }

    @Test
    func 旧日本語rawValue全パターンが変換される() {
        let legacy: [(String, OutputType)] = [
            ("文字起こし", .transcription),
            ("訪問記録", .visitRecord),
            ("会議録", .meetingMinutes),
            ("要約", .summary),
            ("カスタム", .custom),
        ]
        for (raw, expected) in legacy {
            let item = TemplateItem(from: OutputTemplate(
                name: "テスト",
                prompt: "p",
                outputType: raw,
                isPreset: false
            ))
            #expect(item.outputType == expected, "Legacy '\(raw)' should map to \(expected)")
        }
    }
}
