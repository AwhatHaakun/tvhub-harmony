// JSExecutor.ets —— QuickJS 引擎的 ArkTS 封装层
// 负责：初始化、加载拼接脚本、调用扩展方法、桥接 sendMessage 请求与结果回传。

import quickjs from 'libquickjs.so'
import { HostBridge } from './HostBridge'

/**
 * 扩展方法调用结果回调类型。
 */
export type CallResultHandler = (resultJson: string) => void

/**
 * 错误 ProData（catch 分支构造，对应 ProData 结构）。
 */
interface ErrorProData {
  error: string
  data: string | null
  headers: Record<string, string>
  code: number
  redirects: string[]
}

/**
 * JSExecutor：封装 libquickjs.so 的 5 个 native 函数（init/load/call/resolve/dispose）。
 * 线程模型：所有调用在 ArkTS 主线程；网络 IO 由 HostBridge 异步完成。
 */
export class JSExecutor {
  private host: HostBridge | null = null
  // call 的 id → 结果回调（匹配 onResult）
  private resultCallbacks: Map<number, CallResultHandler> = new Map()
  private nextCallId: number = 1
  // C 层当前只有一个 call id；串行化可避免并发调用时结果串线。
  private callQueue: Promise<void> = Promise.resolve()

  /**
   * 初始化 QuickJS 运行时，注册两个桥接回调。
   * @param host HostBridge 实例，处理 sendMessage 协议
   */
  init(host: HostBridge): void {
    this.host = host

    // 回调一：C 层 sendMessage 请求（扩展 await req() 时触发）
    //   签名 (id: number, cmd: string, json: string) => void
    const onRequest = (id: number, cmd: string, json: string): void => {
      host.handleRequest(cmd, json).then((resultJson: string) => {
        quickjs.resolve(id, resultJson) // 完成请求 → C 层 resolve Promise
      }).catch((e: Error) => {
        const errData: ErrorProData = {
          error: String(e),
          data: null,
          headers: {} as Record<string, string>,
          code: 500,
          redirects: [] as string[]
        }
        quickjs.resolve(id, JSON.stringify(errData))
      })
    }

    // 回调二：扩展方法执行完成
    //   签名 (id: number, resultJson: string) => void
    const onResult = (id: number, resultJson: string): void => {
      const cb = this.resultCallbacks.get(id)
      if (cb) {
        this.resultCallbacks.delete(id)
        cb(resultJson)
      }
    }

    quickjs.init(onRequest, onResult)
  }

  /**
   * 加载拼接后的扩展脚本（定义阶段，同步）。
   * @param bundle 由 ExtensionLoader.buildBundle 生成的完整脚本
   */
  load(bundle: string): void {
    quickjs.load(bundle)
  }

  /**
   * 调用扩展方法（如 getClassList/getVideoList），返回 Promise<string>。
   * @param method 全局函数名
   * @param argsJson 参数 JSON（如 '{"url":"1","page":1}'）
   */
  call(method: string, argsJson: string): Promise<string> {
    if (!this.host) {
      return Promise.resolve('{"error":"QuickJS 未初始化"}')
    }
    const run = this.callQueue.then(() => this.invoke(method, argsJson))
    this.callQueue = run.then(() => undefined, () => undefined)
    return run
  }

  private invoke(method: string, argsJson: string): Promise<string> {
    const id = this.nextCallId++
    return new Promise<string>((resolve) => {
      this.resultCallbacks.set(id, resolve)
      quickjs.call(method, argsJson, id)
    })
  }

  /**
   * 释放运行时。
   */
  dispose(): void {
    quickjs.dispose()
    this.resultCallbacks.clear()
    this.callQueue = Promise.resolve()
    this.host = null
  }
}
