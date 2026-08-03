# KNcard Flutter App 技术选型与实施方案

## 1. 文档信息

| 项目 | 内容 |
| --- | --- |
| 文档名称 | KNcard Flutter App 技术选型与实施方案 |
| 文档版本 | v1.0 |
| 编写日期 | 2026-08-01 |
| 目标平台 | Android、iOS |
| 技术基线 | Flutter stable、Dart 3.x |
| 参考实现 | `knowledge-review-electron` 及其 Node/Prisma V2 后端 |
| 当前约束 | App 当前只读使用，不实现内容编辑 |

## 2. 选型结论

推荐采用：

| 层次 | 选择 |
| --- | --- |
| UI 框架 | Flutter stable + Material 3，必要时使用少量自定义 Design System |
| 语言 | Dart 3.x，启用 sound null safety |
| 状态管理 | Riverpod，优先 `riverpod_generator` 和 `flutter_riverpod` |
| 路由 | `go_router`，使用 ShellRoute/StatefulShellRoute 管理主导航 |
| 网络 | Dio + 拦截器 + 统一 ApiClient |
| 数据模型 | Freezed + `json_serializable` |
| 本地数据库 | Drift + SQLite |
| 安全存储 | `flutter_secure_storage` |
| Markdown | `flutter_markdown`，必要时扩展自定义 InlineSyntax/Builder |
| LaTeX | `flutter_math_fork` |
| 图片 | `cached_network_image`，必要时接入自定义缓存策略 |
| 外部链接 | `url_launcher` |
| 网络状态 | `connectivity_plus`，配合真实请求结果判断可用性 |
| 设备信息 | `device_info_plus` |
| 日志 | `talker` 或 `logger`，生产环境脱敏 |
| 文件与临时目录 | `path_provider`、`path`、`archive` |
| 序列化与哈希 | `crypto`，用于对象签名和下载包校验 |
| 测试 | `flutter_test`、`test`、集成测试；Golden 按页面风险选择 |
| 架构 | feature-first + 轻量 Clean Architecture |

核心判断：App 是网络同步和本地离线并重的学习工具，数据一致性、可测试性和生命周期行为比单纯快速堆页面更重要。因此采用明确的 Domain、Repository 和本地数据层，避免 UI 直接操作 API 或数据库。

## 3. Flutter 版本与工程基线

### 3.1 Flutter

使用 Flutter stable channel，不锁定到过时的具体小版本；项目初始化时记录实际 Flutter/Dart 版本，并在 CI 中固定版本。原因：

- stable 通道更适合长期维护和应用商店发布。
- Flutter 的 Android/iOS 构建链和插件兼容性以 stable 为主要验证目标。
- 未来需要平板、桌面或 Web 扩展时，Flutter 的跨平台布局能力可以复用领域层。

### 3.2 工程约束

- 启用 Dart sound null safety。
- 使用 `analysis_options.yaml` 开启较严格的静态检查。
- 所有网络、数据库和文件操作使用异步 API。
- 使用 UTC 存储时间，展示时转换为用户时区。
- 不在 Widget 中直接调用 `Dio`、Drift DAO 或 FSRS 算法。
- 不在日志中输出令牌、密码、完整卡片正文和用户隐私资料。
- Android/iOS 的签名、服务器地址和环境配置通过构建变量管理。

## 4. 架构方案

### 4.1 总体分层

```text
Presentation
  Pages / Widgets / Controllers / Providers
          |
Domain
  Entities / UseCases / Repository Interfaces / Review Engine Interface
          |
Data
  Repository Implementations / Remote DataSource / Local DataSource / DTOs
          |
Infrastructure
  Dio / Drift / Secure Storage / Connectivity / File System / Platform APIs
```

### 4.2 Feature-first 目录

建议目录：

