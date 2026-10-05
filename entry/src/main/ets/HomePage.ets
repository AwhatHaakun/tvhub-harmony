// HomePage.ets —— 应用主壳：底部悬浮 Tab 栏 + 五个页面
// Tab：首页（源驱动内容流）/ 搜索 / 历史 / 收藏 / 设置（含源管理 + 网盘凭据）
// 用 Tabs(barHeight=0) 承载页面，自绘悬浮胶囊底栏叠在内容上方（毛玻璃感）

import { HomeTab } from './HomeTab'
import { SearchPage } from './SearchPage'
import { HistoryPage } from './HistoryPage'
import { FavoritePage } from './FavoritePage'
import { SettingsPage } from './SettingsPage'

@Component
export struct HomePage {
  @State currentTab: number = 0
  private tabsController: TabsController = new TabsController()

  @Builder
  barItem(index: number, label: string) {
    Column() {
      Text(label)
        .fontSize(13)
        .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentTab === index ? '#FFFFFF' : $r('app.color.theme_text_muted'))
    }
    .justifyContent(FlexAlign.Center)
    .height(44)
    .layoutWeight(1)
    .borderRadius(22)
    .linearGradient(this.currentTab === index
      ? { angle: 135, colors: [[$r('app.color.theme_accent'), 0], [$r('app.color.theme_accent_alt'), 1]] }
      : { angle: 135, colors: [['#00000000', 0], ['#00000000', 1]] })
    .shadow(this.currentTab === index
      ? { radius: 14, color: $r('app.color.theme_accent_shadow_alt'), offsetY: 4 }
      : { radius: 0, color: '#00000000' })
    .onClick(() => {
      this.currentTab = index
      this.tabsController.changeIndex(index)
    })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 页面容器
      Tabs({ barPosition: BarPosition.End, index: this.currentTab, controller: this.tabsController }) {
        TabContent() { HomeTab() }
        TabContent() { SearchPage() }
        TabContent() { HistoryPage() }
        TabContent() { FavoritePage() }
        TabContent() { SettingsPage() }
      }
      .barHeight(0)
      .scrollable(false)
      .animationDuration(0)
      .width('100%')
      .height('100%')
      .onChange((index: number) => { this.currentTab = index })

      // 悬浮底栏
      Row() {
        this.barItem(0, '首页')
        this.barItem(1, '搜索')
        this.barItem(2, '历史')
        this.barItem(3, '收藏')
        this.barItem(4, '设置')
      }
      .width('92%')
      .height(60)
      .padding({ left: 4, right: 4 })
      .backgroundColor($r('app.color.theme_card_strong'))
        .borderRadius(30)
      .border({ width: 0.5, color: $r('app.color.theme_overlay_light_38') })
      .shadow({ radius: 24, color: '#55000000', offsetY: 8 })
      .margin({ bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.theme_background'))
  }
}
