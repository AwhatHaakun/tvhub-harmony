# tvhub-harmony 架构说明

> 多源接口模块（ArkTS 纯协议实现）+ 脚本扩展模块（QuickJS 引擎），共壳双模式。

## 模块结构

```
entry/src/main/ets/
├── pages/Index.ets          # 入口：Navigation 容器 + 路由（Detail/Player/Verify/SourcePicker/SourceManage）
├── AppState.ets             # 全局单例：uz 扩展引擎生命周期 + 历史/收藏持久化 + 跨页导航参数
│                             #   currentMode('tvbox'|'uz') / currentVideoId
│                             #   currentSiteApi/Referer/Name（tvbox 定向站点）
│                             #   currentAggGroup（聚合搜索结果组）
├── HomePage.ets             # 主壳：底部悬浮 Tab 栏（首页/搜索/历史/收藏/设置）
├── HomeTab.ets              # 首页：源驱动分类 + 2 列海报 + 上拉分页
├── SearchPage.ets           # 搜索：聚合多站并发 / 仅本站 / uz 回退（见下）
├── DetailPage.ets           # 详情：三路取数 + 线路 Tab + 选集（见下）
├── PlayerPage.ets           # 播放：AVPlayer 状态机（url -> initialized 设 surfaceId -> prepare）
├── HistoryPage / FavoritePage
├── SettingsPage.ets         # 设置：接口管理 + 源管理入口
├── SourcePickerPage.ets     # 三级选择：根接口 -> 源(132) -> 站点
├── TvboxState.ets           # TVBox 状态层：多根接口持久化、源/站点选择、列表/搜索/聚合搜索
├── api/TvboxApi.ets         # 苹果CMS 协议客户端：loadRoot/loadSites/getClass/getVodList/getDetail/splitPlay
├── model/TvModels.ets       # 数据模型：VodItem/VodDetail/PlayLine/SiteConf/SearchVodItem...
└── uz 半边：JSExecutor/HostBridge/ExtensionLoader/RawFileLoader（QuickJS）
```

## 多源并发聚合搜索（2026-08-30）

### 数据流

```
SearchPage（聚合模式）
  └─ tvbox.searchAggregate(wd, onBatch)        [TvboxState]
       ├─ 站点集 = activeSource.sites.filter(status==='ok')
       ├─ 8 个 worker 并发逐站 getVodList(api, wd, pg=1, referer)
       ├─ 单站失败静默；searchSeq 令牌：新轮次/stopSearch() 使旧轮次失效
       └─ 每站完成（含 0 结果/失败）回调 onBatch(SearchVodItem[])
            └─ SearchPage.mergeBatch：按 vod_name 合并进 AggGroup（同站同 ID 去重）
                  UI：分组卡片（N 源徽标 + 站点预览）+ 进度「X/Y 站 · N 部」+ 停止
点分组卡片
  └─ app.currentAggGroup = group.items -> push Detail
       └─ DetailPage.loadAggDetail(group)      [并发 6]
            ├─ 逐项 getDetail(siteApi, vodId, siteReferer)，单站失败跳过
            ├─ 线路合并：站点名(·线路名) 做标签；集数+首集地址相同视为同一片源去重
            └─ 基础信息取第一个成功站点；全部失败 -> 回退单站点路径
```

### 详情三路取数（loadTvboxDetail）

1. `currentAggGroup` 非空：聚合模式，多站线路合并（换源 = 换线路 Tab）
2. `currentSiteApi` 非空：定点模式（历史/收藏/单站搜索结果），直接回原站点
3. 兜底：当前 activeSite（首页等入口）

### 定向站点持久化

- HistoryItem/VideoItem 增加 `siteApi/siteReferer/siteName` 可选字段
- 详情页按实际取数站点写入；历史/收藏回看时 `app.currentSiteApi` 定向回原站点
- 旧数据无站点字段 -> 兜底 activeSite，与升级前行为一致

### 入口一致性（防串台）

所有进详情的入口都显式设置三个跨页字段：
`HomeTab.openDetail` 置空（走 activeSite）；`SearchPage` 置组或站点；
`HistoryPage/FavoritePage.openDetail` 从条目还原站点；uz 模式忽略站点字段。

## TVBox 协议要点（详见 ../tvbox-spike/SPIKE-REPORT.md）

- 分类列表必须用 `?ac=videolist&t=<type_id>`（`ids=` 是批量查影片，不是分类）
- `vod_play_url`：`$$$` 分隔线路、`#` 分隔集、`$` 分隔名址
- `csp_*` 站点依赖 jar（无 JVM 不可跑），标记跳过；`.js/drpy` 站点二期接 QuickJS