```text
lib/
  main.dart
  app/
    app.dart
    router.dart
    theme/
    bootstrap.dart
  core/
    config/
    errors/
    logging/
    network/
    security/
    time/
    result/
    database/
    sync/
  features/
    auth/
      data/
      domain/
      presentation/
    library/
      data/
      domain/
      presentation/
    cards/
      data/
      domain/
      presentation/
    review/
      data/
      domain/
      presentation/
    market/
      data/
      domain/
      presentation/
    sync/
      data/
      domain/
      presentation/
    settings/
      data/
      domain/
      presentation/
  shared/
    widgets/
    markdown/
    pagination/
    formatting/
```

### 4.3 为什么不采用重量级模板

不建议一开始引入大型状态框架、服务定位器或过度抽象的多模块模板。KNcard 的核心复杂度来自同步、复习算法和内容渲染，而不是页面数量。Riverpod + feature-first 已经足以表达依赖关系和生命周期，减少初期样板代码和后期迁移成本。

## 5. 状态管理：Riverpod

### 5.1 选择理由

- Provider 依赖显式，适合认证状态、账户作用域、数据库和同步服务的组合。
- 支持异步状态和 loading/error/data 三态，适合列表、详情、市场和同步任务。
- 测试时可以替换 Provider，不需要启动真实网络或数据库。
- 与 Flutter Widget 生命周期协作好，能避免手写大量 `ChangeNotifier` 清理逻辑。
- 可以把账户切换建模为 ProviderScope 或账户作用域重建，减少旧账户数据残留。

### 5.2 使用规则

- 页面只读取 Controller/Notifier 暴露的状态。
- Repository 和 UseCase 通过 Provider 注入。
- 不把整个应用状态塞进单个全局对象。
- 认证状态、网络状态、同步状态、复习会话和页面筛选状态分开管理。
- 数据库事务由 Repository 执行，Controller 只处理业务结果和 UI 状态。

### 5.3 建议 Provider

```text
authSessionProvider
accountScopeProvider
databaseProvider
apiClientProvider
connectivityStatusProvider
syncCoordinatorProvider
libraryRepositoryProvider
cardRepositoryProvider
reviewRepositoryProvider
reviewSessionControllerProvider
marketRepositoryProvider
reviewSettingsProvider
```

## 6. 路由：go_router

### 6.1 选择理由

- 支持声明式路由、深链接和路由守卫。
- `StatefulShellRoute` 适合底部导航的多分支状态保持。
- 可以集中处理未登录、令牌失效、账户资料未完善和详情页回退。
- 路由参数可直接表达文档 ID、卡片 ID 和牌组 ID。

### 6.2 路由规则

```text
/auth/login
/auth/register
/auth/profile-completion
/(shell)/review
/(shell)/library
/(shell)/cards
/(shell)/market
/(shell)/settings
```

守卫只负责导航决策，不在 `redirect` 中执行长时间全量同步。同步由登录成功后的 Coordinator 负责，避免路由初始化卡死。

## 7. 网络层：Dio

### 7.1 选择理由

- 拦截器适合统一注入 Bearer Token、刷新令牌、请求 ID 和日志脱敏。
- 支持连接超时、接收超时、取消请求和统一异常映射。
- 便于为市场下载、同步批量请求和普通 JSON API 设置不同策略。
- 可在测试中替换 Adapter，验证 401、超时、5xx 和冲突响应。

### 7.2 ApiClient 设计

```text
ApiClient
  get<T>()
  post<T>()
  patch<T>()
  delete<T>()
  downloadToFile()

Interceptors
  AuthInterceptor
  RefreshTokenInterceptor
  RequestIdInterceptor
  SafeLogInterceptor
```

认证刷新必须防止并发刷新风暴：多个请求收到 401 时共享同一个刷新 Future，刷新失败后统一清理会话并通知路由层。

### 7.3 超时和重试

- 普通 API：连接超时 10 秒，接收超时 20 秒；具体值由实际网络测试校准。
- 市场牌组下载：使用更长的接收超时并支持取消。
- 同步请求：由同步 Coordinator 负责指数退避，不在 Dio 全局盲目重试所有请求。
- 4xx 数据错误不重试；401 先刷新令牌；网络异常和 5xx 才按策略重试。

## 8. 数据模型：Freezed + json_serializable

### 8.1 选择理由

