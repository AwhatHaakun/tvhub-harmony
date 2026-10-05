import { http } from '@kit.NetworkKit';
import { Category, Episode, PlayLine, SiteConf, SiteHomeData, SiteStatus, SourceConf, VodDetail, VodItem, VodPage } from '../model/TvModels';
import { TvboxSourceParser, ParsedSource } from './TvboxSourceParser';
import { ErrorHandler } from '../common/utils/ErrorHandler';
import { CONFIG } from '../common/constants/Config';

/**
 * 多源接口协议客户端（ArkTS 版）
 * 翻译自 tvbox-spike/tvbox-client.mjs（Node 参考实现，已全链路验证）
 * 协议：苹果CMS 采集接口 ac=list / videolist(t|wd) / detail / play
 */

const UA: string = CONFIG.PLAYER_UA;
const UA_ALT: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.6261.95 Safari/537.36';

interface RootUrlJson {
  name: string;
  url: string;
}

interface RootJson {
  urls?: RootUrlJson[];
}

interface SiteJson {
  key?: string;
  name?: string;
  api?: string;
  type?: number;
  categories?: string[];
  searchable?: number;
}

interface SourceJson {
  sites?: SiteJson[];
  urls?: RootUrlJson[];
}

interface ClassItemJson {
  type_id: number | string;
  type_name?: string;
  type_pid?: number | string;
}

interface ClassJson {
  class?: ClassItemJson[];
}

interface VodJson {
  vod_id?: number | string;
  vod_name?: string;
  vod_pic?: string;
  vod_remarks?: string;
  vod_year?: string;
  vod_area?: string;
  vod_lang?: string;
  vod_actor?: string;
  vod_director?: string;
  vod_score?: string;
  type_name?: string;
  vod_content?: string;
  vod_play_from?: string;
  vod_play_url?: string;
}

interface VodListJson {
  list?: VodJson[];
  total?: number;
  page?: number;
}

interface DetailJson {
  list?: VodJson[];
}

/**
 * TVBox 配置经常带 BOM、// 注释、块注释、字符串内换行和尾逗号。
 * 这里先做字符串感知清洗，再走标准 JSON.parse。
 */
function stripConfigComments(text: string): string {
  const out: string[] = [];
  let i = 0;
  let inString = false;
  let escaped = false;
  while (i < text.length) {
    const ch: string = text.charAt(i);
    if (inString) {
      out.push(ch);
      if (escaped) {
        escaped = false;
      } else if (ch === '\\') {
        escaped = true;
      } else if (ch === '"') {
        inString = false;
      }
      i++;
      continue;
    }
    if (ch === '"') {
      inString = true;
      out.push(ch);
      i++;
      continue;
    }
    if (ch === '/' && i + 1 < text.length && text.charAt(i + 1) === '/') {
      while (i < text.length && text.charAt(i) !== '\r' && text.charAt(i) !== '\n') i++;
      continue;
    }
    if (ch === '/' && i + 1 < text.length && text.charAt(i + 1) === '*') {
      i += 2;
      while (i + 1 < text.length && !(text.charAt(i) === '*' && text.charAt(i + 1) === '/')) i++;
      i += 2;
      continue;
    }
    out.push(ch);
    i++;
  }
  return out.join('');
}

function repairConfigControls(text: string): string {
  const out: string[] = [];
  let inString = false;
  let escaped = false;
  for (let i = 0; i < text.length; i++) {
    const ch: string = text.charAt(i);
    if (!inString) {
      if (ch === '"') inString = true;
      out.push(ch);
      continue;
    }
    if (escaped) {
      escaped = false;
      out.push(ch);
      continue;
    }
    if (ch === '\\') {
      escaped = true;
      out.push(ch);
      continue;
    }
    if (ch === '"') {
      inString = false;
      out.push(ch);
      continue;
    }
    const code: number = ch.charCodeAt(0);
    out.push(code < 32 ? ' ' : ch);
  }
  return out.join('');
}

function stripTrailingConfigCommas(text: string): string {
  const out: string[] = [];
  let inString = false;
  let escaped = false;
  let i = 0;
  while (i < text.length) {
    const ch: string = text.charAt(i);
    if (inString) {
      out.push(ch);
      if (escaped) {
        escaped = false;
      } else if (ch === '\\') {
        escaped = true;
      } else if (ch === '"') {
        inString = false;
      }
      i++;
      continue;
    }
    if (ch === '"') {
      inString = true;
      out.push(ch);
      i++;
      continue;
    }
    if (ch === ',') {
      let j = i + 1;
      while (j < text.length && /\s/.test(text.charAt(j))) j++;
      if (j < text.length && (text.charAt(j) === '}' || text.charAt(j) === ']')) {
        i++;
        continue;
      }
    }
    out.push(ch);
    i++;
  }
  return out.join('');
}

