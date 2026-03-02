import Foundation
import Observation

// MARK: - SceneSelectViewModel

@Observable
final class SceneSelectViewModel {
    let selectedClient: ClientCache
    let scenes: [RecordingScene] = RecordingScene.allCases

    init(selectedClient: ClientCache) {
        self.selectedClient = selectedClient
    }
}
