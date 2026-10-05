import { app } from './AppState'
import { AggSite, AggSitesCache, Category, PlayLine, SearchVodItem, SiteConf, SiteHomeData, SourceConf, VodDetail, VodItem } from './model/TvModels'
import { getDetail, getVodList, isUsableVod, loadRoot, loadSites, probeSiteHome, rootDisplayName, splitPlay } from './api/TvboxApi'
import { CONFIG, DEFAULT_ROOT } from './common/constants/Config'
import { PerformanceMonitor } from './common/utils/PerformanceMonitor'
import { ErrorHandler } from './common/utils/ErrorHandler'

/**
 * TvboxState.ets —— 多源接口状态层（合二为一的 TVBox 半边）
 * 职责：多接口（roots）持久化管理、源列表合并、站点选择、分类、列表/搜索/详情
 * - 每个"接口"可以是多仓根 URL（返回 urls[]）或单仓 URL（返回 sites[]），自动识别
 * - 已保存接口、选中的源/站点都持久化，重启自动恢复
 * 页面订阅 addDataListener('tvbox') 感知变化
 */

const INITIAL_SOURCE_PROBE_LIMIT: number = 12
const PROBE_BATCH_SIZE = CONFIG.PROBE_BATCH_SIZE

interface SiteProbeSelection {
  site: SiteConf
  data: SiteHomeData
}

export class TvboxState {
  roots: string[] = []
  sources: SourceConf[] = []
  loadingRoot: boolean = false
  rootError: string = ''
  activeSource: SourceConf | null = null
  activeSite: SiteConf | null = null
  categories: Category[] = []
  currentCategory: Category | null = null
  // 首页列表状态
  vodList: VodItem[] = []
  page: number = 1
  hasMore: boolean = true
  loading: boolean = false
  loadingMore: boolean = false
  errorMsg: string = ''
  private listeners: Set<(what: string) => void> = new Set()
  private initPromise: Promise<void> | null = null
  private aggSitesPromise: Promise<void> | null = null

  /** 启动时从持久化恢复；多个页面同时调用只初始化一次 */
  async init(): Promise<void> {
    if (this.initPromise) {
      return this.initPromise
    }
    const promise = this.doInit()
    this.initPromise = promise
    try {
      await promise
    } catch (e) {
      this.initPromise = null
      throw new Error((e as Error).message ?? String(e))
    }
  }

  private async doInit(): Promise<void> {
    PerformanceMonitor.mark('tvbox_init_start')
    const raw = await app.host.getRaw(CONFIG.KEYS.ROOTS)
    if (raw && raw !== '') {
      try {
        this.roots = JSON.parse(raw) as string[]
      } catch (e) {
        this.roots = []
      }
    }
    if (this.roots.length === 0) {
      // 迁移旧版单接口数据（tvbox_root_v1）
      const oldRoot: string = await app.host.getRaw('tvbox_root_v1') ?? ''
      if (oldRoot !== '') {
        this.roots = [oldRoot]
      } else {
        this.roots = [DEFAULT_ROOT]
      }
      await app.host.setRaw(CONFIG.KEYS.ROOTS, JSON.stringify(this.roots))
    }
    await this.reloadAll()
    PerformanceMonitor.mark('tvbox_init_end')
    PerformanceMonitor.measure('tvbox_init_start', 'tvbox_init_end')
  }

  /** 添加接口 URL（多仓或单仓都行），保存并立即加载 */
  async addRoot(url: string): Promise<void> {
    const trimmed: string = url.trim()
    if (trimmed === '') {
      throw new Error('接口地址不能为空')
    }
    if (!ErrorHandler.isValidSourceUrl(trimmed)) {
      throw new Error('接口地址格式无效，必须是 http:// 或 https:// 开头')
    }
    if (this.roots.indexOf(trimmed) >= 0) {
      throw new Error('该接口已在列表中')
    }
    this.roots.push(trimmed)
    await app.host.setRaw(CONFIG.KEYS.ROOTS, JSON.stringify(this.roots))
    await this.reloadAll()
  }