function parseLenientConfig<T>(text: string): T {
  let cleaned: string = text.charCodeAt(0) === 0xFEFF ? text.slice(1) : text;
  cleaned = repairConfigControls(stripConfigComments(cleaned));
  cleaned = stripTrailingConfigCommas(cleaned);
  try {
    return JSON.parse(cleaned) as T;
  } catch (e) {
    const message: string = (e as Error).message ?? String(e);
    throw new Error('配置 JSON 无效：' + message + '；内容前 100 字：' + cleaned.slice(0, 100));
  }
}

/** 单次请求返回文本；fast=true 用短超时（聚合搜索大量并发时快速跳过慢站） */
async function requestText(url: string, referer: string, ua: string, fast: boolean): Promise<string> {
  const httpRequest = http.createHttp();
  try {
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: {
        'User-Agent': ua,
        'Accept': 'application/json,text/plain,*/*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Referer': referer
      },
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: fast ? 8000 : 15000,
      readTimeout: fast ? 8000 : 20000
    });
    if (response.responseCode !== 200) {
      throw new Error('HTTP ' + response.responseCode + ' ' + url);
    }
    return response.result as string;
  } finally {
    httpRequest.destroy();
  }
}

/** 请求 JSON，referer 传单仓 URL 用于防反爬；失败自动换 UA 重试一次；fast=单次短超时 */
async function fetchJson<T>(url: string, referer: string, fast: boolean): Promise<T> {
  let lastErr: string = ''
  const uas: string[] = fast ? [UA] : [UA, UA_ALT]
  for (let i = 0; i < uas.length; i++) {
    try {
      const text = await requestText(url, referer, uas[i], fast);
      try {
        return parseLenientConfig<T>(text);
      } catch (e) {
        throw new Error('接口返回非 JSON（可能被反爬/需验证）' + url + ' 内容前80字: ' + text.slice(0, 80));
      }
    } catch (e) {
      lastErr = (e as Error).message ?? String(e)
    }
  }
  throw new Error(lastErr);
}

function baseOf(api: string): string {
  const hashIndex: number = api.indexOf('#')
  const fragment: string = hashIndex >= 0 ? api.slice(hashIndex) : ''
  const noFragment: string = hashIndex >= 0 ? api.slice(0, hashIndex) : api
  const queryIndex: number = noFragment.indexOf('?')
  const path: string = queryIndex >= 0 ? noFragment.slice(0, queryIndex) : noFragment
  const query: string = queryIndex >= 0 ? noFragment.slice(queryIndex) : ''
  const normalizedPath: string = path.endsWith('/') ? path : path + '/'
  return normalizedPath + query + fragment
}

function withQuery(api: string, query: string): string {
  const hashIndex: number = api.indexOf('#')
  const fragment: string = hashIndex >= 0 ? api.slice(hashIndex) : ''
  const noFragment: string = hashIndex >= 0 ? api.slice(0, hashIndex) : api
  const queryIndex: number = noFragment.indexOf('?')
  const base: string = queryIndex >= 0 ? noFragment.slice(0, queryIndex) : noFragment
  const oldQuery: string = queryIndex >= 0 ? noFragment.slice(queryIndex + 1) : ''
  const requestedKeys: string[] = query.split('&').map((part: string) => {
    const equalIndex: number = part.indexOf('=')
    return (equalIndex >= 0 ? part.slice(0, equalIndex) : part).trim().toLowerCase()
  })
  const keptParts: string[] = oldQuery.split('&').filter((part: string) => {
    const item: string = part.trim()
    if (item === '') return false
    const equalIndex: number = item.indexOf('=')
    const key: string = (equalIndex >= 0 ? item.slice(0, equalIndex) : item).trim().toLowerCase()
    return requestedKeys.indexOf(key) < 0
  })
  const parts: string[] = keptParts.concat(query.split('&').filter((part: string) => part.trim() !== ''))
  return parts.length > 0 ? base + '?' + parts.join('&') + fragment : base + fragment
}

/**
 * 识别 TVBox 配置中的爬虫站点。
 * csp_* 站点依赖 Android/JVM Spider；drpy/JS 站点依赖 JS 爬虫引擎，
 * 当前鸿蒙版只实现可直接访问的苹果 CMS HTTP 接口。
 */
