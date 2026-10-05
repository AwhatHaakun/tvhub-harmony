/**
 * TVBox 源格式兼容增强
 * 支持多种配置格式的解析和转换
 */

import { hilog } from '@kit.PerformanceAnalysisKit'

interface SourceItem {
  name: string
  url: string
}

interface SiteItem {
  api?: string
  key?: string
  name?: string
}

export interface ParsedSource {
  type: 'multi' | 'single' | 'unknown'
  sources?: SourceItem[]
  sites?: SiteItem[]
  error?: string
}

/**
 * 智能解析 TVBox 源配置
 * 支持格式：
 * 1. 多仓根接口 { urls: [...] }
 * 2. 单仓接口 { sites: [...] }
 * 3. 数组格式 [...]
 * 4. 嵌套格式 { data: {...} }
 * 5. 纯站点数组
 */
export class TvboxSourceParser {

  static parse(text: string): ParsedSource {
    try {
      // 清洗 JSON
      const cleaned = TvboxSourceParser.cleanJson(text)
      const obj: ESObject = JSON.parse(cleaned) as ESObject

      return TvboxSourceParser.parseObject(obj)
    } catch (e) {
      hilog.error(0x0000, 'tvhub', 'Parse source failed: %{public}s', String(e))
      return { type: 'unknown', error: String(e) }
    }
  }

  private static cleanJson(text: string): string {
    let cleaned = text

    // 移除 BOM
    if (cleaned.charCodeAt(0) === 0xFEFF) {
      cleaned = cleaned.slice(1)
    }

    // 移除注释
    cleaned = TvboxSourceParser.stripComments(cleaned)

    // 修复控制字符
    cleaned = TvboxSourceParser.repairControlChars(cleaned)

    // 移除尾逗号
    cleaned = TvboxSourceParser.stripTrailingCommas(cleaned)

    return cleaned
  }

  private static stripComments(text: string): string {
    const out: string[] = []
    let i = 0
    let inString = false
    let escaped = false

    while (i < text.length) {
      const ch = text.charAt(i)

      if (inString) {
        out.push(ch)
        if (escaped) {
          escaped = false
        } else if (ch === '\\') {
          escaped = true
        } else if (ch === '"') {
          inString = false
        }
        i++
        continue
      }

      if (ch === '"') {
        inString = true
        out.push(ch)
        i++
        continue
      }

      // 单行注释
      if (ch === '/' && i + 1 < text.length && text.charAt(i + 1) === '/') {
        while (i < text.length && text.charAt(i) !== '\n' && text.charAt(i) !== '\r') {
          i++
        }
        continue
      }

      // 块注释
      if (ch === '/' && i + 1 < text.length && text.charAt(i + 1) === '*') {
        i += 2
        while (i + 1 < text.length && !(text.charAt(i) === '*' && text.charAt(i + 1) === '/')) {
          i++
        }
        i += 2
        continue
      }

      out.push(ch)
      i++
    }

    return out.join('')
  }

  private static repairControlChars(text: string): string {
    const out: string[] = []
    let inString = false
    let escaped = false

    for (let i = 0; i < text.length; i++) {
      const ch = text.charAt(i)

      if (!inString) {
        if (ch === '"') inString = true
        out.push(ch)
        continue
      }

      if (escaped) {
        escaped = false
        out.push(ch)
        continue
      }

      if (ch === '\\') {
        escaped = true
        out.push(ch)
        continue
      }

      if (ch === '"') {
        inString = false
        out.push(ch)
        continue
      }

      const code = ch.charCodeAt(0)
      out.push(code < 32 ? ' ' : ch)
    }

    return out.join('')
  }

  private static stripTrailingCommas(text: string): string {
    const out: string[] = []
    let inString = false
    let escaped = false
    let i = 0

    while (i < text.length) {
      const ch = text.charAt(i)

      if (inString) {
        out.push(ch)
        if (escaped) {
          escaped = false
        } else if (ch === '\\') {
          escaped = true
        } else if (ch === '"') {
          inString = false
        }
        i++
        continue
      }

      if (ch === '"') {
        inString = true
        out.push(ch)
        i++
        continue
      }

      if (ch === ',') {
        let j = i + 1
        while (j < text.length && /\s/.test(text.charAt(j))) j++
        if (j < text.length && (text.charAt(j) === '}' || text.charAt(j) === ']')) {
          i++
          continue
        }
      }

      out.push(ch)
      i++
    }

    return out.join('')
  }