  /** 删除接口（至少保留一个） */
  async removeRoot(url: string): Promise<void> {
    if (this.roots.length <= 1) {
      throw new Error('至少保留一个接口')
    }
    this.roots = this.roots.filter((r: string) => r !== url)
    await app.host.setRaw(CONFIG.KEYS.ROOTS, JSON.stringify(this.roots))
    await this.reloadAll()
  }

  /** 重新加载全部接口，合并为源列表，并恢复上次选择的源/站点 */
  async reloadAll(): Promise<void> {
    PerformanceMonitor.mark('reload_all_start')
    this.loadingRoot = true
    this.rootError = ''
    this.sources = []
    this.activeSource = null
    this.activeSite = null
    this.categories = []
    this.vodList = []
    // 源列表即将变化：聚合站点清单失效（内存清空 + 持久化缓存清除）
    this.aggSites = []
    try {
      await app.host.setRaw(CONFIG.KEYS.AGG_SITES_CACHE, '')
    } catch (e) {
    }
    const errors: string[] = []
    try {
    for (let ri = 0; ri < this.roots.length; ri++) {
      const root = this.roots[ri]
      let mergedAny = false
      // 1) 尝试按多仓根接口解析（{urls:[...]}）
      try {
        const list = await loadRoot(root)
        if (list.length > 0) {
          this.sources = this.sources.concat(list)
          mergedAny = true
        }
      } catch (e) {
        // 不是多仓或请求失败，继续尝试单仓
      }
      // 2) 尝试按单仓配置解析（{sites:[...]}）
      if (!mergedAny) {
        try {
        const sites = await loadSites(root, false)
          if (sites.length > 0) {
            this.sources.push({
              id: root + '#direct',
              name: rootDisplayName(root),
              url: root,
              sites: sites,
              siteIndex: -1,
              rootUrl: root,
            })
            mergedAny = true
          }
        } catch (e) {
          errors.push(rootDisplayName(root) + ' 加载失败: ' + ErrorHandler.handle(e as Error, 'loadSites'))
        }
      }
    }
    if (this.sources.length === 0) {
      this.rootError = errors.length > 0 ? errors.join('；') : '没有任何可用接口'
    } else {
      // 恢复上次选择的源/站点
      const savedSrc: string = await app.host.getRaw(CONFIG.KEYS.ACTIVE_SRC) ?? ''
      const savedSite: string = await app.host.getRaw(CONFIG.KEYS.ACTIVE_SITE) ?? ''
      const preferred: SourceConf | undefined = this.sources.find((s: SourceConf) => s.id === savedSrc)
      const orderedSources: SourceConf[] = []
      if (preferred) orderedSources.push(preferred)
      for (let i = 0; i < this.sources.length; i++) {
        const src: SourceConf = this.sources[i]
        if (!preferred || src.id !== preferred.id) orderedSources.push(src)
      }
      let selected: boolean = false
      const sourceLimit: number = Math.min(orderedSources.length, INITIAL_SOURCE_PROBE_LIMIT)
      for (let i = 0; i < sourceLimit; i++) {
        const preferSite: string = i === 0 ? savedSite : ''
        if (await this.selectSource(orderedSources[i], preferSite)) {
          selected = true
          break
        }
      }
      if (!selected) {
        this.errorMsg = '已加载数据源，但前 ' + sourceLimit + ' 个数据源没有找到可展示内容的标准接口，请从源面板手动选择'
      }
    }
    } finally {
      this.loadingRoot = false
      this.notifyChanged('tvbox')
      PerformanceMonitor.mark('reload_all_end')
      PerformanceMonitor.measure('reload_all_start', 'reload_all_end')
    }
  }

