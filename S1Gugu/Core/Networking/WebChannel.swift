import Foundation
import SwiftSoup

// MARK: - Web 表单通道模型

struct ThreadTypeOption: Sendable, Hashable {
    let id: String
    let name: String
}

struct AttachmentUploadInfo: Sendable, Equatable {
    let uploadURL: URL?
    let fid: Int?
    let uid: String?
    let hash: String
}

/// 论坛编辑器表单信息(来自 forum.php?mod=post 的 inajax 响应)
struct PostEditorInfo: Sendable {
    let formAction: URL?
    let formhash: String?
    let posttime: String?
    let noticeAuthor: String?
    let noticeTrimStr: String?
    let noticeAuthorMsg: String?
    let threadTypes: [ThreadTypeOption]
    let selectedTypeIndex: Int
    let subject: String?
    let message: String?
    let uploadInfo: AttachmentUploadInfo?
}

/// inajax 响应的成败结果(`succeedhandle_*` / `errorhandle_*`)
struct AjaxResult: Sendable {
    let success: Bool
    let message: String
}

// MARK: - WebChannel

/// forum.php 网页表单通道:编辑器表单解析、urlencoded 提交、swfupload 附件上传。
enum WebChannel {

    // MARK: 编辑器表单

    static func getEditorInfo(path: String, query: [String: String]) async throws -> PostEditorInfo {
        let raw = try await S1APIClient.shared.get(path: path, query: query)
        let html = unwrapAjaxHTML(ResponseCleaner.htmlString(raw))
        guard let info = parseEditorInfo(html, baseURL: S1APIClient.shared.baseURL) else {
            // 常见失败:无权限/需要登录时返回 alert_error 片段
            let alertMessage = extractAlertError(html)
            throw APIError.server(alertMessage ?? "获取编辑器信息失败")
        }
        return info
    }

    static func unwrapAjaxHTML(_ html: String) -> String {
        if let match = html.firstMatch(of: /<root>\s*<!\[CDATA\[([\s\S]*)\]\]>\s*<\/root>/) {
            return String(match.1)
        }
        return html
    }

    static func parseEditorInfo(_ html: String, baseURL: URL) -> PostEditorInfo? {
        guard let document = try? SwiftSoup.parse(html) else { return nil }
        let form = (try? document.select("form#postform, form[action*=mod=post]").first()) ?? nil
        let actionString = (try? form?.attr("action")) ?? nil
        let formAction: URL? = actionString.flatMap { resolve($0, baseURL: baseURL) }

        func input(_ name: String) -> String? {
            let value = (try? document.select("input[name=\(name)]").first()?.attr("value")) ?? nil
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }

        var types: [ThreadTypeOption] = []
        var selectedTypeIndex = 0
        if let options = try? document.select("#typeid>option") {
            for (index, element) in options.array().enumerated() {
                let id = (try? element.attr("value"))?.trimmingCharacters(in: .whitespaces) ?? ""
                let name = (try? element.text()) ?? ""
                if (try? element.attr("selected")) == "selected" { selectedTypeIndex = index }
                types.append(ThreadTypeOption(id: id, name: name))
            }
        }

        let subject = input("subject")
        let message = (try? document.select("textarea#e_textarea, textarea[name=message]").first()?.text()) ?? nil

        var uploadInfo: AttachmentUploadInfo?
        if let hash = input("hash") {
            let uploadURL = (try? document.select("form[action*=operation=upload]").first()?.attr("action")) ?? nil
            uploadInfo = AttachmentUploadInfo(
                uploadURL: uploadURL.flatMap { resolve($0, baseURL: baseURL) },
                fid: input("fid").flatMap(Int.init),
                uid: input("uid"),
                hash: hash
            )
        }

        // form 缺失(纯 JS 场景)时仅在有表单 action 或 hash 时认为有效
        guard formAction != nil || form != nil || input("formhash") != nil else { return nil }

        return PostEditorInfo(
            formAction: formAction ?? resolve("forum.php?mod=post", baseURL: baseURL),
            formhash: input("formhash"),
            posttime: input("posttime"),
            noticeAuthor: input("noticeauthor"),
            noticeTrimStr: input("noticetrimstr"),
            noticeAuthorMsg: input("noticeauthormsg"),
            threadTypes: types,
            selectedTypeIndex: selectedTypeIndex,
            subject: subject,
            message: message,
            uploadInfo: uploadInfo
        )
    }

