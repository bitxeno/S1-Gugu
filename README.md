<div align="center">

<img src="S1Gugu/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon1024.png" width="120" height="120" alt="S1 Gugu">

# S1 Gugu

**Stage1st 论坛原生 iOS 客户端。**

[![Version](https://img.shields.io/github/v/release/bitxeno/S1-Gugu?label=version&style=for-the-badge&color=2f6fed)](https://github.com/bitxeno/S1-Gugu/releases)
[![Platform](https://img.shields.io/badge/iOS-17%2B-lightgrey?style=for-the-badge&logo=apple)](#安装)

<a href="https://github.com/bitxeno/S1-Gugu/releases/latest/download/S1Gugu.ipa"><img src="https://img.shields.io/badge/Download-.ipa-2f6fed?style=for-the-badge&logo=apple&logoColor=white" alt="Download .ipa"></a>
&nbsp;
<a href="https://github.com/bitxeno/S1-Gugu/releases/download/AltSource/source.json"><img src="https://img.shields.io/badge/Add-AltSource-2f6fed?style=for-the-badge&logo=altstore&logoColor=white" alt="Add AltSource"></a>

</div>

---

S1 Gugu 是 [Stage1st](https://stage1st.com/2b/)(S1,圣者之扉)论坛的原生 iOS 客户端,功能对齐 Android 端 [S1-Next](https://github.com/ykrank/S1-Next),交互与视觉遵循 Apple Human Interface Guidelines。帖子内容全部原生渲染,不使用 WebView。

## 功能

- **版块浏览**:版块分组、主题列表 50 条/页无限滚动,置顶/投票/附件角标
- **未读标记**:看过的帖子在回复数下方显示「+N」新回复数
- **原生渲染**:40 楼/页分块渲染(文本/内联表情/图片/引用/代码/附件),图片画廊支持缩放与保存
- **账号**:用户名/密码/安全提问登录,凭据存 Keychain,会话持久化与掉线检测
- **收藏与历史**:收藏管理;本地浏览历史(300 条,可搜索);阅读进度自动保存/恢复
- **黑名单**:用户级黑名单(主题/回复隐藏或删除)+ 屏蔽词
- **互动**:回复/引用、发新主题、投票
- **体验**:深色模式、Dynamic Type、奶黄主题(复刻 S1-Next 午后红茶)、iPad 适配

## 安装

> 仓库当前为私有,Release 附件需要登录后才能下载;转公开后以下链接对所有人可用。

- **IPA 直装**:从 [Releases](https://github.com/bitxeno/S1-Gugu/releases) 下载 `S1Gugu.ipa`(未签名),用 AltStore/SideStore/Sideloadly 等工具自签安装。
- **AltStore / SideStore**:在 App 内添加 Source:

  ```
  https://github.com/bitxeno/S1-Gugu/releases/download/AltSource/source.json
  ```

  每次发版该文件自动更新,同版本号自动替换。

## 相关项目

- [S1-Next](https://github.com/ykrank/S1-Next) — Android 端参考实现
- [Stage1st](https://stage1st.com/2b/) — S1 论坛
