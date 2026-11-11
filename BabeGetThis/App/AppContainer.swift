import Foundation
import Observation

/// Composition root. Builds every long-lived dependency once and hands it to
/// the views. No DI framework: add properties here as features land.
@Observable
@MainActor
final class AppContainer {
    let config: AppConfig

    init(config: AppConfig) {
        self.config = config
    }

    static func live(bundle: Bundle = .main) -> AppContainer {
        do {
            return AppContainer(config: try AppConfig(infoDictionary: bundle.infoDictionary ?? [:]))
        } catch {
            fatalError("Invalid app configuration: \(error)")
        }
    }
}
