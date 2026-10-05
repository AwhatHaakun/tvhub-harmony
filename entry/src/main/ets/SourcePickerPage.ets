import { app } from './AppState'
import { tvbox } from './TvboxState'
import { SiteConf, SourceConf } from './model/TvModels'
import { rootDisplayName } from './api/TvboxApi'

/**
 * SourcePickerPage.ets —— 影视源管理页（NavDestination）
 * 能力：添加/删除接口（多仓或单仓 URL，自动识别并保存）、源列表、站点选择
 * 选中站点即持久化（源 id + 站点 key），重启自动恢复
 */
@Component
export struct SourcePickerPage {
  @State rootUrl: string = ''
  @State roots: string[] = []
  @State sources: SourceConf[] = []
  @State sites: SiteConf[] = []
  @State loading: boolean = false
  @State errorMsg: string = ''
  @State currentSourceName: string = ''
  @State activeSourceName: string = ''
  @State activeSiteName: string = ''

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
    this.sources = tvbox.sources
    this.sites = tvbox.activeSource ? tvbox.activeSource.sites : []
    this.currentSourceName = tvbox.activeSource ? tvbox.activeSource.name : ''
    this.activeSourceName = tvbox.activeSource ? tvbox.activeSource.name : ''
    this.activeSiteName = tvbox.activeSite ? tvbox.activeSite.name : ''
    this.errorMsg = tvbox.rootError !== '' ? tvbox.rootError : this.errorMsg
  }

  async addRoot(): Promise<void> {
    const u = this.rootUrl.trim()
    if (u === '') {
      this.toast('请输入接口 URL')
      return
    }
    this.loading = true
    this.errorMsg = ''
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

  async removeRoot(url: string): Promise<void> {
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

  async pickSource(src: SourceConf): Promise<void> {
    this.loading = true
    this.errorMsg = ''
    this.sites = []
    this.currentSourceName = src.name
    try {
      await tvbox.selectSource(src)
      this.syncFromTvbox()
    } catch (e) {
      this.errorMsg = (e as Error).message ?? String(e)
    }
    this.loading = false
  }

  pickSite(site: SiteConf): void {
    if (site.status !== 'ok') return
    tvbox.selectSite(site).then(() => {
      this.syncFromTvbox()
      if (tvbox.activeSite && tvbox.activeSite.key === site.key && tvbox.activeSite.api === site.api) {
        this.toast('已保存：' + site.name)
        app.pathStack.pop()
      } else {
        this.errorMsg = tvbox.errorMsg !== '' ? tvbox.errorMsg : '该站点没有可展示内容，请换一个站点'
      }
    }).catch((e: Error) => {
      this.errorMsg = e.message ?? String(e)
    })
  }

  statusText(s: SiteConf): string {
    if (s.status === 'ok') return '标准接口'
    if (s.status === 'jar') return '需 Spider/JAR'
    return '需 drpy/JS'
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
          Text('影视源').fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.theme_text_title'))
          Blank()
          if (this.activeSiteName !== '') {
            Text(this.activeSourceName + ' / ' + this.activeSiteName)
              .fontSize(11).fontColor($r('app.color.theme_accent')).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')
        .padding({ left: 12, right: 16, top: 8, bottom: 8 })

        // 添加接口
        Row({ space: 8 }) {
          TextInput({ placeholder: '添加接口 URL（多仓/单仓都行，自动识别）', text: this.rootUrl })
            .height(42)
            .layoutWeight(1)
            .fontSize(13)
            .backgroundColor($r('app.color.theme_surface_alt'))
            .fontColor($r('app.color.theme_text_secondary'))
            .placeholderColor($r('app.color.theme_text_dim'))
            .borderRadius(10)
            .onChange((v: string) => { this.rootUrl = v })
          Button('添加')
            .height(42)
            .fontSize(13)
            .fontColor('#FFFFFF')
            .backgroundColor($r('app.color.theme_accent'))
            .borderRadius(10)
            .onClick(() => { this.addRoot() })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 6, bottom: 6 })

        // 已保存接口
        if (this.roots.length > 0) {
          Text('我的接口（已保存 ' + this.roots.length + ' 个）').fontSize(12).fontColor($r('app.color.theme_text_hint'))
            .width('100%').padding({ left: 16, top: 4, bottom: 4 })
          List({ space: 6 }) {
            ForEach(this.roots, (r: string) => {
              ListItem() {
                Row({ space: 6 }) {
                  Text(rootDisplayName(r)).fontSize(12).fontColor($r('app.color.theme_text_button')).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  Text('×')
                    .fontSize(16)
                    .fontColor($r('app.color.theme_error'))
                    .width(24)
                    .textAlign(TextAlign.Center)
                    .onClick(() => { this.removeRoot(r) })
                }
                .width('100%')
                .padding({ left: 12, right: 6, top: 7, bottom: 7 })
                .backgroundColor($r('app.color.theme_surface_deep_alt'))
                .borderRadius(10)
              }
            }, (r: string) => r)
          }
          .listDirection(Axis.Horizontal)
          .width('100%')
          .height(44)
          .padding({ left: 16, right: 16 })
          .scrollBar(BarState.Off)
        }

        if (this.loading) {
          Row({ space: 10 }) {
            LoadingProgress().width(20).height(20).color($r('app.color.theme_accent'))
            Text('加载中…').fontSize(13).fontColor($r('app.color.theme_text_hint'))
          }
          .width('100%').height(40).justifyContent(FlexAlign.Center)
        } else if (this.errorMsg !== '') {
          Text(this.errorMsg).fontSize(12).fontColor($r('app.color.theme_error_soft'))
            .width('100%').padding({ left: 16, right: 16, top: 8 })
        }

        // 当前源下的站点列表（选中源后填充）
        if (this.sites.length > 0) {
          Text(this.currentSourceName + ' · 选择站点（点即保存）').fontSize(13).fontColor($r('app.color.theme_text_hint'))
            .width('100%').padding({ left: 16, top: 8, bottom: 4 })
          List({ space: 8 }) {
            ForEach(this.sites, (s: SiteConf) => {
              ListItem() {
                Row({ space: 8 }) {
                  Column({ space: 2 }) {
                    Text(s.name).fontSize(14).fontColor($r('app.color.theme_text_secondary')).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(s.api === '' ? '内置爬虫' : s.api).fontSize(10).fontColor($r('app.color.theme_text_dim')).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  Text(this.statusText(s))
                    .fontSize(11)
                    .fontColor(s.status === 'ok' ? $r('app.color.theme_accent') : $r('app.color.theme_text_placeholder'))
                    .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                    .backgroundColor(s.status === 'ok' ? $r('app.color.theme_accent_surface') : $r('app.color.theme_surface_alt'))
                    .borderRadius(12)
                }
                .width('100%')
                .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                .backgroundColor(s.status === 'ok' ? $r('app.color.theme_surface') : $r('app.color.theme_surface_deep_alt'))
                .borderRadius(12)
                .opacity(s.status === 'ok' ? 1 : 0.55)
              }
              .onClick(() => { this.pickSite(s) })
            }, (s: SiteConf) => s.key)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .padding({ left: 16, right: 16, bottom: 16 })
        } else {
          // 源列表
          Text('源列表（' + this.sources.length + ' 个）').fontSize(13).fontColor($r('app.color.theme_text_hint'))
            .width('100%').padding({ left: 16, top: 8, bottom: 4 })
          List({ space: 8 }) {
            ForEach(this.sources, (src: SourceConf) => {
              ListItem() {
                Row({ space: 8 }) {
                  Column({ space: 2 }) {
                    Text(src.name).fontSize(14).fontColor($r('app.color.theme_text_secondary')).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(src.rootUrl).fontSize(10).fontColor($r('app.color.theme_text_dim')).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  if (src.id === (tvbox.activeSource ? tvbox.activeSource.id : '')) {
                    Text('当前').fontSize(11).fontColor('#FFFFFF')
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                      .backgroundColor($r('app.color.theme_accent')).borderRadius(12)
                  }
                }
                .width('100%')
                .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                .backgroundColor($r('app.color.theme_surface'))
                .borderRadius(12)
              }
              .onClick(() => { this.pickSource(src) })
            }, (src: SourceConf) => src.id)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .padding({ left: 16, right: 16, bottom: 16 })
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
