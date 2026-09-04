# MyToken 设置界面重构设计

## 目标

重构 MyToken 的设置窗口，把现有单文件设置页拆成清晰的分类、模型和视图。新设置需要覆盖凭证管理、菜单栏显示排序、弹窗显示排序、刷新设置、登录启动、版本更新和问题反馈。设置里的 Routin 签到区块移除。

本次重构遵循两个额外约束：

1. 真实菜单栏和真实弹窗分别消费独立的顺序配置，避免继续通过菜单栏选择项推导弹窗顺序。
2. 设置界面采用现代 macOS 设计语言，并使用液态玻璃材质；在旧系统上保留可用的降级样式。

## 现状问题

当前 `SettingsView.swift` 同时承担导航、凭证列表、用量详情、菜单栏排序、弹窗排序、系统设置和拖拽实现，职责过多。`AppSettings` 使用 `selectedCredentialIDs` 表示菜单栏顺序，使用 `availableCredentialIDs` 辅助排序；`UsagePopoverView` 再通过 `CredentialDisplayOrder.popoverIDs` 把菜单栏选中项排在前面，导致菜单栏顺序和弹窗顺序没有真正解耦。

## 信息架构

设置窗口侧边栏分为五类：

1. **凭证管理**
   - 添加凭证。
   - 编辑凭证。
   - 启用 / 停用凭证。
   - 删除凭证，删除前确认。
   - 自动按供应商分组。
   - 支持按状态和供应商筛选。
   - 主列表保持轻量，不把完整用量详情展开在每一行里。

2. **菜单栏显示**
   - 展示当前菜单栏图标序列的模拟条。
   - 展示区最多显示 5 个已启用凭证。
   - 每行开头使用真实 `MenuBarIndicatorModel` 生成的短码和进度条图标。
   - 行内显示别名、供应商和套餐类型。
   - 待选区显示未进入菜单栏的已启用凭证。
   - 支持展示区内排序、待选区排序、待选区拖入展示区、展示区拖回待选区。
   - 排序实时反映到真实菜单栏。

3. **弹窗显示**
   - 只显示已启用凭证。
   - 使用一个宽约 440 点的弹窗模拟界面。
   - 每行只显示别名、供应商和套餐类型。
   - 模拟列表本身可拖拽排序。
   - 排序实时反映到真实弹窗。

4. **通用**
   - 保留刷新间隔设置。
   - 保留登录启动设置。
   - 暂时保留显示维度、通知开关和通知阈值，避免已有功能意外丢失。

5. **帮助与更新**
   - 显示当前版本。
   - 检查更新。
   - 展示更新状态、下载进度和发布说明。
   - 提供问题反馈入口。
   - 移除设置内的 Routin 签到区块；弹窗中已有的签到能力不在本次设计里删除。

## 顺序与数据模型

新增 `CredentialDisplayOrder`，负责顺序、过滤、迁移和变更规则。真实展示层不再使用 `selectedCredentialIDs + availableCredentialIDs` 推导弹窗顺序。

### 配置字段

```swift
struct CredentialDisplayOrder: Codable, Equatable, Sendable {
    var menuBarCredentialIDs: [UUID]
    var popoverCredentialIDs: [UUID]
}
```

- `menuBarCredentialIDs`：菜单栏展示顺序，最多 5 个 UUID。
- `popoverCredentialIDs`：弹窗完整稳定顺序。
- 展示时统一过滤掉不存在、已删除或 `isEnabled == false` 的凭证。
- 停用凭证不从底层顺序数组移除，重新启用后回到原位置。
- 删除凭证时同步从两个数组移除。
- 新增凭证追加到 `popoverCredentialIDs` 末尾，并自然出现在菜单栏待选区；不自动加入菜单栏展示区。
- `menuBarCredentialIDs.count > 5` 必须被规范化到前 5 个。
- 两个数组都必须去重。

### 派生序列

```text
visibleMenuBarIDs  = menuBarCredentialIDs  过滤为已启用且仍存在
visiblePopoverIDs  = popoverCredentialIDs  过滤为已启用且仍存在
menuBarCandidateIDs = visiblePopoverIDs - visibleMenuBarIDs
```

