@testable import CareNote
import Foundation
import SwiftData
import Testing

// MARK: - TemplateCreateViewModelTests

@Suite("TemplateCreateViewModel Tests", .serialized)
struct TemplateCreateViewModelTests {

    // MARK: - Validation

    @Test @MainActor
    func 空の名前ではisValidがfalse() throws {
        let container = try makeTestModelContainer()
        let vm = TemplateCreateViewModel(
            modelContext: container.mainContext,
            firestoreService: MockTemplateService()
        )
        vm.name = ""
        vm.prompt = "テストプロンプト"
        #expect(vm.isValid == false)
    }

    @Test @MainActor
    func 空のプロンプトではisValidがfalse() throws {
        let container = try makeTestModelContainer()
        let vm = TemplateCreateViewModel(
            modelContext: container.mainContext,
            firestoreService: MockTemplateService()
        )
        vm.name = "テスト"
        vm.prompt = ""
        #expect(vm.isValid == false)
    }

    @Test @MainActor
    func 空白のみの名前ではisValidがfalse() throws {
        let container = try makeTestModelContainer()
        let vm = TemplateCreateViewModel(
            modelContext: container.mainContext,
            firestoreService: MockTemplateService()
        )
        vm.name = "   "
        vm.prompt = "テストプロンプト"
        #expect(vm.isValid == false)
    }

    @Test @MainActor
    func 名前とプロンプト両方あればisValidがtrue() throws {
        let container = try makeTestModelContainer()
        let vm = TemplateCreateViewModel(
            modelContext: container.mainContext,
            firestoreService: MockTemplateService()
        )
        vm.name = "テスト"
        vm.prompt = "テストプロンプト"
        #expect(vm.isValid == true)
    }

    // MARK: - canSelectTenantScope

    @Test @MainActor
    func admin権限とtenantIdがあればテナントスコープ選択可能() throws {
        let container = try makeTestModelContainer()
        let vm = TemplateCreateViewModel(
            modelContext: container.mainContext,
            tenantId: "tenant-1",
            isAdmin: true,
            firestoreService: MockTemplateService()
        )
        #expect(vm.canSelectTenantScope == true)
    }

    @Test @MainActor
    func admin権限なしではテナントスコープ選択不可() throws {
        let container = try makeTestModelContainer()
        let vm = TemplateCreateViewModel(
            modelContext: container.mainContext,
            tenantId: "tenant-1",
            isAdmin: false,
            firestoreService: MockTemplateService()
        )
        #expect(vm.canSelectTenantScope == false)
    }

    @Test @MainActor
    func tenantIdなしではテナントスコープ選択不可() throws {
        let container = try makeTestModelContainer()
        let vm = TemplateCreateViewModel(
            modelContext: container.mainContext,
            tenantId: nil,
            isAdmin: true,
            firestoreService: MockTemplateService()
        )
        #expect(vm.canSelectTenantScope == false)
    }

    // MARK: - Save (Personal)

    @Test @MainActor
    func 個人テンプレートの保存がSwiftDataに保存される() async throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let vm = TemplateCreateViewModel(
            modelContext: context,
            firestoreService: MockTemplateService()
        )
        vm.name = "個人テンプレ"
        vm.prompt = "テストプロンプト"
        vm.scope = .personal

        let result = await vm.save()

