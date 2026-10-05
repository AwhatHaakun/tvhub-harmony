/**
 * 下载管理页面
 */

import { app } from './AppState'
import { DownloadTask } from './services/DownloadService'

@Component
export struct DownloadPage {
  @State tasks: DownloadTask[] = []
  @State selectedTab: number = 0  // 0=全部 1=下载中 2=已完成

  private listener = (tasks: DownloadTask[]) => {
    this.tasks = tasks
  }

  async aboutToAppear(): Promise<void> {
    app.downloadService.addListener(this.listener)
    this.tasks = app.downloadService.getAllTasks()
  }

  aboutToDisappear(): void {
    app.downloadService.removeListener(this.listener)
  }

  private getFilteredTasks(): DownloadTask[] {
    if (this.selectedTab === 1) {
      return this.tasks.filter(t => t.status === 'downloading' || t.status === 'pending')
    } else if (this.selectedTab === 2) {
      return this.tasks.filter(t => t.status === 'completed')
    }
    return this.tasks
  }

  private formatSize(bytes: number): string {
    if (bytes === 0) return '0 B'
    const k = 1024
    const sizes = ['B', 'KB', 'MB', 'GB']
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    return (bytes / Math.pow(k, i)).toFixed(2) + ' ' + sizes[i]
  }

  private formatTime(timestamp: number): string {
    const date = new Date(timestamp)
    const now = new Date()
    const diff = now.getTime() - date.getTime()
    if (diff < 60000) return '刚刚'
    if (diff < 3600000) return Math.floor(diff / 60000) + ' 分钟前'
    if (diff < 86400000) return Math.floor(diff / 3600000) + ' 小时前'
    return `${date.getMonth() + 1}-${date.getDate()} ${date.getHours()}:${date.getMinutes().toString().padStart(2, '0')}`
  }

  private statusText(status: string): string {
    switch (status) {
      case 'pending': return '等待中'
      case 'downloading': return '下载中'
      case 'paused': return '已暂停'
      case 'completed': return '已完成'
      case 'failed': return '失败'
      default: return status
    }
  }

  private statusColor(status: string): ResourceStr {
    switch (status) {
      case 'downloading': return $r('app.color.theme_accent')
      case 'completed': return $r('app.color.theme_success')
      case 'failed': return $r('app.color.theme_error')
      default: return $r('app.color.theme_text_dim')
    }
  }

  build() {
    NavDestination() {
      Column() {
        // 顶栏
        Row() {
          Text('‹')
            .fontSize(30)
            .fontColor($r('app.color.theme_text_secondary'))
            .width(36)
            .onClick(() => { app.pathStack.pop() })
          Text('下载管理')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.theme_text_title'))
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 8, right: 16, top: 10, bottom: 10 })

        // Tab 切换
        Row({ space: 12 }) {
          Text('全部')
            .fontSize(14)
            .fontColor(this.selectedTab === 0 ? '#FFFFFF' : $r('app.color.theme_text_muted'))
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .backgroundColor(this.selectedTab === 0 ? $r('app.color.theme_accent') : $r('app.color.theme_surface_alt'))
            .borderRadius(16)
            .onClick(() => { this.selectedTab = 0 })
          Text('下载中')
            .fontSize(14)
            .fontColor(this.selectedTab === 1 ? '#FFFFFF' : $r('app.color.theme_text_muted'))
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .backgroundColor(this.selectedTab === 1 ? $r('app.color.theme_accent') : $r('app.color.theme_surface_alt'))
            .borderRadius(16)
            .onClick(() => { this.selectedTab = 1 })
          Text('已完成')
            .fontSize(14)
            .fontColor(this.selectedTab === 2 ? '#FFFFFF' : $r('app.color.theme_text_muted'))
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .backgroundColor(this.selectedTab === 2 ? $r('app.color.theme_accent') : $r('app.color.theme_surface_alt'))
            .borderRadius(16)
            .onClick(() => { this.selectedTab = 2 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10 })

        // 任务列表
        if (this.getFilteredTasks().length === 0) {
          Column({ space: 12 }) {
            Text('📥').fontSize(40)
            Text('暂无下载任务').fontSize(14).fontColor($r('app.color.theme_text_dim'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 12 }) {
            ForEach(this.getFilteredTasks(), (task: DownloadTask) => {
              ListItem() {
                Column({ space: 8 }) {
                  Row() {
                    Column({ space: 4 }) {
                      Text(task.vodName)
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.theme_text_title'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(task.episodeName)
                        .fontSize(13)
                        .fontColor($r('app.color.theme_text_muted'))
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    Text(this.statusText(task.status))
                      .fontSize(12)
                      .fontColor(this.statusColor(task.status))
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                      .backgroundColor($r('app.color.theme_surface_alt'))
                      .borderRadius(10)
                  }
                  .width('100%')

                  // 进度条
                  if (task.status === 'downloading' || task.status === 'paused') {
                    Column({ space: 4 }) {
                      Progress({ value: task.progress, total: 100, type: ProgressType.Linear })
                        .width('100%')
                        .height(4)
                        .color($r('app.color.theme_accent'))
                        .backgroundColor($r('app.color.theme_surface_alt'))
                      Row() {
                        Text(task.progress + '%')
                          .fontSize(11)
                          .fontColor($r('app.color.theme_text_dim'))
                        Blank()
                        if (task.totalSize > 0) {
                          Text(this.formatSize(task.downloadedSize) + ' / ' + this.formatSize(task.totalSize))
                            .fontSize(11)
                            .fontColor($r('app.color.theme_text_dim'))
                        }
                      }
                      .width('100%')
                    }
                  }

                  // 操作按钮
                  Row({ space: 8 }) {
                    Text(this.formatTime(task.createdTime))
                      .fontSize(11)
                      .fontColor($r('app.color.theme_text_placeholder'))
                      .layoutWeight(1)

                    if (task.status === 'downloading') {
                      Text('暂停')
                        .fontSize(12)
                        .fontColor($r('app.color.theme_warning'))
                        .onClick(() => {
                          app.downloadService.pauseDownload(task.id)
                        })
                    } else if (task.status === 'paused') {
                      Text('继续')
                        .fontSize(12)
                        .fontColor($r('app.color.theme_accent'))
                        .onClick(() => {
                          app.downloadService.resumeDownload(task.id)
                        })
                    }

                    Text('删除')
                      .fontSize(12)
                      .fontColor($r('app.color.theme_error'))
                      .onClick(() => {
                        app.downloadService.deleteDownload(task.id)
                      })
                  }
                  .width('100%')

                  if (task.error) {
                    Text('错误：' + task.error)
                      .fontSize(11)
                      .fontColor($r('app.color.theme_error'))
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                }
                .width('100%')
                .padding(14)
                .backgroundColor($r('app.color.theme_card'))
                .borderRadius(12)
              }
            }, (task: DownloadTask) => task.id)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16, top: 10, bottom: 16 })
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
