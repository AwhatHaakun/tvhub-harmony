// HomeTab.ets —— 首页 Tab：TVBox 源驱动 + 顶部「当前数据源 ▾」弹层切换
// 分类横向 Tab + 2列海报网格 + 上拉分页；点顶部数据源行弹出半屏选择

import { app } from './AppState'
import { tvbox } from './TvboxState'
import { Category, SourceConf, VodItem } from './model/TvModels'
import { rootDisplayName } from './api/TvboxApi'

@Component
export struct HomeTab {
  @State categories: Category[] = []
  @State classIndex: number = 0
  @State videos: VodItem[] = []
  @State loading: boolean = true
  @State loadingMore: boolean = false
  @State errorMsg: string = ''
  @State sourceName: string = '未配置影视源'
  @State showSourcePanel: boolean = false
  @State selectedRoot: string = ''

  private tvboxListener: (what: string) => void = (what: string) => {
    if (what === 'tvbox') {
      this.syncFromTvbox()
    }
  }

  async aboutToAppear(): Promise<void> {
    tvbox.addDataListener(this.tvboxListener)
    try {
      const ctx = this.getUIContext().getHostContext()
      if (ctx) await app.init(ctx)
      await tvbox.init()
      this.syncFromTvbox()
    } catch (e) {
      this.errorMsg = (e as Error).message ?? String(e)
      this.loading = false
    }
  }

  aboutToDisappear(): void {
    tvbox.removeDataListener(this.tvboxListener)
  }

  syncFromTvbox(): void {
    this.categories = tvbox.categories
    this.videos = tvbox.vodList
    this.loading = tvbox.loading
    this.loadingMore = tvbox.loadingMore
    this.errorMsg = tvbox.errorMsg
    this.sourceName = tvbox.currentSourceName()
    if (this.selectedRoot === '' || tvbox.roots.indexOf(this.selectedRoot) < 0) {
      this.selectedRoot = tvbox.activeSource
        ? tvbox.activeSource.rootUrl
        : (tvbox.roots.length > 0 ? tvbox.roots[0] : '')
    }
    // 状态层可能已自动加载第一类；UI 高亮必须跟 currentCategory 对齐。
    const currentId: string = tvbox.currentCategory ? tvbox.currentCategory.typeId : ''
    const currentIndex: number = this.categories.findIndex((c: Category) => c.typeId === currentId)
    this.classIndex = currentIndex >= 0 ? currentIndex : 0
  }

  switchClass(index: number): void {
    if (index === this.classIndex && this.videos.length > 0) return
    this.classIndex = index
    const cat = this.categories[index]
    if (cat) {
      tvbox.loadCategory(cat, 1, true).then(() => { this.syncFromTvbox() })
    }
  }

  loadMore(): void {
    if (tvbox.loading || tvbox.loadingMore || !tvbox.hasMore) return
    const cat = tvbox.currentCategory
    if (cat) {
      tvbox.loadCategory(cat, tvbox.page + 1, false).then(() => { this.syncFromTvbox() })
    }
  }

  onScrollEnd(lastIndex: number): void {
    if (!this.loading && !this.loadingMore && this.videos.length > 0
      && lastIndex >= this.videos.length - 2) {
      this.loadMore()
    }
  }

  openDetail(vodId: string): void {
    app.currentMode = 'tvbox'
    app.currentVideoId = vodId
    app.currentSiteApi = ''
    app.currentSiteReferer = ''
    app.currentSiteName = ''
    app.currentAggGroup = []
    app.pathStack.pushPathByName('Detail', '')
  }

  // 弹层内切换源
  openSourcePanel(): void {
    this.selectedRoot = tvbox.activeSource
      ? tvbox.activeSource.rootUrl
      : (tvbox.roots.length > 0 ? tvbox.roots[0] : '')
    this.showSourcePanel = true
  }

  pickSource(src: SourceConf): void {
    tvbox.selectSource(src).then(() => {
      this.showSourcePanel = tvbox.activeSite === null
      this.syncFromTvbox()
    }).catch((e: Error) => {
      this.errorMsg = e.message ?? String(e)
    })
  }

