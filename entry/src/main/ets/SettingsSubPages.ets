// SettingsSubPages.ets —— 设置页的二级页面
// 配置、已添加源、添加扩展、网盘凭据分别独立，保留原有数据逻辑。

import { app, SourceItem, ThemeMode } from './AppState'
import { tvbox } from './TvboxState'

function backToSettings(): void {
  app.pathStack.pop()
}

@Component
export struct SettingsConfigPage {
  @State tvboxRootCount: number = 0
  @State tvboxSourceCount: number = 0
  @State tvboxActiveName: string = ''

  private tvboxListener: (what: string) => void = (what: string) => {
    if (what === 'tvbox') this.syncTvboxSummary()
  }

  async aboutToAppear(): Promise<void> {
    tvbox.addDataListener(this.tvboxListener)
    try {
      const ctx = this.getUIContext().getHostContext()
      if (ctx) await app.init(ctx)
      await tvbox.init()
      this.syncTvboxSummary()
    } catch (e) {
      this.tvboxActiveName = '未配置'
    }
  }

  aboutToDisappear(): void {
    tvbox.removeDataListener(this.tvboxListener)
  }

  syncTvboxSummary(): void {
    this.tvboxRootCount = tvbox.roots.length
    this.tvboxSourceCount = tvbox.sources.length
    this.tvboxActiveName = tvbox.currentSourceName()
  }

