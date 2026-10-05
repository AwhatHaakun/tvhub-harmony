/**
 * 多源接口数据模型
 * 与 tvbox-spike/tvbox-client.mjs 一一对应
 */

/** 影片列表项（videolist / 搜索返回） */
export interface VodItem {
  vodId: string;
  name: string;
  pic: string;
  remarks: string;
  year: string;
  area: string;
  actor: string;
  director: string;
  score: string;
  typeName: string;
}

/** 详情（detail 返回，含播放信息） */
export interface VodDetail {
  vodId: string;
  name: string;
  pic: string;
  remarks: string;
  year: string;
  area: string;
  lang: string;
  actor: string;
  director: string;
  score: string;
  typeName: string;
  content: string;
  playFrom: string;
  playUrl: string;
}

/** 单集 */
export interface Episode {
  name: string;
  url: string;
}

/** 播放线路（由 playFrom/playUrl 拆分） */
export interface PlayLine {
  from: string;
  episodes: Episode[];
}

/** 分类 */
export interface Category {
  typeId: string;
  typeName: string;
  typePid: string;
}

/** 站点状态：标准 HTTP 接口可直接调用；jar/drpy 需要对应爬虫运行时 */
export type SiteStatus = 'ok' | 'jar' | 'drpy';

/** 单仓配置里的一个站点 */
export interface SiteConf {
  key: string;
  name: string;
  api: string;
  categories: string[];
  searchable: boolean;
  status: SiteStatus;
}

/** 一个影视源（对应接口 urls[] 的一项，或单仓接口本身） */
export interface SourceConf {
  id: string;
  name: string;
  url: string;
  sites: SiteConf[];
  siteIndex: number; // 当前选中的站点下标，-1 表示未选择
  rootUrl: string; // 来源接口 URL（多接口管理用）
}

/** 分页列表结果 */
export interface VodPage {
  total: number;
  page: number;
  list: VodItem[];
}


/** 首页站点探测成功后可直接应用的数据，避免重复请求分类和首屏列表 */
export interface SiteHomeData {
  categories: Category[];
  category: Category;
  page: VodPage;
}

/** 聚合搜索结果项：影片 + 来源站点（点开详情时定向取数，不依赖当前 activeSite） */
export interface SearchVodItem {
  vod: VodItem;
  siteApi: string;      // 站点 api 基址（ac=detail 用）
  siteReferer: string;  // 来源单仓 URL（防反爬 Referer）
  siteName: string;     // 站点名（详情线路标签/UI 徽标用）
  sourceName: string;   // 父数据源名（全源搜索结果展示用）
}

/** 聚合搜索站点（全部源展开后按 api 去重的清单项，持久化缓存） */
export interface AggSite {
  siteName: string;
  api: string;
  srcName: string;      // 所属源名（进度/徽标显示）
  referer: string;      // 所属源单仓 URL
}

/** 聚合站点清单持久化缓存 */
export interface AggSitesCache {
  ts: number;
  sites: AggSite[];
}
