import UIKit
import SnapKit

/// 楼层评分明细(viewratings)。
@MainActor
final class RateDetailsViewController: UIViewController {

    private let threadId: Int
    private let postId: Int
    private let authorName: String

    private var tableView: UITableView!
    private var rates: [RateInfo] = []
    private let placeholder = StatefulPlaceholderView()

    init(threadId: Int, postId: Int, authorName: String) {
        self.threadId = threadId
        self.postId = postId
        self.authorName = authorName
        super.init(nibName: nil, bundle: nil)
        title = "评分明细"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.backgroundColor = Theme.background
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "rate")
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }

        placeholder.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.topAnchor.constraint(equalTo: view.topAnchor),
            placeholder.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            placeholder.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            placeholder.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        placeholder.state = .loading("加载评分明细")

        Task { await load() }
    }

    private func load() async {
        do {
            let result = try await DiscuzAPI.shared.rates(tid: threadId, pid: postId)
            rates = result
            placeholder.isHidden = !result.isEmpty
            if result.isEmpty {
                placeholder.state = .empty(
                    icon: "star.slash",
                    title: "暂无评分",
                    message: "该楼层近一年内没有评分记录"
                )
                placeholder.isHidden = false
            }
            tableView.reloadData()
        } catch {
            placeholder.state = .error(
                icon: "wifi.exclamationmark",
                title: "评分明细加载失败",
                message: (error as? LocalizedError)?.errorDescription ?? "请稍后重试",
                retry: { [weak self] in
                    guard let self else { return }
                    self.placeholder.state = .loading("加载评分明细")
                    Task { await self.load() }
                }
            )
            placeholder.isHidden = false
        }
    }
}

extension RateDetailsViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rates.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "rate", for: indexPath)
        cell.applyFlatListBackground()
        let rate = rates[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = "\(rate.uname ?? "UID \(rate.uid ?? "-")")  \(rate.symbolScore)"
        config.textProperties.font = .preferredFont(forTextStyle: .subheadline)
        config.secondaryText = [rate.content, rate.time].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        config.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)
        config.secondaryTextProperties.color = Theme.secondaryLabel
        config.secondaryTextProperties.numberOfLines = 2
        config.image = UIImage(systemName: "star")
        config.imageProperties.tintColor = rate.score < 0 ? .systemRed : .systemOrange
        cell.contentConfiguration = config
        return cell
    }
}
