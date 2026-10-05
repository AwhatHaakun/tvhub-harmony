// ExtensionLoader.ets —— 扩展加载器（移植自 M0 spike 的 Node 实现）
// 职责：
//   1. preprocess：剥离 // ignore 成对块（与 uz 运行时行为一致）
//   2. buildBundle：按固定顺序把「集成库 + 工具库 + 视频扩展核心 + 首页核心 + 扩展」拼成一个脚本
//
// 拼接顺序（必须与 M0 一致）：
//   cheerio.js → CryptoJS.min.js → JSEncrypt.min.js → JSONbig.js → buffer.js →
//   node-html-parser.js → uz3lib.js → uzUtils.js → videoCore.js → uzHome.js → 扩展.js

export class ExtensionLoader {
  /**
   * 剥离 // ignore 成对块：每遇到一行单独的 "// ignore" 就翻转剥离状态。
   * 成对标记之间的内容（import/export、本地调试分支）被删除，标记行本身也不保留。
   */
  static preprocess(src: string): string {
    const lines = src.split('\n')
    const out: string[] = []
    let ignore = false
    for (const line of lines) {
      if (line.trim() === '// ignore') {
        ignore = !ignore
        continue
      }
      if (!ignore) {
        out.push(line)
      }
    }
    return out.join('\n')
  }

  /**
   * 把多个源码片段按顺序预处理后拼接为单个脚本。
   * @param sources 顺序排列的源码字符串数组（最后一个通常是扩展）
   */
  static buildBundle(sources: string[]): string {
    return sources.map((s) => ExtensionLoader.preprocess(s)).join('\n\n')
  }

  /**
   * 解析扩展文件顶部的 //@ 元数据注释。
   * @returns { name, version, webSite, codeID, env, isAV, deprecated }
   */
  static parseMeta(src: string): Record<string, string> {
    const meta: Record<string, string> = {}
    const re = /\/\/@(\w+):(.*)/g
    let m = re.exec(src)
    while (m !== null) {
      meta[m[1]] = m[2].trim()
      m = re.exec(src)
    }
    return meta
  }

  /**
   * 判断扩展是否为加密扩展（含 codeID 即为 uz 私有加密，鸿蒙侧无法解密，应跳过）。
   */
  static isEncrypted(src: string): boolean {
    const meta = ExtensionLoader.parseMeta(src)
    return (meta['codeID'] ?? '') !== ''
  }
}
