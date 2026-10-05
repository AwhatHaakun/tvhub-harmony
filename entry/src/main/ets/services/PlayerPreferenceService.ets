/**
 * 播放器偏好设置服务
 */

import { CONFIG } from '../common/constants/Config'
import { HostBridge } from '../HostBridge'

export interface PlayerPreference {
  speed: number
  scaleMode: number
}

export class PlayerPreferenceService {
  private host: HostBridge

  constructor(host: HostBridge) {
    this.host = host
  }

  async getSpeed(): Promise<number> {
    const raw = await this.host.getRaw(CONFIG.KEYS.PLAYER_SPEED)
    if (!raw || raw === '') return 1.0
    try {
      const speed = parseFloat(raw)
      return isNaN(speed) ? 1.0 : speed
    } catch {
      return 1.0
    }
  }

  async setSpeed(speed: number): Promise<void> {
    await this.host.setRaw(CONFIG.KEYS.PLAYER_SPEED, speed.toString())
  }

  async getScaleMode(): Promise<number> {
    const raw = await this.host.getRaw(CONFIG.KEYS.PLAYER_SCALE)
    if (!raw || raw === '') return 0
    try {
      const mode = parseInt(raw)
      return isNaN(mode) ? 0 : mode
    } catch {
      return 0
    }
  }

  async setScaleMode(mode: number): Promise<void> {
    await this.host.setRaw(CONFIG.KEYS.PLAYER_SCALE, mode.toString())
  }

  async getPreference(): Promise<PlayerPreference> {
    const speed = await this.getSpeed()
    const scaleMode = await this.getScaleMode()
    return { speed, scaleMode }
  }
}
