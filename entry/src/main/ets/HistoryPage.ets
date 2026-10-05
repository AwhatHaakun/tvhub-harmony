// HistoryPage.ets —— 历史 Tab：最近观看记录（2 列海报网格）
// 点击进详情；顶部可清空。订阅 dataListener('history') 自动刷新

import { app, AppState, HistoryItem } from './AppState'

@Component
export struct HistoryPage {
  @State items: HistoryItem[] = []
  @State loading: boolean = true

  private listener: (what: string) => void = (what: string) => {
    if (what === 'history') {
      this.refresh()
    }
  }

  async aboutToAppear(): Promise<void> {
    app.addDataListener(this.listener)
    await this.refresh()
  }

  aboutToDisappear(): void {
    app.removeDataListener(this.listener)
  }

  async refresh(): Promise<void> {
    this.items = await app.loadHistory()
    this.loading = false
  }

  openDetail(item: HistoryItem): void {
    app.currentMode = item.mode ?? 'tvbox'
    app.currentVideoId = item.vod_id
    app.currentAggGroup = []
    // 带站点信息的历史直接回原站点取详情（旧数据无站点则走当前 activeSite）
    app.currentSiteApi = item.siteApi ?? ''
    app.currentSiteReferer = item.siteReferer ?? ''
    app.currentSiteName = item.siteName ?? ''
    app.pathStack.pushPathByName('Detail', '')
  }

  build() {
    Column() {
      // 标题 + 清空
      Row() {
        Text('历史').fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.theme_text_title'))
        Blank()
        if (this.items.length > 0) {
          Text('清空')
            .fontSize(13)
            .fontColor($r('app.color.theme_text_hint'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor($r('app.color.theme_surface_alt'))
            .borderRadius(14)
            .onClick(() => { app.clearHistory() })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14 })

      if (this.loading) {
        Column() {
          LoadingProgress().width(42).height(42).color($r('app.color.theme_accent'))
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.items.length === 0) {
        Column({ space: 12 }) {
          Text('🕘').fontSize(40)
          Text('还没有观看记录').fontSize(14).fontColor($r('app.color.theme_text_dim'))
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.items, (item: HistoryItem) => {
            GridItem() {
              Column({ space: 6 }) {
                Image(item.vod_pic)
                  .width('100%')
                  .aspectRatio(0.72)
                  .objectFit(ImageFit.Cover)
                  .borderRadius(12)
                  .backgroundColor($r('app.color.theme_surface_alt'))
                Text(item.vod_name)
                  .fontSize(14)
                  .fontColor($r('app.color.theme_text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(item.vod_remarks)
                  .fontSize(11)
                  .fontColor($r('app.color.theme_text_description'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
            }
            .onClick(() => { this.openDetail(item) })
          }, (item: HistoryItem) => AppState.contentKey(item.mode ?? 'tvbox', item.siteApi ?? '', item.vod_id))
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(12)
        .rowsGap(14)
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 4, bottom: 96 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.theme_background'))
  }
}
