/**
 * 下载服务
 */

import { request } from '@kit.BasicServicesKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { common } from '@kit.AbilityKit'
import { CONFIG } from '../common/constants/Config'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { HostBridge } from '../HostBridge'

export interface DownloadTask {
  id: string
  vodName: string
  episodeName: string
  url: string
  filePath: string
  status: 'pending' | 'downloading' | 'paused' | 'completed' | 'failed'
  progress: number  // 0-100
  totalSize: number
  downloadedSize: number
  createdTime: number
  completedTime?: number
  error?: string
}

export class DownloadService {
  private host: HostBridge
  private ctx: common.Context | null = null
  private tasks: Map<string, DownloadTask> = new Map()
  private activeDownloads: Map<string, request.agent.Task> = new Map()
  private listeners: Set<(tasks: DownloadTask[]) => void> = new Set()

  constructor(host: HostBridge) {
    this.host = host
  }

  async init(ctx: common.Context): Promise<void> {
    this.ctx = ctx
    await this.loadTasks()
  }

  private async loadTasks(): Promise<void> {
    const raw = await this.host.getRaw(CONFIG.KEYS.DOWNLOADS)
    if (!raw || raw === '') return
    try {
      const list = JSON.parse(raw) as DownloadTask[]
      list.forEach(task => {
        this.tasks.set(task.id, task)
      })
    } catch (e) {
      hilog.error(0x0000, 'tvhub', 'Failed to load download tasks: %{public}s', String(e))
    }
  }

  private async saveTasks(): Promise<void> {
    const list = Array.from(this.tasks.values())
    await this.host.setRaw(CONFIG.KEYS.DOWNLOADS, JSON.stringify(list))
    this.notifyListeners()
  }

  async createDownload(vodName: string, episodeName: string, url: string): Promise<string> {
    if (!this.ctx) throw new Error('DownloadService not initialized')

    const id = 'dl_' + Date.now() + '_' + Math.random().toString(36).slice(2, 9)
    const fileName = this.sanitizeFileName(`${vodName}_${episodeName}.mp4`)
    const downloadDir = `${this.ctx.filesDir}/downloads`

    // 确保下载目录存在
    try {
      fs.mkdirSync(downloadDir, true)
    } catch (e) {
      // 目录可能已存在
    }

    const filePath = `${downloadDir}/${fileName}`

    const task: DownloadTask = {
      id,
      vodName,
      episodeName,
      url,
      filePath,
      status: 'pending',
      progress: 0,
      totalSize: 0,
      downloadedSize: 0,
      createdTime: Date.now()
    }

    this.tasks.set(id, task)
    await this.saveTasks()

    // 自动开始下载
    this.startDownload(id).catch((e: Error) => {
      hilog.error(0x0000, 'tvhub', 'Auto-start download failed: %{public}s', String(e))
    })

    return id
  }

  async startDownload(id: string): Promise<void> {
    const task = this.tasks.get(id)
    if (!task) throw new Error('Download task not found')
    if (task.status === 'downloading') return
    if (task.status === 'completed') return

    // 检查并发限制
    if (this.activeDownloads.size >= CONFIG.DOWNLOAD.MAX_CONCURRENT) {
      task.status = 'pending'
      await this.saveTasks()
      return
    }

    task.status = 'downloading'
    task.error = undefined
    await this.saveTasks()

    try {
      const config: request.agent.Config = {
        action: request.agent.Action.DOWNLOAD,
        url: task.url,
        saveas: task.filePath,
        method: 'GET',
        mode: request.agent.Mode.FOREGROUND,
        overwrite: true
      }

      const downloadTask = await request.agent.create(this.ctx!, config)

      this.activeDownloads.set(id, downloadTask)

      // 监听进度
      downloadTask.on('progress', (progress: request.agent.Progress) => {
        task.progress = Math.floor(progress.processed / progress.sizes[0] * 100)
        task.downloadedSize = progress.processed
        this.notifyListeners()
      })

      // 监听完成
      downloadTask.on('completed', () => {
        task.status = 'completed'
        task.progress = 100
        task.completedTime = Date.now()
        this.activeDownloads.delete(id)
        this.saveTasks()
        this.startNextPending()
      })

      // 监听失败
      downloadTask.on('failed', (progress: request.agent.Progress) => {
        task.status = 'failed'
        task.error = `Download failed`
        this.activeDownloads.delete(id)
        this.saveTasks()
        this.startNextPending()
      })

      await downloadTask.start()

    } catch (e) {
      task.status = 'failed'
      task.error = (e as Error).message ?? String(e)
      this.activeDownloads.delete(id)
      await this.saveTasks()
    }
  }

  private startNextPending(): void {
    const entries = Array.from(this.tasks.entries())
    for (let i = 0; i < entries.length; i++) {
      const id = entries[i][0]
      const task = entries[i][1]
      if (task.status === 'pending' && this.activeDownloads.size < CONFIG.DOWNLOAD.MAX_CONCURRENT) {
        this.startDownload(id).catch((e: Error) => {
          hilog.error(0x0000, 'tvhub', 'Start next download failed: %{public}s', String(e))
        })
        break
      }
    }
  }

  async pauseDownload(id: string): Promise<void> {
    const task = this.tasks.get(id)
    if (!task) return
    if (task.status !== 'downloading') return

    const downloadTask = this.activeDownloads.get(id)
    if (downloadTask) {
      try {
        await downloadTask.pause()
        task.status = 'paused'
        this.activeDownloads.delete(id)
        await this.saveTasks()
        this.startNextPending()
      } catch (e) {
        hilog.error(0x0000, 'tvhub', 'Pause download failed: %{public}s', String(e))
      }
    }
  }

  async resumeDownload(id: string): Promise<void> {
    const task = this.tasks.get(id)
    if (!task) return
    if (task.status !== 'paused') return

    await this.startDownload(id)
  }

  async deleteDownload(id: string): Promise<void> {
    const task = this.tasks.get(id)
    if (!task) return

    // 停止下载
    const downloadTask = this.activeDownloads.get(id)
    if (downloadTask) {
      try {
        await downloadTask.pause()
      } catch (e) {
        hilog.error(0x0000, 'tvhub', 'Pause download task failed: %{public}s', String(e))
      }
      this.activeDownloads.delete(id)
    }

    // 删除文件
    try {
      if (fs.accessSync(task.filePath)) {
        fs.unlinkSync(task.filePath)
      }
    } catch (e) {
      hilog.error(0x0000, 'tvhub', 'Delete file failed: %{public}s', String(e))
    }

    // 删除任务记录
    this.tasks.delete(id)
    await this.saveTasks()
    this.startNextPending()
  }

  getAllTasks(): DownloadTask[] {
    return Array.from(this.tasks.values()).sort((a, b) => b.createdTime - a.createdTime)
  }

  getTask(id: string): DownloadTask | undefined {
    return this.tasks.get(id)
  }

  addListener(fn: (tasks: DownloadTask[]) => void): void {
    this.listeners.add(fn)
  }

  removeListener(fn: (tasks: DownloadTask[]) => void): void {
    this.listeners.delete(fn)
  }

  private notifyListeners(): void {
    const tasks = this.getAllTasks()
    this.listeners.forEach(fn => fn(tasks))
  }

  private sanitizeFileName(name: string): string {
    return name
      .replace(/[<>:"/\\|?*]/g, '_')
      .replace(/\s+/g, '_')
      .slice(0, 200)
  }
}