        #expect(result == true)
        let fetched = try context.fetch(FetchDescriptor<OutputTemplate>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "個人テンプレ")
        #expect(fetched.first?.isPreset == false)
    }

    // MARK: - Save (Tenant)

    @Test @MainActor
    func テナントテンプレートの保存がFirestoreServiceを呼ぶ() async throws {
        let container = try makeTestModelContainer()
        let mock = MockTemplateService()
        let vm = TemplateCreateViewModel(
            modelContext: container.mainContext,
            tenantId: "tenant-1",
            isAdmin: true,
            userId: "user-1",
            userName: "テストユーザー",
            firestoreService: mock
        )
        vm.name = "共有テンプレ"
        vm.prompt = "共有プロンプト"
        vm.scope = .tenant

        let result = await vm.save()

        #expect(result == true)
        #expect(mock.createCalledWith?.tenantId == "tenant-1")
        #expect(mock.createCalledWith?.name == "共有テンプレ")
        #expect(mock.createCalledWith?.createdBy == "user-1")
    }

    @Test @MainActor
    func テナント保存でuserIdがnilの場合はエラー() async throws {
        let container = try makeTestModelContainer()
        let mock = MockTemplateService()
        let vm = TemplateCreateViewModel(
            modelContext: container.mainContext,
            tenantId: "tenant-1",
            isAdmin: true,
            userId: nil,
            firestoreService: mock
        )
        vm.name = "共有テンプレ"
        vm.prompt = "共有プロンプト"
        vm.scope = .tenant

        let result = await vm.save()

        #expect(result == false)
        #expect(vm.errorMessage != nil)
        #expect(mock.createCalledWith == nil)
    }

    @Test @MainActor
    func テナント保存でFirestore失敗時にerrorMessage設定() async throws {
        let container = try makeTestModelContainer()
        let mock = MockTemplateService()
        mock.createError = NSError(domain: "test", code: 1)
        let vm = TemplateCreateViewModel(
            modelContext: container.mainContext,
            tenantId: "tenant-1",
            isAdmin: true,
            userId: "user-1",
            firestoreService: mock
        )
        vm.name = "共有テンプレ"
        vm.prompt = "共有プロンプト"
        vm.scope = .tenant

        let result = await vm.save()

        #expect(result == false)
        #expect(vm.errorMessage?.contains("共有テンプレートの保存に失敗しました") == true)
    }

    // MARK: - Save (Tenant Update)

    @Test @MainActor
    func テナントテンプレートの編集でupdateが呼ばれる() async throws {
        let container = try makeTestModelContainer()
        let mock = MockTemplateService()
        let existing = FirestoreTemplate(
            id: "tmpl-1",
            name: "既存",
            prompt: "既存プロンプト",
            outputType: .custom,
            createdBy: "user-1",
            createdByName: "テスト",
            createdAt: Date(),
            updatedAt: Date()
        )
        let vm = TemplateCreateViewModel(
            modelContext: container.mainContext,
            tenantId: "tenant-1",
            isAdmin: true,
            userId: "user-1",
            firestoreService: mock,
            editingTemplate: existing
        )
        vm.name = "更新後"
        vm.prompt = "更新プロンプト"

        #expect(vm.isEditing == true)

        let result = await vm.save()

        #expect(result == true)
        #expect(mock.updateCalledWith?.templateId == "tmpl-1")
        #expect(mock.updateCalledWith?.name == "更新後")
    }

    @Test @MainActor
    func テナントテンプレート更新でFirestore失敗時にerrorMessage設定() async throws {
        let container = try makeTestModelContainer()
        let mock = MockTemplateService()
        mock.updateError = NSError(domain: "test", code: 500)
        let existing = FirestoreTemplate(
            id: "tmpl-1", name: "既存", prompt: "既存P",
            outputType: .custom,
            createdBy: "u1", createdByName: "User", createdAt: Date(), updatedAt: Date()
        )
        let vm = TemplateCreateViewModel(
            modelContext: container.mainContext,
            tenantId: "tenant-1",
            isAdmin: true,
            userId: "user-1",
            firestoreService: mock,
            editingTemplate: existing
        )
        vm.name = "更新後"
        vm.prompt = "更新P"

        let result = await vm.save()

        #expect(result == false)
        #expect(vm.errorMessage?.contains("共有テンプレートの保存に失敗しました") == true)
    }

    // MARK: - Validation failure

    @Test @MainActor
    func バリデーション失敗時にerrorMessage設定() async throws {
        let container = try makeTestModelContainer()
        let vm = TemplateCreateViewModel(
            modelContext: container.mainContext,
            firestoreService: MockTemplateService()
        )
        vm.name = ""
        vm.prompt = ""

        let result = await vm.save()

        #expect(result == false)
        #expect(vm.errorMessage == "名前とプロンプトを入力してください")
    }
}