export function classifySiteStatus(api: string, type?: number): SiteStatus {
  const value: string = api.trim().toLowerCase()
  if (value.startsWith('csp_') || value.startsWith('csp-') || value === '') return 'jar'
  if (value.startsWith('http://') || value.startsWith('https://')) return 'ok'
  // drpy、Python、T4 和相对脚本路径都需要额外规则运行时，不能当 HTTP API 请求。
  return 'drpy'
}

/** 1) 多仓根接口 -> 源列表（id 带来源接口前缀，支持多接口并存） */
export async function loadRoot(rootUrl: string): Promise<SourceConf[]> {
  try {
    const text = await fetchRawText(rootUrl, rootUrl)
    const parsed = TvboxSourceParser.parse(text)

    if (parsed.type === 'multi' && parsed.sources) {
      const list: SourceConf[] = []
      for (let i = 0; i < parsed.sources.length; i++) {
        const src = parsed.sources[i]
        if (!TvboxSourceParser.isValidUrl(src.url)) continue

        list.push({
          id: rootUrl + '#' + i,
          name: src.name || '源' + i,
          url: src.url,
          sites: [],
          siteIndex: -1,
          rootUrl: rootUrl,
        })
      }
      return list
    }

    throw new Error('不是多仓根接口格式')
  } catch (e) {
    throw new Error('加载多仓根接口失败: ' + ErrorHandler.handle(e as Error, 'loadRoot'))
  }
}

/** 获取原始文本（用于自定义解析） */
async function fetchRawText(url: string, referer: string): Promise<string> {
  const req = http.createHttp()
  try {
    const resp = await req.request(url, {
      method: http.RequestMethod.GET,
      connectTimeout: CONFIG.TIMEOUT.NORMAL,
      readTimeout: CONFIG.TIMEOUT.NORMAL,
      header: {
        'User-Agent': CONFIG.PLAYER_UA,
        'Referer': referer.length > 0 ? referer : url
      }
    })
    if (resp.responseCode !== 200) {
      throw new Error('HTTP ' + resp.responseCode)
    }
    return String(resp.result)
  } finally {
    req.destroy()
  }
}

