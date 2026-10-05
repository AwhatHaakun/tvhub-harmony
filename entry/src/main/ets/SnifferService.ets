// SnifferService.ets —— 网页媒体地址识别与请求头整理
// 只负责纯逻辑：Web 页面负责监听请求，播放器负责真正播放。

export type SniffMediaType = 'hls' | 'mp4' | 'unknown'

export interface SniffResult {
  url: string
  type: SniffMediaType
  contentType: string
  referer: string
  userAgent: string
  headers: Record<string, string>
  score: number
}

const MAX_SNIFF_RESULTS: number = 30
const FORWARD_HEADERS: string[] = [
  'user-agent',
  'referer',
  'cookie',
  'origin',
  'authorization',
  'accept'
]

export class SnifferService {
  static readonly maxResults: number = MAX_SNIFF_RESULTS

  static cleanUrl(url: string): string {
    const value: string = url.trim()
    const hash: number = value.indexOf('#')
    return hash >= 0 ? value.slice(0, hash) : value
  }

  static classifyUrl(url: string, contentType: string): SniffMediaType {
    const value: string = SnifferService.cleanUrl(url).toLowerCase()
    const mime: string = SnifferService.mimeToken(contentType)
    if (mime.indexOf('mpegurl') >= 0 || mime.indexOf('m3u8') >= 0
      || value.indexOf('.m3u8') >= 0 || value.indexOf('format=m3u8') >= 0
      || value.indexOf('type=m3u8') >= 0) {
      return 'hls'
    }
    if (mime === 'video/mp4' || mime === 'audio/mp4'
      || value.indexOf('.mp4') >= 0 || value.indexOf('format=mp4') >= 0
      || value.indexOf('type=mp4') >= 0) {
      return 'mp4'
    }
    return 'unknown'
  }

  static isCandidate(url: string, contentType: string): boolean {
    const value: string = SnifferService.cleanUrl(url)
    if (!SnifferService.isHttpUrl(value) || SnifferService.isBlockedResource(value)) return false

    const type: SniffMediaType = SnifferService.classifyUrl(value, contentType)
    if (type === 'hls' || type === 'mp4') return true

    // 无扩展名资源只有在 Content-Type 或 URL 参数明确表示视频时才收录。
    return SnifferService.hasExplicitVideoMime(contentType) || SnifferService.hasExplicitVideoParam(value)
  }

  static scoreUrl(url: string, contentType: string): number {
    if (!SnifferService.isCandidate(url, contentType)) return -1

    const value: string = SnifferService.cleanUrl(url).toLowerCase()
    const type: SniffMediaType = SnifferService.classifyUrl(value, contentType)
    let score: number = type === 'hls' ? 100 : type === 'mp4' ? 90 : 55
    const mime: string = SnifferService.mimeToken(contentType)
    if (mime === 'application/vnd.apple.mpegurl' || mime === 'application/x-mpegurl') score += 4
    if (value.indexOf('master') >= 0 || value.indexOf('playlist') >= 0) score += 2
    if (value.indexOf('stream') >= 0 || value.indexOf('play') >= 0) score += 1
    return score
  }

  static guessContentType(url: string, contentType: string): string {
    const mime: string = SnifferService.mimeToken(contentType)
    if (mime.length > 0) return mime
    const type: SniffMediaType = SnifferService.classifyUrl(url, '')
    if (type === 'hls') return 'application/vnd.apple.mpegurl'
    if (type === 'mp4') return 'video/mp4'
    return 'video/*'
  }

  // 只转发对媒体播放有用的请求头，不把网页上下文请求头原样交给 AVPlayer。
  static normalizeHeaders(headers?: Array<Header>): Record<string, string> {
    const out: Record<string, string> = {}
    if (!headers) return out
    for (const header of headers) {
      const rawKey: string = header.headerKey ?? ''
      const key: string = rawKey.trim().toLowerCase()
      const value: string = (header.headerValue ?? '').trim()
      if (key.length === 0 || value.length === 0 || FORWARD_HEADERS.indexOf(key) < 0) continue
      out[SnifferService.canonicalHeaderName(key)] = value
    }
    return out
  }