- 不可变对象适合同步合并、复习状态转换和页面状态比较。
- 联合类型可以表达卡片类型、FSRS 状态和同步状态。
- 自动生成 `copyWith`、相等判断、JSON 转换，减少手写错误。
- DTO 与 Domain Entity 可以分离，避免后端字段变化直接污染 UI。

### 8.2 模型分层

```text
Remote DTO
  JSON 字段兼容后端
       |
Mapper
       |
Domain Entity
  面向业务的不可变模型
       |
Local Record
  Drift 表和 JSON 扩展字段
```

`CardDto` 不应直接作为 Widget 的模型。后端可能保留 `fsrs`、`pushStatus` 等兼容字段，Domain 层应统一默认值、日期解析和类型校验。

### 8.3 卡片类型建模

可以使用一个通用 `Card` 实体加 `CardType` 枚举，理由是四种类型共享同步、排序和复习字段。展示层通过类型分支渲染；如果未来类型差异明显，再演进为 Freezed sealed union。

## 9. 本地数据库：Drift + SQLite

### 9.1 选择理由

- Drift 提供类型安全的表、查询和事务 API。
- SQLite 适合卡片、文档、复习事件和同步队列的关系查询。
- 支持索引、分页、迁移和流式查询。
- 事务可以保证“更新卡片 + 插入复习事件 + 加入同步队列”原子完成。
- 比单纯 JSON 文件更适合搜索、筛选、排序和大量卡片场景。

### 9.2 表设计

```text
accounts
documents
folders
cards
review_events
review_statistics
market_decks
market_favorites
subscriptions
sync_objects
sync_queue
sync_tombstones
app_settings
```

所有账户相关表必须包含 `account_id`，并建立复合唯一约束。以下索引是 MVP 必需项：

```text
cards(account_id, folder)
cards(account_id, due_at)
cards(account_id, type)
cards(account_id, updated_at)
cards(account_id, suspended)
documents(account_id, folder_id, updated_at)
review_events(account_id, reviewed_at)
sync_queue(account_id, status, next_retry_at)
```

### 9.3 事务边界

复习评分使用一个事务：

1. 读取当前卡片和 FSRS 状态。
2. 计算下一状态。
3. 更新卡片内容不变字段和复习字段。
4. 插入带快照的 `review_event`。
5. 更新当天统计。
6. 写入或合并同步队列对象。

任一步失败都回滚，避免卡片已经更新但复习历史缺失。

### 9.4 数据库迁移

- 每次结构变化递增 schema version。
- 迁移必须有自动化测试和旧版本样本数据库。
- 删除字段先停止写入，再经过至少一个版本的兼容期。
- 大字段和图片不直接塞进主列表查询；使用按需加载或独立资源缓存。

## 10. 安全存储与账户隔离

### 10.1 flutter_secure_storage

用于保存：

- access token。
- refresh token。
- 是否记住账号的非敏感偏好。
- 必要的服务器认证配置。

密码默认不保存。若产品强制保留“记住密码”，必须在安全存储中保存，并明确安全风险；不允许写入 SQLite、SharedPreferences 或普通日志。

### 10.2 账户作用域

- 当前账户 ID 作为所有 Repository 查询的必需条件。
- 退出登录时取消该账户的同步任务和未完成请求。
- 账户切换时重建账户作用域 Provider，并清理内存缓存。
- 服务器地址和设备 ID可以保留，但账户数据、令牌和同步队列必须隔离。

## 11. Markdown、LaTeX 和内容渲染

### 11.1 Markdown

优先使用 `flutter_markdown`，原因是它已经覆盖常见 Markdown 和 GFM 结构，适合作为第一阶段实现基础。需要通过自定义 Builder/InlineSyntax 补充：

- 任务列表和表格的移动端样式。
- 速记词条中的“专题”“真题”“例句”自定义语法。
- 安全链接处理。
- 图片点击放大。
- 代码块复制。

