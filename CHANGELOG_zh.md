# 更新日志

## Unreleased

- 完成核心代码可维护性重构：
  - 新增根目录 `UI/` 模块：`UI/card_popup.lua`、`UI/config_tabs.lua`、`UI/preview_cards.lua`。
  - 配置初始化与默认值模块已合并为 `Core/config_setup.lua`。
  - 预测路由文件合并为 `Core/predictors/routes.lua`。
  - Hook 运行时迁移到 `Core/ui_hooks.lua`，并移除旧兼容包装层。
- 更新预测面板布局行为：
  - 高度固定为普通 Joker 预览基准。
  - 多卡布局支持“等间距模式”与“默认宽度均分回退模式”。
  - 预测区域背景改为商店 Joker 槽位风格深色背景。
- 更新交互行为：
  - Collection 场景始终走原版面板。
  - 移除 Collection 悬停热路径的跳过日志输出。
  - 皇帝/女祭司始终显示完整生成结果，不受当前消耗槽位限制。
- 同步更新文档（`README*`、`AGENT.md`、`docs/*`）以反映当前架构与行为。

## 0.1.0

- 初始化模组工程结构。
- 完成预测 UI 模块化拆分。
- 实现当前范围内卡牌的确定性预测。
- 增加初始化脚本、配置与文档基础。
