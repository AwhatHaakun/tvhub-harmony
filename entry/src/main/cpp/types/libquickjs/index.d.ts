// quickjs.d.ts —— libquickjs.so 的 ArkTS 类型声明
// 放在 entry/src/main/cpp/types/libquickjs/index.d.ts
// 作用：让 `import quickjs from 'libquickjs.so'` 通过 ArkTS 类型检查。

declare namespace quickjs {
  /**
   * 初始化 QuickJS 运行时。
   * @param onRequest C 层 sendMessage 请求回调 (id, cmd, json)
   * @param onResult 扩展方法完成回调 (id, resultJson)
   */
  function init(
    onRequest: (id: number, cmd: string, json: string) => void,
    onResult: (id: number, resultJson: string) => void
  ): void

  /**
   * 加载拼接后的扩展脚本（定义阶段，同步）。
   */
  function load(script: string): void

  /**
   * 调用扩展方法，结果经 onResult 异步回传。
   */
  function call(method: string, argsJson: string, id: number): void

  /**
   * 完成一个 sendMessage 请求（HostBridge 处理完后调用）。
   */
  function resolve(id: number, resultJson: string): void

  /**
   * 释放运行时。
   */
  function dispose(): void
}

export default quickjs
