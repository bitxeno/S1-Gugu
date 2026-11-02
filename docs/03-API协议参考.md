# S1 Goose API 协议参考

> 自 S1-Next(Android)源码逆向整理的 Stage1st(Discuz! X)接口手册。iOS 实现以本文为准。
> 端点定义源:`app/src/main/java/me/ykrank/s1next/data/api/`(S1Service.kt / ApiForum.java / ApiMember.kt / BaseApi.kt)。

## 1. 基础约定

| 项 | 值 |
|---|---|
| Base URL | `https://stage1st.com/2b/`(备选 host:`bbs.saraba1st.com`、`www.saraba1st.com`、`stage1st.com`、`www.stage1st.com`) |
| 移动 API 前缀 | `api/mobile/index.php?module=<module>` |
| version 参数 | 对论坛域请求默认补 `version=1`;`forumdisplay` 用 `version=4`;帖子详情 `viewthread` 用 `version=1` + `submodule=checkpost` + `mobile=no`(引用为 `div.quote > blockquote`,附「本帖最后由…编辑」;v4 为 `div.reply_wrap`) |
| 分页常量 | 主题 50 条/页(tpp=50);帖子 40 楼/页(ppp=40) |
| 编码 | 读:GET + query;写:`application/x-www-form-urlencoded`;附件:multipart/form-data |
| 登录态 | 纯 cookie(`*_saltkey`、`*_auth`),HTTP 端自动携带;无 token 轮换 |
| 防跨站 | 所有写操作带 `formhash`(来自响应 `Variables.formhash`;登录后首个视为过期,需 `module=toplist` 刷新) |
| 头像 | `https://avatar.saraba1st.com/{uid 补零 9 位,拆 3/2/2/2 段}_avatar_big.jpg` |
| 附件图 | `PostAttachment.url`(前缀)+ `.attachment`(文件名)拼接;动态图 `forum.php?mod=image&aid=N&size=…&key=…`(key 必须保留) |

### 公共响应信封
```jsonc
{
  "Variables": { /* 数据 + 混入 member_uid / member_username / formhash / readaccess */ },
  "Message": { "messageval": "post_reply_succeed", "messagestr": "…" },  // 写操作才有
  "error": "…"  // 顶层错误(非空即失败)
}
```
- 列表公共字段:`Variables.{ count, page, perpage, list }`。
- 成功判定:`messageval` 以 `_succeed` / `_success` / `_succeed_mobile` 结尾。
- JSON 不严格(空值 `:,`、未引号 key、坏 `\u`),解码前过 ResponseCleaner(见架构文档 4.3)。

## 2. M1 端点明细

### 2.1 登录
`POST api/mobile/index.php?module=login&loginsubmit=yes&loginfield=auto&cookietime=2592000`
- form:`username`、`password`(明文传输,HTTPS;客户端不做哈希)、`questionid`(0–9,0=无提问)、`answer`
- 成功:Set-Cookie 下发会话;`Variables` 含 `member_uid/member_username/formhash`
- **登录后立即** `GET module=toplist` 刷新 formhash
- 登出:清 HTTPCookieStorage + 重置本地用户态(无服务端登出调用,S1-Next 同)

### 2.2 版块组
`GET api/mobile/index.php?module=forumindex`
- 返回:`Variables.forumlist[]`,条目 `type: "group"` 为分类(含 fid/name),`type: "forum"` 为版块(含 `fup` 指向所属分类 fid、`posts/threads/todayposts` 计数)
- iOS 组装:按 fup 归组为 Section

### 2.3 主题列表
`GET api/mobile/index.php?module=forumdisplay&version=4&filter=typeid&tpp=50&fid={fid}&page={page}`
- 返回 `Variables`:`forum`(版块名等)、`threadlist[]`
- Thread 关键字段:`tid, subject(标题), author, authorid, dbdateline(发布时间串), lastpost(最后回复时间串), replies, views, special(1=投票), attachment(附件数>0), displayorder(置顶>0), typeid`
- 置顶与普通主题混排于 threadlist(displayorder 区分)

### 2.4 帖子详情
`GET api/mobile/index.php?mobile=no&module=viewthread&version=1&submodule=checkpost&ppp=40&tid={tid}&page={page}`(+`authorid` 只看他,M3)
- 返回 `Variables`:`thread`(tid/subject/replies/maxposition/author…)、`postlist[]`、`ppp`;`pagecount`/`page` 可能缺省,用 `maxposition` 或 `replies` 兜底计算
- Post 关键字段:`pid, first("1"=主楼), author, authorid, dateline(时间串), number(楼层号), dbdateline, status, message(服务端预渲染 HTML), attachments{aid: {url, attachment, isimage, filename, filesize}}`(attachments 可能是对象或空数组,双形态)
- `message` 为 HTML 片段:服务端已渲染,含 `<div class="quote"><blockquote>`(引用)、`<img file|zoomfile>`、`<font>`、`<a>`、`<i class="pstatus">本帖最后由…编辑</i>` 等;进入渲染管线(架构文档 §5)

