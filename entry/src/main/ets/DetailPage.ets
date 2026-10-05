// DetailPage.ets —— 详情页：片名/简介 + 多线路切换 + 选集
// 双模式数据源：
//   tvbox（默认）：tvbox.detail + tvbox.splitPlayLines（$$$ 线路 / # 集 / $ 名址）
//   uz：app.detail + AppState.parsePlayLines（$$$ 线路 / ### 集 / $ 名址）
// 由 AppState.currentMode 决定；首页/搜索页进入前设置。
// 两个数据源的 PlayLine/Episode 统一映射为本文件的 PageLine/PageEpisode，
// 避免跨模块接口字段差异（TvModels.PlayLine.from vs AppState.PlayLine.name）。

import { app, AppState, HistoryItem, VideoItem } from './AppState'
import { tvbox } from './TvboxState'
import { SearchVodItem, VodDetail } from './model/TvModels'
import { getDetail, splitPlay } from './api/TvboxApi'

// 统一后的页面详情模型（两种数据源都映射到这里）
interface PageDetail {
  vodId: string
  name: string
  pic: string
  typeName: string
  remarks: string
  content: string
  playFrom: string
  playUrl: string
  // 元信息（uz 扩展无这些字段时留空）
  year: string
  area: string
  lang: string
  actor: string
  director: string
  score: string
}

// 统一后的选集/线路类型（页面 UI 只认这一套）
interface PageEpisode {
  name: string
  url: string
}

interface PageLine {
  name: string
  episodes: PageEpisode[]
}

interface DetailResult {
  mode: string
  detail: PageDetail
  lines: PageLine[]
}

// 聚合详情的一个站点分片
interface AggPart {
  item: SearchVodItem
  detail: VodDetail
}

@Component
export struct DetailPage {
  @State detail: PageDetail | null = null
  @State lines: PageLine[] = []
  @State lineIndex: number = 0
  @State loading: boolean = true
  @State errorMsg: string = ''
  @State isFav: boolean = false
  // 简介展开态（默认收起，超长时显示「展开」）
  @State contentExpanded: boolean = false

  // tvbox 详情实际取数站点（写进历史/收藏，回看时定向到原站点）
  private histSiteApi: string = ''
  private histSiteReferer: string = ''
  private histSiteName: string = ''
  // 聚合模式提示（线路来自多少个站点）
  @State aggSiteCount: number = 0

  async aboutToAppear(): Promise<void> {
    this.loading = true
    try {
      // 先按 currentMode 取详情；失败自动回退另一模式（兼容旧历史/收藏无 mode 标记）
      let loaded: DetailResult | null = null
      if (app.currentMode === 'uz') {
        try {
          loaded = await this.loadUzDetail()
        } catch (e) {
          loaded = await this.loadTvboxDetail()
        }
      } else {
        try {
          loaded = await this.loadTvboxDetail()
        } catch (e) {
          loaded = await this.loadUzDetail()
        }
      }
      if (!loaded) throw new Error('详情为空')
      // 自愈：回退成功后把模式写回，历史/收藏下次直接走对的源
      app.currentMode = loaded.mode
      this.detail = loaded.detail
      this.lines = loaded.lines
      this.lineIndex = 0
      const hist: HistoryItem = this.toHistoryItem(loaded.detail)
      app.currentHistory = hist
      this.isFav = await app.isFavorite(this.toFavoriteItem(loaded.detail))
    } catch (e) {
      this.errorMsg = (e as Error).message ?? String(e)
    }
    this.loading = false
  }

