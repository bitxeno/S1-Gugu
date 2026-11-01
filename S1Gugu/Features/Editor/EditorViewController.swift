import UIKit
import PhotosUI
import SnapKit
import Kingfisher

/// 发帖编辑器基类:正文 TextView + 表情面板(inputView)+ 图片上传 + 草稿。
/// 子类实现 `loadEditorContext()` 与 `performSend()`。
@MainActor
class EditorViewController: UIViewController, UITextViewDelegate {

    let textView = UITextView()
    let subjectField = UITextField()
    private let bottomBar = UIStackView()
    private let emojiButton = UIButton(type: .system)
    private let photoButton = UIButton(type: .system)
    let statusLabel = UILabel()

    private var emojiPanel: UIView?
    private var selectedEmojiGroupIndex = 0

    /// 编辑器上下文(子类加载后赋值;含 formhash/posttime/上传信息)
    var editorInfo: PostEditorInfo?
    /// 已上传附件 aid 列表
    private(set) var attachmentAids: [Int] = []
    private var isUploading = false
    private var isSending = false

    /// 草稿 key(nil 则不存草稿,如编辑模式)
    var draftKey: String?

    /// 正文是否允许为空(编辑/新主题必须非空)
    var allowsEmptyBody = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.contentBackground
        buildUI()
        loadDraft()
        Task {
            await loadEditorContext()
        }
    }

    // MARK: - UI

    private func buildUI() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(primaryAction: UIAction(title: "发送", image: UIImage(systemName: "paperplane")) { [weak self] _ in
            self?.sendTapped()
        })

        subjectField.placeholder = "标题"
        subjectField.borderStyle = .roundedRect
        subjectField.font = .preferredFont(forTextStyle: .body)
        subjectField.adjustsFontForContentSizeCategory = true
        subjectField.isHidden = true // 子类按需显示

        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.delegate = self
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

        emojiButton.setImage(UIImage(systemName: "face.smiling"), for: .normal)
        emojiButton.accessibilityLabel = "表情"
        emojiButton.addAction(UIAction { [weak self] _ in self?.toggleEmojiPanel() }, for: .touchUpInside)

        photoButton.setImage(UIImage(systemName: "photo.badge.plus"), for: .normal)
        photoButton.accessibilityLabel = "插入图片"
        photoButton.addAction(UIAction { [weak self] _ in self?.showPhotoPicker() }, for: .touchUpInside)

        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.textColor = Theme.tertiaryLabel
        statusLabel.textAlignment = .right

        bottomBar.axis = .horizontal
        bottomBar.spacing = 24
        bottomBar.alignment = .center
        bottomBar.layoutMargins = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        bottomBar.isLayoutMarginsRelativeArrangement = true
        bottomBar.addArrangedSubview(emojiButton)
        bottomBar.addArrangedSubview(photoButton)
        bottomBar.addArrangedSubview(statusLabel)

        let stack = UIStackView(arrangedSubviews: [subjectField, textView, UIView(), bottomBar])
        stack.axis = .vertical
        stack.spacing = 8
        view.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }
        textView.snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(view.bounds.height * 0.45)
        }
    }

    private func buildEmojiPanel() -> UIView {
        let panel = UIInputView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 260), inputViewStyle: .keyboard)
        panel.allowsSelfSizing = false

        let segmented = UISegmentedControl(items: SmileyCatalog.groups.map(\.title))
        segmented.selectedSegmentIndex = 0
        segmented.addAction(UIAction { [weak self] action in
            guard let control = action.sender as? UISegmentedControl else { return }
            self?.selectedEmojiGroupIndex = control.selectedSegmentIndex
            self?.reloadEmojiGrid()
        }, for: .valueChanged)

        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 44, height: 44)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        let grid = UICollectionView(frame: .zero, collectionViewLayout: layout)
        grid.backgroundColor = .clear
        grid.dataSource = self
        grid.delegate = self
        grid.register(EmojiCell.self, forCellWithReuseIdentifier: "emoji")

        panel.addSubview(segmented)
        panel.addSubview(grid)
        segmented.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(12)
            make.top.equalTo(panel.safeAreaLayoutGuide).offset(8)
        }
        grid.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.top.equalTo(segmented.snp.bottom).offset(8)
        }
        grid.tag = 100
        return panel
    }

    private func reloadEmojiGrid() {
        (view.subviews.first(where: { $0.tag == 100 }) as? UICollectionView)?.reloadData()
        emojiPanel?.viewWithTag(100)?.reloadInputViews()
        (emojiPanel?.viewWithTag(100) as? UICollectionView)?.reloadData()
    }

    private func toggleEmojiPanel() {
        let showingEmoji = textView.inputView != nil
        if showingEmoji {
            textView.inputView = nil
        } else {
            if emojiPanel == nil { emojiPanel = buildEmojiPanel() }
            textView.inputView = emojiPanel
            reloadEmojiGrid()
        }
        if textView.isFirstResponder {
            textView.reloadInputViews()
        } else {
            textView.becomeFirstResponder()
        }
    }

    // MARK: - 子类钩子

    /// 加载编辑器上下文(formhash/上传信息/回填内容)
    func loadEditorContext() async {}

    /// 执行发送;成功返回提示文案
    func performSend() async throws -> String {
        ""
    }

    var bodyText: String {
        textView.text ?? ""
    }

    var subjectText: String {
        subjectField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - 发送

    private func sendTapped() {
        guard !isSending else { return }
        guard allowsEmptyBody || !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Toast.show("内容不能为空", in: view)
            return
        }
        isSending = true
        statusLabel.text = "发送中…"
        setButtonsEnabled(false)
        Task { [weak self] in
            guard let self else { return }
            do {
                let message = try await self.performSend()
                DraftStore.clearIfMatches(self.draftKey, self.bodyText)
                self.isSending = false
                self.setButtonsEnabled(true)
                self.statusLabel.text = nil
                Toast.show(message.isEmpty ? "发送成功" : message, in: self.view)
                NotificationCenter.default.post(name: .postDidChange, object: nil)
                self.dismiss(animated: true)
            } catch {
                self.isSending = false
                self.setButtonsEnabled(true)
                self.statusLabel.text = nil
                let alert = UIAlertController(
                    title: "发送失败",
                    message: (error as? LocalizedError)?.errorDescription ?? "请稍后重试",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "好", style: .default))
                self.present(alert, animated: true)
            }
        }
    }

    private func setButtonsEnabled(_ enabled: Bool) {
        navigationItem.rightBarButtonItem?.isEnabled = enabled
        emojiButton.isEnabled = enabled
        photoButton.isEnabled = enabled
    }

    // MARK: - 草稿

    private func loadDraft() {
        guard let draftKey else { return }
        let draft = DraftStore.load(draftKey)
        if !draft.isEmpty {
            textView.text = draft
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        guard let draftKey else { return }
        DraftStore.save(draftKey, textView.text ?? "")
    }

    // MARK: - 图片上传

    private func showPhotoPicker() {
        var config = PHPickerConfiguration()
        config.selectionLimit = 6
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func uploadAndInsert(_ images: [UIImage]) {
        guard !isUploading else { return }
        isUploading = true
        statusLabel.text = "上传图片…"
        photoButton.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            do {
                guard let uploadInfo = self.editorInfo?.uploadInfo else {
                    throw APIError.server("未获取到上传凭据,请稍后重试")
                }
                var inserted = 0
                for (index, image) in images.enumerated() {
                    let data = image.jpegData(compressionQuality: 0.85) ?? Data()
                    let aid = try await WebChannel.uploadAttachment(
                        uploadInfo: uploadInfo,
                        imageData: data,
                        fileIndex: index
                    )
                    self.attachmentAids.append(aid)
                    self.insertAtCursor("[attachimg]\(aid)[/attachimg]")
                    inserted += 1
                }
                self.isUploading = false
                self.photoButton.isEnabled = true
                self.statusLabel.text = "已插入 \(inserted) 张图片"
            } catch {
                self.isUploading = false
                self.photoButton.isEnabled = true
                self.statusLabel.text = nil
                Toast.show((error as? LocalizedError)?.errorDescription ?? "上传失败", in: self.view)
            }
        }
    }

    private func insertAtCursor(_ text: String) {
        let selected = textView.selectedRange
        let mutable = NSMutableAttributedString(string: textView.text ?? "")
        let insertPosition = min(selected.location, mutable.length)
        mutable.insert(NSAttributedString(string: text), at: insertPosition)
        textView.attributedText = mutable
        let location = insertPosition + (text as NSString).length
        textView.selectedRange = NSRange(location: min(location, mutable.length), length: 0)
        textViewDidChange(textView)
    }

    // MARK: - 表情插入

    fileprivate func insertEmoji(groupIndex: Int, itemIndex: Int) {
        guard SmileyCatalog.groups.indices.contains(groupIndex) else { return }
        let group = SmileyCatalog.groups[groupIndex]
        insertAtCursor(SmileyCatalog.bbcode(for: group, index: itemIndex))
    }

    /// 正文含论坛附件时须走 web 表单提交(S1-Next 规则)
    func requiresWebFormChannel(_ message: String) -> Bool {
        message.contains("[attachimg]") || message.contains("[attach]")
    }

    /// web 表单提交的公共字段
    func webFormBaseFields(message: String) -> [String: String] {
        var fields: [String: String] = [
            "formhash": editorInfo?.formhash ?? (SessionStore.shared.state.formhash ?? ""),
            "posttime": editorInfo?.posttime ?? String(Int(Date().timeIntervalSince1970)),
            "wysiwyg": "1",
            "message": message,
            "usesig": "1",
        ]
        for aid in attachmentAids {
            fields["attachnew[\(aid)][description]"] = ""
            fields["attachnew[\(aid)][readperm]"] = ""
        }
        return fields
    }
}

