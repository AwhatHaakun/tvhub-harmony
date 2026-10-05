// AppState.ets —— 全局单例：引擎生命周期 + 数据模型 + 业务方法 + 导航栈
// 页面组件通过 app.xxx() 调扩展方法，数据自己 @State 保存并渲染。

import { application, common, ConfigurationConstant } from '@kit.AbilityKit'
import { http } from '@kit.NetworkKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { JSExecutor } from './JSExecutor'
import { HostBridge } from './HostBridge'
import { RawFileLoader } from './RawFileLoader'
import { ExtensionLoader } from './ExtensionLoader'
import { SearchVodItem } from './model/TvModels'
import { CONFIG } from './common/constants/Config'
import { ThemeService, ThemeColor } from './services/ThemeService'
import { DownloadService } from './services/DownloadService'

// ============================ 数据模型（对应扩展返回的 JSON 结构） ============================
export interface VideoClass {
  type_id: string
  type_name: string
  hasSubclass: boolean
}

export interface VideoItem {
  vod_id: string
  vod_name: string
  vod_pic: string
  vod_remarks: string
  vod_year: string
  mode?: string
  // tvbox 定向站点（收藏回看时直接到原站点取详情，避免换源后 vod_id 失配）
  siteApi?: string
  siteReferer?: string
  siteName?: string
}

export interface VideoDetailInfo {
  vod_id: string
  vod_name: string
  type_name: string
  vod_pic: string
  vod_play_from: string
  vod_play_url: string
  vod_content: string
}

export interface PlayUrl {
  name: string
  url: string
  headers?: Record<string, string>
}

export interface Episode {
  name: string
  url: string
}

// 一条播放线路：线路名 + 该线路下的选集
export interface PlayLine {
  name: string
  episodes: Episode[]
}

// 历史记录条目
export interface HistoryItem {
  vod_id: string
  vod_name: string
  vod_pic: string
  vod_remarks: string
  vod_year?: string
  time: number
  // 来源模式：'tvbox' | 'uz'（旧数据缺失时默认 tvbox，详情页会自动回退）
  mode?: string
  // tvbox 定向站点（历史回看时直接到原站点取详情）
  siteApi?: string
  siteReferer?: string
  siteName?: string
  // 断点续播
  lastPlayMs?: number  // 上次播放位置（毫秒）
  episodeUrl?: string  // 上次播放集数 URL
}

// 扩展源（内置 = rawfile 里的猫爪盘搜；自定义 = 从 URL 下载存沙箱）
export interface SourceItem {
  key: string
  name: string
  url: string
  builtin: boolean
}

export type ThemeMode = 'system' | 'light' | 'dark'

// 扩展返回的响应包装
interface ClassListResp { error: string; data: VideoClass[] }
interface VideoListResp { error: string; data: VideoItem[]; total: number }
interface DetailResp { error: string; data: VideoDetailInfo }
interface PlayUrlResp { error: string; urls: PlayUrl[] }

interface SourceRequestInfo {
  cleanUrl: string
  codeUrl: string
  authorization: string
  expectedMd5: string
}

interface SourceDownloadResult {
  code: string
  info: SourceRequestInfo
}

// 盘搜扩展文件名（位于 rawfile/uzcore/ 下）
const EXT_FILE = 'CatPaw_PanSou.js'
// 扩展的 uzTag（与 CatPaw_PanSou.js 里 UZTAG 一致），用于 env 读写隔离
const EXT_UZTAG = 'catpaw.pansou.vod'
const BUILTIN_SOURCE_KEY = 'builtin_catpaw'
const BUILTIN_SOURCE_NAME = '猫爪盘搜'
const EXT_DIR = 'extensions'
const SOURCES_KEY = CONFIG.KEYS.SOURCES
const ACTIVE_SOURCE_KEY = CONFIG.KEYS.ACTIVE_SOURCE

