// HostBridge.ets —— sendMessage 协议实现（对应 M0 结论的协议分发表）
// 职责：把 JS 扩展发来的 sendMessage(cmd, json) 请求翻译成鸿蒙能力调用，并返回 JSON 字符串结果。
//
// 协议表：
//   req           → @ohos.net.http（含 cookie jar、重定向跟随、四种响应类型）
//   toast         → @ohos.promptAction
//   getEnv/setEnv → @ohos.data.preferences（按 uzTag:key 隔离）
//   getStorage/setStorage → preferences
//   goToVerify / openWebToBindEnv → Web 组件（TODO，骨架未实现）
//
// 本文件已按 ArkTS 严格模式改写：不使用 any/unknown/Object 作为字段类型，对象字面量均对应显式 interface。

import { http } from '@kit.NetworkKit'
import { promptAction } from '@kit.ArkUI'
import { preferences } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'

/**
 * req 的 options（扩展传入，JSON.parse 后）。
 */
type HeaderValue = string | string[]
type HeaderRecord = Record<string, HeaderValue>

interface ReqOptions {
  method?: string
  headers?: HeaderRecord
  data?: string
  responseType?: string
  maxRedirects?: number
  sendTimeout?: number
  receiveTimeout?: number
  queryParameters?: Record<string, string>
}

/**
 * sendMessage 的 payload（不同 cmd 字段不同，全部可选）。
 */
interface MsgPayload {
  url?: string
  ua?: string
  options?: ReqOptions
  msg?: string
  duration?: number
  type?: string
  uzTag?: string
  key?: string
  value?: string
  summary?: string
}

/**
 * 重定向记录。
 */
interface RedirectInfo {
  url: string
  code: number
}

/**
 * req 返回的 ProData 结构（与 uzUtils.js 的 ProData 字段一致）。
 */
interface ProData {
  error: string
  data: string | number[] | null
  headers: Record<string, string>
  code: number
  redirects: RedirectInfo[]
}

const COOKIE_JAR_KEY = 'cookieJar'

export class HostBridge {
  private store: preferences.Preferences | null = null
  // 当前扩展 tag：扩展传来的 uzTag 不可信，宿主用它隔离 env/storage/cookie。
  activeUzTag: string = ''
  // cookie jar：uzTag|host -> cookie 字符串（内存 + preferences 持久化，按扩展隔离）
  private cookieJar: Map<string, string> = new Map()
  // goToVerify / openWebToBindEnv 回调：AppState.init 注册，收到后打开 Verify 页
  onVerifyRequest: ((url: string, ua: string, title: string) => void) | null = null

  async init(context: common.Context): Promise<void> {
    this.store = await preferences.getPreferences(context, 'uz_host')
    // 恢复上次会话保存的 cookie
    const saved = await this.store.get(COOKIE_JAR_KEY, '') as string
    if (saved.length > 0) {
      try {
        const obj = JSON.parse(saved) as Record<string, string>
        this.cookieJar = new Map(Object.entries(obj))
      } catch (e) {
        this.cookieJar = new Map()
      }
    }
  }

  /**
   * 处理 sendMessage 请求，返回 JSON 字符串（空值返回 '""'）。
   */
  async handleRequest(cmd: string, json: string): Promise<string> {
    let payload: MsgPayload
    if (json.length > 0) {
      payload = JSON.parse(json) as MsgPayload
    } else {
      payload = {} as MsgPayload
    }

    switch (cmd) {
      case 'req':
        return this.handleReq(payload)
      case 'toast':
        this.handleToast(payload)
        return '""'
      case 'getEnv':
        return JSON.stringify(await this.storeGet(`${this.activeUzTag}:${payload.key ?? ''}`))
      case 'setEnv':
        await this.storePut(`${this.activeUzTag}:${payload.key ?? ''}`, `${payload.value ?? ''}`)
        return '""'
      case 'getStorage':
        return JSON.stringify(await this.storeGet(this.extStorageKey(payload.key ?? '')))
      case 'setStorage':
        await this.storePut(this.extStorageKey(payload.key ?? ''), `${payload.value ?? ''}`)
        return '""'
      case 'goToVerify': {
        const url = payload.url ?? ''
        const ua = payload.ua ?? ''
        if (url.length > 0 && this.onVerifyRequest) {
          this.onVerifyRequest(url, ua, '完成验证')
        }
        return '""'
      }
      case 'openWebToBindEnv': {
        const url = payload.url ?? ''
        const ua = payload.ua ?? ''
        const tips = payload.summary ?? ''
        if (url.length > 0 && this.onVerifyRequest) {
          this.onVerifyRequest(url, ua, tips.length > 0 ? tips : '登录/绑定')
        }
        return '""'
      }
      case 'debugLog':
        return '""'
      default:
        return '""'
    }
  }