### 2.5 收藏
- 列表:`GET module=myfavthread&page={page}` → `Variables.list[]`(`idfield=tid, title, description, dateline` 等)
- 添加:`POST module=favthread&favoritesubmit=yes`,form:`formhash, id(tid), description(备注)`
- 移除:`POST module=favthread&deletesubmit=true&op=delete`,form:`formhash, favid`

### 2.6 formhash 刷新
`GET api/mobile/index.php?module=toplist` → 取 `Variables.formhash`

## 3. M2 端点预告(实现时按此节校准)

| 功能 | 端点 |
|---|---|
| 回复 | `POST module=sendreply&replysubmit=yes`,form:`formhash,tid,message`(引用加 `noticeauthor,noticetrimstr,noticeauthormsg`) |
| 回复编辑上下文 | `GET forum.php?mod=post&action=reply&inajax=yes&tid={tid}&repquote={pid}`(XML CDATA 包 HTML) |
| 发新主题 | `POST module=newthread&extra=&topicsubmit=yes&fid={fid}`,form:`formhash,posttime,typeid,subject,message,allownoticeauthor,usesig,save` |
| 编辑 | `POST forum.php?mod=post&action=edit&editsubmit=yes&inajax=yes&wysiwyg=1&delete=0`,form:`fid,tid,pid,formhash,posttime,subject,message,…` |
| 附件上传 | `POST misc.php?mod=swfupload&action=swfupload&operation=upload&fid=N`,multipart:`uid,hash,id,type,size,filetype,Filedata` → 纯数字 aid(负数失败);含 `[attachimg]aid[/attachimg]` 的正文须走 Web 表单提交 |
| 私信列表 | `GET module=mypm&filter=privatepm&page=N`;会话:`GET module=mypm&subop=view&touid={uid}&page=N` |
| 发私信 | `POST module=sendpm&pmsubmit=true`,form:`formhash,touid,message` |
| 通知 | `GET module=mynotelist&view=mypost&type=post&version=3&page=N` |
| 搜索 | `POST search.php?searchsubmit=yes&mod=forum|user`,form:`formhash,srchtxt` |
| 个人空间 | `GET module=profile&uid={uid}`;好友:`GET module=friend&uid={uid}` |
| 评分 | pre:`GET forum.php?mod=misc&action=rate&infloat=yes&inajax=1&tid&pid`;提交:`POST …action=rate&ratesubmit=yes…`,form:`formhash,tid,pid,score1,reason` |
| 举报 | `GET/POST misc.php?mod=report&…&inajax=1` |
| 投票 | `POST forum.php?mod=misc&action=votepoll&pollsubmit=yes&inajax=1&tid={tid}`,form:`formhash,pollanswers[]`(M3 走 App 后端优先) |
| App 后端 | `POST api/app/user/login` → sid;`user/sign` 签到;`poll/*`;header `authorization: <sid>` |

## 4. inajax 响应(Web 通道)

- 外壳:`<root><![CDATA[ …HTML… ]]></root>`,剥壳取 CDATA。
- 成败判定:含 `succeedhandle_…(msg,…)` 回调为成功;`errorhandle_…(msg,…)` 为失败(首参为消息)。
- HTML 错误页:`div#messagetext`;弹窗错误:`div.alert_error`。

## 5. 已知坑清单(iOS 实现注意)

1. **JSON 修复必须前置**:`:,`→`:null,`;未引号 key 兜底;失败记录原文日志。
2. `version` 参数:拦截统一补,勿漏;漏了部分接口返回空/结构不同。
3. attachments 双形态:对象(无 aid 时)vs 空数组;解码需自定义 `decodeIfPresent` 容错。
4. 图片占位:缩略图 `src` 可能是 `static/.../none.gif`,真实地址在 `file`/`zoomfile` 属性。
5. 分页页数计算:`replies` 与 `ppp` 推算总页数,以响应 `pagecount` 为准(存在时)。
6. 登录响应的 formhash 不可直接用,必须 toplist 刷新。
7. 多 host:URL 中任意 saraba1st/stage1st host 请求都要能被 base URL 替换逻辑覆盖(M3)。
8. 引用块:v1 是 `<blockquote>`,v4 是 `<div class="reply_wrap">`;渲染前统一归一。
9. 时间字段是**服务器本地格式化字符串**(非时间戳),展示原样,不做时区换算。
10. Cookie 过期无显式信号:`member_uid=0` 即掉线,此时清本地态并引导重登。