export class AppState {
  readonly executor: JSExecutor = new JSExecutor()
  readonly host: HostBridge = new HostBridge()
  // 导航栈（Navigation 用）
  readonly pathStack: NavPathStack = new NavPathStack()
  initialized: boolean = false
  themeMode: ThemeMode = 'system'
  // 数据变更多监听器（what：'history' | 'favorite' | 'source'，各 Tab 页按需订阅）
  private dataListeners: Set<(what: string) => void> = new Set()
  private initPromise: Promise<void> | null = null
  // 应用上下文（源下载/文件存储用）
  ctx: common.Context | null = null
  // 源列表 + 当前活动源
  sources: SourceItem[] = []
  activeSourceKey: string = BUILTIN_SOURCE_KEY
  // 当前扩展的 uzTag：宿主用它隔离扩展 env/storage，避免扩展伪造 uzTag 读取别的源
  activeUzTag: string = EXT_UZTAG
  // 服务
  readonly themeService: ThemeService = new ThemeService(this.host)
  readonly downloadService: DownloadService = new DownloadService(this.host)
  currentThemeColor: ThemeColor | null = null

  // ---- 跨页面传递的导航参数（非响应式，页面 aboutToAppear 时读取） ----
  currentKind: string = 'all'
  currentKindName: string = '全部'
  currentSearchWord: string = ''
  currentVideoId: string = ''
  // 跨页导航数据来源模式：'tvbox'（接口适配器）| 'uz'（脚本扩展）| 'sniff'（网页嗅探）
  currentMode: string = 'tvbox'
  // tvbox 定向站点（历史/收藏/聚合结果点开时设置；空 = 用 tvbox.activeSite）
  currentSiteApi: string = ''
  currentSiteReferer: string = ''
  currentSiteName: string = ''
  // 聚合搜索结果组（同名片名的多站点命中；非空时详情页并发聚合各站线路）
  currentAggGroup: SearchVodItem[] = []
  currentDetail: VideoDetailInfo | null = null
  currentEpUrl: string = ''
  currentEpName: string = ''
  // 网页嗅探播放一次性传递的媒体请求头
  currentSniffHeaders: Record<string, string> = {}
  currentSniffReferer: string = ''
  // 详情页生成、播放页真正开始播放后写入的历史条目
  currentHistory: HistoryItem | null = null

  // ---- goToVerify / openWebToBindEnv（扩展要宿主开 Web 验证时触发） ----
  // HostBridge 收到后置位并（可选）触发 onVerifyNeeded 回调，VerifyPage 消费
  verifyUrl: string = ''
  verifyUa: string = ''
  verifyTitle: string = ''
  verifyPending: boolean = false
  onVerifyNeeded: (() => void) | null = null

  async init(ctx: common.Context): Promise<void> {
    if (this.initPromise) return this.initPromise
    const promise = this.doInit(ctx)
    this.initPromise = promise
    try {
      await promise
    } catch (e) {
      this.initPromise = null
      throw new Error((e as Error).message ?? String(e))
    }
  }

  private async doInit(ctx: common.Context): Promise<void> {
    if (this.initialized) return
    this.ctx = ctx
    await this.host.init(ctx)

    // 加载主题模式
    const savedTheme: string = await this.host.getRaw(CONFIG.KEYS.THEME_MODE) ?? ''
    if (savedTheme === 'light' || savedTheme === 'dark' || savedTheme === 'system') {
      this.themeMode = savedTheme as ThemeMode
    }
    this.applyThemeMode()

    // 加载主题色
    this.currentThemeColor = await this.themeService.getCurrentColor()

    // 初始化下载服务
    await this.downloadService.init(ctx)

    // 扩展要求开 Web 验证时：置位 + 通知当前页面 push Verify 页
    this.host.onVerifyRequest = (url: string, ua: string, title: string): void => {
      this.verifyUrl = url
      this.verifyUa = ua
      this.verifyTitle = title
      this.verifyPending = true
      if (this.onVerifyNeeded) {
        this.onVerifyNeeded()
      }
    }
    this.executor.init(this.host)
    await this.loadSources()
    const code = await this.getActiveExtensionCode()
    this.activeUzTag = this.detectExtensionTag(code, this.activeSourceKey)
    this.host.setActiveUzTag(this.activeUzTag, this.activeSourceKey === BUILTIN_SOURCE_KEY)
    const bundle = await RawFileLoader.buildBundleWithExt(ctx, code)
    this.executor.load(bundle)
    this.initialized = true
  }

