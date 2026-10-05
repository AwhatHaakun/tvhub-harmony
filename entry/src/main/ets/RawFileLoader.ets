// RawFileLoader.ets —— 从 rawfile 读取核心库与扩展，拼成 bundle
// 读取顺序必须与 M0 spike 一致（否则 cheerio/Crypto 等工厂函数未定义就实例化会报错）。

import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { ExtensionLoader } from './ExtensionLoader'

/**
 * 核心库拼接顺序（与 uz3lib.js 的依赖关系一致）。
 * 注意：库文件（定义 createCheerio 等工厂函数）必须先于 uz3lib.js（调用工厂实例化）。
 */
const CORE_FILES: string[] = [
  'cheerio.js',
  'CryptoJS.min.js',
  'JSEncrypt.min.js',
  'JSONbig.js',
  'buffer.js',
  'node-html-parser.js',
  'uz3lib.js',
  'uzUtils.js',
  'videoCore.js',
  'uzHome.js',
]

export class RawFileLoader {
  /**
   * 读取 rawfile/uzcore/ 下的核心库 + 指定扩展，拼接为可执行脚本。
   * @param context 应用上下文（用于 resourceManager）
   * @param extFileName 扩展文件名（位于 uzcore/ 下），如 'test-ext.js'
   */
  static async buildBundle(context: common.Context, extFileName: string): Promise<string> {
    const rm = context.resourceManager
    const decoder = util.TextDecoder.create('utf-8')
    const extData = await rm.getRawFileContent('uzcore/' + extFileName)
    return RawFileLoader.buildBundleWithExt(context, decoder.decodeToString(new Uint8Array(extData)))
  }

  /**
   * 核心库（rawfile）+ 传入的扩展源码，拼接为可执行脚本。
   * @param context 应用上下文
   * @param extCode 扩展 JS 源码字符串（内置扩展从 rawfile 读、自定义扩展从沙箱文件读）
   */
  static async buildBundleWithExt(context: common.Context, extCode: string): Promise<string> {
    const rm = context.resourceManager
    const decoder = util.TextDecoder.create('utf-8')
    const sources: string[] = []

    for (const f of CORE_FILES) {
      const data = await rm.getRawFileContent('uzcore/' + f)
      sources.push(decoder.decodeToString(new Uint8Array(data)))
    }

    sources.push(extCode)
    return ExtensionLoader.buildBundle(sources)
  }
}
