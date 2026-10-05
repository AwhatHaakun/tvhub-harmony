/**
 * 主题服务
 */

import { CONFIG } from '../common/constants/Config'
import { HostBridge } from '../HostBridge'

export interface ThemeColor {
  name: string
  accent: string
  accentAlt: string
}

export class ThemeService {
  private host: HostBridge

  constructor(host: HostBridge) {
    this.host = host
  }

  getAvailableColors(): ThemeColor[] {
    return CONFIG.THEME_COLORS
  }

  async getCurrentColor(): Promise<ThemeColor> {
    const raw = await this.host.getRaw(CONFIG.KEYS.THEME_COLOR)
    if (!raw || raw === '') {
      return CONFIG.THEME_COLORS[0] // 默认蓝色
    }
    try {
      const saved = JSON.parse(raw) as ThemeColor
      // 验证是否有效
      const valid = CONFIG.THEME_COLORS.find(c => c.name === saved.name)
      return valid || CONFIG.THEME_COLORS[0]
    } catch {
      return CONFIG.THEME_COLORS[0]
    }
  }

  async setCurrentColor(color: ThemeColor): Promise<void> {
    await this.host.setRaw(CONFIG.KEYS.THEME_COLOR, JSON.stringify(color))
  }
}
