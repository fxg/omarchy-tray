# Omarchy System Tray (Monochrome Themed Tray)

[![Omarchy Plugin](https://img.shields.io/badge/Omarchy-Shell%20Plugin-58a6ff?style=flat-square&logo=archlinux)](https://github.com/basecamp/omarchy)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)

专为 **Omarchy Desktop (Arch Linux + Hyprland + Quickshell)** 打造的**极简单色透明、主题色温融合系统托盘插件**。

彻底终结第三方应用在 Linux 顶栏投放的实心绿/紫彩底大方块，通过 DBus 拦截、内置极简镂空矢量与 Shader 动态着色，让托盘与整体系统主题达到 **100% 像素级融为一体**。

---

## ✨ 核心特性

- 🎨 **消灭丑陋大方底，全单色负空间矢量**：
  - 深度拦截 DBus 上的 StatusNotifierItem 信号，将原生位图/彩色方底替换为通透的单色矢量 SVG。
  - 内置支持：**微信 (WeChat Linux)、Clash Verge、Antigravity、Fcitx5 (拼音/Rime雾凇/英文)、Tailscale、Syncthing** 等常用应用。
- 🌡️ **动态主题色温融合 (Theme Colorization)**：
  - 接入系统的 `MultiEffect` Shader 动态着色通道；
  - 切换到 **Tokyo Night** 时自动泛出微冷蓝灰光泽，切换到 **Gruvbox** 时自动变为温润暖米黄，浅色主题下自动变深色防隐形，与 Wi-Fi、蓝牙、电源、时钟等原生组件颜色完全一致。
- 🔄 **动态自发现与自纳管引擎 (Dynamic Plugin Auto-Discovery)**：
  - 实时监听 Omarchy `pluginRegistry` 与顶栏布局变动，**新安装/启用的插件只要未放置在顶栏槽位，自动纳入托盘抽屉收纳**，零需手动改写代码；
  - **三级合规 ICON 解析管线**：优先读取原生 Nerd Font 字形（随主题 100% 变色），次选单色负空间矢量，兜底采用类别启发字形或标准单色模块徽标，严防任何空白或破损；
  - **动态 Panel 绑定与防崩溃调用**：自动探测插件的 `Panel.qml`，点击在托盘锚点弹出，无面板时自动回退为执行激活指令。
- 📦 **智能收折抽屉 (Tray Drawer)**：
  - 原生支持应用抽屉折叠展开，并将非原生托盘服务（Tailscale、Syncthing 等）无缝收拢进抽屉，保持右侧顶栏极致纯净。
- 🛡️ **防御式防崩溃机制**：
  - 针对 Electron 应用频繁重启退出时的 DBus 菜单调用增加空指针保护，防止桌面 Shell 偶发闪退。

---

## 🚀 安装与启用

### 方式一：标准 Omarchy 插件安装（推荐）

在终端中执行：

```bash
# 1. 添加并启用 fxg.tray 插件
omarchy plugin add https://github.com/fxg/omarchy-tray.git --enable

# 2. 禁用官方默认托盘（避免图标重复显示）
omarchy plugin disable omarchy.tray
```

> [!TIP]
> 推荐通过 `omarchy bar` 调整位置或在 `~/.config/omarchy/bar.json` 中将 `fxg.tray` 放在右侧靠前位置作为托盘抽屉。

### 方式二：手动克隆与安装

```bash
git clone https://github.com/fxg/omarchy-tray.git ~/.config/omarchy/plugins/fxg.tray
omarchy plugin enable fxg.tray
omarchy plugin disable omarchy.tray
```

---

## 🖱️ 原生图形化托盘管理

在顶栏的 **`<` (折叠抽屉箭头)** 上点击 **鼠标右键**，将直接呼出原生的 **Tray icons 管理面板**：
- 可以直接点击每个应用图标右侧的 **📌 (Pin)** 按钮，决定该图标是常驻在外侧、还是折叠收缩在 `<` 抽屉内；
- 可以点击 **👁️ (Hide)** 按钮彻底隐藏不需要的图标；
- 状态由系统自动持久化保存，无需手动修改任何 JSON 配置文件！

---

## 🔌 如何通过 extraServices 将无托盘服务虚拟化收纳进抽屉？

### 💡 为什么需要这个功能？

在日常 Linux 使用中，许多极为重要的后台工具或服务**本身并没有图形化 GUI 托盘**（例如 Tailscale、Syncthing、Docker、Aria2、或者自己编写的一键运维脚本）。
以往它们只能靠在终端敲命令排查，或者在顶栏外部强行霸占一个独立的小组件槽位，显得杂乱无章。

`omarchy-tray` 独创了 **`extraServices` (服务虚拟化纳管)** 机制：**只需简单声明几行属性，即可将任何命令行服务、Web 服务或脚本一秒“伪装”为原生系统托盘图标**，享受折叠收纳、悬浮提示、鼠标左/右键动作、以及右键 `<` 自由勾选 Pin（常驻外侧）或收纳进抽屉的全部待遇！

---

### 📝 手把手实操步骤

#### 第一步：准备图标（二选一）

- **方案 A（最省心：直接使用 Nerd Font 字体字形，强烈推荐）**：
  无需画图！直接指定一个 Unicode 字形编码，例如 `glyph: "\uf013"`（齿轮图标）、`glyph: "\uf1c5"`（相框图片）、`glyph: "\uf085"`（螺丝刀把手）。
  - **特性**：自动根据当前主题（Tokyo Night / Gruvbox / 浅色）100% 自动变色，零色差！
- **方案 B（最精致：使用单色透明 SVG 矢量）**：
  按照 `24x24` 纯白、100% 透明背景规范制作 SVG，保存到本插件的 `icons/my-service.svg`，然后在属性中指定 `icon: "my-service"`。

---

#### 第二步：在 `Tray.qml` 的 `extraServices` 数组中追加定义

打开 `~/.config/omarchy/plugins/fxg.tray/Tray.qml`，找到 `readonly property var extraServices: [`，在数组中追加你自己的服务条目：

```javascript
readonly property var extraServices: [
  // ... 已有的 bing-wallpaper、tailscale、syncthing 等 ...

  // 👇 在这里追加你自己的服务：
  {
    id: "my-service",                    // 唯一标识符（不要与其他应用冲突）
    title: "Docker 监控",                // 在右键管理面板中显示的名称
    tooltipTitle: "Docker (左键看容器, 右键管理)", // 鼠标悬停时的纯粹名词提示
    glyph: "\uf04b",                     // 图标方案 A：直接用 Nerd Font 字形 (如播放/启动图标)
    // icon: "my-service",               // 图标方案 B：若使用 icons/my-service.svg 则配置此项
    status: Status.Active,               // 初始状态 (Active 为启用并可见)

    // 鼠标左键点击时触发的动作：
    activate: function() {
      // 示例：在终端弹窗中实时执行命令，按任意键退出
      Quickshell.execDetached([
        "foot", "--title=Docker Status",
        "sh", "-c", "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'; echo; read -n 1 -s -r -p '按任意键关闭...'"
      ])
    },

    // 鼠标右键或中键触发的辅助动作：
    secondaryActivate: function() {
      // 示例：直接在默认浏览器中打开本地 WebUI (如 Portainer / 本地管理面板)
      Quickshell.execDetached(["xdg-open", "http://localhost:9000"])
    },

    scroll: function(delta, reversed) {},
    display: function(win, x, y) {},
    onlyMenu: false,
    menu: null
  }
]
```

---

#### 第三步：保存并热重载生效

保存文件后，在终端执行一次 Shell 重启：

```bash
omarchy restart shell
```

**立即体验**：
1. 悬停在顶栏右侧的 **`<`** 抽屉，新增的单色图标就会伴随平滑动画一同滑出！
2. 在 **`<`** 上点击 **【鼠标右键】**，在弹出的管理浮窗中就能看到你的新服务，点击 **📌 Pin** 即可决定是将它常驻在外侧，还是折叠在抽屉里！

---

### 🌟 常用场景示范模板

#### 1. Tailscale 虚拟托盘（左键查状态终端，右键开 Web 控制台）
```javascript
{
  id: "tailscale",
  title: "Tailscale",
  tooltipTitle: "Tailscale",
  icon: "tailscale",
  status: Status.Active,
  activate: function() {
    Quickshell.execDetached(["foot", "--title=Tailscale Status", "sh", "-c", "tailscale status; echo; read -n 1 -s -r -p '按任意键关闭...'"])
  },
  secondaryActivate: function() {
    Quickshell.execDetached(["xdg-open", "https://login.tailscale.com/admin/machines"])
  },
  scroll: function(delta, reversed) {},
  display: function(win, x, y) {},
  onlyMenu: false,
  menu: null
}
```

#### 2. 本地 Web 服务（如 Syncthing、Aria2、Jupyter）
```javascript
{
  id: "syncthing",
  title: "Syncthing",
  tooltipTitle: "Syncthing",
  icon: "syncthing",
  status: Status.Active,
  activate: function() {
    Quickshell.execDetached(["xdg-open", "http://127.0.0.1:8384"])
  },
  secondaryActivate: function() {
    Quickshell.execDetached(["xdg-open", "http://127.0.0.1:8384"])
  },
  scroll: function(delta, reversed) {},
  display: function(win, x, y) {},
  onlyMenu: false,
  menu: null
}
```

#### 3. 独立第三方 Omarchy 插件收纳（如 Bing 壁纸：左键呼出原生下拉面板，右键立即刷新）
```javascript
{
  id: "bing-wallpaper",
  title: "Bing Wallpaper",
  tooltipTitle: "Bing Wallpaper",
  glyph: "\uf1c5", // 直接使用插件作者原装的相框图标
  pluginId: "io.github.odessa2.bing-wallpaper", // 插件 ID（自动定位插件目录与服务）
  panelSource: "Panel.qml",                     // 自动将原生下拉面板精准对齐托盘图标弹出
  status: Status.Active,
  activate: function() {
    // 备用兜底调用
    Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "io.github.odessa2.bing-wallpaper"])
  },
  secondaryActivate: function() {
    // 优先通过 QML 服务实例零延迟触发刷新，备用走 IPC
    var svc = root.resolvePluginService("io.github.odessa2.bing-wallpaper")
    if (svc && typeof svc.refresh === "function") {
      svc.refresh()
    } else {
      Quickshell.execDetached(["omarchy-shell", "-q", "bing-wallpaper", "refresh"])
    }
  },
  scroll: function(delta, reversed) {},
  display: function(win, x, y) {},
  onlyMenu: false,
  menu: null
}
```

> [!TIP]
> **插件下拉面板规范**：
> 凡是声明了 `pluginId` 与 `panelSource`（如 `"Panel.qml"`）的收纳插件，左键点击托盘图标时，托盘宿主会自动加载该插件原生的 LayerShell 下拉面板，并将锚点精准对齐当前托盘图标；右键点击则优先执行 `secondaryActivate`（如刷新壁纸）或弹出原生菜单。

---

## 🛠️ 新应用图标扩展与适配指南

若您需要为其他新应用（如 QQ、Slack、Spotify、1Password 等）适配单色矢量图标：

### 1. 嗅探该应用的 DBus 标识

```bash
# 查找正在运行的 StatusNotifierItem 托盘服务
busctl --user list | grep -i "StatusNotifierItem"

# 透视其 Id、Title 与 IconName
busctl --user introspect <Service-Name> /StatusNotifierItem org.kde.StatusNotifierItem
```

### 2. 设计单色透明矢量 SVG

1. **画布基准**：标准 `24x24` viewBox，四周保持 1~2px 呼吸留白。
2. **纯白基底**：路径填充颜色采用 `#fcfcfc`，**无任何背景色块（100% 透明底）**。
3. **负空间镂空**：内部细节通过挖空呈现（如眼睛、分割线）。
4. 将文件保存至本插件的 `icons/<app-name>.svg`。

### 3. 在 `Tray.qml` 中注册映射

在 `trayIconSource` 中添加匹配规则：
```javascript
if (s.indexOf("my-app") !== -1 || iid.indexOf("my-app") !== -1) {
  return pluginIcon("my-app.svg")
}
```

并在 `iconIsSymbolic` 中纳管至主题着色：
```javascript
if (s.indexOf("my-app") !== -1 || iid.indexOf("my-app") !== -1) {
  return true
}
```

---

## 🔄 升级与卸载

### 升级更新
```bash
omarchy plugin update fxg.tray
```

### 卸载插件
```bash
omarchy plugin disable fxg.tray
omarchy plugin remove fxg.tray
omarchy plugin enable omarchy.tray  # 恢复系统原生托盘
```

---

## 📄 License

本项目基于 [MIT License](LICENSE) 开源发布。
