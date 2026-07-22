@testable import CareNote
import Foundation
import Testing

// MARK: - Stub VertexAIConfigFetching

private actor StubVertexAIConfigFetcher: VertexAIConfigFetching {
    var configToReturn: VertexAIConfig?
    var errorToThrow: Error?

    func setConfig(_ config: VertexAIConfig?) {
        configToReturn = config
    }

    func setError(_ error: Error) {
        errorToThrow = error
    }

    func fetchVertexAIConfig() async throws -> VertexAIConfig? {
        if let errorToThrow {
            throw errorToThrow
        }
        return configToReturn
    }
}

private struct TestFetchError: Error {}

// MARK: - VertexAIConfigServiceTests

@Suite("VertexAIConfigService Tests")
struct VertexAIConfigServiceTests {

    @Test
    func 有効なconfigはそのまま採用される() async throws {
        let fetcher = StubVertexAIConfigFetcher()
        await fetcher.setConfig(VertexAIConfig(modelId: "gemini-3.5-flash", thinkingLevel: "minimal"))
        let service = VertexAIConfigService(configFetcher: fetcher)

        let resolved = await service.resolveConfig()

        #expect(resolved.modelId == "gemini-3.5-flash")
        #expect(resolved.thinkingLevel == "minimal")
    }

    @Test
    func denylist対象のmodelIdはデフォルトへフォールバックする() async throws {
        let fetcher = StubVertexAIConfigFetcher()
        await fetcher.setConfig(VertexAIConfig(modelId: "gemini-3-preview", thinkingLevel: "minimal"))
        let service = VertexAIConfigService(configFetcher: fetcher)

        let resolved = await service.resolveConfig()

        #expect(resolved == VertexAIConfig.default)
    }

    @Test
    func 未登録の将来モデル名はそのまま採用される() async throws {
        let fetcher = StubVertexAIConfigFetcher()
        await fetcher.setConfig(VertexAIConfig(modelId: "gemini-3.6-flash", thinkingLevel: "minimal"))
        let service = VertexAIConfigService(configFetcher: fetcher)

        let resolved = await service.resolveConfig()

        #expect(resolved.modelId == "gemini-3.6-flash")
    }

    @Test
    func 無印gemini3flashはデフォルトへフォールバックする() async throws {
        let fetcher = StubVertexAIConfigFetcher()
        await fetcher.setConfig(VertexAIConfig(modelId: "gemini-3-flash", thinkingLevel: "minimal"))
        let service = VertexAIConfigService(configFetcher: fetcher)

        let resolved = await service.resolveConfig()

        #expect(resolved == VertexAIConfig.default)
    }

    @Test
    func previewモデルはデフォルトへフォールバックする() async throws {
        let fetcher = StubVertexAIConfigFetcher()
        await fetcher.setConfig(VertexAIConfig(modelId: "gemini-3-pro-preview", thinkingLevel: "minimal"))
        let service = VertexAIConfigService(configFetcher: fetcher)

        let resolved = await service.resolveConfig()

        #expect(resolved == VertexAIConfig.default)
    }

    @Test
    func expモデルはデフォルトへフォールバックする() async throws {
        let fetcher = StubVertexAIConfigFetcher()
        await fetcher.setConfig(VertexAIConfig(modelId: "gemini-2.0-flash-exp", thinkingLevel: "minimal"))
        let service = VertexAIConfigService(configFetcher: fetcher)

        let resolved = await service.resolveConfig()

        #expect(resolved == VertexAIConfig.default)
    }

    @Test
    func minimal以外のthinkingLevelはデフォルトへフォールバックする() async throws {
        let fetcher = StubVertexAIConfigFetcher()
        await fetcher.setConfig(VertexAIConfig(modelId: "gemini-3.5-flash", thinkingLevel: "high"))
        let service = VertexAIConfigService(configFetcher: fetcher)

        let resolved = await service.resolveConfig()

        #expect(resolved == VertexAIConfig.default)
    }

    @Test
    func fetch失敗時は例外を伝播させずデフォルトへフォールバックする() async throws {
        let fetcher = StubVertexAIConfigFetcher()
        await fetcher.setError(TestFetchError())
        let service = VertexAIConfigService(configFetcher: fetcher)

        let resolved = await service.resolveConfig()

        #expect(resolved == VertexAIConfig.default)
    }

    @Test
    func ドキュメント未作成でnilが返る場合はデフォルトへフォールバックする() async throws {
        let fetcher = StubVertexAIConfigFetcher()
        await fetcher.setConfig(nil)
        let service = VertexAIConfigService(configFetcher: fetcher)

        let resolved = await service.resolveConfig()

        #expect(resolved == VertexAIConfig.default)
    }

    @Test
    func フィールド欠損configはデフォルトへフォールバックする() async throws {
        let fetcher = StubVertexAIConfigFetcher()
        await fetcher.setConfig(VertexAIConfig(modelId: "", thinkingLevel: ""))
        let service = VertexAIConfigService(configFetcher: fetcher)

        let resolved = await service.resolveConfig()

        #expect(resolved == VertexAIConfig.default)
    }
}
