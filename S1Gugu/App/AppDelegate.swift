import UIKit
import SQLiteData

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    override init() {
        super.init()
        prepareDependencies { dependencies in
            dependencies.defaultDatabase = AppDatabase.shared.writer
        }
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppSettings.registerDefaults()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
    }
}
