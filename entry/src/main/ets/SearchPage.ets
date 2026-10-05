// SearchPage.ets -- 搜索 Tab：全源聚合并发搜索 + 结果按片名分组
// 聚合（默认）：搜「全部源」去重后的全部站点（约 180 站，并发 8 逐站回调），
//              同片名合并为一组（N 源徽标）；首次自动加载站点清单（缓存 7 天）
// 本站：仅搜当前 activeSite（单站快速定位）；无源时回退脚本扩展搜索

import { app, VideoItem } from './AppState'
import { tvbox } from './TvboxState'
import { SearchVodItem, VodItem } from './model/TvModels'
import { SearchHistoryService } from './services/SearchHistoryService'
import { PerformanceMonitor } from './common/utils/PerformanceMonitor'

// 同名片名的分组（聚合搜索展示单元）
interface AggGroup {
  name: string
  pic: string
  remarks: string
  year: string
  items: SearchVodItem[]
}

@Component
export struct SearchPage {
  @State keyword: string = ''
  @State results: VideoItem[] = []          // 本站/扩展模式的平铺结果
  @State groups: AggGroup[] = []            // 聚合模式的分组结果
  @State loading: boolean = false
  @State searched: boolean = false
  @State errorMsg: string = ''
  @State modeLabel: string = ''
  // 聚合：'agg' 全源聚合 | 'site' 仅本站
  @State searchMode: string = 'agg'
  @State aggRunning: boolean = false
  @State preparing: boolean = false         // 正在加载全部源站点清单
  @State progDone: number = 0
  @State progTotal: number = 0
  @State groupCount: number = 0
  @State searchHistory: string[] = []       // 搜索历史
  @State showHistory: boolean = false       // 显示搜索历史

  // 当前搜索走哪个模式；openDetail 时写回 app.currentMode
  private lastMode: string = 'tvbox'
  // 本地搜索令牌：新搜索/停止后丢弃旧回调
  private searchToken: number = 0
  // 分组 Map（性能优化：O(1) 查找）
  private groupMap: Map<string, AggGroup> = new Map()
  // 搜索历史服务
  private searchHistoryService: SearchHistoryService = new SearchHistoryService(app.host)

  async aboutToAppear(): Promise<void> {
    this.refreshMeta()
    await this.loadSearchHistory()
  }

  async loadSearchHistory(): Promise<void> {
    try {
      const history = await this.searchHistoryService.getHistory()
      this.searchHistory = history.map(item => item.keyword)
    } catch (e) {
      // 忽略加载失败
    }
  }

  private refreshMeta(): void {
    const srcCount: number = tvbox.sources.length
    const siteName: string = tvbox.activeSite ? tvbox.activeSite.name : ''
    if (srcCount > 0) {
      this.modeLabel = '聚合全部 ' + srcCount + ' 个源' + (tvbox.aggSites.length > 0 ? '（' + tvbox.aggSites.length + ' 站）' : '')
    } else {
      this.modeLabel = siteName !== '' ? 'TVBox · ' + siteName : '扩展'
    }
    // 无任何源时回退本站/扩展模式
    if (srcCount === 0 && this.searchMode === 'agg') {
      this.searchMode = 'site'
    }
  }

  async doSearch(word: string): Promise<void> {
    const w = word.trim()
    if (w.length === 0) return
    this.keyword = w
    this.showHistory = false
    this.loading = true
    this.errorMsg = ''
    this.searched = false
    this.refreshMeta()

    // 保存搜索历史
    this.searchHistoryService.addHistory(w).then(() => {
      this.loadSearchHistory()
    }).catch(() => {})

    PerformanceMonitor.mark('search_start')
    const token: number = ++this.searchToken
    try {
      if (this.searchMode === 'agg' && tvbox.sources.length > 0) {
        await this.doAggSearch(w)
      } else if (tvbox.activeSite) {
        await this.doSiteSearch(w)
      } else {
        await this.doUzSearch(w)
      }
      // 本轮未被停止/未被新搜索取代才标记完成
      if (token === this.searchToken) {
        this.searched = true
        PerformanceMonitor.mark('search_end')
        PerformanceMonitor.measure('search_start', 'search_end')
      }
    } catch (e) {
      this.errorMsg = (e as Error).message ?? String(e)
    }
    this.loading = false
  }

