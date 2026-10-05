// PlayerPage.ets -- 播放页：小窗播放器 + 沉浸式全屏（轻量透明控制层）
// 修复要点：
//  1) 比例：AVPlayer 默认 VIDEO_SCALE_TYPE_FIT=拉伸变形！prepared 后必须显式设置
//     videoScaleType（按 scaleMode），切换时也统一走 applyScale()
//  2) 真全屏：隐藏系统栏 setWindowSystemBarEnable([]) + expandSafeArea 延伸到状态栏/手势条下
//  3) 全屏时控制条 3s 自动隐藏，点画面切换；退出全屏/销毁时恢复系统栏与竖屏
//  4) 断点续播：自动记录播放进度，下次从上次位置继续
//  5) 播放器偏好：记住用户的倍速和比例设置
// 播放链路：url/setMediaSource -> 等 stateChange('initialized') -> 设 surfaceId -> prepare

import { media } from '@kit.MediaKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'
import { app, AppState, HistoryItem } from './AppState'
import { CONFIG } from './common/constants/Config'
import { PlayerPreferenceService } from './services/PlayerPreferenceService'

const SMALL_VIDEO_HEIGHT: number = 210
// 倍速档位
const SPEEDS: number[] = [0.5, 0.75, 1, 1.25, 1.5, 2]
const SCALE_MODES: number[] = [0, 1, 2]

@Component
export struct PlayerPage {
  @State loading: boolean = true
  @State playing: boolean = false
  @State errorMsg: string = ''
  @State currentMs: number = 0
  @State durationMs: number = 0
  @State title: string = ''
  @State isFullscreen: boolean = false
  @State playbackSpeed: number = 1
  // 画面比例模式：0=保持比例(scaled_aspect) 1=裁剪填充(fit_crop) 2=拉伸铺满(fit)
  @State scaleMode: number = 0
  // 全屏时控制条显隐（自动隐藏 + 点画面切换）
  @State controlsVisible: boolean = true
  // 锁定后禁用播放区手势和普通控制；锁定按钮保持可点
  @State locked: boolean = false
  // 'none' | 'speed' | 'scale'
  @State pickerMode: string = 'none'
  @State gestureHint: string = ''
  @State seekPreviewMs: number = -1
  @State videoAreaWidth: number = 0

  private avPlayer: media.AVPlayer | null = null
  private xComponentController: XComponentController = new XComponentController()
  private surfaceId: string = ''
  private playUrl: string = ''
  private playHeaders: Record<string, string> = {} as Record<string, string>
  private urlReady: boolean = false
  private surfaceReady: boolean = false
  private started: boolean = false
  private progressTimer: number = -1
  private seekable: boolean = false
  private pendingSeekMs: number = -1
  private timeoutTimer: number = -1
  private retryCount: number = 0
  private urlSet: boolean = false
  private surfaceSet: boolean = false
  private hideControlsTimer: number = -1
  // 系统栏原状态（恢复用；debug 包默认两者都有）
  private barsHidden: boolean = false
  private historySaved: boolean = false
  private panStartMs: number = 0
  private brightnessValue: number = -1
  private previousBrightness: number = -1
  private volumeValue: number = 1
  private playerPreferenceService: PlayerPreferenceService = new PlayerPreferenceService(app.host)
  private autoSaveTimer: number = -1  // 自动保存进度定时器

