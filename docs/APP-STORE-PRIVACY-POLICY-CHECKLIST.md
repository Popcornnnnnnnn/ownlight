# App Store 隐私政策复查清单

Last updated: 2026-06-21

本文档只管理 Privacy Policy 页面本身和 App Store 隐私入口要求。App Privacy Label、PrivacyInfo.xcprivacy、权限 purpose strings、第三方 SDK manifest、实际网络/数据流审计属于独立上架任务，不能因为本页面写了说明就视为完成。

## 官方依据

- [Apple App Review Guidelines 5.1.1(i) Privacy Policies](https://developer.apple.com/app-store/review/guidelines/)：所有 App 必须在 App Store Connect metadata 和 App 内易访问位置提供隐私政策链接；政策必须说明收集什么数据、如何收集、所有用途、第三方共享保护、保留/删除，以及如何撤回同意或请求删除。
- [Apple App Store Connect App privacy](https://developer.apple.com/help/app-store-connect/reference/app-information/app-privacy/)：Privacy Policy URL 对所有 App 必填；User Privacy Choices URL 可选。
- [Apple App privacy details](https://developer.apple.com/app-store/app-privacy-details/)：App Privacy Label 必须覆盖 App 和第三方 partner 的数据实践；只在设备上处理且不发出设备的数据通常不算 App Store Connect 问卷中的 collected data，但仍应在政策里说清楚产品行为。

## Privacy Page 必须满足

| Status | Check | 当前结论 |
| --- | --- | --- |
| [x] | 公开 HTTPS Privacy Policy URL | 简中：`https://private-moments.popcornnn.xyz/privacy/zh-Hans`；英文：`https://private-moments.popcornnn.xyz/privacy/en`；`/privacy` 为语言选择页 |
| [x] | App 内易访问入口 | Settings > `Privacy & Support` 可按当前 App 语言打开 Privacy Policy |
| [x] | 明确无账号 / 无登录 / 无开发者账号删除 | 页面说明第一版没有账号、注册、登录；删除 App 即删除本地 app container |
| [x] | 明确无广告 / 无 tracking / 无第三方 analytics SDK | 页面已有 `No tracking or third-party analytics` |
| [x] | 说明处理哪些数据 | 页面已有 `Data we handle` 表格，覆盖 moments、media、AI artifacts、settings/diagnostics |
| [x] | 说明如何收集数据 | 表格列出用户创建、录制、选择、Share Sheet/import、设置、AI 生成等来源 |
| [x] | 说明数据用途 | 表格列出 timeline、calendar、search、filters、tags、playback、export、AI 组织与诊断用途 |
| [x] | 说明数据共享边界 | 页面说明第一版不发到开发者账号服务；只有用户主动启用 iCloud/export/share/user-configured AI 时数据才会离开 iPhone |
| [x] | 说明第三方 AI / BYOK provider 边界 | 页面说明用户选择 provider/endpoint，provider 按自身隐私政策处理，Ownlight 不提供开发者托管默认 AI |
| [x] | 说明 iCloud Sync 边界 | 页面说明 iCloud Sync 可选；可用时存到用户 private iCloud database，AI secrets 保持本机 |
| [x] | 说明导出文件风险 | 页面说明 export packages 可能包含私密内容，用户需自行安全保存和删除 |
| [x] | 说明撤回同意 | 页面说明关闭 AI/移除 provider credentials、关闭 iCloud Sync、撤销 iOS 权限 |
| [x] | 说明保留政策 | 页面说明本地内容保留到用户编辑/删除/删 App；iCloud、export、AI provider 各自保留边界 |
| [x] | 说明删除方式 | 页面说明无开发者账号可删，本地删 App，外部导出/iCloud/AI provider 需用户分别删除 |
| [x] | 提供真实联系方式 | `support@popcornnn.xyz` 已配置 Cloudflare Email Routing 并完成外部收信测试 |

## 暂不在 Privacy Page 内完成的事项

| Status | Check | 原因 / 后续位置 |
| --- | --- | --- |
| [x] | App Privacy Data Inventory 第一版 | 2026-06-02 已新增 `docs/APP-PRIVACY-DATA-INVENTORY.md`，逐项盘点实际代码、SDK、网络请求、CloudKit/AI 行为；2026-06-21 v1 提交前已按当前 archive/source preflight 复核 |
| [x] | App Privacy Label 草案 | 2026-06-08 已在 `docs/APP-STORE-SUBMISSION-DRAFT.md` 集中整理主口径、保守备选、目的和 tracking 判断 |
| [x] | App Privacy Label 最终填写 | 2026-06-11 App Store Connect final answer 已发布为 `Data Not Collected`；2026-06-21 复核 Product Page Preview 仍显示 `Data Not Collected` / `Data is not collected from this app`。v1 提交审核前已按当前 archive/source preflight 复核事实一致性 |
| [x] | PrivacyInfo.xcprivacy source preflight | `npm run doctor:app-store` 已检查当前 source manifest、required reason API、tracking/collected-data 基础项；最终 archive privacy report 仍需上传前复核 |
| [x] | 权限 purpose strings source preflight | `npm run doctor:app-store` 已检查 Camera、Photos、Microphone、Speech、Local Network purpose strings 非空且非 placeholder；真实拒绝路径仍属最终 UAT |
| [x] | AI 开启前 explicit consent UI | App 内已实现 AI external processing consent gate；页面之外的功能项仍需最终截图/文案复核 |
| [x] | CloudKit source 措辞复核 | M017 CloudKit 第一阶段 UAT 已关闭，当前 Privacy Policy 和 inventory 已描述 opt-in iCloud Sync / private database / no separate Ownlight account 边界；v1 提交前已按截图、App Privacy label 和 App Review Notes 复核 |
| [x] | 法律本地化 / 中文正式版本 | 已提供独立简体中文和英文 Privacy Policy 页面；v1 提交前已按当前 build 做事实复核，后续行为变更时重新复核 |

## 上架前复查方式

1. 重新打开 Apple 官方文档，确认 Privacy Policy URL、User Privacy Choices URL、5.1.1(i)、5.1.2(i) 没有新变化。
2. 用线上 URL 检查页面可公开访问，无登录、无跳转错误、HTTPS 正常。
3. 对照最终 build 的实际行为，逐项核对本清单，不允许页面写“无 tracking/无 analytics/无开发者服务”但代码实际接入相关 SDK 或 endpoint。
4. 对照 App Store Connect App Privacy Label 草案，确保页面、问卷、App Review Notes、App 内 disclosure 口径一致。
