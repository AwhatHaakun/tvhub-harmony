// Index.ets —— 应用入口：Navigation 容器 + 页面路由
// 主壳 HomePage 内置底部 Tab（首页/搜索/历史/收藏/设置）；
// 压栈页仅剩：Detail（详情/选集）→ Player（播放）、Verify（Web 验证）
//
// 放在工程 entry/src/main/ets/pages/Index.ets

import { app } from '../AppState'
import { HomePage } from '../HomePage'
import { DetailPage } from '../DetailPage'
import { PlayerPage } from '../PlayerPage'
import { VerifyPage } from '../VerifyPage'
import { SourcePickerPage } from '../SourcePickerPage'
import { SourceManagePage } from '../SourceManagePage'
import { SnifferPage } from '../SnifferPage'
import { SettingsAddExtensionPage, SettingsConfigPage, SettingsPanPage, SettingsSourcesPage, SettingsThemePage } from '../SettingsSubPages'

@Entry
@Component
struct Index {
  @Builder
  PageMap(name: string) {
    if (name === 'Detail') {
      DetailPage()
    } else if (name === 'Player') {
      PlayerPage()
    } else if (name === 'Verify') {
      VerifyPage()
    } else if (name === 'SourcePicker') {
      SourcePickerPage()
    } else if (name === 'SourceManage') {
      SourceManagePage()
    } else if (name === 'Sniffer') {
      SnifferPage()
    } else if (name === 'SettingsConfig') {
      SettingsConfigPage()
    } else if (name === 'SettingsSources') {
      SettingsSourcesPage()
    } else if (name === 'SettingsPan') {
      SettingsPanPage()
    } else if (name === 'SettingsAddExtension') {
      SettingsAddExtensionPage()
    } else if (name === 'SettingsTheme') {
      SettingsThemePage()
    }
  }

  aboutToAppear(): void {
    // 扩展 goToVerify / openWebToBindEnv 时，压入 Web 验证页
    // （同一时刻最多一个；扩展是串行 await，verifyPending 防重入）
    app.onVerifyNeeded = () => {
      if (app.verifyPending) {
        app.verifyPending = false // 消费掉，防止重复 push
        app.pathStack.pushPathByName('Verify', '')
      }
    }
  }

  aboutToDisappear(): void {
    app.onVerifyNeeded = null
    app.dispose()
  }

  build() {
    Navigation(app.pathStack) {
      HomePage()
    }
    .navDestination(this.PageMap)
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .backgroundColor($r('app.color.theme_background'))
  }
}