如果 Electron 中保留的是预渲染 HTML，则 App 需要定义 HTML 到 Flutter Widget 的策略。不能直接把不可信 HTML 放进 WebView 作为默认方案，因为链接、脚本和高度自适应会增加安全与交互成本。只有在 Markdown 渲染能力不足且经过安全清洗后，才考虑局部 WebView。

### 11.2 LaTeX

使用 `flutter_math_fork` 渲染行内和块级公式。推荐在 Markdown 解析阶段将 `$...$`、`$$...$$`、`\\(...\\)`、`\\[...\\]` 转换成明确的数学节点。

要求：

- 公式解析失败时显示原文和可读错误占位。
- 块级公式可横向滚动。
- 复杂公式不要在列表滚动中重复创建昂贵对象；必要时做缓存。

### 11.3 图片与链接

- 使用 `cached_network_image` 做缓存、占位和错误态。
- 图片加载不能阻塞正文。
- `url_launcher` 打开外链，协议只允许 `http`、`https`、`mailto` 和锚点。
- 图片 URL 也需要协议白名单；默认拒绝 `data:` 和可执行协议。

## 12. FSRS 复习引擎选型

### 12.1 不能直接复用 ts-fsrs

Electron 使用的是 Node/TypeScript 生态的 `ts-fsrs` 适配器。Flutter/Dart 端不能在技术方案中直接假定存在官方、版本兼容且行为完全一致的 Dart `ts-fsrs` 包。FSRS 的关键在于输出一致，而不是包名看起来相似。

### 12.2 推荐实施顺序

1. 先确认可用 Dart 实现的许可证、版本、参数模型和测试向量。
2. 使用 Electron 适配器产生固定输入/输出测试向量，覆盖四档评分、New/Learning/Review/Relearning、到期时间和复习次数。
3. 如果成熟 Dart 实现无法满足一致性要求，建立独立 `SpacedRepetitionEngine` 接口。
4. 通过受控移植或服务端计算实现适配器，但将算法放在独立包/目录，禁止散落在页面和 Repository 中。
5. 在 Flutter 端和 Electron 端对同一组卡片、时间和评分进行回归比对。

### 12.3 接口建议

```text
SpacedRepetitionEngine
  normalize(Card card) -> FsrsState
  preview(Card card, ReviewSettings settings) -> List<ReviewPreview>
  review(Card card, Rating rating, DateTime now, ReviewSettings settings)
    -> ReviewCalculation
```

`ReviewCalculation` 至少返回新的 FSRS 状态、`dueAt`、`interval`、复习次数、日志字段和评分值。引擎应支持注入时钟，测试不能依赖真实系统时间。

### 12.4 评分映射

```text
Again -> ratingValue 1
Hard  -> ratingValue 2
Good  -> ratingValue 3
Easy  -> ratingValue 4
```

速记词条的“熟悉/模糊/没印象”是 UI 反馈，需要明确映射到 `Good/Hard/Again`。若产品最终保留“太简单”，再映射到 `Easy` 并处理暂停策略。

## 13. 同步架构

### 13.1 组件

```text
SyncCoordinator
  - LoginSyncTrigger
  - ForegroundSyncTrigger
  - ConnectivityRecoveryTrigger
  - ManualSyncTrigger
  - DebouncedPushScheduler

SyncRepository
  - Pull full/incremental objects
  - Push batches <= 100
  - Delete tombstones
  - Register device

ConflictResolver
  - Card resolver
  - Document resolver
  - Settings merger
```

### 13.2 同步对象

第一阶段对接：

- `CARD`：内容字段与复习状态。
- `DOCUMENT`：只读内容和元数据。
- `SETTINGS`：复习设置、计划、收藏和统计所需配置。

`DECK` 主要用于市场订阅和版本元数据，是否纳入通用同步需要和后端接口确认；不要在客户端把市场下载包误当成普通卡片同步对象。

### 13.3 对象签名和队列

- 对规范化 JSON 做稳定排序后计算 SHA-256 签名。
- 签名变化才进入推送队列。
- 删除对象写入 tombstone，服务器确认后再清理本地墓碑。
- 队列字段至少包括账户、对象类型、对象 ID、对象版本、签名、状态、重试次数和错误信息。
- 批量推送最多 100 个对象，成功对象逐条确认版本。