  dispose(): void {
    if (this.initialized) {
      this.executor.dispose()
      this.initialized = false
    }
    this.initPromise = null
  }

  // ---- 业务方法（每个返回强类型数据，出错抛 Error） ----
  async loadClasses(): Promise<VideoClass[]> {
    const r = await this.executor.call('getClassList', '{}')
    const resp = JSON.parse(r) as ClassListResp
    if (resp.error) throw new Error(resp.error)
    return resp.data ?? []
  }

  async search(word: string, kind: string): Promise<VideoItem[]> {
    const args = JSON.stringify({
      searchWord: word,
      searchPgPage: 1,
      searchPg: kind,
      url: kind === 'all' ? '' : kind,
    })
    const r = await this.executor.call('searchVideo', args)
    const resp = JSON.parse(r) as VideoListResp
    if (resp.error) throw new Error(resp.error)
    return resp.data ?? []
  }

  // 首页内容流：按分类拉视频列表（uz getVideoList）。搜索型源（猫爪）会抛错，首页据此显示引导占位
  async videoList(typeId: string, page: number): Promise<VideoItem[]> {
    const args = JSON.stringify({ url: typeId, page: page })
    const r = await this.executor.call('getVideoList', args)
    const resp = JSON.parse(r) as VideoListResp
    if (resp.error) throw new Error(resp.error)
    return resp.data ?? []
  }

  async detail(vodId: string): Promise<VideoDetailInfo> {
    const r = await this.executor.call('getVideoDetail', JSON.stringify({ url: vodId }))
    const resp = JSON.parse(r) as DetailResp
    if (resp.error) throw new Error(resp.error)
    return resp.data
  }

  async playUrl(epUrl: string): Promise<PlayUrl[]> {
    const r = await this.executor.call('getVideoPlayUrl', JSON.stringify({ url: epUrl }))
    const resp = JSON.parse(r) as PlayUrlResp
    if (resp.error) throw new Error(resp.error)
    return resp.urls ?? []
  }

  async setThemeMode(mode: ThemeMode): Promise<void> {
    if (mode !== 'light' && mode !== 'dark' && mode !== 'system') return
    this.themeMode = mode
    this.applyThemeMode()
    await this.host.setRaw(CONFIG.KEYS.THEME_MODE, mode)
  }

  async setThemeColor(color: ThemeColor): Promise<void> {
    this.currentThemeColor = color
    await this.themeService.setCurrentColor(color)
    this.notifyChanged('theme')
  }

  private applyThemeMode(): void {
    try {
      const mode: ConfigurationConstant.ColorMode = this.themeMode === 'dark'
        ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        : this.themeMode === 'light'
          ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
          : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
      application.getApplicationContext().setColorMode(mode)
    } catch (e) {
      // 主题切换失败不影响播放和源加载。
    }
  }

  // ---- 环境变量读写（设置页用，写入 preferences 供扩展 getEnv 读取） ----
  async getEnvValue(key: string): Promise<string> {
    return await this.host.getEnvValue(this.activeUzTag, key)
  }

  async setEnvValue(key: string, value: string): Promise<void> {
    await this.host.setEnvValue(this.activeUzTag, key, value)
  }

  // ---- 历史记录 ----
  async loadHistory(): Promise<HistoryItem[]> {
    const raw = await this.host.getRaw(CONFIG.KEYS.HISTORY)
    if (!raw) return []
    try {
      const arr = JSON.parse(raw) as HistoryItem[]
      return arr ?? []
    } catch (e) {
      return []
    }
  }

  async addHistory(item: HistoryItem): Promise<void> {
    const list = await this.loadHistory()
    const itemKey = AppState.contentKey(item.mode ?? 'tvbox', item.siteApi ?? '', item.vod_id)
    const filtered = list.filter((h: HistoryItem) => AppState.contentKey(h.mode ?? 'tvbox', h.siteApi ?? '', h.vod_id) !== itemKey)
    filtered.unshift(item)
    await this.host.setRaw(CONFIG.KEYS.HISTORY, JSON.stringify(filtered.slice(0, CONFIG.HISTORY_MAX)))
    this.notifyChanged('history')
  }

