# Apex Dashboard 只读解析架构

## 边界与数据流

未来的读取链路为：用户选定文件 → 严格读取 UTF-8 → 解析 YAML 文件头 → 扫描 Markdown 列／卡片／复选框 → 生成不可变 `Dashboard` 快照 → Tasks 界面。解析层不依赖 SwiftUI、AppKit 或 Codex Provider，不修改文件，也不把私人任务写进日志或持久缓存。初期放在现有 `Core`／`Features/Tasks` 边界内；只有独立复用和测试需求出现时再抽成 Swift Package。

首版只解释 [结构分析](apex-dashboard-analysis.md)中已确认的 Apex 子集。YAML 应按 YAML 语义读取 `dashboard` 与 `columns`，不能用跨全文的单个正则猜列名；正文以行扫描器处理标题和任务。未识别的结构应返回明确错误或忽略非任务内容，绝不把任务分配到错误列。具体 YAML 解析依赖在实现阶段评估，不为本次文档任务添加依赖。

## 概念数据模型

| 模型 | 最少字段 | 说明 |
| --- | --- | --- |
| `Dashboard` | `fileURL`, `columns`, `loadedAt` | 一次成功读取的快照，保留来源和原文件顺序。 |
| `Column` | `name`, `type`, `color?`, `cards`, `sourceOrder` | 来自 frontmatter 与对应 `##` 标题；页签按 `sourceOrder` 排列。 |
| `Card` | `id?`, `title`, `type?`, `tasks`, `sourceOrder` | `id` 可能缺失；标题和类型不能代替任务标识。 |
| `Task` | `text`, `completed`, `fileURL`, `lineNumber`, `blockIdentifier?`, `sourceOrder` | `lineNumber` 从 1 开始，指向该快照中的复选框行；只有明确存在 Markdown `^block-id` 时才填 `blockIdentifier`。 |

`fileURL` 让“在 Obsidian 打开”始终指向任务的真实来源，也为未来重新读取与权限检查提供目标。`lineNumber` 方便诊断、在原文中定位和未来写回前核对，但插件重排或外部编辑会改变它；它**不是稳定任务 ID**。`blockIdentifier` 是可选的显式锚点，当前样本没有。界面可为当前快照组合列序号、卡片 ID／序号和任务序号形成临时行标识，刷新后不能据此认定是同一任务。

## 解析规则与失败边界

1. 只读用户选中的 `.md` 文件，严格解码 UTF-8；无效编码报错，不做有损替换。
2. 读取文件头的 `dashboard: true` 和有序 `columns`。正文仅识别代码围栏外行首的 `##` 列标题和 `###` 卡片标题。正文列与声明列若无法可靠匹配，应报格式错误，不按位置猜测归属。
3. 在卡片范围内识别普通复选框行，区分 `[ ]` 与 `[x]`／`[X]`；卡片级 `id:`、`type:` 不显示为任务。保留原始任务文字和一基行号；缺少可解析文本的行不制造空任务。
4. 空列保留为空列；不从 Vault 其他笔记、备份目录或插件配置中聚合任务。标签、日期、提醒、递归、层级折叠等在首版没有独立语义。
5. 成功时一次性发布完整快照；读取或解析失败时不把上一次快照伪装成当前数据。错误分类交由 [连接流程](apex-onboarding-design.md)呈现。

后续若增加写回，必须重新设计稳定定位与冲突校验；本只读模型不赋予 `lineNumber` 写入权限。