菜单栏待选区直接使用 `visiblePopoverIDs` 的相对顺序。这样只需要维护两个独立展示序列，不需要第三个候选区数组。

### 变更 API

`CredentialDisplayOrder` 提供纯函数式变更规则：

- `movingMenuBar(from:to:)`
- `movingPopover(from:to:)`
- `addingToMenuBar(_:at:)`
- `removingFromMenuBar(_:at:)`
- `removingCredential(_:)`

所有变更返回新的 `CredentialDisplayOrder`。UI 层只调用这些规则，不手写分散的数组移动逻辑。

### 持久化与迁移

新配置写入版本化键：

```text
displayOrder.v1
```

首次读取时迁移旧配置：

1. `selectedCredentialIDs` 迁移为 `menuBarCredentialIDs`。
2. `popoverCredentialIDs = selectedCredentialIDs + availableCredentialIDs + orderedKeyIDs`。
3. 合并过程中去重，并保留底层凭证列表中的有效 UUID。
4. 新键存在时忽略旧键。
5. 旧键在一个过渡版本内保留，不主动删除；旧版本回滚时最多损失新排序，不损失凭证和功能。

`UsageStore` 删除凭证时通知顺序模型清理对应 UUID。新增、启用、停用、刷新只影响有效展示序列，不改变未展示的底层稳定顺序。

## 真实展示层联动

### 菜单栏

`StatusBarController` 改为读取：

```text
settings.displayOrder.menuBarCredentialIDs
```

过滤有效启用凭证后生成 `MenuBarIndicatorModel`。它不再读取 `selectedCredentialIDs`。设置页的菜单栏模拟条和真实 `NSStatusItem` 使用同一套图标生成 API，避免设置页出现第二套视觉标准。

### 弹窗

`UsagePopoverView` 改为读取：

```text
settings.displayOrder.popoverCredentialIDs
```

过滤有效启用凭证后直接按顺序渲染。供应商筛选只改变本窗口的显示子集，不改变底层顺序；取消筛选后仍回到完整弹窗顺序。

### 防联动规则

- 调整菜单栏顺序不得改变 `popoverCredentialIDs`。
- 调整弹窗顺序不得改变 `menuBarCredentialIDs`。
- 从弹窗顺序中移动一个已进入菜单栏的凭证，不得影响它在菜单栏中的位置。
- 停用凭证会同时从两个真实展示面消失，但两个底层数组中的位置保留。
- 重新启用后，凭证分别回到两个数组中的原位置。
- 删除凭证必须从两个数组、凭证列表、Keychain 和用量缓存中移除。

## 界面设计

### 设计原则

界面保持原生 macOS 层级，不引入网页式营销结构。视觉重心放在可扫描的凭证列表和实时排序模拟上。深浅色都由系统外观驱动，不使用固定的深蓝色主题。

### 窗口结构

- 建议尺寸：880 × 640 点。
- 最小尺寸：820 × 560 点。
- 左侧导航约 220 点，使用半透明侧边栏。
- 右侧内容区顶部为页面标题和副标题，下方为可滚动内容。
- 全窗口使用现有 `liquidGlassWindowBackground()`。

### 导航

侧边栏使用系统图标和短标签：

| 分类 | 图标语义 |
| --- | --- |
| 凭证管理 | 钥匙 |
| 菜单栏显示 | 菜单栏 / 图标组 |
| 弹窗显示 | 浮层 |
| 通用 | 开关 |
| 帮助与更新 | 生命环 / 问答 |

选中项使用玻璃胶囊高亮；未选中项使用次级文字颜色。侧边栏不显示额外描述文字，保持安静。

### 材质层级

macOS 26 及以上使用 `glassEffect`，旧系统使用 `.regularMaterial`、hairline 描边和低强度阴影降级。

| 层级 | 材质 |
| --- | --- |
| 窗口底层 | 透明玻璃窗口背景 |
| 页面内容区 | 不额外包一层卡片 |
| 重复凭证行 / 分组表面 | 轻玻璃表面 |
| 主操作按钮 | `.glassProminent` |
| 次级按钮 | `.glass` |
| 拖拽中的行 | 提高透明度和轻阴影 |

