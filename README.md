# tvhub-harmony -- 鸿蒙聚合影视壳（多源接口 + 扩展引擎）

> 自用 HAP 项目 ｜ DevEco SDK 6.0.1 / API 21（最低兼容 API 12）｜ 手机 / 平板 / 2in1（触屏+键鼠）
> 架构说明见 `ARCHITECTURE.md`，协议验证见 `../tvbox-spike/SPIKE-REPORT.md`。

## 当前进度（2026-09 一期：多源接口）

- ✅ 协议 spike：`https://tv.1788.space/api.php`（132 源多仓）全链路验证
  - 多仓 -> 单仓 -> 站点（51/111 标准苹果CMS 接口）-> 分类/列表/搜索/详情/播放
- ✅ ArkTS 数据模型 + TVBox 协议客户端（`ets/model/TvModels.ets`、`ets/api/TvboxApi.ets`）
- ✅ TVBox 状态层（`ets/TvboxState.ets`：源/站点/分类/列表/搜索/详情，根接口持久化）
- ✅ UI 双模式改造：
  - 首页（`HomeTab.ets`）：源驱动分类 + 2 列海报 + 上拉分页，右上「切换源」
  - 源选择页（`SourcePickerPage.ets`）：根接口 -> 132 源 -> 站点三级选择
  - 搜索（`SearchPage.ets`）：**多源并发聚合搜索** + 仅本站两档
    - 聚合（默认）：并发搜当前源全部 ok 站点（并发 8，逐站回调），同片名合并为一组（N 源徽标 + 站点预览），实时进度「X/Y 站 · N 部」+ 停止按钮
    - 详情页聚合：点分组卡片 -> 并发取各站详情，**多站线路合并进同一线路 Tab（换源=换线路）**，相同片源自动去重
    - 无站点时回退 uz 扩展搜索
  - 详情（`DetailPage.ets`）：三路取数（聚合组 / 定点站点 / 当前站点）+ 多线路（`$$$`）+ 选集（`#`/`$`）
  - 播放（`PlayerPage.ets`）：TVBox 直链 m3u8 直接播；uz 源保留原解析链路
  - 历史/收藏：记录来源模式（`mode`）+ 定向站点（`siteApi/siteReferer`），换源后回看仍回原站点
  - 设置（`SettingsPage.ets`）：新增「接口配置」页面（根接口配置 + 加载 + 源选择入口）
- ✅ 多源并发搜索（2026-08-30）：SearchPage 聚合模式 + DetailPage 线路聚合 + 历史收藏定向站点
- ✅ 播放器修复 + 全源聚合 + UI 质感（2026-08-30 二轮）：
  - 比例：AVPlayer 默认 VIDEO_SCALE_TYPE_FIT（变形拉伸）已改为 prepared 后显式按 scaleMode 应用比例，默认「保持比例」
  - 真全屏：全屏隐藏系统栏（setWindowSystemBarEnable([])）+ expandSafeArea 延伸到状态栏/手势条下，控制条 3s 自动隐藏、点画面唤出
  - 聚合搜索改为「全部源」：展开放大全部源配置（并发 8）→ 按 api 去重（132 源约 183 唯一站）→ 站点清单持久化缓存 7 天；短超时搜索不重试
  - 详情页重排：大海报 + 背景模糊 + 完整元信息（年份/地区/评分/导演/主演）+ 简介可展开
  - 液态玻璃质感：底部 Tab/搜索框/结果卡/线路 Tab 加背景模糊与流光渐变
- ⏳ 二期剩余：海阔视界 JS 规则引擎（复用 QuickJS 桥）、drpy2.js 爬虫

## 在 DevEco 里调试（Mac）

本目录本身即完整 DevEco 工程（根 `build-profile.json5` + `entry` + `AppScope`），直接用 DevEco Studio 打开 `/Users/mac/Desktop/codex/tvhub-harmony` 即可：

- 根 `build-profile.json5` 引用了本机 `~/.ohos/config` 下的调试签名；不要把该文件提交或分享
- 设备类型：Phone + 2in1（+ 可选 Tablet）
- 命令行构建：`./build-mac.sh`（ohpm install + hvigorw assembleHap，产物在 `entry/build/default/outputs/default/`）
- Native 部分（QuickJS）在 `entry/src/main/cpp/`，首次全量构建约 2 分钟
- 调试没问题后由你自行封包（Build HAP(s)/发布签名）

## 真机验证路径

1. 打开 App -> 设置 -> 配置 -> 粘贴 `https://tv.1788.space/api.php` -> 「加载接口」（应提示 132 个源）
2. 「打开源选择」-> 选「御制(全)」-> 选「爱奇艺|CJ」（标准接口）-> 自动返回
3. 首页出现 43 个分类 Tab + 海报网格；点任一影片 -> 详情（线路/选集）-> 选集 -> 播放
4. 搜索「战」验证聚合搜索：默认「聚合全源」逐站出结果（进度 X/Y 站），点分组卡片进详情，线路 Tab 显示各站线路（站点名前缀），换线路即换源
5. 播放后历史/收藏出现记录；重启 App 验证持久化（历史回看直接回原站点）

## 已知限制

- `csp_*` 内置爬虫与 jar 依赖的站点在鸿蒙上无法运行（无 JVM），已在源选择里标记「需 jar，跳过」
- drpy2.min.js（JS 爬虫）依赖 QuickJS 大框架，二期接入
- 部分站点（牛牛/鸭鸭等）有反爬或已失效，属源生态常态，换源即可
- 内容与源全部为用户自填配置，壳与适配器均为自研；自用不发布