  /** 选择源：自动探测标准站点，跳过失效接口、空分类和空首页。 */
  async selectSource(src: SourceConf, preferSiteKey: string = ''): Promise<boolean> {
    this.activeSource = src
    this.activeSite = null
    this.categories = []
    this.currentCategory = null
    this.vodList = []
    this.errorMsg = ''
    await app.host.setRaw(CONFIG.KEYS.ACTIVE_SRC, src.id)
    let sites: SiteConf[] = []
    try {
      sites = await loadSites(src.url, false)
    } catch (e) {
      this.errorMsg = '加载站点失败: ' + ((e as Error).message ?? String(e))
      this.notifyChanged('tvbox')
      return false
    }
    src.sites = sites
    const candidates: SiteConf[] = this.orderedProbeSites(sites, preferSiteKey)
    if (candidates.length === 0) {
      if (sites.length > 0 && sites.every((s: SiteConf) => s.status === 'jar')) {
        this.errorMsg = '该源仅包含需 Spider/JAR 的站点，当前鸿蒙版暂不支持'
      } else if (sites.length > 0 && sites.every((s: SiteConf) => s.status !== 'ok')) {
        this.errorMsg = '该源仅包含当前鸿蒙版暂不支持的爬虫站点'
      } else {
        this.errorMsg = '该源没有可用站点'
      }
      this.notifyChanged('tvbox')
      return false
    }

    this.loading = true
    this.notifyChanged('tvbox')
    const referer: string = src.url
    const selection: SiteProbeSelection | null = await this.probeSourceSites(candidates, referer)
    this.loading = false
    if (selection) {
      await this.applySiteHome(selection.site, selection.data)
      return true
    }
    this.errorMsg = '已尝试 ' + candidates.length + ' 个标准站点，均分类失败或没有可展示内容'
    this.notifyChanged('tvbox')
    return false
  }

  private orderedProbeSites(sites: SiteConf[], preferSiteKey: string): SiteConf[] {
    const result: SiteConf[] = []
    const seen: Set<string> = new Set<string>()
    const preferred: SiteConf | undefined = sites.find((s: SiteConf) =>
      s.key === preferSiteKey && s.status === 'ok')
    if (preferred) {
      result.push(preferred)
      seen.add(preferred.api)
    }
    for (let i = 0; i < sites.length; i++) {
      const site: SiteConf = sites[i]
      if (site.status !== 'ok' || seen.has(site.api)) continue
      result.push(site)
      seen.add(site.api)
    }
    return result
  }

  private async probeSourceSites(sites: SiteConf[], referer: string): Promise<SiteProbeSelection | null> {
    for (let start = 0; start < sites.length; start += PROBE_BATCH_SIZE) {
      const tasks: Promise<SiteProbeSelection | null>[] = []
      const end: number = Math.min(start + PROBE_BATCH_SIZE, sites.length)
      for (let i = start; i < end; i++) {
        tasks.push(this.probeOneSite(sites[i], referer))
      }
      const results: (SiteProbeSelection | null)[] = await Promise.all(tasks)
      for (let i = 0; i < results.length; i++) {
        if (results[i]) return results[i]
      }
    }
    return null
  }

  private async probeOneSite(site: SiteConf, referer: string): Promise<SiteProbeSelection | null> {
    try {
      const data: SiteHomeData = await probeSiteHome(site.api, referer)
      const result: SiteProbeSelection = { site: site, data: data }
      return result
    } catch (e) {
      return null
    }
  }

  private async applySiteHome(site: SiteConf, data: SiteHomeData): Promise<void> {
    this.activeSite = site
    this.categories = data.categories
    this.currentCategory = data.category
    this.vodList = data.page.list
    this.page = data.page.page
    this.hasMore = data.page.list.length > 0 && data.page.list.length < data.page.total
    this.errorMsg = ''
    await app.host.setRaw(CONFIG.KEYS.ACTIVE_SITE, site.key)
    this.notifyChanged('tvbox')
  }

  /** 用户明确选择站点时也先探测首页；失败则保留在选择页并显示原因。 */
  async selectSite(site: SiteConf): Promise<void> {
    if (site.status !== 'ok') {
      this.errorMsg = site.status === 'jar'
        ? '该站点需要 Spider/JAR，当前鸿蒙版暂不支持'
        : '该站点需要 drpy/JS 爬虫引擎，当前鸿蒙版暂不支持'
      this.categories = []
      this.vodList = []
      this.loading = false
      this.notifyChanged('tvbox')
      return
    }
    this.loading = true
    this.errorMsg = ''
    this.notifyChanged('tvbox')
    try {
      const referer: string = this.activeSource ? this.activeSource.url : ''
      const data: SiteHomeData = await probeSiteHome(site.api, referer)
      this.loading = false
      await this.applySiteHome(site, data)
    } catch (e) {
      this.activeSite = null
      this.categories = []
      this.currentCategory = null
      this.vodList = []
      this.loading = false
      this.errorMsg = '站点探测失败: ' + ((e as Error).message ?? String(e))
      this.notifyChanged('tvbox')
    }
  }