// MARK: - 表情网格

extension EditorViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        SmileyCatalog.groups[selectedEmojiGroupIndex].count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "emoji", for: indexPath) as! EmojiCell
        let group = SmileyCatalog.groups[selectedEmojiGroupIndex]
        cell.configure(url: SmileyCatalog.url(for: group, index: indexPath.item + 1))
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        insertEmoji(groupIndex: selectedEmojiGroupIndex, itemIndex: indexPath.item + 1)
    }
}

final class EmojiCell: UICollectionViewCell {

    private let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        contentView.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(4)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(url: URL?) {
        imageView.kf.setImage(with: url, options: [.memoryCacheExpiration(.days(7)), .diskCacheExpiration(.days(30))])
    }
}

// MARK: - PHPicker

extension EditorViewController: PHPickerViewControllerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        let providers = results.map(\.itemProvider)
        guard !providers.isEmpty else { return }

        // 线程安全收集器(Swift 6 下跨队列闭包不能直接捕获可变局部变量)
        final class ImageCollector: @unchecked Sendable {
            private let lock = NSLock()
            private var items: [UIImage] = []
            func append(_ image: UIImage) {
                lock.lock()
                items.append(image)
                lock.unlock()
            }
            var all: [UIImage] {
                lock.lock()
                defer { lock.unlock() }
                return items
            }
        }
        let collector = ImageCollector()
        let group = DispatchGroup()
        for provider in providers where provider.canLoadObject(ofClass: UIImage.self) {
            group.enter()
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                if let image = object as? UIImage {
                    collector.append(image)
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self, collector] in
            let images = collector.all
            guard let self, !images.isEmpty else { return }
            self.uploadAndInsert(images)
        }
    }
}

extension DraftStore {
    /// 发送成功且内容与草稿一致时才清空
    static func clearIfMatches(_ key: String?, _ text: String) {
        guard let key else { return }
        if load(key) == text || text.isEmpty {
            clear(key)
        }
    }
}