  async aboutToAppear(): Promise<void> {
    const hist: HistoryItem | null = app.currentHistory
    this.title = hist && hist.vod_name.length > 0 ? `${hist.vod_name} · ${app.currentEpName}` : app.currentEpName
    this.setOrientation(window.Orientation.PORTRAIT)

    // 加载播放器偏好设置
    try {
      const pref = await this.playerPreferenceService.getPreference()
      this.playbackSpeed = pref.speed
      this.scaleMode = pref.scaleMode
    } catch (e) {
      // 使用默认值
    }

    try {
      if (app.currentMode === 'sniff') {
        this.playUrl = app.currentEpUrl
        this.playHeaders = AppState.normalizeHeaders(app.currentSniffHeaders)
        if (app.currentSniffReferer.length > 0 && !this.playHeaders['Referer']) {
          this.playHeaders['Referer'] = app.currentSniffReferer
        }
        if (!this.playHeaders['User-Agent']) {
          this.playHeaders['User-Agent'] = CONFIG.PLAYER_UA
        }
        // 嗅探状态是一次性跨页参数，读取后清空，避免返回播放器后重复消费。
        app.currentSniffHeaders = {}
        app.currentSniffReferer = ''
        this.urlReady = true
        this.tryStart()
      } else if (app.currentMode === 'tvbox') {
        this.playUrl = app.currentEpUrl
        this.playHeaders = { 'User-Agent': CONFIG.PLAYER_UA } as Record<string, string>
        const referer: string = app.currentHistory?.siteReferer ?? ''
        if (referer.length > 0) {
          this.playHeaders['Referer'] = referer
        }
        this.urlReady = true
        // 断点续播：检查历史记录中是否有播放位置
        if (hist && hist.lastPlayMs && hist.lastPlayMs > 5000 && hist.episodeUrl === app.currentEpUrl) {
          this.pendingSeekMs = hist.lastPlayMs
          hilog.info(0x0000, 'tvhub', 'Resume from %{public}dms', hist.lastPlayMs)
        }
        this.tryStart()
      } else {
        const urls = await app.playUrl(app.currentEpUrl)
        if (urls.length === 0) {
          this.errorMsg = '没有拿到播放地址'
          this.loading = false
          return
        }
        this.playUrl = urls[0].url
        this.playHeaders = AppState.normalizeHeaders(urls[0].headers)
        this.urlReady = true
        this.tryStart()
      }
    } catch (e) {
      this.errorMsg = (e as Error).message ?? String(e)
      this.loading = false
    }
  }

  aboutToDisappear(): void {
    this.setOrientation(window.Orientation.PORTRAIT)
    this.restoreSystemBars()
    this.restoreBrightness()
    if (this.progressTimer >= 0) {
      clearInterval(this.progressTimer)
      this.progressTimer = -1
    }
    if (this.timeoutTimer >= 0) {
      clearTimeout(this.timeoutTimer)
      this.timeoutTimer = -1
    }
    if (this.hideControlsTimer >= 0) {
      clearTimeout(this.hideControlsTimer)
      this.hideControlsTimer = -1
    }
    if (this.autoSaveTimer >= 0) {
      clearInterval(this.autoSaveTimer)
      this.autoSaveTimer = -1
    }
    if (this.avPlayer) {
      this.avPlayer.off('stateChange')
      this.avPlayer.off('error')
      this.avPlayer.release()
      this.avPlayer = null
    }
  }

  private async setOrientation(orientation: window.Orientation): Promise<void> {
    try {
      const hostCtx = this.getUIContext().getHostContext()
      if (!hostCtx) return
      const win = await window.getLastWindow(hostCtx)
      await win.setPreferredOrientation(orientation)
    } catch (e) {
      hilog.warn(0x0000, 'tvhub', 'set orientation failed: %{public}s', String(e))
    }
  }

  // 真全屏：隐藏系统栏（状态栏+导航手势条），窗口延伸全屏
  private async hideSystemBars(): Promise<void> {
    try {
      const hostCtx = this.getUIContext().getHostContext()
      if (!hostCtx) return
      const win = await window.getLastWindow(hostCtx)
      await win.setWindowSystemBarEnable([])
      this.barsHidden = true
    } catch (e) {
      hilog.warn(0x0000, 'tvhub', 'hide system bars failed: %{public}s', String(e))
    }
  }

  private async restoreSystemBars(): Promise<void> {
    if (!this.barsHidden) return
    try {
      const hostCtx = this.getUIContext().getHostContext()
      if (!hostCtx) return
      const win = await window.getLastWindow(hostCtx)
      await win.setWindowSystemBarEnable(['status', 'navigation'])
      this.barsHidden = false
    } catch (e) {
      hilog.warn(0x0000, 'tvhub', 'restore system bars failed: %{public}s', String(e))
    }
  }

  toggleFullscreen(): void {
    if (this.locked) return
    this.isFullscreen = !this.isFullscreen
    if (this.isFullscreen) {
      this.setOrientation(window.Orientation.LANDSCAPE)
      this.hideSystemBars()
      this.controlsVisible = true
      this.scheduleHideControls()
    } else {
      this.setOrientation(window.Orientation.PORTRAIT)
      this.restoreSystemBars()
      this.controlsVisible = true
      this.cancelHideControls()
    }
  }

  // 全屏时控制条 3s 自动隐藏
  private scheduleHideControls(): void {
    this.cancelHideControls()
    if (!this.isFullscreen || this.locked) return
    this.hideControlsTimer = setTimeout(() => {
      if (this.isFullscreen) {
        this.controlsVisible = false
      }
    }, CONFIG.HIDE_CONTROLS_MS)
  }