  /** 聚合搜索：逐站回调合并分组，进度实时刷新（含清单准备阶段） */
  private async doAggSearch(w: string): Promise<void> {
    const token: number = this.searchToken
    this.groups = []
    this.groupMap.clear()
    this.groupCount = 0
    this.progDone = 0
    this.progTotal = 0
    this.preparing = true
    this.aggRunning = true
    this.lastMode = 'tvbox'
    try {
      await tvbox.searchAggregate(w, (batch: SearchVodItem[]) => {
        if (token !== this.searchToken) return
        this.preparing = tvbox.aggPreparing
        this.mergeBatch(batch)
        this.progDone = tvbox.aggDone
        this.progTotal = tvbox.aggTotal
      })
    } finally {
      if (token === this.searchToken) {
        this.aggRunning = false
        this.preparing = false
        this.progDone = tvbox.aggDone
        this.progTotal = tvbox.aggTotal
      }
    }
    if (token === this.searchToken && this.groups.length === 0 && this.errorMsg === '') {
      this.errorMsg = this.progTotal + ' 个站点均无结果（或均不可用），可换关键词或稍后重试'
    }
  }

  /** 把一个站点的结果合并进分组（使用 Map 优化：O(n) -> O(1)） */
  private mergeBatch(batch: SearchVodItem[]): void {
    for (const it of batch) {
      let group = this.groupMap.get(it.vod.name)

      if (!group) {
        // 新建分组
        group = {
          name: it.vod.name,
          pic: it.vod.pic,
          remarks: it.vod.remarks,
          year: it.vod.year,
          items: []
        }
        this.groupMap.set(it.vod.name, group)
        this.groups.push(group)
      }

      // 同站同 ID 去重（个别站搜索分页返回重复）
      const isDup = group.items.some(x =>
        x.siteApi === it.siteApi && x.vod.vodId === it.vod.vodId
      )

      if (!isDup) {
        group.items.push(it)
      }

      // 补充空字段
      if (group.remarks === '' && it.vod.remarks !== '') {
        group.remarks = it.vod.remarks
      }
      if (group.pic === '' && it.vod.pic !== '') {
        group.pic = it.vod.pic
      }
    }

    // 聚合搜索不等所有站点完成；第一批有结果即可进入结果列表。
    if (batch.length > 0) {
      this.searched = true
    }
    // 重新赋值触发 ArkUI 对数组增量结果的刷新，而不是等本轮 Promise 完成。
    this.groups = this.groups.slice()
    this.groupCount = this.groups.length
  }

  /** 停止聚合搜索（进行中的请求自然结束，回调丢弃） */
  stopAgg(): void {
    this.searchToken++
    tvbox.stopSearch()
    this.aggRunning = false
    this.preparing = false
    this.searched = this.groups.length > 0
    this.loading = false
  }

  /** 删除搜索历史项 */
  removeHistoryItem(keyword: string): void {
    this.searchHistoryService.removeHistory(keyword).then(() => {
      this.loadSearchHistory()
    }).catch(() => {})
  }

  /** 清空搜索历史 */
  clearHistory(): void {
    this.searchHistoryService.clearHistory().then(() => {
      this.loadSearchHistory()
    }).catch(() => {})
  }

