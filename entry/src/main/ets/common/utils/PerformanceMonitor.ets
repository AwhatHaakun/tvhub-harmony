/**
 * 性能监控工具
 */

import { hilog } from '@kit.PerformanceAnalysisKit'

interface PerformanceMark {
  label: string
  timestamp: number
}

export class PerformanceMonitor {
  private static marks: Map<string, PerformanceMark> = new Map()

  static mark(label: string): void {
    const timestamp = Date.now()
    PerformanceMonitor.marks.set(label, { label, timestamp })
    hilog.debug(0x0000, 'perf', '[MARK] %{public}s at %{public}d', label, timestamp)
  }

  static measure(startLabel: string, endLabel: string): number {
    const start = PerformanceMonitor.marks.get(startLabel)
    const end = PerformanceMonitor.marks.get(endLabel)

    if (!start || !end) {
      hilog.warn(0x0000, 'perf', 'Missing marks for measurement: %{public}s -> %{public}s', startLabel, endLabel)
      return -1
    }

    const duration = end.timestamp - start.timestamp
    hilog.info(0x0000, 'perf', '[MEASURE] %{public}s -> %{public}s: %{public}dms',
      startLabel, endLabel, duration)

    return duration
  }

  static clear(label?: string): void {
    if (label) {
      PerformanceMonitor.marks.delete(label)
    } else {
      PerformanceMonitor.marks.clear()
    }
  }
}
