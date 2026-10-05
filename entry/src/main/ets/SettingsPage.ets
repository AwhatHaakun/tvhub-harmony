// SettingsPage.ets —— 设置首页：各功能独立进入二级页面。

import { app } from './AppState'

@Component
export struct SettingsPage {
  build() {
    Column() {
      Text('设置')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.theme_text_title'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 14 })

      Scroll() {
        Column({ space: 12 }) {
          this.entry('配置', '接口和当前数据源', 'SettingsConfig')
          this.entry('嗅探', '在网页内监听 m3u8 / MP4 媒体请求', 'Sniffer')
          this.entry('源管理', '查看、切换或删除已添加的扩展', 'SettingsSources')
          this.entry('网盘', 'Cookie、Token 和转存配置', 'SettingsPan')
          this.entry('添加扩展', '添加 .js / .js.md5 扩展源', 'SettingsAddExtension')
          this.entry('主题模式', '日间、夜间或跟随系统', 'SettingsTheme')
          this.entry('主题色', '更改应用主题色', 'ThemeColor')
          this.entry('下载管理', '查看和管理下载任务', 'Download')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 96 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.theme_background'))
  }

  @Builder
  entry(title: string, description: string, path: string) {
    Row({ space: 12 }) {
      Column({ space: 5 }) {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.theme_text_title'))
        Text(description)
          .fontSize(12)
          .fontColor($r('app.color.theme_text_hint'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›')
        .fontSize(22)
        .fontColor($r('app.color.theme_text_dim'))
    }
    .width('100%')
    .padding({ left: 16, right: 14, top: 16, bottom: 16 })
    .backgroundColor($r('app.color.theme_surface'))
    .borderRadius(14)
    .onClick(() => { app.pathStack.pushPathByName(path, '') })
  }
}
