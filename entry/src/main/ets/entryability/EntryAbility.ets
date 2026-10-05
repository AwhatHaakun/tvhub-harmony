// EntryAbility.ets —— 应用入口（标准 Empty Ability 模板，无改动）
// 放在工程 entry/src/main/ets/entryability/EntryAbility.ets

import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'tvhub', 'Ability onCreate')
  }

  onDestroy(): void {
    hilog.info(0x0000, 'tvhub', 'Ability onDestroy')
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'tvhub', 'loadContent failed: %{public}s', JSON.stringify(err))
        return
      }
      hilog.info(0x0000, 'tvhub', 'loadContent succeeded')
    })
  }

  onWindowStageDestroy(): void {}

  onForeground(): void {}

  onBackground(): void {}
}