  private async loadTvboxDetail(): Promise<DetailResult> {
    // 1) 聚合模式：同片名多站点命中 -> 并发取各站详情合并线路（换源=换线路 Tab）
    if (app.currentAggGroup.length > 0) {
      try {
        return await this.loadAggDetail(app.currentAggGroup)
      } catch (e) {
        // 全部站点失败 -> 继续走单站点回退
      }
    }
    // 2) 定点模式：历史/收藏/单站搜索结果带站点信息，直接到原站点取详情
    if (app.currentSiteApi !== '') {
      const vd = await getDetail(app.currentSiteApi, app.currentVideoId, app.currentSiteReferer)
      this.histSiteApi = app.currentSiteApi
      this.histSiteReferer = app.currentSiteReferer
      this.histSiteName = app.currentSiteName
      return this.toDetailResult(vd)
    }
    // 3) 当前站点（首页等入口）
    const vd = await tvbox.detail(app.currentVideoId)
    const site = tvbox.activeSite
    const src = tvbox.activeSource
    this.histSiteApi = site ? site.api : ''
    this.histSiteReferer = src ? src.url : ''
    this.histSiteName = site ? site.name : ''
    return this.toDetailResult(vd)
  }

  /** 聚合详情：并发取组内全部站点详情，合并线路（站点名做线路前缀），去重相同片源 */
  private async loadAggDetail(group: SearchVodItem[]): Promise<DetailResult> {
    const parts: AggPart[] = []
    let idx: number = 0
    const worker = async (): Promise<void> => {
      while (idx < group.length) {
        const it: SearchVodItem = group[idx]
        idx++
        try {
          const d = await getDetail(it.siteApi, it.vod.vodId, it.siteReferer)
          parts.push({ item: it, detail: d })
        } catch (e) {
          // 单站失败跳过，不阻塞其它站
        }
      }
    }
    const workers: Promise<void>[] = []
    const n: number = Math.min(6, group.length)
    for (let i = 0; i < n; i++) {
      workers.push(worker())
    }
    await Promise.all(workers)
    if (parts.length === 0) {
      throw new Error('聚合详情：全部站点获取失败')
    }
    // 基础信息取第一个成功站点；历史/收藏定向也取它
    const base: AggPart = parts[0]
    this.histSiteApi = base.item.siteApi
    this.histSiteReferer = base.item.siteReferer
    this.histSiteName = base.item.siteName
    this.aggSiteCount = parts.length
    const lines: PageLine[] = []
    const seen: Set<string> = new Set<string>()
    for (let p = 0; p < parts.length; p++) {
      const raw = splitPlay(parts[p].detail.playFrom, parts[p].detail.playUrl)
      const siteName: string = parts[p].item.siteName
      for (let i = 0; i < raw.length; i++) {
        if (raw[i].episodes.length === 0) continue
        // 去重：集数+首集地址相同的线路视为同一片源
        const key: string = raw[i].episodes.map((e) => e.url).join('|')
        if (seen.has(key)) continue
        seen.add(key)
        const eps: PageEpisode[] = []
        for (let k = 0; k < raw[i].episodes.length; k++) {
          eps.push({ name: raw[i].episodes[k].name, url: raw[i].episodes[k].url })
        }
        const label: string = raw.length > 1 ? siteName + '·' + raw[i].from : siteName
        lines.push({ name: label, episodes: eps })
      }
    }
    if (lines.length === 0) {
      throw new Error('聚合详情：未解析出播放地址')
    }
    return {
      mode: 'tvbox',
      detail: {
        vodId: base.detail.vodId, name: base.detail.name, pic: base.detail.pic,
        typeName: base.detail.typeName, remarks: base.detail.remarks, content: base.detail.content,
        playFrom: base.detail.playFrom, playUrl: base.detail.playUrl,
        year: base.detail.year, area: base.detail.area, lang: base.detail.lang,
        actor: base.detail.actor, director: base.detail.director, score: base.detail.score
      },
      lines: lines
    }
  }