  private cancelHideControls(): void {
    if (this.hideControlsTimer >= 0) {
      clearTimeout(this.hideControlsTimer)
      this.hideControlsTimer = -1
    }
  }

  // 点画面：全屏=切换控制条（锁定后仍允许显隐），小窗=播放/暂停
  tapSurface(): void {
    if (this.isFullscreen) {
      if (this.controlsVisible) {
        this.controlsVisible = false
        this.cancelHideControls()
      } else {
        this.controlsVisible = true
        this.scheduleHideControls()
      }
      return
    }
    // 小窗单击仍受锁定保护，避免锁定后误触播放/暂停。
    if (this.locked) return
    this.togglePlay()
  }

  onSurfaceReady(): void {
    this.surfaceId = this.xComponentController.getXComponentSurfaceId()
    this.surfaceReady = true
    this.tryStart()
  }

  async tryStart(): Promise<void> {
    if (!this.urlReady || !this.surfaceReady || this.started) return
    this.started = true
    hilog.info(0x0000, 'tvhub', 'tryStart url=%{public}s mode=%{public}s', this.playUrl, app.currentMode)
    if (!this.playUrl.startsWith('http://') && !this.playUrl.startsWith('https://')) {
      this.onErrorText('播放地址无效：' + this.playUrl.slice(0, 80))
      return
    }
    try {
      this.avPlayer = await media.createAVPlayer()
      hilog.info(0x0000, 'tvhub', 'createAVPlayer ok, surface=%{public}s', this.surfaceId)
      this.avPlayer.on('stateChange', (state: media.AVPlayerState, reason: media.StateChangeReason) => { this.onStateChange(state) })
      this.avPlayer.on('error', (err: BusinessError) => { this.onError(err) })

      if (Object.keys(this.playHeaders).length > 0) {
        const mediaSource = media.createMediaSourceWithUrl(this.playUrl, this.playHeaders)
        const strategy: media.PlaybackStrategy = { preferredBufferDuration: 20 }
        this.avPlayer.setMediaSource(mediaSource, strategy)
      } else {
        this.avPlayer.url = this.playUrl
      }
      this.urlSet = true
      this.surfaceSet = false
      hilog.info(0x0000, 'tvhub', 'url set, waiting stateChange=initialized...')
      this.timeoutTimer = setTimeout(() => {
        if (!this.playing && this.errorMsg === '') {
          this.onErrorText('加载超时：该线路无法播放，请返回换线路/换源')
        }
      }, 20000)
    } catch (e) {
      this.onErrorText((e as Error).message ?? String(e))
    }
  }

  onStateChange(state: media.AVPlayerState): void {
    hilog.info(0x0000, 'tvhub', 'stateChange -> %{public}s', state)
    if (state === 'initialized' && this.urlSet && !this.surfaceSet) {
      this.surfaceSet = true
      try {
        if (this.avPlayer) {
          this.avPlayer.surfaceId = this.surfaceId
          hilog.info(0x0000, 'tvhub', 'surface set, prepare...')
          this.avPlayer.prepare().catch((e: BusinessError) => { this.onError(e) })
        }
      } catch (e) {
        this.onErrorText((e as Error).message ?? String(e))
      }
    } else if (state === 'prepared') {
      this.seekable = true
      // 关键修复：默认是 FIT（拉伸变形），必须显式应用当前比例模式
      this.applyScale()
      this.applyCurrentVolume()
      this.avPlayer?.play()
      if (this.pendingSeekMs >= 0 && this.avPlayer) {
        this.avPlayer.seek(this.pendingSeekMs, media.SeekMode.SEEK_CLOSEST)
        this.currentMs = this.pendingSeekMs
        this.pendingSeekMs = -1
      }
    } else if (state === 'playing') {
      this.playing = true
      this.saveHistory()
      this.loading = false
      this.clearTimeoutTimer()
      this.startProgress()
    } else if (state === 'paused') {
      this.playing = false
    } else if (state === 'completed') {
      this.playing = false
      this.stopProgress()
    } else if (state === 'error') {
      // 错误统一交给 onError 回调处理（重试/提示），避免与旧播放器 error 竞态互相覆盖
      this.playing = false
      this.stopProgress()
      this.seekable = false
      this.clearTimeoutTimer()
    }
  }