  private static parseObject(obj: ESObject): ParsedSource {
    // 格式 1: { urls: [...] } - 多仓根接口
    if (obj.urls && Array.isArray(obj.urls)) {
      const urls: ESObject[] = obj.urls as ESObject[]
      const sources: SourceItem[] = []
      for (let i = 0; i < urls.length; i++) {
        const item: ESObject = urls[i]
        const source: SourceItem = {
          name: (item.name || item.title || '未命名源') as string,
          url: (item.url || item.link || '') as string
        }
        if (source.url) {
          sources.push(source)
        }
      }
      return {
        type: 'multi',
        sources: sources
      }
    }

    // 格式 2: { sites: [...] } - 单仓接口
    if (obj.sites && Array.isArray(obj.sites)) {
      return {
        type: 'single',
        sites: obj.sites as SiteItem[]
      }
    }

    // 格式 3: { data: {...} } - 嵌套格式
    if (obj.data && typeof obj.data === 'object') {
      return TvboxSourceParser.parseObject(obj.data as ESObject)
    }

    // 格式 4: 数组直接包含站点
    if (Array.isArray(obj)) {
      const arr: ESObject[] = obj as ESObject[]
      // 判断是源列表还是站点列表
      if (arr.length > 0) {
        const first: ESObject = arr[0] as ESObject

        // 包含 url/link 字段 -> 源列表
        if (first.url || first.link) {
          const sources: SourceItem[] = []
          for (let i = 0; i < arr.length; i++) {
            const item: ESObject = arr[i]
            const source: SourceItem = {
              name: (item.name || item.title || '未命名源') as string,
              url: (item.url || item.link || '') as string
            }
            if (source.url) {
              sources.push(source)
            }
          }
          return {
            type: 'multi',
            sources: sources
          }
        }

        // 包含 api 字段 -> 站点列表
        if (first.api || first.key) {
          return {
            type: 'single',
            sites: arr as SiteItem[]
          }
        }
      }
    }

    // 格式 5: { spider: "...", sites: [...] } - 带爬虫的配置
    if (obj.spider && obj.sites) {
      return {
        type: 'single',
        sites: obj.sites as SiteItem[]
      }
    }

    // 格式 6: 其他可能的嵌套结构
    const keys = Object.keys(obj)
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i]
      const value: Object | undefined = obj[key]
      if (typeof value === 'object' && value !== null) {
        const nested = TvboxSourceParser.parseObject(value as ESObject)
        if (nested.type !== 'unknown') {
          return nested
        }
      }
    }

    return {
      type: 'unknown',
      error: '无法识别的配置格式'
    }
  }

  /**
   * 站点字段兼容性映射
   * 不同源可能使用不同的字段名
   */
  static normalizeSite(site: ESObject): SiteItem {
    return {
      key: (site.key || site.id || site.name || '') as string,
      name: (site.name || site.title || site.key || '未命名') as string,
      api: (site.api || site.url || site.link || '') as string
    }
  }

  /**
   * 检测配置格式版本
   */
  static detectVersion(obj: ESObject): string {
    if (obj.version) return String(obj.version)
    if (obj.urls) return 'multi-repo'
    if (obj.sites) return 'single-repo'
    return 'unknown'
  }

  /**
   * 验证 URL 格式
   */
  static isValidUrl(url: string): boolean {
    if (!url || typeof url !== 'string') return false
    const trimmed = url.trim()
    return trimmed.startsWith('http://') || trimmed.startsWith('https://')
  }

  /**
   * 从文本中提取可能的 JSON
   * 处理包含前缀说明文字的情况
   */
  static extractJson(text: string): string {
    // 查找第一个 { 或 [
    const openBrace = text.indexOf('{')
    const openBracket = text.indexOf('[')

    let start = -1
    if (openBrace >= 0 && openBracket >= 0) {
      start = Math.min(openBrace, openBracket)
    } else if (openBrace >= 0) {
      start = openBrace
    } else if (openBracket >= 0) {
      start = openBracket
    }

    if (start < 0) return text

    // 从第一个括号开始提取
    return text.slice(start)
  }
}
