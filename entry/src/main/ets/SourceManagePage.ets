import { app } from './AppState'
import { tvbox } from './TvboxState'
import { SiteConf, SourceConf } from './model/TvModels'

/**
 * SourceManagePage.ets —— 接口管理页（添加/删除接口，与「选择数据源」分离）
 * 删除带二次确认，防误触；添加自动识别多仓/单仓
 */
@Component
export struct SourceManagePage {
  @State rootUrl: string = ''
  @State roots: string[] = []
  @State sourceCount: number = 0
  @State expandedRoot: string = ''
  @State loading: boolean = false
  @State errorMsg: string = ''

  async aboutToAppear(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext()
      if (ctx) await app.init(ctx)
      await tvbox.init()
    } catch (e) {
      this.errorMsg = (e as Error).message ?? String(e)
    }
    this.syncFromTvbox()
  }

  syncFromTvbox(): void {
    this.roots = tvbox.roots
    this.sourceCount = tvbox.sources.length
    if (this.expandedRoot !== '' && this.roots.indexOf(this.expandedRoot) < 0) {
      this.expandedRoot = ''
    }
  }

  async addRoot(): Promise<void> {
    const u = this.rootUrl.trim()
    if (u === '') {
      this.toast('请输入接口 URL')
      return
    }
    this.loading = true
    try {
      await tvbox.addRoot(u)
      this.rootUrl = ''
      this.syncFromTvbox()
      this.toast('接口已添加并保存')
    } catch (e) {
      this.toast('添加失败：' + ((e as Error).message ?? String(e)))
    }
    this.loading = false
  }

  confirmRemove(url: string): void {
    this.getUIContext().showAlertDialog({
      title: '删除接口',
      message: '确定删除该接口？删除后需重新添加。',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.theme_error'),
        action: () => { this.doRemove(url) }
      }
    })
  }

  async doRemove(url: string): Promise<void> {
    this.loading = true
    try {
      await tvbox.removeRoot(url)
      this.syncFromTvbox()
      this.toast('已删除接口')
    } catch (e) {
      this.toast('删除失败：' + ((e as Error).message ?? String(e)))
    }
    this.loading = false
  }

  rootName(url: string): string {
    const t: string = url.replace(/^https?:\/\//, '').replace(/\/$/, '')
    const slash: number = t.indexOf('/')
    return slash > 0 ? t.slice(0, slash) : t
  }

  sourcesFor(url: string): SourceConf[] {
    return tvbox.sources.filter((src: SourceConf) => src.rootUrl === url)
  }

  sourceCountFor(url: string): number {
    const sources = this.sourcesFor(url)
    return sources.length
  }

  toggleRoot(url: string): void {
    this.expandedRoot = this.expandedRoot === url ? '' : url
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message })
    } catch (e) {
      // toast is best-effort UI feedback.
    }
  }

  build() {
    NavDestination() {
      Column() {
        // 顶栏
        Row() {
          Text('‹').fontSize(26).fontColor($r('app.color.theme_text_secondary')).padding({ left: 4, right: 8 })
            .onClick(() => { app.pathStack.pop() })
        Text('订阅源管理').fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.theme_text_title'))
          Blank()
        }
        .width('100%')
        .padding({ left: 12, right: 16, top: 8, bottom: 8 })

        // 添加接口
        Row({ space: 8 }) {
          TextInput({ placeholder: '添加订阅源 URL（多仓/单仓都行，自动识别）', text: this.rootUrl })
            .height(42)
            .layoutWeight(1)
            .fontSize(13)
            .backgroundColor($r('app.color.theme_surface_alt'))
            .fontColor($r('app.color.theme_text_secondary'))
            .placeholderColor($r('app.color.theme_text_dim'))
            .borderRadius(10)
            .onChange((v: string) => { this.rootUrl = v })
          Button(this.loading ? '…' : '添加')
            .height(42)
            .fontSize(13)
            .fontColor('#FFFFFF')
            .backgroundColor($r('app.color.theme_accent'))
            .borderRadius(10)
            .onClick(() => { this.addRoot() })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 6, bottom: 8 })

        if (this.errorMsg !== '') {
          Text(this.errorMsg).fontSize(12).fontColor($r('app.color.theme_error_soft'))
            .width('100%').padding({ left: 16, right: 16, top: 4 })
        }

        // 订阅源列表
        Text('已启用订阅源（' + this.roots.length + '）· 共解析出 ' + this.sourceCount + ' 个数据源')
          .fontSize(13).fontColor($r('app.color.theme_text_hint'))
          .width('100%').padding({ left: 16, top: 8, bottom: 6 })

        List({ space: 10 }) {
          ForEach(this.roots, (r: string) => {
            ListItem() {
              Column() {
                Row({ space: 10 }) {
                  Column({ space: 4 }) {
                    Text(this.rootName(r)).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.theme_text_secondary'))
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(r).fontSize(11).fontColor($r('app.color.theme_text_dim')).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Column({ space: 3 }) {
                    Text(this.sourceCountFor(r) + ' 个数据源')
                      .fontSize(12).fontColor($r('app.color.theme_accent'))
                  }
                  .alignItems(HorizontalAlign.End)

                  Text(this.expandedRoot === r ? '▾' : '›')
                    .fontSize(16).fontColor($r('app.color.theme_text_dim')).width(20)
                    .textAlign(TextAlign.Center)
                }

                if (this.expandedRoot === r) {
                  Divider().color($r('app.color.theme_overlay_light_26')).margin({ top: 10, bottom: 8 })

                  if (this.sourceCountFor(r) === 0) {
                    Text('该订阅源没有解析出数据源，可能已失效或接口格式不支持。')
                      .fontSize(12).fontColor($r('app.color.theme_text_hint'))
                      .width('100%')
                      .padding({ top: 4, bottom: 4 })
                  } else {
                    Column({ space: 8 }) {
                      ForEach(this.sourcesFor(r), (src: SourceConf) => {
                        Column({ space: 6 }) {
                          Row({ space: 8 }) {
                            Text(src.name).fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.theme_text_body_alt'))
                              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                            Blank()
                            Text(src.sites.length + ' 站点').fontSize(10).fontColor($r('app.color.theme_text_dim'))
                          }
                          .layoutWeight(1)
                          ForEach(src.sites, (site: SiteConf) => {
                            Row({ space: 8 }) {
                              Column({ space: 2 }) {
                                Text(site.name).fontSize(13).fontColor($r('app.color.theme_text_secondary'))
                                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                                Text(site.api).fontSize(10).fontColor($r('app.color.theme_text_dim'))
                                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                              }
                              .alignItems(HorizontalAlign.Start)
                              .layoutWeight(1)

                              if (tvbox.activeSite && tvbox.activeSite.key === site.key) {
                                Text('当前').fontSize(10).fontColor('#FFFFFF')
                                  .padding({ left: 7, right: 7, top: 2, bottom: 2 })
                                  .backgroundColor($r('app.color.theme_accent')).borderRadius(8)
                              } else {
                                Text('站点').fontSize(10).fontColor($r('app.color.theme_text_hint'))
                              }
                            }
                            .width('100%')
                            .padding(8)
                            .backgroundColor($r('app.color.theme_surface_deep'))
                            .borderRadius(8)
                          }, (site: SiteConf) => site.key)

                        }
                        .width('100%')
                        .padding(8)
                        .backgroundColor($r('app.color.theme_surface_deep_alt'))
                        .borderRadius(10)
                      }, (src: SourceConf) => src.id)
                    }
                    .width('100%')
                  }
                }
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 12, bottom: 12 })
              .backgroundColor($r('app.color.theme_surface'))
              .borderRadius(12)
              .onClick(() => { this.toggleRoot(r) })
            }
            .swipeAction({
              end: {
                builder: (): void => { this.deleteButton(r) }
              }
            })
          }, (r: string) => r)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .padding({ left: 16, right: 16, bottom: 16 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.theme_background'))
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.theme_background'))
  }

  @Builder
  deleteButton(url: string) {
    Row() {
      Text('删除')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
    }
    .width(82)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.theme_error'))
    .borderRadius(12)
    .margin({ left: 8, top: 2, bottom: 2 })
    .onClick(() => { this.confirmRemove(url) })
  }
}
