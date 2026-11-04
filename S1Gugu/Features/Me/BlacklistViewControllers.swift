import UIKit
import SnapKit

/// 用户黑名单管理:uid/用户名、回复强度、主题强度、备注。
@MainActor
final class BlacklistViewController: UIViewController {

    private var tableView: UITableView!
    private var entries: [BlackListEntry] = []
    private let placeholder = StatefulPlaceholderView()

    private static let postLevelNames = [0: "正常", 1: "隐藏", 2: "删除"]
    private static let forumLevelNames = [0: "正常", 3: "隐藏", 4: "删除"]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.title = "黑名单"

        tableView = UITableView(frame: view.bounds, style: .insetGrouped)
        tableView.backgroundColor = Theme.background
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "blacklist")
        view.addSubview(tableView)

        navigationItem.rightBarButtonItem = UIBarButtonItem(primaryAction: UIAction(
            title: "添加黑名单",
            image: UIImage(systemName: "plus")
        ) { [weak self] _ in
            self?.showAddAlert()
        })

        placeholder.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.topAnchor.constraint(equalTo: view.topAnchor),
            placeholder.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            placeholder.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            placeholder.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        placeholder.state = .empty(
            icon: "eye.slash",
            title: "黑名单为空",
            message: "添加用户后,其主题与回复将按强度被隐藏或删除"
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { await reload() }
    }

    private func reload() async {
        await BlacklistService.shared.reload()
        entries = BlacklistService.shared.snapshot.entries
        placeholder.isHidden = !entries.isEmpty
        tableView.reloadData()
    }

    private func displayName(_ entry: BlackListEntry) -> String {
        if let name = entry.name, !name.isEmpty { return name }
        return "UID \(entry.uid)"
    }

    private func detailText(_ entry: BlackListEntry) -> String {
        var parts: [String] = []
        parts.append("回复:\(Self.postLevelNames[entry.postLevel] ?? "正常")")
        parts.append("主题:\(Self.forumLevelNames[entry.forumLevel] ?? "正常")")
        if let remark = entry.remark, !remark.isEmpty { parts.append("备注:\(remark)") }
        return parts.joined(separator: " · ")
    }

    private func showAddAlert() {
        let alert = UIAlertController(title: "添加黑名单", message: "UID 与用户名至少填一项", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "UID(可选)"; $0.keyboardType = .numberPad }
        alert.addTextField { $0.placeholder = "用户名(可选)" }
        alert.addTextField { $0.placeholder = "备注(可选,屏蔽时显示)" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "添加", style: .default) { [weak self] _ in
            let uid = Int(alert.textFields?[0].text ?? "") ?? 0
            let name = alert.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines)
            let remark = alert.textFields?[2].text?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard uid > 0 || (name != nil && !name!.isEmpty) else { return }
            Task {
                await BlacklistService.shared.addBlackList(
                    uid: uid,
                    name: name?.isEmpty == true ? nil : name,
                    postLevel: 1,
                    forumLevel: 3,
                    remark: remark?.isEmpty == true ? nil : remark
                )
                await self?.reload()
            }
        })
        present(alert, animated: true)
    }

    private func showEntryMenu(_ entry: BlackListEntry) {
        let alert = UIAlertController(title: displayName(entry), message: detailText(entry), preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "回复强度:隐藏", style: .default) { _ in
            self.update(entry: entry, postLevel: 1)
        })
        alert.addAction(UIAlertAction(title: "回复强度:删除", style: .default) { _ in
            self.update(entry: entry, postLevel: 2)
        })
        alert.addAction(UIAlertAction(title: "回复强度:正常", style: .default) { _ in
            self.update(entry: entry, postLevel: 0)
        })
        alert.addAction(UIAlertAction(title: "主题强度:隐藏", style: .default) { _ in
            self.update(entry: entry, forumLevel: 3)
        })
        alert.addAction(UIAlertAction(title: "主题强度:删除", style: .default) { _ in
            self.update(entry: entry, forumLevel: 4)
        })
        alert.addAction(UIAlertAction(title: "主题强度:正常", style: .default) { _ in
            self.update(entry: entry, forumLevel: 0)
        })
        alert.addAction(UIAlertAction(title: "删除记录", style: .destructive) { _ in
            Task {
                await BlacklistService.shared.removeBlackList(id: entry.id)
                await self.reload()
            }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func update(entry: BlackListEntry, postLevel: Int? = nil, forumLevel: Int? = nil) {
        var updated = entry
        if let postLevel { updated.postLevel = postLevel }
        if let forumLevel { updated.forumLevel = forumLevel }
        Task {
            await BlacklistService.shared.updateBlackList(updated)
            await self.reload()
        }
    }
}

extension BlacklistViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        entries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "blacklist", for: indexPath)
        cell.applyFlatListBackground()
        let entry = entries[indexPath.row]
        var config = cell.appDefaultContentConfiguration()
        config.text = displayName(entry)
        config.secondaryText = detailText(entry)
        config.textProperties.font = .preferredFont(forTextStyle: .body)
        config.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)
        config.secondaryTextProperties.color = Theme.secondaryLabel
        config.image = UIImage(systemName: "person.crop.circle.badge.xmark")
        config.imageProperties.tintColor = .systemRed
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        showEntryMenu(entries[indexPath.row])
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let entry = entries[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
            Task {
                await BlacklistService.shared.removeBlackList(id: entry.id)
                await self?.reload()
                completion(true)
            }
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}

