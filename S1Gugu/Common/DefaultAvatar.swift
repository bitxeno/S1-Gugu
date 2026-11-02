import UIKit

/// 未设置头像时的默认头像。
///
/// 服务端 `avatar.stage1st.com` 对没有自定义头像的用户返回 `noavatar.svg`,而 Kingfisher
/// 不支持解码 SVG,直接请求会失败,头像会停在占位符号上。这里提供打包好的位图(由
/// `noavatar.svg` 渲染)作为占位与加载失败时的兜底,保证视觉上与站点默认头像一致。
enum DefaultAvatar {

    /// 站点默认头像地址(原始 SVG,Kingfisher 无法解码,仅供需要原始资源的场景引用)。
    static let remoteURL = URL(string: "https://avatar.stage1st.com/noavatar.svg")!

    /// 打包进 App 的默认头像位图。
    static var image: UIImage {
        UIImage(named: "DefaultAvatar") ?? UIImage(systemName: "person.crop.circle.fill")!
    }
}
