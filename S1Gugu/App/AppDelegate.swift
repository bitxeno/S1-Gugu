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

    /// 图片磁盘缓存上限(字节)。Kingfisher 默认 0 = 不限制,长期刷帖会无限增长。
    static let imageDiskCacheSizeLimit: UInt = 500 * 1024 * 1024

    /// 全局图片管线:S1 图床/附件对请求头有校验,统一补 Referer;
    /// 弱网下自动重试两次,所有 Kingfisher 调用(大图/表情/头像)共用。
    private func configureImagePipeline() {
        KingfisherManager.shared.defaultOptions = [
            .requestModifier(S1ImageRequestModifier()),
            .retryStrategy(DelayRetryStrategy(maxRetryCount: 2, retryInterval: .seconds(1))),
        ]

        // 限制磁盘缓存为 500MB。Kingfisher 只在进入后台/终止时裁剪,且超限会直接
        // 裁到上限的一半,所以这里先设上限,启动时再主动清理一次,避免老缓存继续堆积。
        ImageCache.default.diskStorage.config.sizeLimit = Self.imageDiskCacheSizeLimit
        ImageCache.default.cleanExpiredDiskCache()
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting sceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default", sessionRole: sceneSession.role)
    }
}
