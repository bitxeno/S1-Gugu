import Foundation

/// 分页加载的标识去重防线。
///
/// 服务端分页接口的已知脏数据:页边界重复返回末条、置顶内容每页重复、
/// 标识字段缺失时解析为 0。重复元素进入 diffable data source 会抛
/// IDENTIFIER_ALREADY_EXISTS 崩溃,或渲染出重复行。
/// 分页数据写入模型数组前必须经过这里,不要手写 Set + filter 组合。
extension Array {

    /// 去除 key 重复的元素,保留首次出现。
    /// 用于整页写入(首页 / 跳页 / 刷新)前的页内去重。
    func uniqued<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Element] {
        uniqued(by: keyPath, excluding: [])
    }

    /// 返回 key 未在 existing 中出现过的元素,自身内部重复同样去除。
    /// 用于非追加方向的并入(如私信会话顶部插入更早消息)。
    func uniqued<Key: Hashable>(
        by keyPath: KeyPath<Element, Key>,
        excluding existing: some Collection<Element>
    ) -> [Element] {
        var seen = Set<Key>(existing.map { $0[keyPath: keyPath] })
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }

    /// 追加元素并丢弃 key 已存在(含追加序列内部重复)的元素。
    /// 翻页追加的统一入口,覆盖页边界重复与置顶内容跨页重复。
    mutating func appendUniqued<Key: Hashable>(
        contentsOf newElements: [Element],
        by keyPath: KeyPath<Element, Key>
    ) {
        append(contentsOf: newElements.uniqued(by: keyPath, excluding: self))
    }
}
