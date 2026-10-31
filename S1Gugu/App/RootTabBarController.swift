import UIKit

@MainActor
final class RootTabBarController: UITabBarController {

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        viewControllers = [
            themedNavigation(
                ForumGroupsViewController(),
                title: "论坛",
                image: UIImage(systemName: "square.grid.2x2.fill")
            ),
            themedNavigation(
                FavoritesViewController(),
                title: "收藏",
                image: UIImage(systemName: "star.fill")
            ),
            themedNavigation(
                MessagesViewController(),
                title: "消息",
                image: UIImage(systemName: "envelope.fill")
            ),
            themedNavigation(
                MeViewController(),
                title: "我的",
                image: UIImage(systemName: "person.crop.circle.fill")
            ),
        ]
    }

    private func themedNavigation(
        _ root: UIViewController,
        title: String,
        image: UIImage?
    ) -> UINavigationController {
        root.title = title
        let nav = UINavigationController(rootViewController: root)
        nav.tabBarItem = UITabBarItem(title: title, image: image, selectedImage: image)
        return nav
    }
}

extension RootTabBarController: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        true
    }
}