  async clearHistory(): Promise<void> {
    await this.host.setRaw(CONFIG.KEYS.HISTORY, '[]')
    this.notifyChanged('history')
  }

  // ---- 收藏 ----
  async loadFavorites(): Promise<VideoItem[]> {
    const raw = await this.host.getRaw(CONFIG.KEYS.FAVORITE)
    if (!raw) return []
    try {
      const arr = JSON.parse(raw) as VideoItem[]
      return arr ?? []
    } catch (e) {
      return []
    }
  }

  async toggleFavorite(item: VideoItem): Promise<boolean> {
    const list = await this.loadFavorites()
    const itemKey = AppState.contentKey(item.mode ?? 'tvbox', item.siteApi ?? '', item.vod_id)
    const idx = list.findIndex((f: VideoItem) => AppState.contentKey(f.mode ?? 'tvbox', f.siteApi ?? '', f.vod_id) === itemKey)
    if (idx >= 0) {
      list.splice(idx, 1)
      await this.host.setRaw(CONFIG.KEYS.FAVORITE, JSON.stringify(list))
      this.notifyChanged('favorite')
      return false
    } else {
      list.unshift(item)
      await this.host.setRaw(CONFIG.KEYS.FAVORITE, JSON.stringify(list))
      this.notifyChanged('favorite')
      return true
    }
  }

  async isFavorite(item: VideoItem): Promise<boolean> {
    const list = await this.loadFavorites()
    const key = AppState.contentKey(item.mode ?? 'tvbox', item.siteApi ?? '', item.vod_id)
    return list.some((f: VideoItem) => AppState.contentKey(f.mode ?? 'tvbox', f.siteApi ?? '', f.vod_id) === key)
  }

  addDataListener(fn: (what: string) => void): void {
    this.dataListeners.add(fn)
  }

  removeDataListener(fn: (what: string) => void): void {
    this.dataListeners.delete(fn)
  }

  notifyChanged(what: string): void {
    this.dataListeners.forEach((fn) => { fn(what) })
  }

  // ---- 源管理（M4 扩展订阅/多源） ----

  async loadSources(): Promise<SourceItem[]> {
    const raw = await this.host.getRaw(CONFIG.KEYS.SOURCES)
    let list: SourceItem[] = []
    if (raw) {
      try {
        list = JSON.parse(raw) as SourceItem[]
      } catch (e) {
        list = []
      }
    }
    // 确保内置源在列表首位
    const hasBuiltin = list.some((s: SourceItem) => s.key === BUILTIN_SOURCE_KEY)
    if (!hasBuiltin) {
      list.unshift({ key: BUILTIN_SOURCE_KEY, name: BUILTIN_SOURCE_NAME, url: '', builtin: true } as SourceItem)
    }
    this.sources = list
    // 读活动源，非法则回退内置
    const active = await this.host.getRaw(CONFIG.KEYS.ACTIVE_SOURCE)
    if (active && list.some((s: SourceItem) => s.key === active)) {
      this.activeSourceKey = active
    } else {
      this.activeSourceKey = BUILTIN_SOURCE_KEY
    }
    return list
  }

  // 下载明文扩展 .js 或校验地址 .js.md5，支持 URL 内嵌 Basic Auth。
  async addSourceFromUrl(url: string, name: string): Promise<void> {
    const source = await this.downloadExtension(url)
    this.validateExtension(source.code)
    const key = 'custom_' + Date.now().toString()
    await this.saveExtFile(key, source.code)
    // 不把 URL 中的用户名/密码存进配置或设置页展示；源码已落地到沙箱，不影响切换使用。
    const item: SourceItem = {
      key,
      name: (name && name.trim()) ? name.trim() : '自定义源',
      url: source.info.cleanUrl,
      builtin: false
    }
    const list = await this.loadSources()
    list.push(item)
    await this.host.setRaw(SOURCES_KEY, JSON.stringify(list))
    this.sources = list
  }