### 13.4 冲突处理

```text
CARD
  内容字段：服务器版本优先
  复习字段：本地复习次数不少于服务器时保留本地 FSRS

DOCUMENT
  比较 updatedAt，较新版本胜出

SETTINGS
  字段级合并，保留有效的本地偏好和复习计划
```

冲突解析必须是纯函数或可独立测试的服务，不能隐藏在 Dio 回调或页面事件中。

### 13.5 移动端生命周期

Electron 可以依赖常驻进程和 5 分钟定时器；移动端不能假定后台常驻。Flutter 使用：

- App 启动/登录。
- `AppLifecycleState.resumed`。
- `connectivity_plus` 的网络恢复事件。
- 用户主动点击同步。
- Android WorkManager/iOS BackgroundTasks 作为尽力而为的后台机制，不能作为数据可靠性的唯一保证。

真正可靠的保证是所有变化先落本地队列，前台恢复时继续处理。

## 14. 市场牌组下载

### 14.1 下载流程

1. 获取牌组详情和版本信息。
2. 下载到临时文件，支持取消和进度。
3. 校验文件大小、哈希或服务端签名。
4. 解压到临时目录。
5. 验证 `manifest.json`、`cards.json` 和资源引用。
6. 解析并校验所有卡片。
7. 在数据库事务中写入牌组元数据和卡片。
8. 成功后删除临时目录；失败时不留下半成品。

### 14.2 安全边界

- 防止 ZIP 路径穿越，解压路径必须限制在临时目录。
- 限制单包大小、文件数量和解压后总大小。
- JSON 解析后进行字段长度和类型校验。
- 资源 URL 不默认执行脚本。
- 牌组版本更新不得静默覆盖用户本地复习状态；需要明确合并规则。

## 15. 认证与令牌

### 15.1 SessionManager

负责：

- 登录、注册、退出登录。
- 读取和保存令牌。
- 刷新令牌。
- 当前用户资料。
- 账户状态和资料完善状态。
- 令牌失效通知。

### 15.2 认证边界

- 访问令牌只存在内存和安全存储的必要位置。
- 退出登录时清理令牌、取消请求、停止同步和清理账户 Provider。
- 自动登录失败不应让登录页永久显示加载中。
- 所有认证请求设置明确超时。
- 修改密码成功后应使旧刷新令牌失效或重新建立会话，具体以服务端行为为准。

## 16. UI 与响应式设计

### 16.1 设计原则

- Material 3 作为基础组件系统，颜色、间距、字体和状态统一定义。
- 复习页面优先保证题干、选项和评分按钮的触控面积。
- 使用 `SafeArea`、滚动容器和稳定布局约束适配刘海屏及小屏幕。
- 卡片列表使用轻量列表项，不把复杂内容全部渲染在列表中。
- 详情页使用 Sliver 或分段区域，支持较长文档和代码块横向滚动。
- 所有交互状态必须可视化：加载、提交中、离线、待同步、失败和成功。

### 16.2 可访问性

- 使用语义化控件和 `Semantics` 标签。
- 不只依赖颜色表达对错或熟练度。
- 支持系统字体放大，不固定高度裁切题干。
- 评分按钮和选项按钮满足移动端触控尺寸。
- 支持系统返回键和屏幕阅读器的合理焦点顺序。

## 17. 测试方案

### 17.1 单元测试

覆盖：

- 卡片 JSON 映射和字段默认值。
- 到期判断、每日总上限和新卡上限。
- 复习优先级与排序。
- FSRS 四档评分和速记反馈映射。
- 复习事件生成和统计聚合。
- Markdown 危险链接过滤、LaTeX 节点和公式失败回退。
- 同步签名、队列去重、版本更新和冲突合并。

### 17.2 Repository 测试

- 使用内存 SQLite 或测试数据库。
- 验证复习事务原子性。
- 验证账户隔离和退出登录清理。
- 验证增量拉取、批量推送、删除墓碑和重试。
- 验证损坏市场包不会写入半成品。