  // 显示订阅源的完整数据源列表。
  sourceEntries(root: string): SourceConf[] {
    const sources = tvbox.sources.filter((src: SourceConf) => src.rootUrl === root)
    return sources
  }

  sourceCount(root: string): number {
    return this.sourceEntries(root).length
  }

  isRootActive(root: string): boolean {
    return tvbox.activeSource ? tvbox.activeSource.rootUrl === root : false
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 主体内容
      Column() {
        // 当前数据源行（点击弹层切换）
        Row({ space: 8 }) {
          Text('当前数据源').fontSize(13).fontColor($r('app.color.theme_text_hint'))
          Text(this.sourceName)
            .fontSize(13)
            .fontColor($r('app.color.theme_text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text('▾').fontSize(14).fontColor($r('app.color.theme_accent'))
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 4 })
        .onClick(() => { this.openSourcePanel() })

        // 分类横向 Tab
        if (this.categories.length > 0) {
          List({ space: 8 }) {
            ForEach(this.categories, (c: Category, index: number) => {
              ListItem() {
                Text(c.typeName)
                  .fontSize(14)
                  .fontColor(this.classIndex === index ? '#FFFFFF' : $r('app.color.theme_text_muted'))
                  .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                  .backgroundColor(this.classIndex === index ? $r('app.color.theme_accent') : $r('app.color.theme_surface_alt'))
                  .borderRadius(18)
              }
              .onClick(() => { this.switchClass(index) })
            }, (c: Category) => c.typeId)
          }
          .listDirection(Axis.Horizontal)
          .width('100%')
          .height(52)
          .padding({ left: 16, right: 16, top: 10 })
          .scrollBar(BarState.Off)
        }

        // 内容区
        if (this.loading) {
          Column() {
            LoadingProgress().width(42).height(42).color($r('app.color.theme_accent'))
            Text('加载中…').fontSize(14).fontColor($r('app.color.theme_text_hint')).margin({ top: 14 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.errorMsg !== '') {
          Column({ space: 12 }) {
            Text('⚠️').fontSize(40)
            Text(this.errorMsg).fontSize(14).fontColor($r('app.color.theme_text_hint')).textAlign(TextAlign.Center)
            Text('点上方「当前数据源」换个源').fontSize(13).fontColor($r('app.color.theme_text_dim'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .padding(32)
        } else if (this.videos.length === 0) {
          Column() {
            Text('该分类暂无内容').fontSize(14).fontColor($r('app.color.theme_text_dim'))
            Text('点上方「当前数据源」选择影视源').fontSize(12).fontColor($r('app.color.theme_text_placeholder')).margin({ top: 8 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Grid() {
            ForEach(this.videos, (item: VodItem) => {
              GridItem() {
                Column({ space: 6 }) {
                  Image(item.pic)
                    .width('100%')
                    .aspectRatio(0.72)
                    .objectFit(ImageFit.Cover)
                    .borderRadius(12)
                    .backgroundColor($r('app.color.theme_surface_alt'))
                  Text(item.name)
                    .fontSize(14)
                    .fontColor($r('app.color.theme_text_secondary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (item.remarks.length > 0) {
                    Text(item.remarks)
                      .fontSize(11)
                      .fontColor($r('app.color.theme_text_description'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                }
                .alignItems(HorizontalAlign.Start)
              }
              .onClick(() => { this.openDetail(item.vodId) })
            }, (item: VodItem, index: number) => item.vodId + '_' + index.toString())

            if (this.loadingMore) {
              GridItem() {
                Row() {
                  LoadingProgress().width(22).height(22).color($r('app.color.theme_accent'))
                  Text('加载更多…').fontSize(12).fontColor($r('app.color.theme_text_dim')).margin({ left: 8 })
                }
                .width('100%')
                .height(44)
                .justifyContent(FlexAlign.Center)
              }
              .columnStart(0)
              .columnEnd(1)
            } else if (!tvbox.hasMore && this.videos.length > 6) {
              GridItem() {
                Text('— 到底了 —').fontSize(12).fontColor($r('app.color.theme_text_placeholder')).textAlign(TextAlign.Center)
                  .width('100%').height(44)
              }
              .columnStart(0)
              .columnEnd(1)
            }
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(12)
          .rowsGap(14)
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16, top: 4, bottom: 96 })
          .scrollBar(BarState.Off)
          .onScrollIndex((first: number, last: number) => { this.onScrollEnd(last) })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.theme_background'))

      // 遮罩
      if (this.showSourcePanel) {
        Column().width('100%').height('100%').backgroundColor('#66000000')
          .onClick(() => { this.showSourcePanel = false })
      }

      // 半屏数据源面板
      if (this.showSourcePanel) {
        Column() {
          Row() {
            Text('选择数据源').fontSize(17).fontWeight(FontWeight.Bold).fontColor($r('app.color.theme_text_title'))
            Blank()
            Text('管理接口').fontSize(13).fontColor($r('app.color.theme_accent'))
              .onClick(() => { this.showSourcePanel = false; app.pathStack.pushPathByName('SourceManage', '') })
          }
          .width('100%')
          .padding({ left: 18, right: 18, top: 16, bottom: 10 })

          Text('显示全部数据源；点击后自动探测可播放站点').fontSize(11).fontColor($r('app.color.theme_text_dim'))
            .width('100%').padding({ left: 18, bottom: 8 })

          List({ space: 8 }) {
            ForEach(tvbox.roots, (root: string) => {
              ListItem() {
                Column({ space: 3 }) {
                  Row({ space: 5 }) {
                    Text(rootDisplayName(root))
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.selectedRoot === root ? '#FFFFFF' : $r('app.color.theme_text_body_alt'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (this.isRootActive(root)) {
                      Text('当前').fontSize(9).fontColor('#FFFFFF')
                        .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                        .backgroundColor($r('app.color.theme_accent')).borderRadius(8)
                    }
                  }
                    Text(this.sourceCount(root) + ' 个数据源')
                    .fontSize(10).fontColor(this.selectedRoot === root ? $r('app.color.theme_text_accent_soft') : $r('app.color.theme_text_dim'))
                }
                .alignItems(HorizontalAlign.Start)
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor(this.selectedRoot === root ? $r('app.color.theme_accent') : $r('app.color.theme_surface_alt'))
                .borderRadius(12)
              }
              .onClick(() => { this.selectedRoot = root })
            }, (root: string) => root)
          }
          .listDirection(Axis.Horizontal)
          .width('100%')
          .height(62)
          .padding({ left: 16, right: 16, bottom: 6 })
          .scrollBar(BarState.Off)

          List({ space: 8 }) {
            ForEach(this.sourceEntries(this.selectedRoot), (src: SourceConf) => {
              ListItem() {
                Row({ space: 10 }) {
                  Column({ space: 4 }) {
                    Text(src.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.theme_text_secondary'))
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(src.url).fontSize(11).fontColor($r('app.color.theme_text_dim')).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text('点击加载').fontSize(10).fontColor($r('app.color.theme_text_dim'))
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  if (tvbox.activeSource && tvbox.activeSource.id === src.id) {
                    Text('当前').fontSize(11).fontColor('#FFFFFF')
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                      .backgroundColor($r('app.color.theme_accent')).borderRadius(12)
                  }
                }
                .width('100%')
                .padding({ left: 14, right: 14, top: 12, bottom: 12 })
                .backgroundColor($r('app.color.theme_surface_alt'))
                .borderRadius(12)
              }
              .onClick(() => { this.pickSource(src) })
            }, (src: SourceConf) => src.id)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .padding({ left: 16, right: 16 })
        }
        .width('100%')
        .height('62%')
        .backgroundColor($r('app.color.theme_surface'))
        .borderRadius({ topLeft: 22, topRight: 22 })
        .padding({ bottom: 8 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.theme_background'))
  }
}
