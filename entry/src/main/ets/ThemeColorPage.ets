/**
 * 主题色配置页面
 */

import { app } from './AppState'
import { ThemeColor } from './services/ThemeService'

@Component
export struct ThemeColorPage {
  @State colors: ThemeColor[] = []
  @State currentColor: ThemeColor | null = null

  async aboutToAppear(): Promise<void> {
    this.colors = app.themeService.getAvailableColors()
    this.currentColor = await app.themeService.getCurrentColor()
  }

  async selectColor(color: ThemeColor): Promise<void> {
    this.currentColor = color
    await app.setThemeColor(color)
  }

  build() {
    NavDestination() {
      Column() {
        // 顶栏
        Row() {
          Text('‹')
            .fontSize(30)
            .fontColor($r('app.color.theme_text_secondary'))
            .width(36)
            .onClick(() => { app.pathStack.pop() })
          Text('主题色')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.theme_text_title'))
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 8, right: 16, top: 10, bottom: 10 })

        Text('选择一个主题色')
          .fontSize(13)
          .fontColor($r('app.color.theme_text_hint'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })

        // 颜色列表
        List({ space: 12 }) {
          ForEach(this.colors, (color: ThemeColor) => {
            ListItem() {
              Row({ space: 14 }) {
                // 颜色预览圆
                Stack() {
                  Column()
                    .width(48)
                    .height(48)
                    .backgroundColor(color.accent)
                    .borderRadius(24)

                  if (this.currentColor?.name === color.name) {
                    Text('✓')
                      .fontSize(24)
                      .fontColor('#FFFFFF')
                      .fontWeight(FontWeight.Bold)
                  }
                }

                // 颜色名称
                Column({ space: 4 }) {
                  Text(color.name)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.theme_text_title'))

                  Row({ space: 4 }) {
                    Column()
                      .width(20)
                      .height(20)
                      .backgroundColor(color.accent)
                      .borderRadius(4)
                    Column()
                      .width(20)
                      .height(20)
                      .backgroundColor(color.accentAlt)
                      .borderRadius(4)
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                if (this.currentColor?.name === color.name) {
                  Text('当前')
                    .fontSize(12)
                    .fontColor($r('app.color.theme_accent'))
                }
              }
              .width('100%')
              .padding(16)
              .backgroundColor(this.currentColor?.name === color.name
                ? $r('app.color.theme_accent_translucent')
                : $r('app.color.theme_card'))
              .borderRadius(12)
              .border({
                width: 2,
                color: this.currentColor?.name === color.name
                  ? $r('app.color.theme_accent')
                  : 'transparent'
              })
            }
            .onClick(() => {
              this.selectColor(color)
            })
          }, (color: ThemeColor) => color.name)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 10, bottom: 16 })

        Text('主题色更改后需要重启应用生效')
          .fontSize(12)
          .fontColor($r('app.color.theme_text_placeholder'))
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding({ bottom: 20 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.theme_background'))
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.theme_background'))
  }
}
