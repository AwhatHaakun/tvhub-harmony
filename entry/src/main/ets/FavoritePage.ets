// FavoritePage.ets —— 收藏 Tab：我的收藏（2 列海报网格）
// 点击进详情。订阅 dataListener('favorite') 自动刷新

import { app, AppState, VideoItem } from './AppState'

@Component
export struct FavoritePage {
  @State items: VideoItem[] = []
  @State loading: boolean = true

  private listener: (what: string) => void = (what: string) => {
    if (what === 'favorite') {
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
    this.items = await app.loadFavorites()
    this.loading = false
  }

  openDetail(item: VideoItem): void {
    app.currentMode = item.mode ?? 'tvbox'
    app.currentVideoId = item.vod_id
    app.currentAggGroup = []
    // 带站点信息的收藏直接回原站点取详情（旧数据无站点则走当前 activeSite）
    app.currentSiteApi = item.siteApi ?? ''
    app.currentSiteReferer = item.siteReferer ?? ''
    app.currentSiteName = item.siteName ?? ''
    app.pathStack.pushPathByName('Detail', '')
  }

  build() {
    Column() {
      Text('收藏').fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.theme_text_title'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 14 })

      if (this.loading) {
        Column() {
          LoadingProgress().width(42).height(42).color($r('app.color.theme_accent'))
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.items.length === 0) {
        Column({ space: 12 }) {
          Text('⭐').fontSize(40)
          Text('还没有收藏，去详情页点 ☆ 收藏').fontSize(14).fontColor($r('app.color.theme_text_dim'))
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.items, (item: VideoItem) => {
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
          }, (item: VideoItem) => AppState.contentKey(item.mode ?? 'tvbox', item.siteApi ?? '', item.vod_id))
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
