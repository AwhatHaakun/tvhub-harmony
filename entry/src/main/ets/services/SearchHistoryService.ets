/**
 * 搜索历史服务
 */

import { CONFIG } from '../common/constants/Config'
import { HostBridge } from '../HostBridge'

export interface SearchHistoryItem {
  keyword: string
  time: number
}

export class SearchHistoryService {
  private host: HostBridge

  constructor(host: HostBridge) {
    this.host = host
  }

  async getHistory(): Promise<SearchHistoryItem[]> {
    const raw = await this.host.getRaw(CONFIG.KEYS.SEARCH_HISTORY)
    if (!raw || raw === '') return []
    try {
      const list = JSON.parse(raw) as SearchHistoryItem[]
      return (list || []).slice(0, CONFIG.SEARCH_HISTORY_MAX)
    } catch {
      return []
    }
  }

  async addHistory(keyword: string): Promise<void> {
    const trimmed = keyword.trim()
    if (trimmed.length === 0) return

    const list = await this.getHistory()
    // 去重：移除已存在的相同关键词
    const filtered = list.filter(item => item.keyword !== trimmed)
    // 插入到最前面
    filtered.unshift({ keyword: trimmed, time: Date.now() })
    // 限制数量
    const limited = filtered.slice(0, CONFIG.SEARCH_HISTORY_MAX)
    await this.host.setRaw(CONFIG.KEYS.SEARCH_HISTORY, JSON.stringify(limited))
  }

  async removeHistory(keyword: string): Promise<void> {
    const list = await this.getHistory()
    const filtered = list.filter(item => item.keyword !== keyword)
    await this.host.setRaw(CONFIG.KEYS.SEARCH_HISTORY, JSON.stringify(filtered))
  }

  async clearHistory(): Promise<void> {
    await this.host.setRaw(CONFIG.KEYS.SEARCH_HISTORY, '[]')
  }
}
