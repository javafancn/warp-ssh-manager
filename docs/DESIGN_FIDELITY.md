# Warp SSH Manager v0.3 — 设计图还原与验收

## 唯一设计基准

- `docs/reference/approved-themes.png`：深色/浅色并排的已确认设计图
- `docs/reference/approved-dark.png`：原始深色版
- `docs/theme-preview.html`：可交互的**视觉预览**，它不会连接真实服务器，也不是 GPUI 的实际截图

## 已修改的原生 GPUI 界面

| 设计图元素 | 实现位置 | 说明 |
| --- | --- | --- |
| 轻量应用顶部栏 | `apps/wsm-desktop/src/main.rs` | 应用标题、`+ 新建主机`、设置展开、三态主题切换；去除拥挤工具按钮 |
| Folders 三栏左侧 | 同上 | All Servers、Favorites、Recent、树形折叠组、数量徽标、行内新建分组 |
| Connections 中栏 | 同上 | 搜索、紧凑主机行、环境色标签、收藏星标、蓝色选中状态 |
| Server Details 右栏 | 同上 | 连接字段、分组选项、标签 chips + 可编辑输入、备注、收藏、固定底部操作 |
| 底部状态栏 | 同上 | 显示实际 SSH Include/Tab Config 状态、主机数量、应用提示，不虚构 SSH 在线状态 |
| Quick Connect | `apps/wsm-desktop/src/quick_connect.rs` | 搜索、收藏优先/最近连接优先、环境标签、星标、回车连接第一项 |
| 深色/浅色/系统 | `apps/wsm-desktop/src/theme.rs` | 一套语义色板，GPUI Component 主题同时更新，偏好保存在 `appearance.txt` |
| macOS 12+ 部署目标 | `scripts/*`, `apps/wsm-desktop/Cargo.toml` | 部署目标 12.0，Universal 2 构建及二进制最低系统版本检查脚本 |

## 视觉验收（需在 Mac 上实际对照）

- [ ] 1320×810 默认窗口下三栏连续排列，无溢出和内容遮挡
- [ ] 深色背景为海军蓝/炭黑，浅色为白灰；蓝色强调、紫色测试标签、绿色开发标签
- [ ] Dark → Light → System 三态切换后，输入框、滚动列表、浮窗一致；重启偏好持久化
- [ ] System 模式中切换 macOS 外观，主窗口及时更新
- [ ] 服务器列表和收藏状态实时更新；右侧字段加载正常；仅自管主机可修改 SSH 连接参数
- [ ] 菜单栏 Quick Connect 打开、过滤和 Enter 连接（按实际 Warp 和 SSH 状态验收）
- [ ] Intel Mac + Apple Silicon Mac 在 macOS 12 上分别验证启动和操作
- [ ] `.app` Mach-O 同时包含 `x86_64` 和 `arm64`，最低部署目标不高于 macOS 12

## 已知边界

- **尚未完成 macOS 编译和真机视觉对比**，不可把现阶段源码称为已通过验收的正式应用。
- Quick Connect 目前仍是浮动 GPUI 窗口，通过原生托盘菜单打开；不是精准锚定菜单栏图标的 `NSPopover`。
- GPUI / GPUI Component 使用现有固定版本；`minimum_system_version = 12.0` 仅是部署声明，不是 Monterey 运行保证。
- 页面中使用文本图标代替部分 SF Symbols，以确保所有 UI 逻辑保持 Rust 实现；最终视觉微调需在系统字体实际渲染下完成。
- 主题预览只是前端静态演示，真实数据、文件同步和 Warp 连接发生于 Rust 应用中。