  // ---------------- req 实现（含重定向跟随 + cookie jar + 响应类型映射） ----------------
  private async handleReq(payload: MsgPayload): Promise<string> {
    const url: string = this.withQuery(payload.url ?? '', payload.options?.queryParameters)
    const options: ReqOptions = payload.options ?? {} as ReqOptions
    const method: http.RequestMethod = this.toMethod(options.method)
    const respType: string = options.responseType ?? ''
    const expectDataType: http.HttpDataType =
      (respType === 'arraybuffer' || respType === 'bytes') ? http.HttpDataType.ARRAY_BUFFER : http.HttpDataType.STRING
    // fetch 默认会跟随重定向；这里同样给一个合理默认值。
    const maxRedirects: number = options.maxRedirects ?? 5
    const sendTimeout: number = options.sendTimeout ?? 30000
    const receiveTimeout: number = options.receiveTimeout ?? 30000

    const proData: ProData = {
      error: '',
      data: null,
      headers: {} as Record<string, string>,
      code: 500,
      redirects: [] as RedirectInfo[]
    }
    let currentUrl = url
    const request = http.createHttp()

    try {
      for (let hop = 0; hop <= maxRedirects; hop++) {
        const header: Record<string, string> = this.normalizeHeaders(options.headers ?? {} as HeaderRecord)
        const host = this.hostOf(currentUrl)
        const cookie = this.cookieJar.get(this.cookieKey(host))
        if (cookie) {
          header['Cookie'] = cookie
        }
        if (options.data !== undefined && options.data !== null && method !== http.RequestMethod.GET
          && header['Content-Type'] === undefined) {
          header['Content-Type'] = 'application/json'
        }

        const httpOptions: http.HttpRequestOptions = {
          method: method,
          header: header,
          expectDataType: expectDataType,
          connectTimeout: sendTimeout,
          readTimeout: receiveTimeout
        }
        if (options.data !== undefined && options.data !== null && method !== http.RequestMethod.GET) {
          httpOptions.extraData = options.data
        }

        const resp = await request.request(currentUrl, httpOptions)
        proData.code = resp.responseCode
        const respHeaders: Record<string, string> = this.normalizeHeaders(resp.header as HeaderRecord)
        proData.headers = respHeaders

        const setCookie: string = respHeaders['set-cookie'] ?? respHeaders['Set-Cookie'] ?? ''
        if (setCookie.length > 0) {
          this.cookieJar.set(this.cookieKey(host), setCookie)
          await this.saveCookieJar()
        }

        const isRedirect: boolean = proData.code >= 300 && proData.code < 400
        const location: string = respHeaders['location'] ?? respHeaders['Location'] ?? ''
        if (isRedirect && location.length > 0 && hop < maxRedirects) {
          const ri: RedirectInfo = { url: currentUrl, code: proData.code }
          proData.redirects.push(ri)
          currentUrl = this.resolveUrl(currentUrl, location)
          continue
        }

        if (expectDataType === http.HttpDataType.ARRAY_BUFFER) {
          proData.data = this.arrayBufferToNumberArray(resp.result as ArrayBuffer)
        } else {
          proData.data = resp.result as string
        }
        break
      }
    } catch (e) {
      proData.error = `${(e as Error).message ?? ''}`
      proData.code = 500
    } finally {
      request.destroy()
    }

    return JSON.stringify(proData)
  }

  // ---------------- toast 实现 ----------------
  private handleToast(payload: MsgPayload): void {
    const msg = payload.msg ?? ''
    const duration = payload.duration ?? 2
    try {
      promptAction.openToast({ message: msg, duration: duration * 1000 }).catch(() => {})
    } catch (e) {
      // toast 是尽力而为的 UI 反馈，失败不应中断扩展请求。
    }
  }

  setActiveUzTag(tag: string, adoptLegacyCookies: boolean = false): void {
    if (tag === this.activeUzTag && !adoptLegacyCookies) return
    this.activeUzTag = tag
    if (adoptLegacyCookies) {
      // 兼容旧版全局 cookie jar：只在首次进入内置源时迁移，避免泄露给自定义源。
      const oldKeys: string[] = []
      this.cookieJar.forEach((v, k) => { if (k.indexOf('|') < 0) oldKeys.push(k) })
      for (const k of oldKeys) {
        const nk = this.cookieKey(k)
        if (!this.cookieJar.has(nk)) this.cookieJar.set(nk, this.cookieJar.get(k) ?? '')
        this.cookieJar.delete(k)
      }
      if (oldKeys.length > 0) {
        this.saveCookieJar().catch(() => {})
      }
    }
  }

