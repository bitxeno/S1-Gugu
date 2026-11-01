import UIKit
import SQLiteData
import Kingfisher

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
        configureImagePipeline()
        return true
    }

    /// 全局图片管线:S1 图床/附件对请求头有校验,统一补 Referer;
    /// 弱网下自动重试两次,所有 Kingfisher 调用(大图/表情/头像)共用。
    private func configureImagePipeline() {
        KingfisherManager.shared.defaultOptions = [
            .requestModifier(S1ImageRequestModifier()),
            .retryStrategy(DelayRetryStrategy(maxRetryCount: 2, retryInterval: .seconds(1))),
        ]
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting sceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default", sessionRole: sceneSession.role)
    }
}
