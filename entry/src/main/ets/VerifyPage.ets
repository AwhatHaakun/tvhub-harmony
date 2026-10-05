// VerifyPage.ets —— Web 验证页：扩展 goToVerify / openWebToBindEnv 时打开
// 用途：部分源要求人机验证或网页登录，扩展会 await goToVerify，宿主在此打开
// 对应网页，用户完成验证/登录后点「完成」，把 Web 侧 cookie 回写进宿主 cookie jar，
// 扩展随后重试请求即带上了验证后的 cookie。
//
// 数据流：HostBridge.onVerifyRequest → AppState.verify* 置位 + onVerifyNeeded
//        → 当前页 push 'Verify' → 本页 Web 加载 verifyUrl（带 UA）→ 用户操作
//        → 点「完成」→ WebCookieManager.fetchCookie → host.importWebCookie → pop

import { webview } from '@kit.ArkWeb'
import { app } from './AppState'

@Component
export struct VerifyPage {
  @State url: string = ''
  @State ua: string = ''
  @State title: string = '完成验证'
  @State saving: boolean = false

  private controller: webview.WebviewController = new webview.WebviewController()

  aboutToAppear(): void {
    this.url = app.verifyUrl
    this.ua = app.verifyUa
    if (app.verifyTitle.length > 0) {
      this.title = app.verifyTitle
    }
  }

  // 完成：抓 Web cookie 回写宿主 jar，清位并返回
  async finish(): Promise<void> {
    if (this.saving) return
    this.saving = true
    try {
      const cookie = await webview.WebCookieManager.fetchCookie(this.url)
      if (cookie && cookie.length > 0) {
        await app.host.importWebCookie(this.url, cookie)
      }
    } catch (e) {
      // 抓 cookie 失败不阻塞返回（有些验证不写 cookie，只靠页面状态）
    }
    app.verifyPending = false
    app.pathStack.pop()
  }

  cancel(): void {
    app.verifyPending = false
    app.pathStack.pop()
  }

  build() {
    // 必须以 NavDestination 为根：Navigation 压栈页面缺它会黑屏
    NavDestination() {
      Column() {
        // 顶栏：关闭 + 标题 + 完成
        Row() {
          Text('✕')
            .fontSize(20)
            .fontColor($r('app.color.theme_text_secondary'))
            .width(40)
            .textAlign(TextAlign.Center)
            .onClick(() => { this.cancel() })
          Text(this.title)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.theme_text_title'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(this.saving ? '保存中…' : '完成')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.theme_accent'))
            .width(64)
            .textAlign(TextAlign.Center)
            .onClick(() => { this.finish() })
        }
        .width('100%')
        .height(52)
        .padding({ left: 4, right: 8 })
        .backgroundColor($r('app.color.theme_bar'))

        // 提示条
        Text('在下方完成验证/登录后，点右上角「完成」')
          .fontSize(12)
          .fontColor($r('app.color.theme_text_hint'))
          .width('100%')
          .padding({ left: 16, top: 6, bottom: 6 })
          .backgroundColor($r('app.color.theme_bar'))

        // Web 区（ua 为空时用桌面 Safari UA，与 uzUtils 默认一致）
        // UA 在 onControllerAttached 里通过 controller 设置（此时 src 尚未加载，设置生效）
        Web({ src: this.url, controller: this.controller })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .onControllerAttached(() => {
            this.controller.setCustomUserAgent(this.ua.length > 0 ? this.ua
              : 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0.1 Safari/605.1.15')
          })
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
}