  /** 按分类拉列表；reset=true 替换 */
  async loadCategory(cat: Category, pg: number, reset: boolean): Promise<void> {
    const site = this.activeSite
    if (!site) return
    if (reset) {
      this.loading = true
      this.errorMsg = ''
    } else {
      this.loadingMore = true
    }
    this.currentCategory = cat
    try {
      const referer: string = this.activeSource ? this.activeSource.url : ''
      const page = await getVodList(site.api, cat.typeId, '', pg, referer, false)
      const usable = page.list.filter(isUsableVod)
      this.vodList = reset ? usable : this.vodList.concat(usable)
      this.page = pg
      this.hasMore = usable.length > 0
    } catch (e) {
      if (reset) {
        this.vodList = []
        this.errorMsg = (e as Error).message ?? String(e)
      }
      this.hasMore = false
    }
    this.loading = false
    this.loadingMore = false
    this.notifyChanged('tvbox')
  }

  /** 搜索（单站点） */
  async search(wd: string, pg: number): Promise<VodItem[]> {
    const site = this.activeSite
    if (!site) throw new Error('未选择站点')
    const referer: string = this.activeSource ? this.activeSource.url : ''
    const page = await getVodList(site.api, '', wd, pg, referer, false)
    return page.list.filter(isUsableVod)
  }

  // ---- 聚合搜索（全部源去重站点，多站并发，逐站回调追加） ----
  // searchSeq 递增令牌：新一轮搜索/手动停止后，旧轮次的回调与循环全部失效
  searchSeq: number = 0
  aggDone: number = 0
  aggTotal: number = 0
  // 正在加载全部源的站点清单（首次聚合/缓存过期时，约 1-2 分钟）
  aggPreparing: boolean = false
  // 去重后的聚合站点清单（内存缓存；roots 重载时清空）
  aggSites: AggSite[] = []

  /** 停止进行中的聚合搜索（正在途中的请求自然结束，回调不再生效） */
  stopSearch(): void {
    this.searchSeq++
  }

  /**
   * 确保聚合站点清单就绪：内存 -> 持久化缓存(7天) -> 全量加载。
   * 全量加载 = 并发(8)展开全部源配置，取 status==='ok' 站点并按 api 去重
   * （132 源展开约 450 站，去重后约 180 站）。
   */
  private async ensureAggSites(): Promise<void> {
    if (this.aggSites.length > 0) return
    if (!this.aggSitesPromise) {
      this.aggSitesPromise = this.loadAggSites().finally(() => {
        this.aggSitesPromise = null
      })
    }
    return this.aggSitesPromise
  }

  private async loadAggSites(): Promise<void> {
    PerformanceMonitor.mark('load_agg_sites_start')
    // 1) 持久化缓存
    try {
      const raw: string = await app.host.getRaw(CONFIG.KEYS.AGG_SITES_CACHE)
      if (raw && raw !== '') {
        const cache = JSON.parse(raw) as AggSitesCache
        if (cache && cache.sites && cache.sites.length > 0
          && Date.now() - cache.ts < CONFIG.AGG_CACHE_TTL_MS) {
          this.aggSites = cache.sites
          PerformanceMonitor.mark('load_agg_sites_end')
          PerformanceMonitor.measure('load_agg_sites_start', 'load_agg_sites_end')
          return
        }
      }
    } catch (e) {
      // 缓存损坏，走全量加载
    }
    // 2) 全量加载：展开所有源（含多根接口合并的全部源）
    this.aggPreparing = true
    try {
      const sites: AggSite[] = []
      const seen: Set<string> = new Set<string>()
      const srcs: SourceConf[] = this.sources
      let idx: number = 0
      const worker = async (): Promise<void> => {
        while (idx < srcs.length) {
          const src: SourceConf = srcs[idx]
          idx++
          try {
            const list: SiteConf[] = await loadSites(src.url, true)
            for (let i = 0; i < list.length; i++) {
              const s: SiteConf = list[i]
              if (s.status !== 'ok' || !s.searchable) continue
              const key: string = s.api.endsWith('/') ? s.api.slice(0, s.api.length - 1) : s.api
              if (seen.has(key)) continue
              seen.add(key)
              sites.push({
                siteName: s.name,
                api: s.api,
                srcName: src.name,
                referer: src.url
              })
            }
          } catch (e) {
            // 单源失败跳过，不阻塞其它源
          }
        }
      }
      const workers: Promise<void>[] = []
      const n: number = Math.min(CONFIG.CONCURRENT_WORKERS, srcs.length)
      for (let i = 0; i < n; i++) {
        workers.push(worker())
      }
      await Promise.all(workers)
      this.aggSites = sites
      // 写缓存（失败不影响本次）
      try {
        const cache: AggSitesCache = { ts: Date.now(), sites: sites }
        await app.host.setRaw(CONFIG.KEYS.AGG_SITES_CACHE, JSON.stringify(cache))
      } catch (e) {
      }
    } finally {
      this.aggPreparing = false
      PerformanceMonitor.mark('load_agg_sites_end')
      PerformanceMonitor.measure('load_agg_sites_start', 'load_agg_sites_end')
    }
  }