  private async doSiteSearch(w: string): Promise<void> {
    this.lastMode = 'tvbox'
    this.groups = []
    this.groupCount = 0
    const list: VodItem[] = await tvbox.search(w, 1)
    this.results = list.map((v: VodItem) => ({
      vod_id: v.vodId, vod_name: v.name, vod_pic: v.pic,
      vod_remarks: v.remarks, vod_year: v.year
    } as VideoItem))
  }

  private async doUzSearch(w: string): Promise<void> {
    this.lastMode = 'uz'
    this.groups = []
    this.groupCount = 0
    this.results = await app.search(w, 'all')
  }

  /** 聚合分组 -> 详情（多站聚合线路） */
  openAggDetail(g: AggGroup): void {
    app.currentMode = 'tvbox'
    app.currentVideoId = g.items[0].vod.vodId
    app.currentSiteApi = ''
    app.currentSiteReferer = ''
    app.currentSiteName = ''
    app.currentAggGroup = g.items
    app.pathStack.pushPathByName('Detail', '')
  }

  /** 单条结果 -> 详情（定向站点） */
  openDetail(item: VideoItem): void {
    app.currentMode = this.lastMode
    app.currentVideoId = item.vod_id
    app.currentAggGroup = []
    if (this.lastMode === 'tvbox' && tvbox.activeSite && tvbox.activeSource) {
      app.currentSiteApi = tvbox.activeSite.api
      app.currentSiteReferer = tvbox.activeSource.url
      app.currentSiteName = tvbox.activeSite.name
    } else {
      app.currentSiteApi = ''
      app.currentSiteReferer = ''
      app.currentSiteName = ''
    }
    app.pathStack.pushPathByName('Detail', '')
  }

  /** 分组卡片上的站点预览文案：前 3 个站名 + 余量 */
  private sitePreview(g: AggGroup): string {
    const names: string[] = []
    for (let i = 0; i < g.items.length && i < 3; i++) {
      const item: SearchVodItem = g.items[i]
      const label: string = item.sourceName.length > 0
        ? item.sourceName + ' · ' + item.siteName
        : item.siteName
      names.push(label)
    }
    let s = names.join(' / ')
    if (g.items.length > 3) {
      s += ' 等' + g.items.length + '站'
    }
    return s
  }

  @Builder
  modePill(label: string, mode: string, enabled: boolean) {
    Text(label)
      .fontSize(12)
      .fontColor(enabled ? (this.searchMode === mode ? '#FFFFFF' : $r('app.color.theme_text_muted')) : $r('app.color.theme_text_placeholder'))
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .linearGradient(this.searchMode === mode && enabled
        ? { angle: 135, colors: [[$r('app.color.theme_accent'), 0], [$r('app.color.theme_accent_alt'), 1]] }
        : { angle: 135, colors: [[$r('app.color.theme_surface_alt'), 0], [$r('app.color.theme_surface_alt'), 1]] })
      .borderRadius(14)
      .shadow(this.searchMode === mode && enabled
        ? { radius: 12, color: $r('app.color.theme_accent_shadow'), offsetY: 3 }
        : { radius: 0, color: '#00000000' })
      .onClick(() => {
        if (!enabled) return
        this.searchMode = mode
      })
  }

