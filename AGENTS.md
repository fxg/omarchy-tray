# Omarchy Tray (fxg.tray) — Agent & Developer Architecture Guidelines

本规范文档（`AGENTS.md`）定义了 `omarchy-tray` 插件的核心设计哲学、架构红线与代码演进准则。
任何 AI Agent 或开发人员在接手、维护或扩展此插件代码时，**必须严格遵循以下原则**。

---

## 🏛️ 核心设计哲学与架构红线

### 1. 零系统侵入与环境自洽原则 (Zero-Intrusion & Self-Contained)
- **绝对严禁污染系统底层**：
  - 严禁任何试图修改、覆盖或依赖 `/usr/share/omarchy/` 官方系统底座代码的逻辑。
  - 所有定制能力与修复逻辑，必须 100% 封装在插件自有代码目录内。
- **严禁绝对路径硬编码**：
  - 严禁在 QML 或脚本中硬编码任何特定用户的本地路径（如 `/home/xxx/`）。
  - 图标与资源统一使用 `Qt.resolvedUrl("icons/<name>.svg")` 相对动态解析。
  - 访问用户配置或缓存必须使用 `Quickshell.env("HOME")`。
- **自举打包与独立可用**：
  - 插件纳管的单色透明矢量图标必须自包含在 `icons/` 目录下，确保任意新环境执行 `omarchy plugin add` 即可开箱即用。

---

### 2. 原生图形化交互第一，严禁倒退为手动改配置 (Native GUI First)
- **保护用户原生操作直觉**：
  - 状态分配规则：**折叠收纳 (Drawer)**、**固定常驻 (Pin)**、**完全隐藏 (Hide)** 的归属，必须且只能通过在顶栏 **`<` (折叠箭头)** 上点击 **【鼠标右键】** 呼出的原生 `managePopup` 面板由用户可视化勾选完成。
- **严禁强迫用户编辑底层 JSON 文件**：
  - 严禁设计需要用户手动到终端编辑 JSON 的繁琐流程。
  - 状态变更必须通过 Omarchy 内置的 `persistTrayState(pinned, hidden)` 接口自动持久化到系统配置中。

---

### 3. 双模图标呈现与系统 Theme 动态融合准则 (Dual-Mode Theming Engine)

顶栏系统托盘必须保持极致的通透、克制与色调一致性，杜绝任何第三方实心彩底大方块破坏桌面美感。图标渲染严格遵循双模规范：

#### 规则 A：插件原生字形优先 (Plugin Native Glyph First)
- 如果纳管的组件本身自带标准 Nerd Font / Font Awesome 字形（如 Bing Wallpaper 官方自带的 `\uf1c5`），**必须直接使用其原装字形**。
- 字形渲染采用原生 `Text` 组件，颜色直接深度绑定当前主题前景色（`root.foreground`）。
- **目标**：100% 还原插件作者原本的视觉设计，同时享受零延迟、零 GPU 滤镜消耗的动态主题变色。

#### 规则 B：第三方应用单色负空间重绘 (Monochrome Negative-Space Vector)
- 对微信（WeChat）、Clash Verge 等向 DBus 投放大色块或彩底方块的应用，必须通过 DBus 嗅探拦截并重绘为 `icons/<name>.svg`。
- **标准设计规范**：
  - 画布规格：`24x24` viewBox，四周保持 1~2px 呼吸留白；
  - 100% 透明背景，基底采用 `#fcfcfc` 纯白填充；
  - 内部层次与细节一律使用**负空间（镂空）**表达；
  - 纳管至 `TrayIcon` 的 `MultiEffect` Shader 动态着色通道，实时跟随系统主题色温（Tokyo Night 泛冷蓝灰、Gruvbox 泛暖米黄、浅色主题泛深灰）。

---

### 4. 无原生托盘服务的优雅收纳与防御性调用 (Defensive Invocation)
- **服务虚拟化收纳**：
  - 对本身没有原生 GUI 托盘的服务（如 Tailscale、Syncthing），通过 `extraServices` 虚拟化注册接入托盘抽屉，收缩顶栏杂质。
- **防御式安全调用（Defensive Call）**：
  - 托盘常驻进程必须具备极高的稳定性。所有鼠标点击触发的 IPC 动作或外部命令（如 `omarchy-shell`、`xdg-open`）必须做好异常防崩溃与空指针包裹，杜绝因外部服务未启动或退出而拖垮整个桌面 Shell。

---

### 5. 质量保证与发布合规 (Validation & Conventional Commits)
- **本地严格校验红线**：
  - 任何改动在提交前，必须在本地运行并完全通过官方规范校验：
    ```bash
    omarchy plugin validate .
    ```
- **提交与推送**：
  - Git 提交严格遵循 Conventional Commits 规范（`feat:`、`fix:`、`refactor:` 等）；
  - 远程提交必须使用 SSH 协议（`git@github.com:...`）。