/// 屏蔽词管理:词 + 强度(隐藏/删除)。
@MainActor
final class BlackWordViewController: UIViewController {

    private var tableView: UITableView!
    private var entries: [BlackWordEntry] = []
    private let placeholder = StatefulPlaceholderView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.title = "屏蔽词"

        tableView = UITableView(frame: view.bounds, style: .insetGrouped)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.backgroundColor = Theme.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "blackword")
        view.addSubview(tableView)

        navigationItem.rightBarButtonItem = UIBarButtonItem(primaryAction: UIAction(
            title: "添加屏蔽词",
            image: UIImage(systemName: "plus")
        ) { [weak self] _ in
            self?.showAddAlert()
        })

        placeholder.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.topAnchor.constraint(equalTo: view.topAnchor),
            placeholder.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            placeholder.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            placeholder.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        placeholder.state = .empty(
            icon: "text.badge.minus",
            title: "暂无屏蔽词",
            message: "命中屏蔽词的主题与回复将被隐藏或删除"
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { await reload() }
    }

    private func reload() async {
        await BlacklistService.shared.reload()
        entries = BlacklistService.shared.snapshot.words
        placeholder.isHidden = !entries.isEmpty
        tableView.reloadData()
    }

    private func showAddAlert() {
        let alert = UIAlertController(title: "添加屏蔽词", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "关键词" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "隐藏", style: .default) { [weak self] _ in
            self?.add(word: alert.textFields?.first?.text, level: 1)
        })
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            self?.add(word: alert.textFields?.first?.text, level: 2)
        })
        present(alert, animated: true)
    }

    private func add(word: String?, level: Int) {
        let trimmed = word?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return }
        Task {
            await BlacklistService.shared.addBlackWord(word: trimmed, level: level)
            await self.reload()
        }
    }

    private func toggleLevel(_ entry: BlackWordEntry) {
        var updated = entry
        updated.level = entry.level == 2 ? 1 : 2
        Task {
            await BlacklistService.shared.updateBlackWord(updated)
            await self.reload()
        }
    }
}

extension BlackWordViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        entries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "blackword", for: indexPath)
        cell.applyFlatListBackground()
        let entry = entries[indexPath.row]
        var config = cell.appDefaultContentConfiguration()
        config.text = entry.word
        config.secondaryText = entry.level == 2 ? "命中时删除" : "命中时隐藏(占位)"
        config.textProperties.font = .preferredFont(forTextStyle: .body)
        config.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)
        config.secondaryTextProperties.color = Theme.secondaryLabel
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        toggleLevel(entries[indexPath.row])
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let entry = entries[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
            Task {
                await BlacklistService.shared.removeBlackWord(id: entry.id)
                await self?.reload()
                completion(true)
            }
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}