  // 统一应用画面比例（prepared 之后调用才生效；未 prepared 时只存状态）
  private applyScale(): void {
    if (!this.avPlayer) return
    try {
      if (this.scaleMode === 1) {
        this.avPlayer.videoScaleType = media.VideoScaleType.VIDEO_SCALE_TYPE_FIT_CROP
      } else if (this.scaleMode === 2) {
        this.avPlayer.videoScaleType = media.VideoScaleType.VIDEO_SCALE_TYPE_FIT
      } else {
        this.avPlayer.videoScaleType = media.VideoScaleType.VIDEO_SCALE_TYPE_SCALED_ASPECT
      }
      hilog.info(0x0000, 'tvhub', 'videoScaleType applied, mode=%{public}d', this.scaleMode)
    } catch (e) {
      hilog.warn(0x0000, 'tvhub', 'applyScale failed: %{public}s', String(e))
    }
  }

  onError(err: BusinessError): void {
    hilog.error(0x0000, 'tvhub', 'avplayer error code=%{public}d msg=%{public}s', err.code, err.message)
    if (this.retryCount < 1) {
      this.retryPlayback()
    } else {
      this.onErrorText('重试后仍播放失败(' + err.code + ')：' + err.message)
    }
  }

  private async retryPlayback(): Promise<void> {
    this.retryCount++
    hilog.info(0x0000, 'tvhub', 'retry #%{public}d url=%{public}s', this.retryCount, this.playUrl)
    try {
      if (this.avPlayer) {
        // 先解绑回调，避免旧播放器 error 事件干扰新播放器
        this.avPlayer.off('stateChange')
        this.avPlayer.off('error')
        this.avPlayer.release()
      }
    } catch (e) {
      // 释放失败忽略
    }
    this.avPlayer = null
    this.started = false
    this.seekable = false
    this.urlSet = false
    this.surfaceSet = false
    this.pendingSeekMs = this.currentMs
    this.clearTimeoutTimer()
    this.stopProgress()
    // 保留原 URL 和请求头重试；协议换写容易把可用 http 源改成不可用 https。
    await this.tryStart()
  }

  onErrorText(msg: string): void {
    this.clearTimeoutTimer()
    this.stopProgress()
    this.playing = false
    this.loading = false
    this.errorMsg = msg
  }

  private clearTimeoutTimer(): void {
    if (this.timeoutTimer >= 0) {
      clearTimeout(this.timeoutTimer)
      this.timeoutTimer = -1
    }
  }

  private saveHistory(): void {
    if (this.historySaved || !app.currentHistory) return
    this.historySaved = true
    app.currentHistory.time = Date.now()
    app.addHistory(app.currentHistory).catch(() => {})
  }

  startProgress(): void {
    if (this.progressTimer >= 0) return
    this.progressTimer = setInterval(() => {
      if (this.avPlayer) {
        this.currentMs = this.avPlayer.currentTime
        this.durationMs = this.avPlayer.duration
      }
    }, CONFIG.PROGRESS_UPDATE_INTERVAL_MS)

    // 启动自动保存进度定时器
    if (this.autoSaveTimer < 0) {
      this.autoSaveTimer = setInterval(() => {
        this.savePlayProgress()
      }, CONFIG.AUTO_SAVE_PROGRESS_INTERVAL_MS)
    }
  }

  stopProgress(): void {
    if (this.progressTimer >= 0) {
      clearInterval(this.progressTimer)
      this.progressTimer = -1
    }
    if (this.autoSaveTimer >= 0) {
      clearInterval(this.autoSaveTimer)
      this.autoSaveTimer = -1
    }
  }

  private savePlayProgress(): void {
    if (!app.currentHistory || !this.playing) return
    if (this.currentMs < 5000) return  // 前 5 秒不保存
    if (this.durationMs > 0 && this.currentMs > this.durationMs * 0.95) {
      // 播放超过 95% 视为看完，清除进度
      app.currentHistory.lastPlayMs = undefined
      app.currentHistory.episodeUrl = undefined
    } else {
      app.currentHistory.lastPlayMs = this.currentMs
      app.currentHistory.episodeUrl = app.currentEpUrl
    }
    app.addHistory(app.currentHistory).catch(() => {})
  }

  togglePlay(): void {
    if (this.locked) return
    if (!this.avPlayer) return
    if (this.playing) {
      this.avPlayer.pause()
    } else {
      this.avPlayer.play()
    }
  }

