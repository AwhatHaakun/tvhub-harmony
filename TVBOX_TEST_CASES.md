# TVBox 源兼容性测试用例

## 测试用例 1：标准多仓格式
```json
{
  "urls": [
    {"name": "源1", "url": "https://example.com/1.json"},
    {"name": "源2", "url": "https://example.com/2.json"}
  ]
}
```
**预期**: type = 'multi', 2 个源

---

## 测试用例 2：非标多仓格式（title + link）
```json
{
  "urls": [
    {"title": "源A", "link": "https://example.com/a.json"},
    {"title": "源B", "link": "https://example.com/b.json"}
  ]
}
```
**预期**: type = 'multi', 自动映射字段

---

## 测试用例 3：标准单仓格式
```json
{
  "sites": [
    {
      "key": "iqiyi",
      "name": "爱奇艺",
      "api": "https://api.example.com/",
      "searchable": 1
    }
  ]
}
```
**预期**: type = 'single', 1 个站点

---

## 测试用例 4：数组源列表
```json
[
  {"name": "源1", "url": "https://example.com/1.json"},
  {"name": "源2", "url": "https://example.com/2.json"}
]
```
**预期**: type = 'multi', 2 个源

---

## 测试用例 5：数组站点列表
```json
[
  {"key": "site1", "api": "https://api.example.com/"},
  {"key": "site2", "api": "https://api2.example.com/"}
]
```
**预期**: type = 'single', 2 个站点

---

## 测试用例 6：嵌套格式
```json
{
  "data": {
    "urls": [
      {"name": "源1", "url": "https://example.com/1.json"}
    ]
  }
}
```
**预期**: type = 'multi', 递归解析

---

## 测试用例 7：带注释的配置
```json
{
  // 这是源列表
  "urls": [
    {"name": "源1", "url": "https://example.com/1.json"}, // 第一个源
    /* 块注释 */
    {"name": "源2", "url": "https://example.com/2.json"}
  ]
}
```
**预期**: 注释被清除，正常解析

---

## 测试用例 8：尾逗号
```json
{
  "urls": [
    {"name": "源1", "url": "https://example.com/1.json"},
  ],
}
```
**预期**: 尾逗号被清除，正常解析

---

## 测试用例 9：前置文本
```
这是一段说明文字
可以有多行

{
  "urls": [
    {"name": "源1", "url": "https://example.com/1.json"}
  ]
}
```
**预期**: 自动提取 JSON 部分

---

## 测试用例 10：BOM + 控制字符
```
﻿{"urls":[{"name":"源\x001","url":"https://example.com/1.json"}]}
```
**预期**: BOM 被移除，控制字符被替换

---

## 测试用例 11：searchable 数字/布尔混用
```json
{
  "sites": [
    {"key": "s1", "api": "https://a.com", "searchable": 1},
    {"key": "s2", "api": "https://b.com", "searchable": true},
    {"key": "s3", "api": "https://c.com", "searchable": 0}
  ]
}
```
**预期**: 全部正确识别可搜索性

---

## 测试用例 12：空 URL 过滤
```json
{
  "urls": [
    {"name": "源1", "url": ""},
    {"name": "源2", "url": "https://example.com/2.json"},
    {"name": "源3", "url": "invalid"}
  ]
}
```
**预期**: 只保留有效 URL

---

## 测试用例 13：缺失字段补全
```json
{
  "sites": [
    {"api": "https://example.com/"}
  ]
}
```
**预期**: 自动生成 key 和 name

---

## 测试用例 14：带爬虫配置
```json
{
  "spider": "https://example.com/spider.jar",
  "sites": [
    {"key": "s1", "name": "站点1", "api": "https://api.example.com/"}
  ]
}
```
**预期**: type = 'single', spider 字段被保留

---

## 测试用例 15：深度嵌套
```json
{
  "config": {
    "data": {
      "sources": {
        "urls": [
          {"name": "源1", "url": "https://example.com/1.json"}
        ]
      }
    }
  }
}
```
**预期**: 递归查找并解析

---

## 自动化测试脚本

```typescript
const testCases = [
  {
    name: '标准多仓',
    input: '{"urls":[{"name":"源1","url":"https://a.com"}]}',
    expected: { type: 'multi', count: 1 }
  },
  // ... 更多测试用例
]

testCases.forEach(test => {
  const result = TvboxSourceParser.parse(test.input)
  console.assert(result.type === test.expected.type, test.name + ' 失败')
})
```

---

## 边界条件测试

### 1. 空配置
```json
{}
```
**预期**: type = 'unknown'

### 2. 空数组
```json
[]
```
**预期**: type = 'unknown'

### 3. 纯字符串
```
"https://example.com"
```
**预期**: 解析失败

### 4. 超大文件（5MB+）
**预期**: 可能超时，建议分批处理

---

**测试覆盖率目标**: 95%+
