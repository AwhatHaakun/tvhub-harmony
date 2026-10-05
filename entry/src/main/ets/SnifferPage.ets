// SnifferPage.ets —— 在 ArkWeb 内加载网页并监听媒体资源请求。
// 这是“网页内嗅探”，不会抓取其他 App 的系统网络流量。

import { webview } from '@kit.ArkWeb'
import { app } from './AppState'
import { SnifferService, SniffMediaType, SniffResult } from './SnifferService'

const SNIFFER_UA: string = 'Mozilla/5.0 (Linux; Android 13; HarmonyOS 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'

@Component
export struct SnifferPage {
  @State pageUrl: string = ''
  @State webUrl: string = ''
  @State results: SniffResult[] = []
  @State statusText: string = '输入影视网页地址后开始加载'
  @State loading: boolean = false
  @State sniffing: boolean = true

  private controller: webview.WebviewController = new webview.WebviewController()
  private currentPageUrl: string = ''

  aboutToAppear(): void {
    this.sniffing = true
  }

  loadPage(): void {
    const value: string = this.pageUrl.trim()
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      this.toast('请输入 http(s) 开头的网页地址')
      return
    }
    this.pageUrl = value
    this.currentPageUrl = value
    this.results = []
    this.loading = true
    this.sniffing = true
    this.statusText = '正在加载网页，等待媒体请求…'
    this.webUrl = value
  }

  startSniff(): void {
    this.sniffing = true
    this.results = []
    this.statusText = this.webUrl.length > 0 ? '正在嗅探媒体请求…' : '请先加载网页'
  }

  clearResults(): void {
    this.results = []
    this.statusText = this.webUrl.length > 0 ? '已清空，继续等待媒体请求…' : '输入影视网页地址后开始加载'
  }

  onInterceptRequest(event: OnInterceptRequestEvent): WebResourceResponse {
    try {
      const request = event.request
      const url: string = request.getRequestUrl()
      const headers: Array<Header> = request.getRequestHeader()
      const referer: string = SnifferService.getHeader(headers, 'referer')
      const userAgent: string = SnifferService.getHeader(headers, 'user-agent') || SNIFFER_UA
      const contentType: string = SnifferService.guessContentType(url, '')
      const score: number = SnifferService.scoreUrl(url, contentType)
      if (this.sniffing && score >= 0) {
        const result: SniffResult = {
          url: url,
          type: SnifferService.classifyUrl(url, contentType),
          contentType: contentType,
          referer: referer.length > 0 ? referer : this.currentPageUrl,
          userAgent: userAgent,
          headers: SnifferService.normalizeHeaders(headers),
          score: score
        }
        this.results = SnifferService.mergeResult(this.results, result)
        this.statusText = `已发现 ${this.results.length} 个候选地址`
      }
    } catch (e) {
      // 监听失败不影响网页继续加载。
    }
    // 返回 null 表示不改写响应，让 ArkWeb 继续加载原资源。
    return null as never
  }

  onPageBegin(): void {
    this.loading = true
  }

  onPageEnd(): void {
    this.loading = false
    if (this.results.length === 0) {
      this.statusText = '网页已加载，暂未发现 m3u8/MP4；可点击网页播放按钮后继续等待'
    }
  }

  play(result: SniffResult): void {
    app.currentEpUrl = result.url
    app.currentEpName = result.type === 'hls' ? '嗅探 HLS' : result.type === 'mp4' ? '嗅探 MP4' : '嗅探视频'
    app.currentMode = 'sniff'
    app.currentSniffHeaders = result.headers
    app.currentSniffReferer = result.referer.length > 0 ? result.referer : this.currentPageUrl
    app.currentHistory = null
    app.pathStack.pushPathByName('Player', '')
  }

  goBack(): void {
    app.pathStack.pop()
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          Text('‹')
            .fontSize(30)
            .fontColor($r('app.color.theme_text_secondary'))
            .width(38)
            .textAlign(TextAlign.Center)
            .onClick(() => { this.goBack() })
          Text('网页嗅探')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.theme_text_title'))
            .layoutWeight(1)
          Text('清空')
            .fontSize(13)
            .fontColor($r('app.color.theme_accent'))
            .width(46)
            .textAlign(TextAlign.Center)
            .onClick(() => { this.clearResults() })
        }
        .width('100%')
        .height(52)
        .padding({ left: 4, right: 8 })
        .backgroundColor($r('app.color.theme_bar'))

        Column({ space: 10 }) {
          TextInput({ text: this.pageUrl, placeholder: '粘贴影视网页播放地址' })
            .width('100%')
            .height(44)
            .fontSize(14)
            .fontColor($r('app.color.theme_text_secondary'))
            .placeholderColor($r('app.color.theme_text_placeholder'))
            .backgroundColor($r('app.color.theme_surface'))
            .borderRadius(10)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => { this.pageUrl = value })
          Row({ space: 10 }) {
            Button(this.loading ? '加载中…' : '加载网页')
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .backgroundColor($r('app.color.theme_accent'))
              .fontColor('#FFFFFF')
              .borderRadius(9)
              .enabled(!this.loading)
              .onClick(() => { this.loadPage() })
            Button(this.sniffing ? '嗅探中' : '开始嗅探')
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .backgroundColor(this.sniffing ? $r('app.color.theme_accent_surface_alt') : $r('app.color.theme_surface_alt'))
              .fontColor($r('app.color.theme_text_accent'))
              .borderRadius(9)
              .onClick(() => { this.startSniff() })
          }
          Text(this.statusText)
            .fontSize(12)
            .fontColor($r('app.color.theme_text_hint'))
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 8 })

        if (this.webUrl.length > 0) {
          Web({ src: this.webUrl, controller: this.controller })
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .onControllerAttached(() => {
              this.controller.setCustomUserAgent(SNIFFER_UA)
            })
            .onInterceptRequest((event: OnInterceptRequestEvent): WebResourceResponse => this.onInterceptRequest(event))
            .onPageBegin(() => { this.onPageBegin() })
            .onPageEnd(() => { this.onPageEnd() })
            .width('100%')
            .height(300)
        } else {
          Column() {
            Text('网页预览区').fontSize(14).fontColor($r('app.color.theme_text_dim'))
            Text('加载页面后，在网页内点击播放，候选媒体地址会出现在下方').fontSize(12).fontColor($r('app.color.theme_text_placeholder')).margin({ top: 8 })
          }
          .width('100%')
          .height(150)
          .justifyContent(FlexAlign.Center)
        }

        Column() {
          Row() {
            Text('媒体候选').fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.theme_text_title'))
            Blank()
            Text(`${this.results.length}/${SnifferService.maxResults}`).fontSize(12).fontColor($r('app.color.theme_text_dim'))
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 8 })

          if (this.results.length === 0) {
            Text('暂未发现媒体地址')
              .fontSize(13)
              .fontColor($r('app.color.theme_text_dim'))
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 18, bottom: 24 })
          } else {
            List({ space: 8 }) {
              ForEach(this.results, (item: SniffResult) => {
                ListItem() {
                  Row({ space: 8 }) {
                    Column({ space: 4 }) {
                      Row({ space: 8 }) {
                        Text(this.typeName(item.type))
                          .fontSize(11)
                          .fontColor(item.type === 'hls' ? $r('app.color.theme_accent') : $r('app.color.theme_success'))
                        Text(item.contentType).fontSize(10).fontColor($r('app.color.theme_text_dim')).maxLines(1)
                      }
                      Text(item.url)
                        .fontSize(12)
                        .fontColor($r('app.color.theme_text_body'))
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                    Button('播放')
                      .height(34)
                      .fontSize(12)
                      .backgroundColor($r('app.color.theme_accent'))
                      .fontColor('#FFFFFF')
                      .borderRadius(8)
                      .onClick(() => { this.play(item) })
                  }
                  .width('100%')
                  .padding(10)
                  .backgroundColor($r('app.color.theme_surface'))
                  .borderRadius(10)
                }
              }, (item: SniffResult) => item.url)
            }
            .width('100%')
            .layoutWeight(1)
            .padding({ left: 12, right: 12, bottom: 14 })
            .scrollBar(BarState.Off)
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.theme_background'))
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.theme_background'))
  }

  private typeName(type: SniffMediaType): string {
    return type === 'hls' ? 'HLS' : type === 'mp4' ? 'MP4' : '视频'
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message })
    } catch (e) {
      // best effort
    }
  }
}
