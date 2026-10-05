/**
 * 全局配置常量
 */

interface TimeoutConfig {
  NORMAL: number;
  FAST: number;
  RETRY: number;
  DOWNLOAD: number;
}

interface GridColumnsConfig {
  PHONE_PORTRAIT: number;
  PHONE_LANDSCAPE: number;
  TABLET: number;
}

interface StorageKeys {
  ROOTS: string;
  ACTIVE_SRC: string;
  ACTIVE_SITE: string;
  AGG_SITES_CACHE: string;
  HISTORY: string;
  FAVORITE: string;
  SOURCES: string;
  ACTIVE_SOURCE: string;
  THEME_MODE: string;
  THEME_COLOR: string;
  PLAYER_SPEED: string;
  PLAYER_SCALE: string;
  SEARCH_HISTORY: string;
  SITE_HEALTH: string;
  DOWNLOADS: string;
}

interface ThemeColor {
  name: string;
  accent: string;
  accentAlt: string;
}

interface DownloadConfig {
  MAX_CONCURRENT: number;
  CHUNK_SIZE: number;
  RETRY_COUNT: number;
}

interface AppConfig {
  CONCURRENT_WORKERS: number;
  TIMEOUT: TimeoutConfig;
  AGG_CACHE_TTL_MS: number;
  SITE_HEALTH_TTL_MS: number;
  PROBE_BATCH_SIZE: number;
  HISTORY_MAX: number;
  SEARCH_HISTORY_MAX: number;
  GRID_COLUMNS: GridColumnsConfig;
  PLAYER_UA: string;
  PROGRESS_UPDATE_INTERVAL_MS: number;
  HIDE_CONTROLS_MS: number;
  AUTO_SAVE_PROGRESS_INTERVAL_MS: number;
  KEYS: StorageKeys;
  THEME_COLORS: ThemeColor[];
  DOWNLOAD: DownloadConfig;
}

export const CONFIG: AppConfig = {
  // 网络配置
  CONCURRENT_WORKERS: 8,
  TIMEOUT: {
    NORMAL: 15000,
    FAST: 8000,
    RETRY: 20000,
    DOWNLOAD: 30000
  },

  // 缓存配置
  AGG_CACHE_TTL_MS: 7 * 24 * 3600 * 1000, // 7天
  SITE_HEALTH_TTL_MS: 24 * 3600 * 1000,   // 24小时

  // UI 配置
  PROBE_BATCH_SIZE: 4,
  HISTORY_MAX: 50,
  SEARCH_HISTORY_MAX: 10,
  GRID_COLUMNS: {
    PHONE_PORTRAIT: 2,
    PHONE_LANDSCAPE: 3,
    TABLET: 4
  },

  // 播放器配置
  PLAYER_UA: 'Mozilla/5.0 (Linux; Android 13; HarmonyOS 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
  PROGRESS_UPDATE_INTERVAL_MS: 1000,
  HIDE_CONTROLS_MS: 3000,
  AUTO_SAVE_PROGRESS_INTERVAL_MS: 10000,

  // 存储键
  KEYS: {
    ROOTS: 'tvbox_roots_v1',
    ACTIVE_SRC: 'tvbox_active_src_v1',
    ACTIVE_SITE: 'tvbox_active_site_v1',
    AGG_SITES_CACHE: 'agg_sites_cache_v2',
    HISTORY: 'history_v1',
    FAVORITE: 'favorite_v1',
    SOURCES: 'sources_v1',
    ACTIVE_SOURCE: 'active_source_v1',
    THEME_MODE: 'theme_mode_v1',
    THEME_COLOR: 'theme_color_v1',
    PLAYER_SPEED: 'player_speed_preference_v1',
    PLAYER_SCALE: 'player_scale_preference_v1',
    SEARCH_HISTORY: 'search_history_v1',
    SITE_HEALTH: 'site_health_v1',
    DOWNLOADS: 'downloads_v1'
  },

  // 主题色配置
  THEME_COLORS: [
    { name: '蓝色', accent: '#007AFF', accentAlt: '#0051D5' },
    { name: '紫色', accent: '#AF52DE', accentAlt: '#8E44AD' },
    { name: '绿色', accent: '#34C759', accentAlt: '#28A745' },
    { name: '橙色', accent: '#FF9500', accentAlt: '#FF6B00' },
    { name: '粉色', accent: '#FF2D55', accentAlt: '#E91E63' },
    { name: '青色', accent: '#5AC8FA', accentAlt: '#00BCD4' }
  ],

  // 下载配置
  DOWNLOAD: {
    MAX_CONCURRENT: 3,
    CHUNK_SIZE: 1024 * 1024, // 1MB
    RETRY_COUNT: 3
  }
}

export const DEFAULT_ROOT = 'https://tv.1788.space/api.php'