  onSeek(value: number): void {
    if (this.locked) return
    this.currentMs = value
    if (this.avPlayer && this.seekable) {
      this.avPlayer.seek(value, media.SeekMode.SEEK_CLOSEST)
    } else {
      this.pendingSeekMs = value
    }
  }

  // 相对位移：pct 为总时长的比例（快进 +0.01 / 后退 -0.01 即每次 1%）
  seekRelative(pct: number): void {
    if (this.locked) return
    const total: number = this.durationMs > 0 ? this.durationMs : 60000
    let target: number = this.currentMs + total * pct
    if (target < 0) {
      target = 0
    }
    if (this.durationMs > 0 && target > this.durationMs) {
      target = this.durationMs
    }
    this.onSeek(target)
    this.toast((pct >= 0 ? '快进 ' : '后退 ') + Math.abs(Math.round(pct * 100)) + '%')
  }

  private toSpeedEnum(s: number): media.PlaybackSpeed {
    if (s === 0.5) { return media.PlaybackSpeed.SPEED_FORWARD_0_50_X }
    if (s === 0.75) { return media.PlaybackSpeed.SPEED_FORWARD_0_75_X }
    if (s === 1.25) { return media.PlaybackSpeed.SPEED_FORWARD_1_25_X }
    if (s === 1.5) { return media.PlaybackSpeed.SPEED_FORWARD_1_50_X }
    if (s === 2) { return media.PlaybackSpeed.SPEED_FORWARD_2_00_X }
    return media.PlaybackSpeed.SPEED_FORWARD_1_00_X
  }

  private fmt(ms: number): string {
    const total = Math.floor(ms / 1000)
    const h = Math.floor(total / 3600)
    const m = Math.floor((total % 3600) / 60)
    const s = total % 60
    const mm = m < 10 ? '0' + m : String(m)
    const ss = s < 10 ? '0' + s : String(s)
    return h > 0 ? `${h}:${mm}:${ss}` : `${m}:${ss}`
  }

  scaleName(mode: number): string {
    if (mode === 1) return '裁剪填充'
    if (mode === 2) return '拉伸铺满'
    return '保持比例'
  }

  scaleLabel(): string {
    return this.scaleName(this.scaleMode)
  }

  private clampValue(value: number, min: number, max: number): number {
    return Math.min(max, Math.max(min, value))
  }

  private applyCurrentVolume(): void {
    if (!this.avPlayer) return
    this.avPlayer.setVolume(this.volumeValue)
  }

  private adjustVolume(deltaVp: number): void {
    if (this.locked) return
    const next: number = this.clampValue(this.volumeValue - deltaVp / 300, 0, 1)
    if (next === this.volumeValue) return
    this.volumeValue = next
    this.applyCurrentVolume()
    this.gestureHint = '音量 ' + Math.round(next * 100) + '%'
  }

  private async adjustBrightness(deltaVp: number): Promise<void> {
    if (this.locked) return
    const hostCtx = this.getUIContext().getHostContext()
    if (!hostCtx) return
    const win = await window.getLastWindow(hostCtx)
    if (this.brightnessValue < 0) {
      const current: number = win.getWindowProperties().brightness
      this.brightnessValue = current > 0 ? current : 0.5
      this.previousBrightness = this.brightnessValue
    }
    const next: number = this.clampValue(this.brightnessValue - deltaVp / 300, 0.05, 1)
    if (next === this.brightnessValue) return
    this.brightnessValue = next
    await win.setWindowBrightness(next)
    this.gestureHint = '亮度 ' + Math.round(next * 100) + '%'
  }

  private adjustBrightnessSafe(deltaVp: number): void {
    this.adjustBrightness(deltaVp).catch(() => {})
  }

  private restoreBrightness(): void {
    if (this.previousBrightness < 0) return
    const value: number = this.previousBrightness
    this.previousBrightness = -1
    this.brightnessValue = -1
    const hostCtx = this.getUIContext().getHostContext()
    if (!hostCtx) return
    window.getLastWindow(hostCtx).then((win: window.Window) => {
      return win.setWindowBrightness(value)
    }).catch(() => {})
  }

  private onSeekPanStart(): void {
    if (this.locked) return
    this.panStartMs = this.currentMs
    this.seekPreviewMs = this.currentMs
    this.updateSeekHint(this.currentMs)
  }

  private onSeekPanUpdate(offsetX: number): void {
    if (this.locked) return
    const total: number = this.durationMs > 0 ? this.durationMs : 60000
    const width: number = (this.videoAreaWidth > 1 ? this.videoAreaWidth : 1) * 0.44
    const target: number = this.clampValue(this.panStartMs + offsetX / width * total, 0, total)
    this.seekPreviewMs = target
    this.updateSeekHint(target)
  }