玻璃样式继续收敛在 `LiquidGlassSurface`，设置页不直接散落硬编码材质参数。浅色和深色下都必须满足正文对比度；描边和阴影按系统外观调整强度。

### 形状与排版

- 页面区块圆角：18 点。
- 凭证行圆角：12 点。
- 普通控件圆角：8 到 10 点。
- 状态徽标：6 点或胶囊。
- 间距使用 8 点网格。
- 标题使用系统字体，不引入自定义字体。
- 页面标题使用 `.title2` / `.title3`。
- 正文使用 13 到 15 点。
- 元数据和数值使用 `monospacedDigit`。
- 供应商和状态只用小面积色彩，不让整个页面变成多色卡片堆。

## 页面布局

### 凭证管理

页面顶部为标题、数量摘要和“添加凭证”按钮。标题下方放一行筛选控件：

- 全部 / 启用 / 停用。
- 供应商胶囊筛选。
- 搜索别名。

凭证按供应商分组。分组头显示供应商图标、名称和数量，可折叠。凭证行为单行结构：

```text
[供应商图标] 别名 / 供应商 / 套餐类型 / 状态摘要     [启用开关] [编辑] [删除]
```

停用行降低不透明度并显示“已停用”。删除按钮触发确认对话框，说明会删除本地密钥和缓存。列表保留键盘焦点和 VoiceOver 标签。

### 菜单栏显示

页面顶部放一个真实比例的菜单栏模拟条，实时渲染当前展示区图标序列。下方为两块区域：

```text
展示区 3/5
[短码+进度条图标] 别名 / 供应商 / 套餐类型     [移除]

待选区 6
[短码+进度条图标] 别名 / 供应商 / 套餐类型     [添加]
```

宽窗口时展示区和待选区左右并排；窄窗口时上下堆叠。所有行常驻可拖拽，不再提供“先点击排序再拖动”的二级模式。展示区满 5 个时拒绝拖入，按钮也禁用。

每行保留无拖拽的辅助操作：加入展示区、移到待选区、上移、下移。这些操作服务键盘和辅助功能用户，不作为主要视觉入口。

### 弹窗显示

页面直接提供一个 440 点宽的模拟弹窗。模拟弹窗内的行就是排序编辑对象：

```text
[供应商图标] 别名        供应商 · 套餐类型     [拖拽把手]
```

模拟弹窗底部显示“实时同步到菜单栏弹窗”。真实弹窗继续展示完整用量内容；设置页只负责顺序预览和调整，不复制完整用量卡片。

### 通用

使用系统分组表单：

1. 刷新：1 / 5 / 15 / 30 分钟。
2. 启动：登录时启动。
3. 显示：当前显示维度。
4. 通知：通知开关、低阈值、高阈值。

每个分组有短标题和一行说明，不在同一表单里混杂多个大卡片。

### 帮助与更新

更新状态使用独立状态区，不与反馈按钮挤在一行：

1. 当前版本。
2. 检查更新状态。
3. 下载进度。
4. 可用版本的发布说明。
5. 重试 / 安装更新。
6. 提交问题反馈。

更新说明继续使用现有 Markdown 渲染器。

## 组件与文件拆分

### 模型和控制器

- `Models/CredentialDisplayOrder.swift`：顺序规则、过滤和迁移。
- `App/CredentialOrderingController.swift`：桥接设置、凭证仓库和用量仓库。

### 设置视图

- `Views/Settings/SettingsWindowView.swift`：窗口壳、侧边栏和页面路由。
- `Views/Settings/CredentialManagementView.swift`。
- `Views/Settings/CredentialRowView.swift`。
- `Views/Settings/MenuBarOrderingView.swift`。
- `Views/Settings/PopoverOrderingView.swift`。
- `Views/Settings/GeneralSettingsView.swift`。
- `Views/Settings/HelpUpdateView.swift`。

### 共享组件

- `Views/Settings/Components/SettingsPageHeader.swift`。
- `Views/Settings/Components/CredentialSummaryRow.swift`。
- `Views/Settings/Components/MenuBarIndicatorPreview.swift`。
- `Views/Settings/Components/CredentialDropDelegate.swift`。
- `Views/Settings/Components/ProviderFilterChips.swift`。