### 17.3 Widget 测试

- 登录成功、失败、超时和令牌失效。
- 复习答题、反馈、评分和完成页。
- 卡片筛选、分页和空状态。
- 文档渲染和外链点击。
- 同步状态、离线标识和重试按钮。

### 17.4 集成测试

至少覆盖：

1. 首次登录并完成全量同步。
2. 断网阅读和复习，恢复网络后同步。
3. 两个设备制造卡片内容与复习状态冲突。
4. 下载合法牌组和处理损坏牌组包。
5. 退出账户后切换账户，确认数据不串号。

## 18. CI、质量和发布

CI 建议步骤：

1. `flutter pub get`
2. `dart format --set-exit-if-changed .`
3. `flutter analyze`
4. `flutter test`
5. 关键集成测试和构建检查

发布前检查：

- Android/iOS 真机网络切换。
- 低网络、高延迟和请求超时。
- 系统字体放大和无障碍。
- 大量卡片滚动和长文档渲染。
- 应用被系统杀死后恢复同步队列。
- 应用商店隐私声明、权限说明和安全存储检查。

## 19. 分阶段实施计划

### 阶段 0：工程骨架

- 建立 Flutter stable 工程、环境配置和 CI。
- 接入 Riverpod、go_router、Dio、Drift、Freezed。
- 建立错误模型、日志和安全存储。
- 用假数据跑通主导航和登录门禁。

### 阶段 1：只读内容与本地复习

- 完成账户模型和本地数据库。
- 完成卡片库、文档阅读和统一内容渲染。
- 完成复习队列、FSRS 接口、本地事务和历史统计。
- 完成离线复习和本地待同步队列。

### 阶段 2：云同步

- 接入登录、刷新令牌、全量拉取和批量推送。
- 完成卡片、文档、设置的冲突合并。
- 完成网络恢复、前台恢复、手动同步和失败重试。
- 完成账户切换与数据隔离验收。

### 阶段 3：市场

- 完成市场列表、搜索、排序、详情和收藏。
- 完成牌组包下载、校验、导入和版本元数据。
- 完成订阅牌组更新检查。

### 阶段 4：质量和体验

- 完成真机性能、无障碍、异常网络和大数据量测试。
- 完成统计、热力图、通知等 P2 能力。
- 根据真实接口和 FSRS 回归结果调整兼容层。

## 20. 关键风险与决策记录

| 风险/决策 | 处理方式 |
| --- | --- |
| Dart FSRS 实现不一定与 TS 一致 | 先做测试向量，再决定引入库或独立移植 |
| 移动端后台任务不可靠 | 以本地队列为可靠边界，后台同步只做尽力而为 |
| Electron 存在 HTML/Markdown 双形态 | 先统一内容契约，再决定 Markdown 优先或安全 HTML 兼容层 |
| 市场下载包可能损坏或过大 | 临时文件、哈希、大小限制、事务导入和失败清理 |
| 服务器冲突可能覆盖复习结果 | 卡片内容与复习状态分字段合并，并记录冲突结果 |
| 当前不做编辑但未来要扩展 | Domain/Repository 预留接口，页面和路由不暴露编辑能力 |
| 登录门禁与离线访问存在张力 | 默认登录后才能使用账户数据；登录后的缓存可离线阅读和复习 |

## 21. 最终推荐

采用“Flutter stable + Riverpod + go_router + Dio + Freezed + Drift + 安全存储”的组合，原因是它能同时覆盖：

- 移动端声明式 UI 和多分支导航。
- 网络认证、同步、重试和错误处理。
- 可查询、可迁移、可事务化的离线数据。
- FSRS 适配和复习流程的可测试性。
- 未来增加编辑能力时的领域层扩展空间。

当前阶段最重要的实现顺序不是先做编辑器，而是先建立可靠的本地数据边界、复习事务和同步队列。编辑能力可以在后续加入，但如果一开始没有把账户隔离、复习状态一致性和离线行为设计好，后续编辑会放大数据冲突和恢复成本。

