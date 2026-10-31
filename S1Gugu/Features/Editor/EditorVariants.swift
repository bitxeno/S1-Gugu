import UIKit

/// 回复 / 引用回复
@MainActor
final class ReplyViewController: EditorViewController {

    private struct Quote: Sendable {
        let pid: Int
        let author: String
        let summary: String
    }

    private let threadId: Int
    private var quote: Quote?

    init(threadId: Int, quotePost: Post? = nil) {
        self.threadId = threadId
        if let quotePost {
            quote = Quote(
                pid: quotePost.pid,
                author: quotePost.author,
                summary: Self.summary(of: quotePost)
            )
        }
        super.init(nibName: nil, bundle: nil)
        draftKey = "reply.\(threadId)"
        title = quote == nil ? "回复" : "引用回复"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 引用摘要:楼层正文纯文本前 100 字(对齐 S1-Next noticeauthormsg 规则)
    static func summary(of post: Post) -> String {
        let blocks = BlockSplitter.split(html: post.preprocessedHTML, baseURL: nil)
        let text = blocks.compactMap { block -> String? in
            if case let .text(attributed) = block { return attributed.value.string }
            if case let .code(code) = block { return code }
            return nil
        }.joined(separator: " ")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(100))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 引用摘要提示条
        if let quote {
            let hint = UILabel()
            hint.text = "引用 \(quote.author):\(quote.summary)"
            hint.font = .preferredFont(forTextStyle: .footnote)
            hint.textColor = .secondaryLabel
            hint.numberOfLines = 2
            view.addSubview(hint)
            hint.snp.makeConstraints { make in
                make.leading.trailing.equalToSuperview().inset(16)
                make.bottom.equalTo(view.keyboardLayoutGuide).offset(-56)
            }
        }
    }

    override func loadEditorContext() async {
        do {
            editorInfo = try await WebChannel.getEditorInfo(
                path: "forum.php",
                query: [
                    "mod": "post",
                    "action": "reply",
                    "inajax": "yes",
                    "tid": String(threadId),
                    "repquote": String(quote?.pid ?? 0),
                ]
            )
        } catch {
            // 表单获取失败时仍可发送(走 mobile API + 全局 formhash)
            Toast.show((error as? LocalizedError)?.errorDescription ?? "编辑器信息获取失败", in: view)
        }
    }

    override func performSend() async throws -> String {
        let message = bodyText
        if requiresWebFormChannel(message), let action = editorInfo?.formAction {
            // 含论坛附件:web 表单通道
            var fields = webFormBaseFields(message: message)
            fields["subject"] = ""
            fields["replysubmit"] = "yes"
            if let quote {
                fields["noticeauthor"] = editorInfo?.noticeAuthor ?? ""
                fields["noticetrimstr"] = editorInfo?.noticeTrimStr ?? ""
            }
            _ = try await WebChannel.submitForm(action: action, fields: fields)
            return "回复成功"
        }
        // 纯文本:mobile API;引用时补 notice 字段
        var quoteContext: DiscuzAPI.QuoteContext?
        if let quote {
            quoteContext = try await DiscuzAPI.shared.replyQuoteContext(tid: threadId, repQuotePid: quote.pid)
        }
        try await DiscuzAPI.shared.reply(tid: threadId, message: message, quote: quoteContext)
        DraftStore.clear(draftKey ?? "")
        return "回复成功"
    }
}

/// 发新主题
@MainActor
final class NewThreadViewController: EditorViewController {

    private let forumId: Int
    private var selectedTypeId: String?

    init(forumId: Int, forumName: String?) {
        self.forumId = forumId
        super.init(nibName: nil, bundle: nil)
        draftKey = "newthread.\(forumId)"
        title = "发新主题"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        subjectField.isHidden = false
    }