现有 `SettingsView.swift` 在新入口验证通过后删除，避免长期保留两套入口。

## 拖拽实现

- 使用自定义 `UTType`，例如 `ai.routin.mytoken.credential`。
- 每个 `NSItemProvider` 携带凭证 UUID。
- 所有行支持 `.onDrag`。
- 目标行和区域空位支持 `.onDrop`。
- 拖拽数据进入视图前先校验 UUID 是否存在于允许来源。
- 跨区域移动和区域内移动都由 `CredentialDisplayOrder` 的纯函数处理。
- 插入位置显示 2 点高亮线。
- 被拖拽行使用轻微透明和阴影，不使用夸张缩放。
- 尊重“减弱动态效果”；开启后取消弹簧动画和拖拽缩放。

## 错误与边界

- 凭证名称为空或密钥无效时，编辑器保持打开并显示具体错误。
- 删除缓存失败时，凭证从界面移除，但显示“缓存清理失败”提示。
- 登录启动同步失败时，开关回滚并显示系统级错误信息。
- 更新检查失败保留旧状态并提供重试。
- 排序数组包含无效 UUID 时静默过滤，不阻塞 UI。
- 菜单栏超过 5 个时按持久化顺序截断到 5 个。

## 无障碍

每一行提供完整 VoiceOver 标签，例如：

```text
DeepSeek 生产环境，供应商 DeepSeek，套餐余额，已启用
```

排序行提供明确的辅助操作名称：上移、下移、添加到菜单栏、从菜单栏移除。拖拽把手不作为唯一修改顺序的方式。玻璃表面上的文字和图标在浅色、深色、增强对比度模式下都保持可读。

## 测试

### 单元测试

1. 新配置初始化和持久化解码。
2. 旧 `selectedCredentialIDs` / `availableCredentialIDs` 迁移。
3. 菜单栏最多 5 个、去重、过滤停用和已删除凭证。
4. 弹窗完整顺序过滤停用和已删除凭证。
5. 菜单栏排序不影响弹窗顺序。
6. 弹窗排序不影响菜单栏顺序。
7. 新增凭证只进入弹窗末尾和菜单栏待选区。
8. 删除凭证同步清理两个数组。
9. 真实菜单栏和真实弹窗读取新字段。
10. 旧字段不再作为弹窗顺序来源。

### 界面测试

1. 设置窗口能展示五个导航分类。
2. 凭证能按供应商分组。
3. 禁用凭证后菜单栏和弹窗模拟立即消失该凭证。
4. 菜单栏拖拽更新模拟条。
5. 弹窗拖拽更新模拟列表。
6. 删除凭证后两个排序页不再显示该凭证。

### 手工验收

1. 配置至少 7 个启用凭证。
2. 分别调整菜单栏和弹窗顺序，确认真实界面实时更新且互不影响。
3. 停用并重新启用凭证，确认两个顺序都能恢复。
4. 删除凭证，确认排序、Keychain 和缓存清理。
5. 在浅色、深色、增强对比度和“减弱动态效果”下检查设置窗口。
6. 窗口缩放到最小宽度，确认两个排序区域正确堆叠。
7. 重启应用，确认新顺序持久化。
8. 从旧配置升级，确认菜单栏顺序不丢。

## 实施阶段

1. 新增 `CredentialDisplayOrder` 和迁移测试。
2. 接入新配置，并切换真实菜单栏和真实弹窗的数据源。
3. 搭建新设置窗口壳和导航。
4. 重建凭证管理页。
5. 重建菜单栏展示区 / 待选区拖拽页。
6. 重建弹窗模拟排序页。
7. 重建通用设置和帮助更新页。
8. 移除设置内 Routin 签到区块和旧设置文件。
9. 运行全量测试和多屏、浅深色、窄窗口手工验收。

## 风险

拖拽排序是最容易产生平台差异的部分，因此排序规则必须先落到纯函数测试中，SwiftUI 的拖拽层只负责输入输出。液态玻璃 API 有系统版本差异，所有新页面必须统一通过 `LiquidGlassSurface` 取得材质，不允许页面内各自实现降级逻辑。独立顺序配置迁移时必须保留旧键一个版本，降低回滚影响。