  private onSeekPanEnd(): void {
    if (this.locked) return
    if (this.seekPreviewMs >= 0) {
      this.onSeek(this.seekPreviewMs)
    }
    this.seekPreviewMs = -1
    this.gestureHint = ''
  }

  private updateSeekHint(target: number): void {
    this.gestureHint = this.fmt(target) + ' / ' + this.fmt(this.durationMs > 0 ? this.durationMs : 60000)
  }

  private onDoubleTap(zone: string): void {
    if (this.locked) return
    if (zone === 'left') {
      this.seekRelative(-0.01)
    } else if (zone === 'right') {
      this.seekRelative(0.01)
    } else {
      this.togglePlay()
    }
  }

  private toggleLock(): void {
    this.locked = !this.locked
    this.pickerMode = 'none'
    this.controlsVisible = true
    if (this.locked) {
      this.cancelHideControls()
      this.toast('已锁定，点击解锁继续操作')
    } else {
      this.scheduleHideControls()
      this.toast('已解锁')
    }
  }

  private showPicker(mode: string): void {
    if (this.locked) return
    this.pickerMode = mode
    this.controlsVisible = true
    this.cancelHideControls()
  }

  private closePicker(): void {
    const wasOpen: boolean = this.pickerMode !== 'none'
    this.pickerMode = 'none'
    if (wasOpen && this.isFullscreen) {
      this.scheduleHideControls()
    }
  }

  private chooseSpeed(speed: number): void {
    this.playbackSpeed = speed
    if (this.avPlayer) {
      this.avPlayer.setSpeed(this.toSpeedEnum(speed))
    }
    // 保存偏好设置
    this.playerPreferenceService.setSpeed(speed).catch(() => {})
    this.closePicker()
    this.toast('倍速 ' + speed.toFixed(2).replace(/0$/, '') + 'x')
  }

