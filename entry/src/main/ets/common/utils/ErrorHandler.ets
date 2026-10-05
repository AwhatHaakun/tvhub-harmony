/**
 * 全局错误处理器
 */

import { hilog } from '@kit.PerformanceAnalysisKit'

export class ErrorHandler {
  static handle(e: Error, context: string): string {
    const message = (e as Error).message ?? String(e)
    hilog.error(0x0000, 'tvhub', '[%{public}s] %{public}s', context, message)
    return ErrorHandler.userFriendlyMessage(message)
  }

  private static userFriendlyMessage(message: string): string {
    if (message.includes('HTTP 401')) {
      return '需要登录验证，请检查源配置'
    }
    if (message.includes('HTTP 403')) {
      return '访问被拒绝，该源可能有反爬限制'
    }
    if (message.includes('HTTP 404')) {
      return '资源不存在，请换个源试试'
    }
    if (message.includes('HTTP 5')) {
      return '服务器错误，请稍后重试'
    }
    if (message.includes('timeout') || message.includes('超时')) {
      return '网络超时，请检查网络连接'
    }
    if (message.includes('Network') || message.includes('网络')) {
      return '网络错误，请检查网络连接'
    }
    if (message.includes('JSON') || message.includes('parse')) {
      return '数据格式错误，该源可能不兼容'
    }
    return message
  }

  static maskUrl(url: string): string {
    try {
      return url.replace(/(\?|&)(token|key|auth)=[^&]+/gi, '$1$2=***')
    } catch {
      return url
    }
  }

  static isValidSourceUrl(url: string): boolean {
    try {
      // 简单URL验证,避免使用全局URL类
      const httpPattern = /^https?:\/\//i
      if (!httpPattern.test(url)) {
        return false
      }
      // 提取hostname部分
      const match = url.match(/^https?:\/\/([^/:?#]+)/)
      if (!match) {
        return false
      }
      const hostname = match[1]
      // 禁止本地地址
      if (hostname === 'localhost' || hostname === '127.0.0.1' || hostname.startsWith('192.168.')) {
        return false
      }
      return true
    } catch {
      return false
    }
  }

  static sanitizeContent(html: string): string {
    if (!html) return ''
    return html
      .replace(/<script[^>]*>.*?<\/script>/gi, '')
      .replace(/<iframe[^>]*>.*?<\/iframe>/gi, '')
      .replace(/on\w+\s*=\s*["'][^"']*["']/gi, '')
      .trim()
  }
}