  // 扩展格式校验：拒绝加密扩展与爬虫壳 JSON 源，避免加载后一片空白
  private validateExtension(code: string): void {
    if (code.length === 0) {
      throw new Error('下载内容为空')
    }
    const trimmed = code.trim()
    // 1) JSON 源（TVBox / 王二小等爬虫壳）：以 { 或 [ 开头即判定为 JSON 配置
    //    （TVBox JSON 源一定以 { 或 [ 开头；明文脚本扩展以函数/变量声明开头）
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      throw new Error('这是 JSON 源（TVBox/爬虫壳格式），请在「配置」页面添加')
    }
    // 2) 加密扩展（//@codeID: 元数据）
    if (ExtensionLoader.isEncrypted(code)) {
      throw new Error('加密扩展无法在鸿蒙运行，请使用明文扩展')
    }
    // 3) 简单 JS 检查：必须包含扩展方法定义
    if (code.indexOf('getClassList') < 0 && code.indexOf('getVideoList') < 0) {
      throw new Error('不是有效的脚本扩展（缺少 getClassList/getVideoList 方法）')
    }
  }

  async removeSource(key: string): Promise<void> {
    if (key === BUILTIN_SOURCE_KEY) return
    const list = await this.loadSources()
    const filtered = list.filter((s: SourceItem) => s.key !== key)
    await this.host.setRaw(SOURCES_KEY, JSON.stringify(filtered))
    this.sources = filtered
    try { fs.unlinkSync(this.extFilePath(key)) } catch (e) {}
    // 删除的是活动源则切回内置
    if (this.activeSourceKey === key) {
      await this.setActiveSource(BUILTIN_SOURCE_KEY)
    }
  }

  async setActiveSource(key: string): Promise<void> {
    this.activeSourceKey = key
    await this.host.setRaw(ACTIVE_SOURCE_KEY, key)
    await this.reloadActive()
    this.notifyChanged('source')
  }

  // 当前活动源名（首页顶部显示）
  activeSourceName(): string {
    const s = this.sources.find((x: SourceItem) => x.key === this.activeSourceKey)
    return s ? s.name : ''
  }

  // 重新加载当前活动源（dispose → re-init → load 新 bundle）
  async reloadActive(): Promise<void> {
    const ctx = this.ctx
    if (!ctx) return
    const code = await this.getActiveExtensionCode()
    this.activeUzTag = this.detectExtensionTag(code, this.activeSourceKey)
    this.host.setActiveUzTag(this.activeUzTag, this.activeSourceKey === BUILTIN_SOURCE_KEY)
    this.executor.dispose()
    this.executor.init(this.host)
    const bundle = await RawFileLoader.buildBundleWithExt(ctx, code)
    this.executor.load(bundle)
  }

  // ---- 源管理内部工具 ----

  private async getActiveExtensionCode(): Promise<string> {
    const ctx = this.ctx
    if (!ctx) return ''
    if (this.activeSourceKey === BUILTIN_SOURCE_KEY) {
      const rm = ctx.resourceManager
      const decoder = util.TextDecoder.create('utf-8')
      const data = await rm.getRawFileContent('uzcore/' + EXT_FILE)
      return decoder.decodeToString(new Uint8Array(data))
    }
    try {
      return await this.readExtFile(this.activeSourceKey)
    } catch (e) {
      // 自定义源文件丢失时不让应用启动失败，回退内置源。
      this.activeSourceKey = BUILTIN_SOURCE_KEY
      await this.host.setRaw(ACTIVE_SOURCE_KEY, BUILTIN_SOURCE_KEY)
      const rm = ctx.resourceManager
      const decoder = util.TextDecoder.create('utf-8')
      const data = await rm.getRawFileContent('uzcore/' + EXT_FILE)
      return decoder.decodeToString(new Uint8Array(data))
    }
  }

  private detectExtensionTag(code: string, fallback: string): string {
    const match = code.match(/UZTAG\s*=\s*['\"]([^'\"]+)['\"]/)
    return match && match[1] ? match[1] : fallback
  }

  private async downloadExtension(inputUrl: string): Promise<SourceDownloadResult> {
    const info = this.parseSourceUrl(inputUrl)
    let expectedMd5: string = ''
    if (info.expectedMd5.length > 0) {
      const checksumText = await this.downloadText(info.cleanUrl, info.authorization)
      expectedMd5 = this.readMd5(checksumText)
    }

    const bytes = await this.downloadBytes(info.codeUrl, info.authorization)
    if (expectedMd5.length > 0) {
      const actualMd5 = await this.md5Hex(bytes)
      if (actualMd5 !== expectedMd5) {
        throw new Error('源文件 MD5 校验失败')
      }
    }

    const decoder = util.TextDecoder.create('utf-8')
    const code: string = decoder.decodeToString(bytes)
    const result: SourceDownloadResult = { code: code, info: info }
    return result
  }

  private parseSourceUrl(inputUrl: string): SourceRequestInfo {
    const input: string = inputUrl.trim()
    if (!input.startsWith('http://') && !input.startsWith('https://')) {
      throw new Error('源地址必须以 http:// 或 https:// 开头')
    }

    const schemeEnd: number = input.indexOf('://')
    const authorityStart: number = schemeEnd + 3
    let authorityEnd: number = input.length
    const slash: number = input.indexOf('/', authorityStart)
    const question: number = input.indexOf('?', authorityStart)
    const hash: number = input.indexOf('#', authorityStart)
    if (slash >= 0 && slash < authorityEnd) authorityEnd = slash
    if (question >= 0 && question < authorityEnd) authorityEnd = question
    if (hash >= 0 && hash < authorityEnd) authorityEnd = hash

    let cleanUrl: string = input
    let authorization: string = ''
    const at: number = input.lastIndexOf('@', authorityEnd)
    if (at > authorityStart) {
      const userInfo: string = input.slice(authorityStart, at)
      const colon: number = userInfo.indexOf(':')
      const rawUser: string = colon >= 0 ? userInfo.slice(0, colon) : userInfo
      const rawPassword: string = colon >= 0 ? userInfo.slice(colon + 1) : ''
      if (rawUser.length === 0 || colon < 0) {
        throw new Error('源地址认证信息格式无效，应为 用户名:密码@域名')
      }
      const username: string = this.decodeUserInfo(rawUser)
      const password: string = this.decodeUserInfo(rawPassword)
      const encoder = util.TextEncoder.create('utf-8')
      const base64 = new util.Base64Helper().encodeToStringSync(encoder.encode(`${username}:${password}`))
      authorization = 'Basic ' + base64
      cleanUrl = input.slice(0, authorityStart) + input.slice(at + 1)
    }

    const isMd5: boolean = this.isMd5Url(cleanUrl)
    const codeUrl: string = isMd5 ? this.replaceMd5Suffix(cleanUrl) : cleanUrl
    return {
      cleanUrl: cleanUrl,
      codeUrl: codeUrl,
      authorization: authorization,
      expectedMd5: isMd5 ? 'pending' : ''
    }
  }

  private isMd5Url(url: string): boolean {
    const pathEnd: number = this.firstQueryOrHash(url)
    return url.slice(0, pathEnd).toLowerCase().endsWith('.md5')
  }

  private replaceMd5Suffix(url: string): string {
    const pathEnd: number = this.firstQueryOrHash(url)
    return url.slice(0, pathEnd - 4) + url.slice(pathEnd)
  }

  private firstQueryOrHash(url: string): number {
    const question: number = url.indexOf('?')
    const hash: number = url.indexOf('#')
    if (question < 0) return hash < 0 ? url.length : hash
    if (hash < 0) return question
    return question < hash ? question : hash
  }

  private decodeUserInfo(value: string): string {
    try {
      return decodeURIComponent(value)
    } catch (e) {
      return value
    }
  }

  private async downloadText(url: string, authorization: string): Promise<string> {
    const bytes = await this.downloadBytes(url, authorization)
    return util.TextDecoder.create('utf-8').decodeToString(bytes)
  }

  private async downloadBytes(url: string, authorization: string): Promise<Uint8Array> {
    const request = http.createHttp()
    try {
      const headers: Record<string, string> = {}
      if (authorization.length > 0) headers['Authorization'] = authorization
      const resp = await request.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 20000,
        readTimeout: 20000,
      })
      if (resp.responseCode !== 200) {
        if (resp.responseCode === 401) {
          throw new Error('下载失败 HTTP 401：该源需要 Basic Auth，请检查地址中的用户名和密码')
        }
        throw new Error('下载失败 HTTP ' + resp.responseCode)
      }
      return new Uint8Array(resp.result as ArrayBuffer)
    } finally {
      request.destroy()
    }
  }

  private readMd5(text: string): string {
    const match = text.match(/[0-9a-fA-F]{32}/)
    if (!match || !match[0]) {
      throw new Error('MD5 校验文件格式无效')
    }
    return match[0].toLowerCase()
  }

  private async md5Hex(data: Uint8Array): Promise<string> {
    const md = cryptoFramework.createMd('MD5')
    md.updateSync({ data: data })
    const digest = md.digestSync().data
    let hex: string = ''
    for (const value of digest) {
      hex += value < 16 ? '0' : ''
      hex += value.toString(16)
    }
    return hex
  }

  private extFilePath(key: string): string {
    return `${this.ctx?.filesDir ?? ''}/${EXT_DIR}/${key}.js`
  }

  private async saveExtFile(key: string, code: string): Promise<void> {
    const dir = `${this.ctx?.filesDir ?? ''}/${EXT_DIR}`
    try { fs.mkdirSync(dir, true) } catch (e) {}
    const file = fs.openSync(this.extFilePath(key), fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    try {
      fs.writeSync(file.fd, code)
    } finally {
      fs.closeSync(file)
    }
  }

  private async readExtFile(key: string): Promise<string> {
    return fs.readTextSync(this.extFilePath(key))
  }

  // ---- 工具 ----

  // 历史/收藏唯一键：不同站点的 vod_id 可能相同，不能只用 vod_id。
  static contentKey(mode: string, siteApi: string, vodId: string): string {
    return `${mode}|${siteApi}|${vodId}`
  }

  // 解析选集串 "名称1$地址1###名称2$地址2"
  static parseEpisodes(playUrl: string): Episode[] {
    const eps: Episode[] = []
    const groups = playUrl.split('###')
    for (const g of groups) {
      if (g.length === 0) continue
      const idx = g.indexOf('$')
      if (idx >= 0) {
        eps.push({ name: g.slice(0, idx), url: g.slice(idx + 1) })
      } else {
        eps.push({ name: g, url: g })
      }
    }
    return eps
  }

  // 解析多线路：vod_play_from 与 vod_play_url 均按 '$$$' 分隔（uz 标准协议）
  // 单线路扩展（如猫爪盘搜）返回长度 1 的数组；空组跳过、名字缺失时按序号命名
  static parsePlayLines(playFrom: string, playUrl: string): PlayLine[] {
    const names = playFrom.split('$$$')
    const groups = playUrl.split('$$$')
    const lines: PlayLine[] = []
    const count = Math.max(names.length, groups.length)
    for (let i = 0; i < count; i++) {
      const urlGroup = i < groups.length ? groups[i] : ''
      const eps = AppState.parseEpisodes(urlGroup)
      if (eps.length === 0) continue
      const rawName = i < names.length ? names[i].trim() : ''
      lines.push({ name: rawName.length > 0 ? rawName : `线路${i + 1}`, episodes: eps })
    }
    return lines
  }

  // 标准化播放请求头：剔除空值，把 uz 的 cookie 字段名转成 Cookie
  static normalizeHeaders(h?: Record<string, string>): Record<string, string> {
    const out: Record<string, string> = {}
    if (!h) return out
    const keys = Object.keys(h)
    for (const k of keys) {
      const v = h[k]
      if (!v) continue
      out[k === 'cookie' ? 'Cookie' : k] = v
    }
    return out
  }
}

// 全局单例
export const app = new AppState()