    override func loadEditorContext() async {
        do {
            let info = try await WebChannel.getEditorInfo(
                path: "forum.php",
                query: ["mod": "post", "action": "newthread", "inajax": "yes", "fid": String(forumId)]
            )
            editorInfo = info
            if !info.threadTypes.isEmpty {
                let types = info.threadTypes
                let selectedIndex = min(info.selectedTypeIndex, types.count - 1)
                let chosen = types[max(selectedIndex, 0)]
                if !chosen.id.isEmpty {
                    selectedTypeId = chosen.id
                }
                navigationItem.titleView = makeTypeMenu(types: types, selected: chosen)
            }
        } catch {
            Toast.show((error as? LocalizedError)?.errorDescription ?? "编辑器信息获取失败", in: view)
        }
    }

    private func makeTypeMenu(types: [ThreadTypeOption], selected: ThreadTypeOption) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle("\(selected.name) ▾", for: .normal)
        button.setTitleColor(Theme.accent, for: .normal)
        button.showsMenuAsPrimaryAction = true
        button.menu = UIMenu(children: types.filter { !$0.id.isEmpty }.map { type in
            UIAction(title: type.name, state: type.id == selected.id ? .on : .off) { [weak self] _ in
                self?.selectedTypeId = type.id
                button.setTitle("\(type.name) ▾", for: .normal)
            }
        })
        return button
    }

    override func performSend() async throws -> String {
        let subject = subjectText
        guard !subject.isEmpty else {
            throw APIError.server("请填写标题")
        }
        let message = bodyText
        if requiresWebFormChannel(message), let action = editorInfo?.formAction {
            var fields = webFormBaseFields(message: message)
            fields["subject"] = subject
            fields["topicsubmit"] = "yes"
            if let selectedTypeId { fields["typeid"] = selectedTypeId }
            fields["allownoticeauthor"] = "1"
            _ = try await WebChannel.submitForm(action: action, fields: fields)
            return "发布成功"
        }
        try await DiscuzAPI.shared.newThread(
            fid: forumId,
            typeId: selectedTypeId,
            subject: subject,
            message: message,
            formhash: editorInfo?.formhash,
            posttime: editorInfo?.posttime
        )
        DraftStore.clear(draftKey ?? "")
        return "发布成功"
    }
}

/// 编辑自己的帖子
@MainActor
final class EditPostViewController: EditorViewController {

    private let forumId: Int
    private let threadId: Int
    private let postId: Int
    private var originalSubject: String = ""
    private var originalBody: String = ""

    init(forumId: Int, threadId: Int, postId: Int) {
        self.forumId = forumId
        self.threadId = threadId
        self.postId = postId
        super.init(nibName: nil, bundle: nil)
        title = "编辑帖子"
        allowsEmptyBody = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        subjectField.isHidden = false
        statusLabel.text = "加载中…"
    }

    override func loadEditorContext() async {
        do {
            let info = try await WebChannel.getEditorInfo(
                path: "forum.php",
                query: [
                    "mod": "post",
                    "action": "edit",
                    "inajax": "yes",
                    "fid": String(forumId),
                    "tid": String(threadId),
                    "pid": String(postId),
                ]
            )
            editorInfo = info
            originalSubject = info.subject ?? ""
            originalBody = info.message ?? ""
            subjectField.text = originalSubject
            textView.text = originalBody
            statusLabel.text = nil
        } catch {
            statusLabel.text = nil
            let alert = UIAlertController(
                title: "无法编辑",
                message: (error as? LocalizedError)?.errorDescription ?? "获取帖子内容失败",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "好", style: .default) { [weak self] _ in
                self?.dismiss(animated: true)
            })
            present(alert, animated: true)
        }
    }

    override func performSend() async throws -> String {
        let message = bodyText
        let subject = subjectText
        guard let action = editorInfo?.formAction else {
            throw APIError.server("缺少编辑表单信息")
        }
        var fields = webFormBaseFields(message: message)
        fields["subject"] = subject
        fields["fid"] = String(forumId)
        fields["tid"] = String(threadId)
        fields["pid"] = String(postId)
        fields["editsubmit"] = "yes"
        fields["delete"] = "0"
        _ = try await WebChannel.submitForm(action: action, fields: fields)
        return "编辑成功"
    }
}
