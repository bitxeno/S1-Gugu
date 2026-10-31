import UIKit
import Kingfisher
import Photos

/// 图片画廊:翻页 + 双指缩放 + 保存相册/复制链接。
@MainActor
final class GalleryViewController: UIViewController {

    private let images: [PostImage]
    private var startIndex: Int

    private var pageController: UIPageViewController!
    private let pageIndicator = UILabel()

    init(images: [PostImage], startIndex: Int) {
        self.images = images
        self.startIndex = max(0, min(startIndex, images.count - 1))
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        pageController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
        pageController.dataSource = self
        pageController.delegate = self
        addChild(pageController)
        view.addSubview(pageController.view)
        pageController.didMove(toParent: self)
        if let first = zoomController(at: startIndex) {
            pageController.setViewControllers([first], direction: .forward, animated: false)
        }

        pageIndicator.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        pageIndicator.textColor = .white
        pageIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageIndicator)

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.accessibilityLabel = "关闭"
        closeButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: false) }, for: .touchUpInside)

        let saveButton = UIButton(type: .system)
        saveButton.setImage(UIImage(systemName: "square.and.arrow.down"), for: .normal)
        saveButton.tintColor = .white
        saveButton.accessibilityLabel = "保存到相册"
        saveButton.addAction(UIAction { [weak self] _ in self?.saveCurrentImage() }, for: .touchUpInside)

        let shareButton = UIButton(type: .system)
        shareButton.setImage(UIImage(systemName: "link"), for: .normal)
        shareButton.tintColor = .white
        shareButton.accessibilityLabel = "复制图片链接"
        shareButton.addAction(UIAction { [weak self] _ in self?.copyLink() }, for: .touchUpInside)

        let topBar = UIStackView(arrangedSubviews: [closeButton, UIView(), shareButton, saveButton])
        topBar.axis = .horizontal
        topBar.spacing = 20
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            topBar.heightAnchor.constraint(equalToConstant: 36),
            pageIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageIndicator.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
        updateIndicator()
    }

    private func zoomController(at index: Int) -> ZoomImageViewController? {
        guard images.indices.contains(index) else { return nil }
        let controller = ZoomImageViewController(image: images[index])
        controller.index = index
        return controller
    }

    private func updateIndicator() {
        pageIndicator.text = "\(startIndex + 1) / \(images.count)"
    }

    private func saveCurrentImage() {
        let url = images[startIndex].url
        KingfisherManager.shared.retrieveImage(with: url) { [weak self] result in
            guard let self, let image = try? result.get().image else {
                DispatchQueue.main.async {
                    Toast.show("图片下载失败", in: self?.view ?? UIView())
                }
                return
            }
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                DispatchQueue.main.async {
                    guard status == .authorized || status == .limited else {
                        Toast.show("没有相册权限", in: self.view ?? UIView())
                        return
                    }
                    PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAsset(from: image)
                    } completionHandler: { success, _ in
                        DispatchQueue.main.async {
                            Toast.show(success ? "已保存到相册" : "保存失败", in: self.view ?? UIView())
                        }
                    }
                }
            }
        }
    }

    private func copyLink() {
        UIPasteboard.general.string = images[startIndex].url.absoluteString
        Toast.show("已复制图片链接", in: view)
    }
}

extension GalleryViewController: UIPageViewControllerDataSource, UIPageViewControllerDelegate {

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let zoom = viewController as? ZoomImageViewController, zoom.index > 0 else { return nil }
        return zoomController(at: zoom.index - 1)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let zoom = viewController as? ZoomImageViewController, zoom.index < images.count - 1 else { return nil }
        return zoomController(at: zoom.index + 1)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed,
              let current = pageViewController.viewControllers?.first as? ZoomImageViewController
        else { return }
        startIndex = current.index
        updateIndicator()
    }
}

/// 单张大图,UIScrollView 缩放。
@MainActor
final class ZoomImageViewController: UIViewController, UIScrollViewDelegate {

    let imageInfo: PostImage
    var index: Int = 0

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let activity = UIActivityIndicatorView(style: .large)

    init(image: PostImage) {
        self.imageInfo = image
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false

        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissGallery)))

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        imageView.addGestureRecognizer(doubleTap)

        activity.hidesWhenStopped = true
        activity.startAnimating()

        view.addSubview(scrollView)
        scrollView.addSubview(imageView)
        view.addSubview(activity)
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        activity.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        activity.center = view.center
        activity.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]

        KingfisherManager.shared.retrieveImage(with: imageInfo.url) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.activity.stopAnimating()
                guard let image = try? result.get().image else {
                    self.imageView.image = UIImage(systemName: "photo")
                    self.imageView.tintColor = .secondaryLabel
                    return
                }
                self.imageView.image = image
                self.layoutImage()
            }
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        layoutImage()
    }

    private func layoutImage() {
        guard let image = imageView.image else { return }
        let bounds = scrollView.bounds
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.zoomScale = 1

        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        imageView.frame = CGRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
        scrollView.contentSize = bounds.size
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        let size = imageView.frame.size
        let bounds = scrollView.bounds
        imageView.frame.origin = CGPoint(
            x: max((bounds.width - size.width) / 2, 0),
            y: max((bounds.height - size.height) / 2, 0)
        )
    }

    @objc private func doubleTapped(_ recognizer: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let point = recognizer.location(in: imageView)
            let rect = CGRect(x: point.x - 60, y: point.y - 60, width: 120, height: 120)
            scrollView.zoom(to: rect, animated: true)
        }
    }

    @objc private func dismissGallery() {
        presentingViewController?.dismiss(animated: false)
    }
}