  private chooseScale(mode: number): void {
    this.scaleMode = mode
    this.applyScale()
    // 保存偏好设置
    this.playerPreferenceService.setScaleMode(mode).catch(() => {})
    this.closePicker()
    this.toast('画面比例：' + this.scaleName(mode))
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message })
    } catch (e) {
      // toast is best-effort UI feedback.
    }
  }

  @Builder
  gestureLayer() {
    Row() {
      Column()
        .width('28%')
        .height('100%')
        .gesture(
          GestureGroup(GestureMode.Exclusive,
            PanGesture({ direction: PanDirection.Vertical, distance: 8 })
              .onActionUpdate((event: GestureEvent) => { this.adjustBrightness(event.offsetY) })
              .onActionEnd(() => { this.gestureHint = '' }),
            TapGesture({ count: 2 }).onAction(() => { this.onDoubleTap('left') })
          )
        )
      Column()
        .width('44%')
        .height('100%')
        .gesture(
          GestureGroup(GestureMode.Exclusive,
            PanGesture({ direction: PanDirection.Horizontal, distance: 8 })
              .onActionStart(() => { this.onSeekPanStart() })
              .onActionUpdate((event: GestureEvent) => { this.onSeekPanUpdate(event.offsetX) })
              .onActionEnd(() => { this.onSeekPanEnd() }),
            GestureGroup(GestureMode.Exclusive,
              TapGesture({ count: 2 }).onAction(() => { this.onDoubleTap('center') }),
              TapGesture().onAction(() => { this.tapSurface() })
            )
          )
        )
      Column()
        .width('28%')
        .height('100%')
        .gesture(
          GestureGroup(GestureMode.Exclusive,
            PanGesture({ direction: PanDirection.Vertical, distance: 8 })
              .onActionUpdate((event: GestureEvent) => { this.adjustVolume(event.offsetY) })
              .onActionEnd(() => { this.gestureHint = '' }),
            TapGesture({ count: 2 }).onAction(() => { this.onDoubleTap('right') })
          )
        )
    }
    .width('100%')
    .height('100%')
    .zIndex(3)
  }

  @Builder
  gestureFeedback() {
    if (this.gestureHint.length > 0) {
      Text(this.gestureHint)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)
        .padding({ left: 12, right: 12, top: 7, bottom: 7 })
        .backgroundColor('#B3000000')
        .borderRadius(16)
        .position({ x: 0, y: this.isFullscreen ? 78 : 30 })
        .hitTestBehavior(HitTestMode.None)
        .zIndex(7)
    }
  }

  @Builder
  pickerOverlay() {
    if (this.pickerMode !== 'none') {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#33000000')
        .position({ x: 0, y: 0 })
        .onClick(() => { this.closePicker() })
        .zIndex(7)

      Column({ space: 4 }) {
        Text(this.pickerMode === 'speed' ? '倍速' : '画面比例')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.theme_text_title'))
          .padding({ top: 6, bottom: 4 })
        if (this.pickerMode === 'speed') {
          ForEach(SPEEDS, (speed: number) => {
            Row() {
              Text(speed.toFixed(2).replace(/0$/, '') + 'x').fontSize(14).fontColor($r('app.color.theme_text_secondary'))
              Blank()
              if (this.playbackSpeed === speed) {
                Text('当前').fontSize(12).fontColor($r('app.color.theme_link'))
              }
            }
            .width('100%')
            .padding(12)
            .backgroundColor(this.playbackSpeed === speed ? $r('app.color.theme_accent_translucent') : '#00000000')
            .borderRadius(10)
            .onClick(() => { this.chooseSpeed(speed) })
          }, (speed: number) => speed.toString())
        } else {
          ForEach(SCALE_MODES, (mode: number) => {
            Row() {
              Text(this.scaleName(mode)).fontSize(14).fontColor($r('app.color.theme_text_secondary'))
              Blank()
              if (this.scaleMode === mode) {
                Text('当前').fontSize(12).fontColor($r('app.color.theme_link'))
              }
            }
            .width('100%')
            .padding(12)
            .backgroundColor(this.scaleMode === mode ? $r('app.color.theme_accent_translucent') : '#00000000')
            .borderRadius(10)
            .onClick(() => { this.chooseScale(mode) })
          }, (mode: number) => mode.toString())
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 14 })
      .backgroundColor($r('app.color.theme_sheet'))
      .borderRadius({ topLeft: 18, topRight: 18 })
      .zIndex(8)
    }
  }

  @Builder
  videoOverlays() {
    if (this.loading) {
      Column() {
        LoadingProgress().width(40).height(40).color('#FFFFFF')
        Text('播放中…').fontSize(13).fontColor($r('app.color.theme_text_video')).margin({ top: 10 })
      }.width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor('#99000000')
    }
    if (this.errorMsg.length > 0) {
      Column() {
        Text(this.errorMsg)
          .fontSize(13)
          .fontColor('#FFFFFF')
          .textAlign(TextAlign.Center)
          .padding(16)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#B3000000')
    }
  }

  // 两行控制条：进度条独占一行（全宽好拖）+ 按钮一行；通透玻璃（iOS 风）
  @Builder
  controlBar() {
    Column({ space: 2 }) {
      // ── 行1：进度条（独立全宽，不再被按钮挤压） ──
      Row({ space: 8 }) {
        Text(this.fmt(this.currentMs)).fontSize(11).fontColor($r('app.color.theme_text_secondary'))
        Slider({ value: this.currentMs, min: 0, max: this.durationMs > 0 ? this.durationMs : 1, style: SliderStyle.OutSet })
          .layoutWeight(1)
          .height(40)
          .blockColor('#FFFFFF')
          .selectedColor($r('app.color.theme_accent'))
          .trackColor($r('app.color.theme_overlay_light_33'))
          .enabled(!this.locked)
          .onChange((v: number, mode: SliderChangeMode) => {
            this.currentMs = v
            if (mode === SliderChangeMode.End) this.onSeek(v)
          })
        Text(this.fmt(this.durationMs)).fontSize(11).fontColor($r('app.color.theme_text_secondary'))
      }
      .width('100%')

      // ── 行2：按钮 ──
      Row({ space: 10 }) {
        // 后退 -1%
        Text('⟲').fontSize(22).fontColor('#FFFFFF').onClick(() => { this.seekRelative(-0.01) })
        // 播放/暂停
        Image(this.playing ? $r('app.media.pause_icon') : $r('app.media.play_icon'))
          .width(30).height(30)
          .fillColor('#FFFFFF')
          .onClick(() => { this.togglePlay() })
        // 快进 +1%
        Text('⟳').fontSize(22).fontColor('#FFFFFF').onClick(() => { this.seekRelative(0.01) })

        Blank()

        // 锁定按钮始终可点；锁定后其他控制由方法内部拦截。
        Text(this.locked ? '解锁' : '锁定')
          .fontSize(12)
          .fontColor(this.locked ? $r('app.color.theme_lock') : '#FFFFFF')
          .padding({ left: 9, right: 9, top: 5, bottom: 5 })
          .backgroundColor(this.locked ? $r('app.color.theme_lock_translucent') : $r('app.color.theme_overlay_light_26'))
          .borderRadius(8)
          .onClick(() => { this.toggleLock() })
        // 倍速
        Text(this.playbackSpeed.toFixed(1) + 'x')
          .fontSize(12)
          .fontColor('#FFFFFF')
          .padding({ left: 9, right: 9, top: 5, bottom: 5 })
          .backgroundColor($r('app.color.theme_overlay_light_26'))
          .borderRadius(8)
          .onClick(() => { this.showPicker('speed') })
        // 画面比例
        Text(this.scaleLabel())
          .fontSize(12)
          .fontColor('#FFFFFF')
          .padding({ left: 9, right: 9, top: 5, bottom: 5 })
          .backgroundColor($r('app.color.theme_overlay_light_26'))
          .borderRadius(8)
          .onClick(() => { this.showPicker('scale') })
        // 全屏
        Image(this.isFullscreen ? $r('app.media.exit_fullscreen_icon') : $r('app.media.fullscreen_icon'))
          .width(24).height(24)
          .fillColor('#FFFFFF')
          .onClick(() => { this.toggleFullscreen() })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 14, right: 12, top: 8, bottom: this.isFullscreen ? 18 : 8 })
    .linearGradient({ angle: 180, colors: [['#00000000', 0], ['#B3000000', 1]] })
    .zIndex(5)
  }

  build() {
    NavDestination() {
      Column() {
        // 小屏顶栏
        if (!this.isFullscreen) {
          Row() {
            Text('‹').fontSize(30).fontColor($r('app.color.theme_text_secondary')).width(36).onClick(() => { app.pathStack.pop() })
            Text(this.title).fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.theme_text_title')).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            Image($r('app.media.fullscreen_icon')).width(22).height(22).fillColor($r('app.color.theme_accent'))
              .margin({ right: 8 })
              .onClick(() => { this.toggleFullscreen() })
          }
          .width('100%')
          .padding({ left: 8, right: 8, top: 10, bottom: 6 })
        }

        // 视频容器（全屏时延伸到状态栏/手势条下 = 真全屏）
        Stack({ alignContent: Alignment.Bottom }) {
          XComponent({ id: 'video_surface', type: XComponentType.SURFACE, controller: this.xComponentController })
            .width('100%')
            .height('100%')
            .onLoad(() => { this.onSurfaceReady() })

          this.gestureLayer()

          this.videoOverlays()
          if (this.controlsVisible || !this.isFullscreen) {
            this.controlBar()
          }

          // 全屏顶栏 overlay：返回 = 先退出全屏回小屏
          if (this.isFullscreen && this.controlsVisible) {
            Row() {
              Text('‹').fontSize(30).fontColor('#FFFFFF').width(44).textAlign(TextAlign.Center)
                .onClick(() => { this.toggleFullscreen() })
              Text(this.title).fontSize(15).fontColor('#FFFFFF').maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
              Image($r('app.media.exit_fullscreen_icon')).width(24).height(24).fillColor('#FFFFFF')
                .padding(10)
                .onClick(() => { this.toggleFullscreen() })
            }
            .width('100%')
            .height(58)
            .padding({ left: 10, right: 10, top: 10 })
            .linearGradient({ angle: 180, colors: [['#99000000', 0], ['#00000000', 1]] })
            .position({ x: 0, y: 0 })
            .zIndex(6)
          }

          this.pickerOverlay()
          this.gestureFeedback()
        }
        .width('100%')
        .height(this.isFullscreen ? '100%' : SMALL_VIDEO_HEIGHT)
        .backgroundColor('#000000')
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          this.videoAreaWidth = Number(newArea.width)
        })
        .expandSafeArea(this.isFullscreen ? [SafeAreaType.SYSTEM] : [], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 小屏下方信息区
        if (!this.isFullscreen) {
          Column({ space: 6 }) {
            Text(this.title).fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.theme_text_title'))
            Text('比例默认保持·全屏点画面显隐控制条').fontSize(12).fontColor($r('app.color.theme_text_dim'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 16, right: 16, top: 14 })
          Blank()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.theme_background'))
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.theme_background'))
  }
}