/** 取接口 URL 的简短名称（域名），用于显示 */
export function rootDisplayName(rootUrl: string): string {
  const trimmed: string = rootUrl.replace(/^https?:\/\//, '').replace(/\/$/, '');
  const slash: number = trimmed.indexOf('/');
  return slash > 0 ? trimmed.slice(0, slash) : trimmed;
}

/** 2) 单仓配置 -> 站点列表；fast=短超时单次（聚合清单加载用） */
export async function loadSites(srcUrl: string, fast: boolean): Promise<SiteConf[]> {
  try {
    const text = await fetchRawText(srcUrl, srcUrl)
    const parsed = TvboxSourceParser.parse(text)

    if (parsed.type === 'single' && parsed.sites) {
      const list: SiteConf[] = []
      for (let i = 0; i < parsed.sites.length; i++) {
        const s = TvboxSourceParser.normalizeSite(parsed.sites[i] as ESObject)
        const api: string = (s.api || '') as string

        list.push({
          key: (s.key || String(i)) as string,
          name: (s.name || s.key || '源' + i) as string,
          api: api,
          categories: [],
          searchable: true,
          status: classifySiteStatus(api, 0)
        })
      }
      return list
    }

    throw new Error('不是单仓配置格式')
  } catch (e) {
    throw new Error('加载单仓配置失败: ' + ErrorHandler.handle(e as Error, 'loadSites'))
  }
}

/** 3) 分类 */
export async function getClass(api: string, referer: string, fast: boolean = false): Promise<Category[]> {
  const j = await fetchJson<ClassJson>(withQuery(baseOf(api), 'ac=list'), referer, fast);
  const raw = j.class || [];
  const list: Category[] = [];
  for (let i = 0; i < raw.length; i++) {
    list.push({
      typeId: String(raw[i].type_id),
      typeName: raw[i].type_name || '',
      typePid: String(raw[i].type_pid || '')
    });
  }
  return list;
}

/** 4) 列表 / 搜索：t=分类ID（注意不是 ids），wd=关键词，pg=页码；fast=聚合搜索短超时单次 */
export async function getVodList(api: string, t: string, wd: string, pg: number, referer: string, fast: boolean): Promise<VodPage> {
  let url: string = withQuery(baseOf(api), 'ac=videolist&pg=' + pg);
  if (t !== '') {
    url = url + '&t=' + encodeURIComponent(t);
  }
  if (wd !== '') {
    url = url + '&wd=' + encodeURIComponent(wd);
  }
  const j = await fetchJson<VodListJson>(url, referer, fast);
  const raw = j.list || [];
  const list: VodItem[] = [];
  for (let i = 0; i < raw.length; i++) {
    list.push(toVodItem(raw[i]));
  }
  return { total: j.total || list.length, page: j.page || pg, list: list };
}

/** 5) 详情 */
export async function getDetail(api: string, vodId: string, referer: string): Promise<VodDetail> {
  const url: string = withQuery(baseOf(api), 'ac=detail&ids=' + encodeURIComponent(vodId));
  const j = await fetchJson<DetailJson>(url, referer, false);
  const raw = (j.list || [])[0];
  if (!raw) {
    throw new Error('detail 为空: ' + vodId);
  }
  return {
    vodId: String(raw.vod_id || vodId),
    name: raw.vod_name || '',
    pic: raw.vod_pic || '',
    remarks: raw.vod_remarks || '',
    year: raw.vod_year || '',
    area: raw.vod_area || '',
    lang: raw.vod_lang || '',
    actor: raw.vod_actor || '',
    director: raw.vod_director || '',
    score: raw.vod_score || '',
    typeName: raw.type_name || '',
    content: (raw.vod_content || '').replace(/<[^>]+>/g, '').trim(),
    playFrom: raw.vod_play_from || '',
    playUrl: raw.vod_play_url || ''
  };
}

function toVodItem(v: VodJson): VodItem {
  return {
    vodId: String(v.vod_id || ''),
    name: v.vod_name || '',
    pic: v.vod_pic || '',
    remarks: v.vod_remarks || '',
    year: v.vod_year || '',
    area: v.vod_area || '',
    actor: v.vod_actor || '',
    director: v.vod_director || '',
    score: v.vod_score || '',
    typeName: v.type_name || ''
  };
}

/** 6) 播放地址拆分：$$$ 线路 / # 集 / $ 名址 */
export function splitPlay(playFrom: string, playUrl: string): PlayLine[] {
  // $$$ 分组是按下标对齐的；过滤空组会让后续线路错位。
  const froms: string[] = playFrom.split('$$$');
  const urlParts: string[] = playUrl.split('$$$');
  const lines: PlayLine[] = [];
  const count: number = Math.max(froms.length, urlParts.length);
  for (let i = 0; i < count; i++) {
    const epsRaw: string[] = (i < urlParts.length ? urlParts[i] : '').split('#').filter(s => s !== '');
    const episodes: Episode[] = [];
    for (let k = 0; k < epsRaw.length; k++) {
      const idx: number = epsRaw[k].indexOf('$');
      let url: string = '';
      if (idx > 0) {
        url = epsRaw[k].slice(idx + 1).trim();
      } else {
        url = epsRaw[k].trim();
      }
      if (url === '') continue;
      const name: string = idx > 0 ? epsRaw[k].slice(0, idx).trim() : (k + 1).toString();
      episodes.push({ name: name, url: url });
    }
    const from: string = i < froms.length ? froms[i].trim() : '';
    if (episodes.length === 0) continue;
    lines.push({ from: from.length > 0 ? from : `线路${i + 1}`, episodes: episodes });
  }
  return lines;
}

/** 便捷：列表里过滤明显垃圾条目（占位图/无名称） */
export function isUsableVod(v: VodItem): boolean {
  return v.vodId !== '' && v.name !== '' && !v.name.startsWith('同步图片') && v.pic.indexOf('err') < 0;
}


/**
 * 探测标准站点是否适合首页：分类接口成功后，先尝试“全部”，再尝试前几个分类。
 * 只有拿到有效影片才返回，调用方可继续尝试同一数据源中的下一个站点。
 */
export async function probeSiteHome(api: string, referer: string): Promise<SiteHomeData> {
  const rawCategories: Category[] = await getClass(api, referer, true);
  if (rawCategories.length === 0) {
    throw new Error('分类为空');
  }
  const allCategory: Category = { typeId: '', typeName: '全部', typePid: '' };
  const categories: Category[] = [allCategory].concat(rawCategories);
  const limit: number = Math.min(categories.length, 7);
  let lastError: string = '';
  for (let i = 0; i < limit; i++) {
    try {
      const page: VodPage = await getVodList(api, categories[i].typeId, '', 1, referer, true);
      const usable: VodItem[] = page.list.filter(isUsableVod);
      if (usable.length > 0) {
        const usablePage: VodPage = { total: page.total, page: page.page, list: usable };
        const result: SiteHomeData = { categories: categories, category: categories[i], page: usablePage };
        return result;
      }
    } catch (e) {
      lastError = (e as Error).message ?? String(e);
    }
  }
  throw new Error(lastError.length > 0 ? lastError : '分类与首页列表均为空');
}