    // MARK: 提交

    static func submitForm(action: URL, fields: [String: String]) async throws -> AjaxResult {
        let raw = try await S1APIClient.shared.postFormToURL(url: action, form: fields)
        let html = ResponseCleaner.htmlString(raw)
        let result = parseAjaxResult(html)
        if !result.success {
            throw APIError.actionFailed(result.message)
        }
        return result
    }

    static func parseAjaxResult(_ html: String) -> AjaxResult {
        if let match = html.firstMatch(of: /succeedhandle_[^(]*\(([^)]*)\)/) {
            return AjaxResult(success: true, message: ajaxParam(String(match.1), index: 1))
        }
        if let match = html.firstMatch(of: /errorhandle_[^(]*\(([^)]*)\)/) {
            return AjaxResult(success: false, message: ajaxParam(String(match.1), index: 0))
        }
        // 投票等接口成功时(showmessage location => true)只回跳转脚本,无 handle 回调
        if html.contains("window.location.href") {
            return AjaxResult(success: true, message: "")
        }
        if let alert = extractAlertError(html) {
            return AjaxResult(success: false, message: alert)
        }
        return AjaxResult(success: false, message: "服务器响应无法识别")
    }

    private static func ajaxParam(_ params: String, index: Int) -> String {
        let parts = params.split(separator: ",", omittingEmptySubsequences: false)
        guard index < parts.count else { return "" }
        return String(parts[index])
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
    }

    static func extractAlertError(_ html: String) -> String? {
        guard let document = try? SwiftSoup.parse(html) else { return nil }
        if let text = try? document.select("#messagetext").first()?.text(), !text.isEmpty {
            return text
        }
        if let text = try? document.select("div.alert_error").first()?.text(), !text.isEmpty {
            return text
        }
        return nil
    }

    // MARK: 附件上传(swfupload)

    /// 上传图片,返回附件 aid(负数为失败)
    static func uploadAttachment(
        uploadInfo: AttachmentUploadInfo,
        imageData: Data,
        fileIndex: Int
    ) async throws -> Int {
        let uploadURL = uploadInfo.uploadURL
            ?? URL(string: "misc.php?mod=swfupload&action=swfupload&operation=upload&fid=\(uploadInfo.fid ?? 0)", relativeTo: S1APIClient.shared.baseURL)!
            .absoluteURL
        let raw = try await S1APIClient.shared.postMultipart(
            url: uploadURL,
            fields: [
                "uid": uploadInfo.uid ?? "",
                "hash": uploadInfo.hash,
                "id": "WU_FILE_\(fileIndex)",
                "type": "image/jpeg",
                "size": String(imageData.count),
                "filetype": "jpeg",
            ],
            fileFieldName: "Filedata",
            fileName: "image\(fileIndex).jpg",
            mimeType: "image/jpeg",
            fileData: imageData
        )
        let body = String(data: raw, encoding: .utf8) ?? ""
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        // 响应为纯数字 aid,负数为失败
        if let firstNumber = trimmed.firstMatch(of: /-?\d+/) {
            let aid = Int(firstNumber.0) ?? -1
            guard aid > 0 else {
                throw APIError.server("附件上传失败(\(aid))")
            }
            return aid
        }
        throw APIError.server("附件上传失败:\(String(body.prefix(120)))")
    }

    // MARK: Helpers

    static func resolve(_ href: String, baseURL: URL) -> URL? {
        if let url = URL(string: href), url.scheme != nil { return url }
        return URL(string: href, relativeTo: baseURL)?.absoluteURL
    }
}
