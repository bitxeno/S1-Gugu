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
    private let draftBoxButton = UIButton(type: .system)
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
    private var hasSentSuccessfully = false
    private var isLoadingDraft = false
    private var editedWhileLoadingDraft = false
    private var draftSaveTask: Task<Void, Never>?

    /// 草稿 key(nil 则不存草稿,如编辑模式)
    var draftKey: String?
    /// 是否显示并持久化标题字段。
    var includesSubjectInDraft: Bool { false }
    /// 子类按当前编辑对象筛选可恢复草稿。
    func loadDraftPickerEntries() async -> [EditorDraftEntry] { [] }
    private var loadedDraftKey: String?

    /// 正文是否允许为空(编辑/新主题必须非空)
    var allowsEmptyBody = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.contentBackground
        buildUI()
        loadDraft()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveDraftForBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
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
        subjectField.isHidden = !includesSubjectInDraft
        subjectField.addTarget(self, action: #selector(subjectDidChange(_:)), for: .editingChanged)

        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.delegate = self
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

        draftBoxButton.setImage(UIImage(systemName: "tray.full"), for: .normal)
        draftBoxButton.accessibilityLabel = "草稿箱"
        draftBoxButton.accessibilityHint = "选择并恢复之前保存的草稿"
        draftBoxButton.addAction(UIAction { [weak self] _ in
            self?.showDraftPicker()
        }, for: .touchUpInside)
        draftBoxButton.snp.makeConstraints { make in
            make.width.height.equalTo(44)
        }

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
        bottomBar.addArrangedSubview(draftBoxButton)
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
        let submittedDraft = currentDraft
        Task { [weak self] in
            guard let self else { return }
            do {
                let message = try await self.performSend()
                self.hasSentSuccessfully = true
                self.draftSaveTask?.cancel()
                await DraftStore.clearIfMatches(self.draftKey, submittedDraft)
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
        draftBoxButton.isEnabled = enabled
        emojiButton.isEnabled = enabled
        photoButton.isEnabled = enabled
        (navigationItem.titleView as? UIButton)?.isEnabled = enabled
        textView.isEditable = enabled
        subjectField.isEnabled = enabled
    }

    // MARK: - 草稿

    var draftExtraValue: String? { nil }

    private func showDraftPicker() {
        guard !isLoadingDraft else { return }
        draftBoxButton.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            let entries = await loadDraftPickerEntries()
            self.draftBoxButton.isEnabled = true
            guard self.presentedViewController == nil else { return }
            guard !entries.isEmpty else {
                Toast.show("暂无可恢复的草稿", in: self.view)
                return
            }
            self.presentDraftPicker(entries)
        }
    }

    private func presentDraftPicker(_ entries: [EditorDraftEntry]) {
        let alert = UIAlertController(title: "草稿箱", message: nil, preferredStyle: .actionSheet)
        for entry in entries {
            let subject = entry.subject.trimmingCharacters(in: .whitespacesAndNewlines)
            let bodyPreview = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = subject.isEmpty ? String(bodyPreview.prefix(36)) : subject
            let date = Date(timeIntervalSince1970: TimeInterval(entry.timestamp))
            let formatter = DateFormatter()
            formatter.locale = Locale.current
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            let subtitle = formatter.string(from: date)
            alert.addAction(UIAlertAction(title: "\(title.isEmpty ? "无标题草稿" : title) · \(subtitle)", style: .default) { [weak self] _ in
                self?.restoreDraft(entry)
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = draftBoxButton
            popover.sourceRect = draftBoxButton.bounds
        }
        present(alert, animated: true)
    }

    private func restoreDraft(_ entry: EditorDraftEntry) {
        guard !isSending else { return }
        draftSaveTask?.cancel()
        let draft = EditorDraft(subject: entry.subject, body: entry.body, extraValue: entry.extraValue)
        isLoadingDraft = true
        if includesSubjectInDraft { subjectField.text = draft.subject }
        textView.text = draft.body
        applyDraftExtraValue(draft.extraValue)
        editedWhileLoadingDraft = false
        isLoadingDraft = false
        saveDraft()
        textView.becomeFirstResponder()
    }


    private var currentDraft: EditorDraft {
        EditorDraft(subject: includesSubjectInDraft ? (subjectField.text ?? "") : "",
                    body: textView.text ?? "",
                    extraValue: draftExtraValue)
    }

    private func loadDraft() {
        guard let draftKey else { return }
        loadedDraftKey = draftKey
        isLoadingDraft = true
        Task { [weak self] in
            guard let self else { return }
            let draft = await DraftStore.load(draftKey)
            if !self.editedWhileLoadingDraft, let draft, draft.hasContent {
                if self.includesSubjectInDraft { self.subjectField.text = draft.subject }
                self.textView.text = draft.body
                self.applyDraftExtraValue(draft.extraValue)
            }
            self.isLoadingDraft = false
            if self.editedWhileLoadingDraft { self.saveDraft() }
        }
    }

    func applyDraftExtraValue(_ value: String?) {}

    func saveDraft() {
        guard !hasSentSuccessfully, let draftKey = loadedDraftKey else { return }
        if isLoadingDraft {
            editedWhileLoadingDraft = true
            return
        }
        draftSaveTask?.cancel()
        let draft = currentDraft
        draftSaveTask = Task { [weak self] in
            guard let self else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            if draft.hasContent {
                _ = await DraftStore.save(draftKey, draft)
            } else {
                await DraftStore.clear(draftKey)
            }
        }
    }

    @objc private func saveDraftForBackground() {
        saveDraft()
    }

    func textViewDidChange(_ textView: UITextView) {
        saveDraft()
    }

    @objc private func subjectDidChange(_ field: UITextField) {
        saveDraft()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveDraft()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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