  static getHeader(headers: Array<Header> | undefined, name: string): string {
    if (!headers) return ''
    const target: string = name.trim().toLowerCase()
    for (const header of headers) {
      if ((header.headerKey ?? '').trim().toLowerCase() === target) {
        return (header.headerValue ?? '').trim()
      }
    }
    return ''
  }

  static mergeResult(results: SniffResult[], result: SniffResult): SniffResult[] {
    const cleanedUrl: string = SnifferService.cleanUrl(result.url)
    if (!SnifferService.isCandidate(cleanedUrl, result.contentType)) return results.slice(0, MAX_SNIFF_RESULTS)

    const candidate: SniffResult = {
      url: cleanedUrl,
      type: result.type,
      contentType: result.contentType,
      referer: result.referer,
      userAgent: result.userAgent,
      headers: result.headers,
      score: result.score
    }
    const merged: SniffResult[] = results.slice()
    const index: number = merged.findIndex((item: SniffResult) => SnifferService.cleanUrl(item.url) === cleanedUrl)
    if (index < 0) {
      merged.push(candidate)
    } else {
      const old: SniffResult = merged[index]
      if (candidate.score > old.score || Object.keys(candidate.headers).length > Object.keys(old.headers).length) {
        merged[index] = candidate
      }
    }
    merged.sort((a: SniffResult, b: SniffResult) => {
      if (b.score !== a.score) return b.score - a.score
      return a.url.localeCompare(b.url)
    })
    return merged.slice(0, MAX_SNIFF_RESULTS)
  }

  private static isHttpUrl(url: string): boolean {
    const value: string = url.toLowerCase()
    return (value.startsWith('http://') || value.startsWith('https://')) && value.length > 10
  }

  private static mimeToken(contentType: string): string {
    const value: string = contentType.trim().toLowerCase()
    const semicolon: number = value.indexOf(';')
    return semicolon >= 0 ? value.slice(0, semicolon).trim() : value
  }

  private static hasExplicitVideoMime(contentType: string): boolean {
    const mime: string = SnifferService.mimeToken(contentType)
    // video/* 是未知类型的占位值，不能把普通网页请求误判为媒体。
    return mime.startsWith('video/') && mime !== 'video/*'
  }

  private static hasExplicitVideoParam(url: string): boolean {
    const value: string = SnifferService.cleanUrl(url).toLowerCase()
    const markers: string[] = [
      'format=video', 'type=video', 'mime=video', 'content-type=video',
      'media=video', 'format=mp4', 'type=mp4', 'format=m3u8', 'type=m3u8'
    ]
    return markers.some((marker: string) => value.indexOf(marker) >= 0)
  }

  private static isBlockedResource(url: string): boolean {
    const value: string = url.toLowerCase()
    const blocked: string[] = [
      '.jpg', '.jpeg', '.png', '.gif', '.webp', '.svg', '.ico',
      '.css', '.js', '.json', '.woff', '.woff2', '.ttf', '.otf',
      '.ts?', '.ts&', '.ts#', '/segment', '/thumbnail', '/favicon',
      'analytics', 'doubleclick', 'googletagmanager', 'google-analytics',
      'adserver', '/ads/', '/advert', 'tracking', 'beacon', 'pixel'
    ]
    if (blocked.some((part: string) => value.indexOf(part) >= 0)) {
      return SnifferService.classifyUrl(value, '') !== 'hls'
    }
    return value.startsWith('blob:') || value.startsWith('data:') || value.startsWith('file:')
  }

  private static canonicalHeaderName(name: string): string {
    if (name === 'user-agent') return 'User-Agent'
    if (name === 'referer') return 'Referer'
    if (name === 'cookie') return 'Cookie'
    if (name === 'origin') return 'Origin'
    if (name === 'authorization') return 'Authorization'
    return 'Accept'
  }
}