  build() {
    NavDestination() {
      Column() {
        this.header('配置')
        Scroll() {
          Column({ space: 14 }) {
            Text('接口配置')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.theme_text_title'))
              .width('100%')

            Row({ space: 10 }) {
              Text('订阅源').fontSize(15).fontColor($r('app.color.theme_text_hint'))
              Text(this.tvboxRootCount > 0
                ? `${this.tvboxRootCount} 个订阅 · ${this.tvboxSourceCount} 个数据源`
                : '点击配置订阅源')
                .fontSize(13).fontColor($r('app.color.theme_text_secondary')).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
              Text('>').fontSize(16).fontColor($r('app.color.theme_text_dim'))
            }
            .width('100%')
            .padding(14)
            .backgroundColor($r('app.color.theme_surface'))
            .borderRadius(12)
            .onClick(() => { app.pathStack.pushPathByName('SourceManage', '') })

            Column({ space: 4 }) {
              Text('当前数据源').fontSize(12).fontColor($r('app.color.theme_text_hint'))
              Text(this.tvboxActiveName.length > 0 ? this.tvboxActiveName : '未配置')
                .fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.theme_text_secondary'))
              Text('点首页顶部「当前数据源 ▾」可切换').fontSize(11).fontColor($r('app.color.theme_text_dim'))
            }
            .width('100%')
            .padding(14)
            .backgroundColor($r('app.color.theme_surface'))
            .borderRadius(12)
            .alignItems(HorizontalAlign.Start)

            Text('配置说明')
              .fontSize(13)
              .fontColor($r('app.color.theme_text_hint'))
              .width('100%')
            Text('在这里管理聚合接口和当前使用的数据源。首页只展示可用的标准接口，Spider/JAR 或失效接口会自动跳过。')
              .fontSize(12)
              .fontColor($r('app.color.theme_text_dim'))
              .lineHeight(18)
              .width('100%')
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 32 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.theme_background'))
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.theme_background'))
  }

  @Builder
  header(title: string) {
    Row() {
      Text('‹')
        .fontSize(30)
        .fontColor($r('app.color.theme_text_secondary'))
        .width(40)
        .textAlign(TextAlign.Center)
        .onClick(() => { backToSettings() })
      Text(title)
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.theme_text_title'))
        .layoutWeight(1)
    }
    .width('100%')
    .height(54)
    .padding({ left: 4, right: 16 })
    .backgroundColor($r('app.color.theme_bar'))
  }
}

@Component
export struct SettingsSourcesPage {
  @State sources: SourceItem[] = []
  @State activeKey: string = ''
  @State busy: boolean = false

  async aboutToAppear(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext()
      if (ctx) await app.init(ctx)
    } catch (e) {
      // 初始化失败时仍允许显示已有状态。
    }
    await this.refreshSources()
  }

  async refreshSources(): Promise<void> {
    this.sources = await app.loadSources()
    this.activeKey = app.activeSourceKey
  }

  async switchSource(key: string): Promise<void> {
    if (key === this.activeKey || this.busy) return
    this.busy = true
    try {
      await app.setActiveSource(key)
      this.activeKey = key
      this.toast('已切换，首页内容已刷新')
    } catch (e) {
      this.toast('切换失败：' + ((e as Error).message ?? String(e)))
    }
    this.busy = false
  }

  async removeSource(key: string): Promise<void> {
    if (this.busy) return
    this.busy = true
    try {
      await app.removeSource(key)
      await this.refreshSources()
      this.toast('已删除')
    } catch (e) {
      this.toast('删除失败：' + ((e as Error).message ?? String(e)))
    }
    this.busy = false
  }

  build() {
    NavDestination() {
      Column() {
        this.header('源管理')
        Scroll() {
          Column({ space: 10 }) {
            Text('已添加扩展源')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.theme_text_title'))
              .width('100%')
              .margin({ top: 14 })
            Text('在这里切换或删除已经添加的 脚本扩展。添加新扩展请进入「添加扩展」。')
              .fontSize(12)
              .fontColor($r('app.color.theme_text_dim'))
              .lineHeight(18)
              .width('100%')

            if (this.sources.length === 0) {
              Text('暂未添加扩展源')
                .fontSize(13)
                .fontColor($r('app.color.theme_text_dim'))
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 28, bottom: 28 })
            } else {
              ForEach(this.sources, (s: SourceItem) => {
                Row({ space: 10 }) {
                  Column({ space: 4 }) {
                    Text(s.name)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.theme_text_title'))
                    if (s.url.length > 0) {
                      Text(s.url)
                        .fontSize(11)
                        .fontColor($r('app.color.theme_text_dim'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  if (s.key === this.activeKey) {
                    Text('当前')
                      .fontSize(12)
                      .fontColor($r('app.color.theme_accent'))
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                      .backgroundColor($r('app.color.theme_accent_overlay'))
                      .borderRadius(8)
                  } else {
                    Button('切换')
                      .fontSize(12)
                      .height(32)
                      .backgroundColor($r('app.color.theme_surface_alt'))
                      .fontColor($r('app.color.theme_text_button'))
                      .borderRadius(8)
                      .enabled(!this.busy)
                      .onClick(() => { this.switchSource(s.key) })
                  }
                  if (!s.builtin) {
                    Text('删除')
                      .fontSize(12)
                      .fontColor($r('app.color.theme_error'))
                      .width(40)
                      .textAlign(TextAlign.Center)
                      .onClick(() => { this.removeSource(s.key) })
                  }
                }
                .width('100%')
                .padding(12)
                .backgroundColor($r('app.color.theme_surface'))
                .borderRadius(12)
              }, (s: SourceItem) => s.key)
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 32 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.theme_background'))
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.theme_background'))
  }

  @Builder
  header(title: string) {
    Row() {
      Text('‹')
        .fontSize(30)
        .fontColor($r('app.color.theme_text_secondary'))
        .width(40)
        .textAlign(TextAlign.Center)
        .onClick(() => { backToSettings() })
      Text(title)
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.theme_text_title'))
        .layoutWeight(1)
    }
    .width('100%')
    .height(54)
    .padding({ left: 4, right: 16 })
    .backgroundColor($r('app.color.theme_bar'))
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message })
    } catch (e) {
      // toast is best-effort UI feedback.
    }
  }
}

@Component
export struct SettingsAddExtensionPage {
  @State srcUrl: string = ''
  @State srcName: string = ''
  @State busy: boolean = false

  async aboutToAppear(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext()
      if (ctx) await app.init(ctx)
    } catch (e) {
      // 初始化失败由实际操作时的错误提示反馈。
    }
  }

  async addSource(): Promise<void> {
    const url: string = this.srcUrl.trim()
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      this.toast('请输入 http(s) 开头的扩展地址')
      return
    }
    if (this.busy) return
    this.busy = true
    try {
      await app.addSourceFromUrl(url, this.srcName.trim())
      this.srcUrl = ''
      this.srcName = ''
      this.toast('已添加，源管理中可以切换')
    } catch (e) {
      this.toast('添加失败：' + ((e as Error).message ?? String(e)))
    }
    this.busy = false
  }

  build() {
    NavDestination() {
      Column() {
        this.header('添加扩展')
        Scroll() {
          Column({ space: 14 }) {
            Text('添加 脚本扩展')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.theme_text_title'))
              .width('100%')
              .margin({ top: 14 })
            Text('支持明文 .js、.js.md5 地址，以及 https://用户名:密码@域名 的 Basic Auth 地址。')
              .fontSize(12)
              .fontColor($r('app.color.theme_text_dim'))
              .lineHeight(18)
              .width('100%')

            TextInput({ placeholder: '扩展 .js / .js.md5 地址', text: this.srcUrl })
              .width('100%')
              .height(46)
              .fontSize(14)
              .fontColor($r('app.color.theme_text_secondary'))
              .placeholderColor($r('app.color.theme_text_placeholder'))
              .backgroundColor($r('app.color.theme_surface'))
              .borderRadius(10)
              .padding({ left: 12, right: 12 })
              .onChange((v: string) => { this.srcUrl = v })
            TextInput({ placeholder: '名称（可选）', text: this.srcName })
              .width('100%')
              .height(46)
              .fontSize(14)
              .fontColor($r('app.color.theme_text_secondary'))
              .placeholderColor($r('app.color.theme_text_placeholder'))
              .backgroundColor($r('app.color.theme_surface'))
              .borderRadius(10)
              .padding({ left: 12, right: 12 })
              .onChange((v: string) => { this.srcName = v })
            Button(this.busy ? '处理中…' : '下载并添加')
              .width('100%')
              .height(46)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .backgroundColor($r('app.color.theme_accent'))
              .fontColor('#FFFFFF')
              .borderRadius(10)
              .enabled(!this.busy)
              .onClick(() => { this.addSource() })
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 32 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.theme_background'))
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.theme_background'))
  }

  @Builder
  header(title: string) {
    Row() {
      Text('‹')
        .fontSize(30)
        .fontColor($r('app.color.theme_text_secondary'))
        .width(40)
        .textAlign(TextAlign.Center)
        .onClick(() => { backToSettings() })
      Text(title)
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.theme_text_title'))
        .layoutWeight(1)
    }
    .width('100%')
    .height(54)
    .padding({ left: 4, right: 16 })
    .backgroundColor($r('app.color.theme_bar'))
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message })
    } catch (e) {
      // toast is best-effort UI feedback.
    }
  }
}

@Component
export struct SettingsPanPage {
  @State quarkCookie: string = ''
  @State aliToken: string = ''
  @State baiduCookie: string = ''
  @State saveDirName: string = ''
  @State pansouHost: string = ''
  @State loaded: boolean = false

  async aboutToAppear(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext()
      if (ctx) await app.init(ctx)
      await this.loadEnv()
    } catch (e) {
      this.loaded = true
    }
  }

  async loadEnv(): Promise<void> {
    try {
      this.quarkCookie = await app.getEnvValue('夸克Cookie')
      this.aliToken = await app.getEnvValue('阿里RefreshToken')
      this.baiduCookie = await app.getEnvValue('百度网盘Cookie')
      this.saveDirName = await app.getEnvValue('转存文件夹名称')
      this.pansouHost = await app.getEnvValue('盘搜地址')
    } catch (e) {
      // 读取失败保持空值。
    }
    this.loaded = true
  }

  async saveEnv(): Promise<void> {
    try {
      await app.setEnvValue('夸克Cookie', this.quarkCookie.trim())
      await app.setEnvValue('阿里RefreshToken', this.aliToken.trim())
      await app.setEnvValue('百度网盘Cookie', this.baiduCookie.trim())
      await app.setEnvValue('转存文件夹名称', this.saveDirName.trim() || 'uz影视')
      await app.setEnvValue('盘搜地址', this.pansouHost.trim() || 'https://pan.199333.xyz')
      this.toast('已保存，重新进入详情页生效')
    } catch (e) {
      this.toast('保存失败：' + ((e as Error).message ?? String(e)))
    }
  }

  build() {
    NavDestination() {
      Column() {
        this.header('网盘')
        Scroll() {
          Column({ space: 14 }) {
            if (!this.loaded) {
              Column() {
                LoadingProgress().width(42).height(42).color($r('app.color.theme_accent'))
              }
              .width('100%')
              .height(120)
              .justifyContent(FlexAlign.Center)
            } else {
              Text('网盘凭据')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.theme_text_title'))
                .width('100%')
                .margin({ top: 14 })

              this.fieldLabel('夸克网盘 Cookie', '播放夸克源必需。网页登录 pan.quark.cn 后 F12 复制整串 Cookie')
              this.darkArea(this.quarkCookie, '粘贴夸克 Cookie', (v: string) => { this.quarkCookie = v })

              this.fieldLabel('阿里云盘 RefreshToken', '播放阿里源必需。网页登录 alipan.com 后取 refresh_token')
              this.darkArea(this.aliToken, '粘贴阿里 refresh_token', (v: string) => { this.aliToken = v })

              this.fieldLabel('百度网盘 Cookie', '播放百度源必需（含 BDUSS）。非 SVIP 限速，建议优先夸克/阿里')
              this.darkArea(this.baiduCookie, '粘贴百度网盘 Cookie', (v: string) => { this.baiduCookie = v })

              this.fieldLabel('转存文件夹名称', '夸克/阿里转存到的文件夹名（每次播放会清空）')
              this.darkInput(this.saveDirName, 'uz影视', (v: string) => { this.saveDirName = v })

              this.fieldLabel('盘搜地址', 'PanSou 聚合搜索站，失效可换镜像')
              this.darkInput(this.pansouHost, 'https://pan.199333.xyz', (v: string) => { this.pansouHost = v })

              Button('保存')
                .width('100%')
                .height(48)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .backgroundColor($r('app.color.theme_accent'))
                .fontColor('#FFFFFF')
                .borderRadius(12)
                .margin({ top: 6 })
                .onClick(() => { this.saveEnv() })

              Text('凭据获取步骤见：extensions-src/catpaw/网盘Cookie配置指南.md')
                .fontSize(12)
                .fontColor($r('app.color.theme_text_dim'))
                .lineHeight(18)
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 32 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.theme_background'))
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.theme_background'))
  }

  @Builder
  header(title: string) {
    Row() {
      Text('‹')
        .fontSize(30)
        .fontColor($r('app.color.theme_text_secondary'))
        .width(40)
        .textAlign(TextAlign.Center)
        .onClick(() => { backToSettings() })
      Text(title)
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.theme_text_title'))
        .layoutWeight(1)
    }
    .width('100%')
    .height(54)
    .padding({ left: 4, right: 16 })
    .backgroundColor($r('app.color.theme_bar'))
  }

  @Builder
  fieldLabel(title: string, desc: string) {
    Column({ space: 4 }) {
      Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.theme_text_title'))
      Text(desc).fontSize(12).fontColor($r('app.color.theme_text_description')).lineHeight(17)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  darkArea(value: string, placeholder: string, onChange: (v: string) => void) {
    TextArea({ text: value, placeholder: placeholder })
      .height(84)
      .fontSize(13)
      .fontColor($r('app.color.theme_text_secondary'))
      .placeholderColor($r('app.color.theme_text_placeholder'))
      .backgroundColor($r('app.color.theme_surface'))
      .borderRadius(10)
      .padding(12)
      .onChange(onChange)
  }

  @Builder
  darkInput(value: string, placeholder: string, onChange: (v: string) => void) {
    TextInput({ text: value, placeholder: placeholder })
      .height(46)
      .fontSize(14)
      .fontColor($r('app.color.theme_text_secondary'))
      .placeholderColor($r('app.color.theme_text_placeholder'))
      .backgroundColor($r('app.color.theme_surface'))
      .borderRadius(10)
      .padding({ left: 12, right: 12 })
      .onChange(onChange)
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message })
    } catch (e) {
      // toast is best-effort UI feedback.
    }
  }
}

@Component
export struct SettingsThemePage {
  @State selectedMode: ThemeMode = 'system'

  aboutToAppear(): void {
    this.selectedMode = app.themeMode
  }

  async chooseMode(mode: ThemeMode): Promise<void> {
    this.selectedMode = mode
    try {
      await app.setThemeMode(mode)
      this.toast(mode === 'light' ? '已切换到日间模式' : mode === 'dark' ? '已切换到夜间模式' : '已跟随系统主题')
    } catch (e) {
      this.toast('主题保存失败：' + ((e as Error).message ?? String(e)))
    }
  }

  build() {
    NavDestination() {
      Column() {
        this.header('主题模式')
        Scroll() {
          Column({ space: 12 }) {
            Text('显示模式')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.theme_text_title'))
              .width('100%')
              .margin({ top: 14 })
            Text('选择应用使用的颜色主题。跟随系统会根据设备当前的日间/夜间设置自动变化。')
              .fontSize(12)
              .fontColor($r('app.color.theme_text_hint'))
              .lineHeight(18)
              .width('100%')

            this.option('日间模式', '使用浅色背景和深色文字', 'light')
            this.option('夜间模式', '使用深色背景和浅色文字', 'dark')
            this.option('跟随系统', '跟随系统主题自动切换', 'system')
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 32 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.theme_background'))
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.theme_background'))
  }

  @Builder
  option(title: string, description: string, mode: ThemeMode) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.theme_text_title'))
        Text(description)
          .fontSize(12)
          .fontColor($r('app.color.theme_text_hint'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(this.selectedMode === mode ? '✓' : '')
        .fontSize(20)
        .fontColor($r('app.color.theme_accent'))
        .width(26)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.theme_surface'))
    .borderRadius(12)
    .onClick(() => { this.chooseMode(mode) })
  }

  @Builder
  header(title: string) {
    Row() {
      Text('‹')
        .fontSize(30)
        .fontColor($r('app.color.theme_text_secondary'))
        .width(40)
        .textAlign(TextAlign.Center)
        .onClick(() => { backToSettings() })
      Text(title)
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.theme_text_title'))
        .layoutWeight(1)
    }
    .width('100%')
    .height(54)
    .padding({ left: 4, right: 16 })
    .backgroundColor($r('app.color.theme_bar'))
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message })
    } catch (e) {
      // toast is best-effort UI feedback.
    }
  }
}