  private cookieKey(host: string): string {
    return `${this.activeUzTag}|${host}`
  }

  private extStorageKey(key: string): string {
    return `ext:${this.activeUzTag}:${key}`
  }

  private toMethod(method?: string): http.RequestMethod {
    switch ((method ?? 'GET').toUpperCase()) {
      case 'POST': return http.RequestMethod.POST
      case 'PUT': return http.RequestMethod.PUT
      case 'DELETE': return http.RequestMethod.DELETE
      case 'HEAD': return http.RequestMethod.HEAD
      default: return http.RequestMethod.GET
    }
  }

  private normalizeHeaders(headers: HeaderRecord): Record<string, string> {
    const out: Record<string, string> = {} as Record<string, string>
    const keys = Object.keys(headers)
    for (const k of keys) {
      const v: HeaderValue = headers[k]
      out[k] = Array.isArray(v) ? v.join('; ') : v
    }
    return out
  }

  private withQuery(url: string, params?: Record<string, string>): string {
    if (!params) return url
    const keys = Object.keys(params)
    if (keys.length === 0) return url
    const query: string = keys.map((k: string) =>
      `${encodeURIComponent(k)}=${encodeURIComponent(params[k] ?? '')}`).join('&')
    return url + (url.indexOf('?') >= 0 ? '&' : '?') + query
  }

  // ---------------- 存储 ----------------
  private async storeGet(key: string): Promise<string> {
    if (!this.store) return ''
    const v = await this.store.get(key, '') as string
    return v
  }

  private async storePut(key: string, value: string): Promise<void> {
    if (!this.store) return
    await this.store.put(key, value)
    await this.store.flush()
  }

  // 供设置页直接读写扩展环境变量（key 形如 "catpaw.pansou.vod:夸克Cookie"）
  async getEnvValue(uzTag: string, key: string): Promise<string> {
    return await this.storeGet(`${uzTag}:${key}`)
  }

  async setEnvValue(uzTag: string, key: string, value: string): Promise<void> {
    await this.storePut(`${uzTag}:${key}`, value)
  }

  // 通用键值读写（历史/收藏等壳自身数据用）
  async getRaw(key: string): Promise<string> {
    return await this.storeGet(key)
  }

  async setRaw(key: string, value: string): Promise<void> {
    await this.storePut(key, value)
  }

  // Verify 页完成后回写：把 Web 侧 cookie 并入 jar（同 host 按键去重合并），并持久化
  async importWebCookie(url: string, cookie: string): Promise<void> {
    const host = this.hostOf(url)
    if (host.length === 0 || cookie.trim().length === 0) return
    const key = this.cookieKey(host)
    const exist = this.cookieJar.get(key) ?? ''
    this.cookieJar.set(key, this.mergeCookie(exist, cookie.trim()))
    await this.saveCookieJar()
  }

  private mergeCookie(a: string, b: string): string {
    if (a.length === 0) return b
    if (b.length === 0) return a
    const map: Map<string, string> = new Map()
    const putAll = (s: string): void => {
      const parts = s.split(';')
      for (const p of parts) {
        const kv = p.trim()
        const eq = kv.indexOf('=')
        if (eq > 0) map.set(kv.slice(0, eq).trim(), kv)
      }
    }
    putAll(a)
    putAll(b)
    const out: string[] = []
    map.forEach((v) => { out.push(v) })
    return out.join('; ')
  }

  private async saveCookieJar(): Promise<void> {
    if (!this.store) return
    const obj: Record<string, string> = {} as Record<string, string>
    this.cookieJar.forEach((v, k) => { obj[k] = v })
    await this.store.put(COOKIE_JAR_KEY, JSON.stringify(obj))
    await this.store.flush()
  }

  // ---------------- 工具 ----------------
  private hostOf(url: string): string {
    const m = url.match(/^https?:\/\/([^\/:]+)/)
    return m ? m[1] : ''
  }

  private resolveUrl(base: string, loc: string): string {
    if (loc.startsWith('http://') || loc.startsWith('https://')) return loc
    if (loc.startsWith('/')) {
      const m = base.match(/^(https?:\/\/[^\/]+)/)
      return m ? m[1] + loc : loc
    }
    const withoutQuery = base.split('?')[0]
    const slash = withoutQuery.lastIndexOf('/')
    return slash >= 0 ? withoutQuery.slice(0, slash + 1) + loc : loc
  }

  private arrayBufferToNumberArray(buf: ArrayBuffer): number[] {
    const arr = new Uint8Array(buf)
    const out: number[] = []
    for (let i = 0; i < arr.length; i++) {
      out.push(arr[i])
    }
    return out
  }
}