  build() {
    Column() {
      // 标题
      Row() {
        Column({ space: 2 }) {
          Text('搜索').fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.theme_text_title'))
          Text(this.modeLabel).fontSize(11).fontColor($r('app.color.theme_text_dim'))
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14 })

      // 搜索框（液态玻璃感：半透明 + 模糊 + 高光描边）
      Row() {
        Search({ placeholder: '搜索片名（聚合全部源）', value: this.keyword })
          .layoutWeight(1)
          .height(46)
          .fontColor($r('app.color.theme_text_title'))
          .backgroundColor($r('app.color.theme_card'))
          .placeholderColor($r('app.color.theme_text_dim'))
          .textFont({ size: 15 })
          .onSubmit((v: string) => { this.doSearch(v) })
          .onChange((v: string) => {
            this.keyword = v
            this.showHistory = v.length === 0 && this.searchHistory.length > 0
          })
          .onFocus(() => {
            if (this.keyword.length === 0 && this.searchHistory.length > 0) {
              this.showHistory = true
            }
          })
        Text('搜索').fontSize(15).fontColor('#FFFFFF').width(52).textAlign(TextAlign.Center)
          .linearGradient({ angle: 135, colors: [[$r('app.color.theme_accent'), 0], [$r('app.color.theme_accent_alt'), 1]] })
          .height(38)
          .borderRadius(19)
          .onClick(() => { this.doSearch(this.keyword) })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10 })

      // 搜索历史（输入框获得焦点且为空时显示）
      if (this.showHistory && this.searchHistory.length > 0) {
        Column() {
          Row() {
            Text('搜索历史').fontSize(13).fontColor($r('app.color.theme_text_hint')).layoutWeight(1)
            Text('清空').fontSize(12).fontColor($r('app.color.theme_text_dim'))
              .onClick(() => { this.clearHistory() })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 6 })

          List({ space: 8 }) {
            ForEach(this.searchHistory, (keyword: string) => {
              ListItem() {
                Row({ space: 8 }) {
                  Text('🔍').fontSize(14).fontColor($r('app.color.theme_text_dim'))
                  Text(keyword).fontSize(14).fontColor($r('app.color.theme_text_secondary'))
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text('×').fontSize(18).fontColor($r('app.color.theme_text_dim'))
                    .onClick(() => { this.removeHistoryItem(keyword) })
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .backgroundColor($r('app.color.theme_surface_alt'))
                .borderRadius(8)
              }
              .onClick(() => {
                this.keyword = keyword
                this.doSearch(keyword)
              })
            }, (keyword: string) => keyword)
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .scrollBar(BarState.Off)
        }
        .width('100%')
      }

      // 模式切换（有源即显示聚合）
      if (tvbox.sources.length > 0 || tvbox.activeSite) {
        Row({ space: 8 }) {
          this.modePill('聚合全源', 'agg', tvbox.sources.length > 0)
          this.modePill('仅本站', 'site', tvbox.activeSite !== null)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10 })
      }

      // 聚合进度行（准备清单 / 逐站搜索 / 完成统计）
      if (this.aggRunning || (this.searchMode === 'agg' && this.searched && this.progTotal > 0)) {
        Row({ space: 8 }) {
          if (this.aggRunning) {
            LoadingProgress().width(16).height(16).color($r('app.color.theme_accent'))
          }
          if (this.preparing) {
            Text('正在加载全部源的站点清单（首次约 1-2 分钟，之后走缓存）')
              .fontSize(12)
              .fontColor($r('app.color.theme_text_hint'))
              .layoutWeight(1)
          } else {
            Text(this.aggRunning
              ? '聚合搜索中 ' + this.progDone + '/' + this.progTotal + ' 站 · ' + this.groupCount + ' 部'
              : '已搜 ' + this.progDone + '/' + this.progTotal + ' 站 · 命中 ' + this.groupCount + ' 部')
              .fontSize(12)
              .fontColor($r('app.color.theme_text_hint'))
              .layoutWeight(1)
          }
          if (this.aggRunning) {
            Text('停止')
              .fontSize(12)
              .fontColor($r('app.color.theme_error_bright'))
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .backgroundColor($r('app.color.theme_error_translucent'))
              .borderRadius(12)
              .onClick(() => { this.stopAgg() })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10 })
      }

      // 内容区
      if (this.loading && !this.aggRunning) {
        Column() {
          LoadingProgress().width(42).height(42).color($r('app.color.theme_accent'))
          Text('搜索中…').fontSize(14).fontColor($r('app.color.theme_text_hint')).margin({ top: 14 })
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.errorMsg && this.groups.length === 0 && this.results.length === 0) {
        Column() {
          Text('搜索失败').fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.theme_text_title'))
          Text(this.errorMsg).fontSize(13).fontColor($r('app.color.theme_text_hint')).textAlign(TextAlign.Center).margin({ top: 10 })
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).padding(24)
      } else if (!this.searched && this.groups.length === 0) {
        Column({ space: 12 }) {
          Text('🔍').fontSize(40)
          Text('输入片名回车，聚合搜索全部源').fontSize(15).fontColor($r('app.color.theme_text_dim'))
          if (this.modeLabel.length > 0) {
            Text('当前：' + this.modeLabel).fontSize(12).fontColor($r('app.color.theme_text_placeholder'))
          }
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.searchMode === 'agg') {
        if (this.groups.length === 0) {
          Column() {
            Text('没有搜到结果').fontSize(15).fontColor($r('app.color.theme_text_dim'))
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          List({ space: 12 }) {
            ForEach(this.groups, (g: AggGroup) => {
              ListItem() {
                Row({ space: 12 }) {
                  Image(g.pic)
                    .width(94)
                    .height(130)
                    .objectFit(ImageFit.Cover)
                    .borderRadius(10)
                    .backgroundColor($r('app.color.theme_surface_alt'))
                  Column({ space: 6 }) {
                    Row({ space: 6 }) {
                      Text(g.name)
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.theme_text_title'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                      Text(g.items.length + '源')
                        .fontSize(11)
                        .fontColor('#FFFFFF')
                        .linearGradient({ angle: 135, colors: [[$r('app.color.theme_accent'), 0], [$r('app.color.theme_accent_alt'), 1]] })
                        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                        .borderRadius(10)
                    }
                    .width('100%')
                    if (g.remarks.length > 0) {
                      Text(g.remarks)
                        .fontSize(12)
                        .fontColor($r('app.color.theme_text_muted'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    if (g.year.length > 0) {
                      Text(g.year).fontSize(12).fontColor($r('app.color.theme_text_dim'))
                    }
                    Text(this.sitePreview(g))
                      .fontSize(11)
                      .fontColor($r('app.color.theme_text_placeholder'))
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }
                .width('100%')
                .padding(12)
                .backgroundColor($r('app.color.theme_card'))
                            .borderRadius(14)
                .border({ width: 0.5, color: $r('app.color.theme_overlay_light_14') })
              }
              .onClick(() => { this.openAggDetail(g) })
            }, (g: AggGroup) => g.name + '_' + g.items.length.toString())
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 14, right: 14, top: 4, bottom: 96 })
        }
      } else {
        if (this.results.length === 0) {
          Column() {
            Text('没有搜到结果').fontSize(15).fontColor($r('app.color.theme_text_dim'))
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          List({ space: 12 }) {
            ForEach(this.results, (item: VideoItem) => {
              ListItem() {
                Row({ space: 12 }) {
                  Image(item.vod_pic)
                    .width(94)
                    .height(130)
                    .objectFit(ImageFit.Cover)
                    .borderRadius(10)
                    .backgroundColor($r('app.color.theme_surface_alt'))
                  Column({ space: 6 }) {
                    Text(item.vod_name)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.theme_text_title'))
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (item.vod_remarks.length > 0) {
                      Text(item.vod_remarks)
                        .fontSize(12)
                        .fontColor($r('app.color.theme_text_muted'))
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    if (item.vod_year.length > 0) {
                      Text(item.vod_year)
                        .fontSize(12)
                        .fontColor($r('app.color.theme_text_dim'))
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }
                .width('100%')
                .padding(12)
                .backgroundColor($r('app.color.theme_card'))
                            .borderRadius(14)
                .border({ width: 0.5, color: $r('app.color.theme_overlay_light_14') })
              }
              .onClick(() => { this.openDetail(item) })
            }, (item: VideoItem) => item.vod_id)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 14, right: 14, top: 4, bottom: 96 })
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.theme_background'))
  }
}
