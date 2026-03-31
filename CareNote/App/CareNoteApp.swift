import FirebaseAuth
import FirebaseCore
import SwiftData
import SwiftUI

// MARK: - CareNoteApp

@main
struct CareNoteApp: App {
    @State private var authViewModel = AuthViewModel()

    let modelContainer: ModelContainer

    init() {
        if !CareNoteApp.isRunningTests {
            FirebaseApp.configure()
            Self.migrateToProIfNeeded()
        }

        let schema = Schema([
            RecordingRecord.self,
            ClientCache.self,
            OutboxItem.self,
            OutputTemplate.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("ModelContainer の初期化に失敗しました: \(error)")
        }
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    /// Dev→Prod移行: 古いFirebase Authセッション(Keychain)をクリアして再認証を強制する
    /// UserDefaultsのフラグで一度だけ実行される
    // TODO: 全TestFlightユーザーが更新完了後に削除する (added 2026-03-30)
    private static func migrateToProIfNeeded() {
        let key = "didMigrateToProd_v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        do {
            try Auth.auth().signOut()
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            // signOut失敗時はフラグを立てず次回起動で再試行
        }
    }

    /// OutputType/RecordingScene の旧日本語rawValueを英語識別子に一括変換
    private static func migrateEnumRawValues(context: ModelContext) {
        let key = "didMigrateEnumRawValues_v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        do {
            let recordings = try context.fetch(FetchDescriptor<RecordingRecord>())
            for record in recordings {
                if let old = record.outputType, let newType = OutputType.fromLegacy(old) {
                    record.outputType = newType.rawValue
                }
                if let newScene = RecordingScene.fromLegacy(record.scene) {
                    record.scene = newScene.rawValue
                }
            }

            let templates = try context.fetch(FetchDescriptor<OutputTemplate>())
            for template in templates {
                if let newType = OutputType.fromLegacy(template.outputType) {
                    template.outputType = newType.rawValue
                }
            }

            try context.save()
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            // マイグレーション失敗時はフラグを立てず次回起動で再試行
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch authViewModel.authState {
                case .signedOut:
                    SignInView(viewModel: authViewModel)
                case .signedIn(_, let tenantId, _):
                    MainTabView(tenantId: tenantId)
                        .task {
                            let cacheService = ClientCacheService(
                                firestoreService: FirestoreService(),
                                modelContainer: modelContainer
                            )
                            try? await cacheService.refreshIfNeeded(tenantId: tenantId)
                        }
                }
            }
            .onAppear {
                authViewModel.checkAuthState()
                Self.migrateEnumRawValues(context: modelContainer.mainContext)
                PresetTemplates.seedIfNeeded(modelContext: modelContainer.mainContext)
            }
            .environment(authViewModel)
        }
        .modelContainer(modelContainer)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let navigateToRecordingList = Notification.Name("navigateToRecordingList")
}

// MARK: - MainTabView

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext

    let tenantId: String

    @State private var selectedTab = 0
    @State private var recordingNavigationId = UUID()
    @State private var recordingListViewModel: RecordingListViewModel?

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                if let viewModel = recordingListViewModel {
                    RecordingListView(viewModel: viewModel)
                }
            }
            .task {
                if recordingListViewModel == nil {
                    recordingListViewModel = RecordingListViewModel(
                        recordingRepository: RecordingRepository(modelContext: modelContext),
                        firestoreService: FirestoreService(),
                        tenantId: tenantId
                    )
                }
            }
            .tabItem {
                Label("ホーム", systemImage: "list.bullet")
            }
            .tag(0)

            NavigationStack {
                NewRecordingNavigationView()
            }
            .id(recordingNavigationId)
            .tabItem {
                Label("新規録音", systemImage: "mic.circle.fill")
            }
            .tag(1)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("設定", systemImage: "gearshape")
            }
            .tag(2)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToRecordingList)) { _ in
            selectedTab = 0
            recordingNavigationId = UUID()
        }
    }
}

// MARK: - NewRecordingNavigationView

struct NewRecordingNavigationView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ClientSelectView(
            viewModel: ClientSelectViewModel(
                clientRepository: ClientRepository(modelContext: modelContext)
            )
        )
        .navigationDestination(for: ClientCache.self) { client in
            SceneSelectView(
                viewModel: SceneSelectViewModel(selectedClient: client)
            )
        }
    }
}