  private toDetailResult(vd: VodDetail): DetailResult {
    const raw = tvbox.splitPlayLines(vd.playFrom, vd.playUrl)
    const lines: PageLine[] = []
    for (let i = 0; i < raw.length; i++) {
      const eps: PageEpisode[] = []
      for (let k = 0; k < raw[i].episodes.length; k++) {
        eps.push({ name: raw[i].episodes[k].name, url: raw[i].episodes[k].url })
      }
      lines.push({ name: raw[i].from, episodes: eps })
    }
    return {
      mode: 'tvbox',
      detail: {
        vodId: vd.vodId, name: vd.name, pic: vd.pic, typeName: vd.typeName,
        remarks: vd.remarks, content: vd.content, playFrom: vd.playFrom, playUrl: vd.playUrl,
        year: vd.year, area: vd.area, lang: vd.lang, actor: vd.actor,
        director: vd.director, score: vd.score
      },
      lines: lines
    }
  }

  private async loadUzDetail(): Promise<DetailResult> {
    this.histSiteApi = ''
    this.histSiteReferer = ''
    this.histSiteName = ''
    this.aggSiteCount = 0
    const ud = await app.detail(app.currentVideoId)
    const raw = AppState.parsePlayLines(ud.vod_play_from, ud.vod_play_url)
    const lines: PageLine[] = []
    for (let i = 0; i < raw.length; i++) {
      const eps: PageEpisode[] = []
      for (let k = 0; k < raw[i].episodes.length; k++) {
        eps.push({ name: raw[i].episodes[k].name, url: raw[i].episodes[k].url })
      }
      lines.push({ name: raw[i].name, episodes: eps })
    }
    return {
      mode: 'uz',
      detail: {
        vodId: ud.vod_id, name: ud.vod_name, pic: ud.vod_pic, typeName: ud.type_name,
        remarks: '', content: ud.vod_content, playFrom: ud.vod_play_from, playUrl: ud.vod_play_url,
        year: '', area: '', lang: '', actor: '', director: '', score: ''
      },
      lines: lines
    }
  }

  private toHistoryItem(detail: PageDetail): HistoryItem {
    const hist: HistoryItem = {
      vod_id: detail.vodId,
      vod_name: detail.name,
      vod_pic: detail.pic,
      vod_remarks: detail.remarks,
      vod_year: detail.year,
      time: Date.now(),
      mode: app.currentMode
    }
    if (app.currentMode === 'tvbox') {
      hist.siteApi = this.histSiteApi
      hist.siteReferer = this.histSiteReferer
      hist.siteName = this.histSiteName
    }
    return hist
  }

  private toFavoriteItem(detail: PageDetail): VideoItem {
    const item: VideoItem = {
      vod_id: detail.vodId,
      vod_name: detail.name,
      vod_pic: detail.pic,
      vod_remarks: detail.remarks,
      vod_year: detail.year,
      mode: app.currentMode
    }
    if (app.currentMode === 'tvbox') {
      item.siteApi = this.histSiteApi
      item.siteReferer = this.histSiteReferer
      item.siteName = this.histSiteName
    }
    return item
  }

  async toggleFav(): Promise<void> {
    if (!this.detail) return
    this.isFav = await app.toggleFavorite(this.toFavoriteItem(this.detail))
  }

  playEp(ep: PageEpisode): void {
    app.currentEpUrl = ep.url
    app.currentEpName = ep.name
    app.pathStack.pushPathByName('Player', '')
  }

