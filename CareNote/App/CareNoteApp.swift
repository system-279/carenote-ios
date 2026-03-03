import FirebaseCore
import SwiftData
import SwiftUI

// MARK: - CareNoteApp

@main
struct CareNoteApp: App {
    @State private var authViewModel = AuthViewModel()

    let modelContainer: ModelContainer

    init() {
        FirebaseApp.configure()

        let schema = Schema([
            RecordingRecord.self,
            ClientCache.self,
            OutboxItem.self,
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

    var body: some Scene {
        WindowGroup {
            Group {
                switch authViewModel.authState {
                case .signedOut:
                    SignInView(viewModel: authViewModel)
                case .signedIn:
                    MainTabView()
                }
            }
            .onAppear {
                authViewModel.checkAuthState()
            }
        }
        .modelContainer(modelContainer)
    }
}

// MARK: - MainTabView

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            NavigationStack {
                RecordingListView(
                    viewModel: RecordingListViewModel(
                        recordingRepository: RecordingRepository(modelContext: modelContext)
                    )
                )
            }
            .tabItem {
                Label("ホーム", systemImage: "list.bullet")
            }

            NavigationStack {
                NewRecordingNavigationView()
            }
            .tabItem {
                Label("新規録音", systemImage: "mic.circle.fill")
            }
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