  /**
   * 聚合搜索：搜「全部源」去重后的全部站点（并发 8，逐站回调）。
   * 首次调用会先加载站点清单（aggPreparing=true，UI 提示"准备站点"），
   * 清单持久化缓存 7 天；roots 重载后自动失效重建。
   */
  async searchAggregate(wd: string, onBatch: (items: SearchVodItem[]) => void): Promise<void> {
    if (this.sources.length === 0) throw new Error('没有可用源，请先在设置里加载接口')
    await this.ensureAggSites()
    const sites: AggSite[] = this.aggSites
    if (sites.length === 0) throw new Error('全部源的站点加载失败，请检查网络后重试')
    const seq: number = ++this.searchSeq
    this.aggTotal = sites.length
    this.aggDone = 0
    let idx: number = 0
    const worker = async (): Promise<void> => {
      while (idx < sites.length && seq === this.searchSeq) {
        const site: AggSite = sites[idx]
        idx++
        const batch: SearchVodItem[] = []
        try {
          const page = await getVodList(site.api, '', wd, 1, site.referer, true)
          if (seq !== this.searchSeq) return
          const usable: VodItem[] = page.list.filter(isUsableVod)
          for (let i = 0; i < usable.length; i++) {
            batch.push({
              vod: usable[i],
              siteApi: site.api,
              siteReferer: site.referer,
              siteName: site.siteName,
              sourceName: site.srcName
            })
          }
        } catch (e) {
          // 单站失败静默，不阻塞其它站点
        }
        this.aggDone++
        onBatch(batch)
      }
    }
    const workers: Promise<void>[] = []
    const n: number = Math.min(CONFIG.CONCURRENT_WORKERS, sites.length)
    for (let i = 0; i < n; i++) {
      workers.push(worker())
    }
    await Promise.all(workers)
  }

  /** 清理监听器（防止内存泄漏） */
  dispose(): void {
    this.listeners.clear()
    this.stopSearch()
  }

  /** 详情 + 播放线路拆分 */
  async detail(vodId: string): Promise<VodDetail> {
    const site = this.activeSite
    if (!site) throw new Error('未选择站点')
    const referer: string = this.activeSource ? this.activeSource.url : ''
    return await getDetail(site.api, vodId, referer)
  }

  /** 拆分播放线路（TVBox 分隔符：$$$ / # / $） */
  splitPlayLines(playFrom: string, playUrl: string): PlayLine[] {
    return splitPlay(playFrom, playUrl)
  }

  currentSourceName(): string {
    if (this.activeSource && this.activeSite) {
      return this.activeSource.name + ' · ' + this.activeSite.name
    }
    return this.activeSource ? this.activeSource.name : '未配置 TVBox 源'
  }

  addDataListener(fn: (what: string) => void): void {
    this.listeners.add(fn)
  }

  removeDataListener(fn: (what: string) => void): void {
    this.listeners.delete(fn)
  }

  notifyChanged(what: string): void {
    this.listeners.forEach((fn: (what: string) => void) => { fn(what) })
  }
}

// 全局单例
export const tvbox = new TvboxState()