  async downloadEp(ep: PageEpisode): Promise<void> {
    if (!this.detail) return
    try {
      await app.downloadService.createDownload(
        this.detail.name,
        ep.name,
        ep.url
      )
      this.toast('已添加到下载列表')
    } catch (e) {
      this.toast('下载添加失败：' + ((e as Error).message ?? String(e)))
    }
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message })
    } catch (e) {
      // toast is best-effort UI feedback.
    }
  }

  currentEpisodes(): PageEpisode[] {
    if (this.lines.length === 0 || this.lineIndex >= this.lines.length) return []
    return this.lines[this.lineIndex].episodes
  }

  build() {
    // 必须以 NavDestination 为根：Navigation 压栈页面缺它会黑屏
    NavDestination() {
      Column() {
        // 顶栏
        Row() {
          Text('‹')
            .fontSize(30)
            .fontColor($r('app.color.theme_text_secondary'))
            .width(36)
            .onClick(() => { app.pathStack.pop() })
          Text(this.detail?.name ?? '详情')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.theme_text_title'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(this.isFav ? '★' : '☆')
            .fontSize(26)
            .fontColor(this.isFav ? $r('app.color.theme_warning') : $r('app.color.theme_text_dim'))
            .width(40)
            .textAlign(TextAlign.Center)
            .onClick(() => { this.toggleFav() })
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 10 })

        if (this.loading) {
          Column() {
            LoadingProgress().width(42).height(42).color($r('app.color.theme_accent'))
            Text('加载详情中…').fontSize(14).fontColor($r('app.color.theme_text_hint')).margin({ top: 14 })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.errorMsg) {
          Column() {
            Text('解析失败').fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.theme_text_title'))
            Text(this.errorMsg).fontSize(13).fontColor($r('app.color.theme_text_hint')).textAlign(TextAlign.Center).margin({ top: 10 })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).padding(24)
        } else if (this.detail) {
          Scroll() {
            Column({ space: 14 }) {
              // 海报大图头部（背景模糊 + 前景海报 + 信息）
              Stack({ alignContent: Alignment.BottomStart }) {
                // 背景：海报撑满 + 底部深色渐变遮罩
                Image(this.detail.pic)
                  .width('100%')
                  .height(220)
                  .objectFit(ImageFit.Cover)
                  .blur(12)
                  .brightness(0.5)
                Column()
                  .width('100%')
                  .height(220)
                  .linearGradient({ angle: 180, colors: [[$r('app.color.theme_detail_gradient_start'), 0], [$r('app.color.theme_detail_gradient_end'), 1]] })
                // 前景：海报 + 信息
                Row({ space: 14 }) {
                  Image(this.detail.pic)
                    .width(118)
                    .height(166)
                    .objectFit(ImageFit.Cover)
                    .borderRadius(12)
                    .border({ width: 0.5, color: $r('app.color.theme_overlay_light_33') })
                    .shadow({ radius: 16, color: '#66000000', offsetY: 6 })
                  Column({ space: 8 }) {
                    Text(this.detail.name).fontSize(19).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
                      .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                    // 元信息胶囊行
                    Row({ space: 6 }) {
                      if (this.detail.year.length > 0) {
                        Text(this.detail.year).fontSize(11).fontColor($r('app.color.theme_text_secondary'))
                          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                          .backgroundColor($r('app.color.theme_overlay_light_33')).borderRadius(6)
                      }
                      if (this.detail.area.length > 0) {
                        Text(this.detail.area).fontSize(11).fontColor($r('app.color.theme_text_secondary'))
                          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                          .backgroundColor($r('app.color.theme_overlay_light_33')).borderRadius(6)
                      }
                      if (this.detail.typeName.length > 0) {
                        Text(this.detail.typeName).fontSize(11).fontColor('#FFFFFF')
                          .linearGradient({ angle: 135, colors: [[$r('app.color.theme_accent'), 0], [$r('app.color.theme_accent_alt'), 1]] })
                          .padding({ left: 8, right: 8, top: 3, bottom: 3 }).borderRadius(6)
                      }
                    }
                    .width('100%')
                    if (this.detail.score.length > 0 && this.detail.score !== '0.0') {
                      Row({ space: 3 }) {
                        Text('★').fontSize(13).fontColor($r('app.color.theme_warning'))
                        Text('评分 ' + this.detail.score).fontSize(12).fontColor($r('app.color.theme_warning'))
                      }
                    }
                    if (this.detail.director.length > 0) {
                      Text('导演：' + this.detail.director).fontSize(12).fontColor($r('app.color.theme_text_button'))
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    if (this.detail.actor.length > 0) {
                      Text('主演：' + this.detail.actor).fontSize(12).fontColor($r('app.color.theme_text_button'))
                        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }
                .width('100%')
                .padding(16)
              }
              .width('100%')
              .clip(true)

              // 简介卡（可展开）
              if (this.detail.content.length > 0) {
                Column({ space: 6 }) {
                  Text('简介').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.theme_text_secondary'))
                  Text(this.detail.content)
                    .fontSize(13)
                    .fontColor($r('app.color.theme_text_muted'))
                    .lineHeight(21)
                    .maxLines(this.contentExpanded ? 1000 : 3)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (this.detail.content.length > 90) {
                    Text(this.contentExpanded ? '收起' : '展开')
                      .fontSize(12)
                      .fontColor($r('app.color.theme_accent'))
                      .onClick(() => { this.contentExpanded = !this.contentExpanded })
                  }
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding(16)
                .backgroundColor($r('app.color.theme_card'))
                            .borderRadius(14)
                .border({ width: 0.5, color: $r('app.color.theme_overlay_light_14') })
              }

              // 线路 Tab（≥2 条线路才显示；聚合模式显示来源站数）
              if (this.aggSiteCount > 1) {
                Text('聚合 ' + this.aggSiteCount + ' 个站点 · ' + this.lines.length + ' 条线路，点击切换')
                  .fontSize(12)
                  .fontColor($r('app.color.theme_accent'))
              }
              if (this.lines.length > 1) {
                List({ space: 8 }) {
                  ForEach(this.lines, (line: PageLine, index: number) => {
                    ListItem() {
                      Text(line.name)
                        .fontSize(13)
                        .fontColor(this.lineIndex === index ? '#FFFFFF' : $r('app.color.theme_text_muted'))
                        .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                        .linearGradient(this.lineIndex === index
                          ? { angle: 135, colors: [[$r('app.color.theme_accent'), 0], [$r('app.color.theme_accent_alt'), 1]] }
                          : { angle: 135, colors: [[$r('app.color.theme_overlay_light_22'), 0], [$r('app.color.theme_overlay_light_18'), 1]] })
                        .borderRadius(16)
                    }
                    .onClick(() => { this.lineIndex = index })
                  }, (line: PageLine, index: number) => line.name + '_' + index.toString())
                }
                .listDirection(Axis.Horizontal)
                .width('100%')
                .height(36)
                .scrollBar(BarState.Off)
              }

              // 选集
              if (this.currentEpisodes().length > 0) {
                Text('选集（' + this.currentEpisodes().length + '）')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.theme_text_secondary'))
                Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                  ForEach(this.currentEpisodes(), (ep: PageEpisode) => {
                    Button(ep.name)
                      .fontSize(13)
                      .height(40)
                      .padding({ left: 14, right: 14 })
                      .backgroundColor($r('app.color.theme_overlay_surface'))
                      .border({ width: 0.5, color: $r('app.color.theme_overlay_light_1A') })
                      .fontColor($r('app.color.theme_text_body_alt'))
                      .borderRadius(10)
                      .margin({ right: 8, bottom: 8 })
                      .onClick(() => { this.playEp(ep) })
                      .gesture(
                        LongPressGesture({ repeat: false })
                          .onAction(() => { this.downloadEp(ep) })
                      )
                  }, (ep: PageEpisode) => ep.url)
                }
                .width('100%')

                Text('提示：点击播放，长按下载')
                  .fontSize(11)
                  .fontColor($r('app.color.theme_text_placeholder'))
                  .margin({ top: 4 })
              } else {
                Text('未解析出播放地址，请换一条结果或换线路')
                  .fontSize(14)
                  .fontColor($r('app.color.theme_text_description'))
              }
            }
            .width('100%')
            .padding(16)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.theme_background'))
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.theme_background'))
  }
}
