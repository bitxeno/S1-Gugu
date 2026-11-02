import UIKit

/// 图片原始像素尺寸缓存(URL → 像素宽高)。
///
/// 帖子里的图片在下载完成前只能靠 HTML 的 width/height 属性估高;属性缺失或与实际
/// 比例不符时,图片落地后 cell 高度会突变,导致列表布局重算、滚动条跳动。这里把每张
/// 图加载后的真实像素尺寸持久化下来,再次滚动到同一张图时即可在下载前按真实比例
/// 预留高度,加载完成不再改变布局。
///
/// 内存 + Caches 目录 JSON 双份;LRU 上限 2000 条,写入做了防抖。
final class ImageDimensionStore: @unchecked Sendable {

    static let shared = ImageDimensionStore()

    private let lock = NSLock()
    private var storage: [String: CGSize] = [:]
    /// LRU 顺序,末尾为最近使用
    private var order: [String] = []
    private let maxEntries = 2000

    private let fileURL: URL
    private let ioQueue = DispatchQueue(label: "app.bitxeno.s1gugu.image-dimensions", qos: .utility)
    private var pendingSave: DispatchWorkItem?

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        fileURL = caches.appendingPathComponent("image-dimensions.json")
        load()
    }

    // MARK: - 读取

    func size(for url: URL) -> CGSize? {
        lock.lock()
        defer { lock.unlock() }
        let key = url.absoluteString
        guard let size = storage[key] else { return nil }
        // 命中即刷新 LRU 位置
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
            order.append(key)
        }
        return size
    }

    // MARK: - 写入

    func store(size: CGSize, for url: URL) {
        guard size.width > 0, size.height > 0 else { return }
        let key = url.absoluteString
        lock.lock()
        // 已记录且一致则不重复写入
        if let existing = storage[key], existing == size {
            lock.unlock()
            return
        }
        storage[key] = size
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
        order.append(key)
        while order.count > maxEntries {
            let evicted = order.removeFirst()
            storage[evicted] = nil
        }
        let snapshot = storage
        lock.unlock()
        scheduleSave(snapshot)
    }

    // MARK: - 持久化

    /// 清空(随「清除图片缓存」一起清理)。
    func clear() {
        lock.lock()
        storage.removeAll()
        order.removeAll()
        pendingSave?.cancel()
        pendingSave = nil
        lock.unlock()
        ioQueue.async { [fileURL] in
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let raw = try? JSONDecoder().decode([String: [CGFloat]].self, from: data)
        else { return }
        for (key, value) in raw where value.count == 2 {
            storage[key] = CGSize(width: value[0], height: value[1])
        }
        // 无历史 LRU 顺序,按字典顺序兜底
        order = Array(storage.keys)
    }

    private func scheduleSave(_ snapshot: [String: CGSize]) {
        let fileURL = self.fileURL
        let work = DispatchWorkItem {
            var encodable: [String: [CGFloat]] = [:]
            encodable.reserveCapacity(snapshot.count)
            for (key, size) in snapshot {
                encodable[key] = [size.width, size.height]
            }
            guard let data = try? JSONEncoder().encode(encodable) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
        lock.lock()
        pendingSave?.cancel()
        pendingSave = work
        lock.unlock()
        ioQueue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
