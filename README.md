# Omarchy System Tray (Monochrome Themed Tray)

[![Omarchy Plugin](https://img.shields.io/badge/Omarchy-Shell%20Plugin-58a6ff?style=flat-square&logo=archlinux)](https://github.com/basecamp/omarchy)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)

专为 **Omarchy Desktop (Arch Linux + Hyprland + Quickshell)** 打造的**极简单色透明、主题色温融合系统托盘插件**。

彻底终结第三方应用在 Linux 顶栏投放的实心绿/紫彩底大方块，通过 DBus 拦截、内置极简镂空矢量与 Shader 动态着色，让托盘与整体系统主题达到 **100% 像素级融为一体**。

---

## ✨ 核心特性

- 🎨 **消灭丑陋大方底，全单色负空间矢量**：
  - 深度拦截 DBus 上的 StatusNotifierItem 信号，将原生位图/彩色方底替换为通透的单色矢量 SVG。
  - 内置支持：**微信 (WeChat Linux)、Clash Verge、Antigravity、Fcitx5 (拼音/英文)、Tailscale、Syncthing** 等常用应用。
- 🌡️ **动态主题色温融合 (Theme Colorization)**：
  - 接入系统的 `MultiEffect` Shader 动态着色通道；
  - 切换到 **Tokyo Night** 时自动泛出微冷蓝灰光泽，切换到 **Gruvbox** 时自动变为温润暖米黄，浅色主题下自动变深色防隐形，与 Wi-Fi、蓝牙、电源、时钟等原生组件颜色完全一致。
- 📦 **智能收折抽屉 (Tray Drawer)**：
  - 原生支持应用抽屉折叠展开，并将非原生托盘服务（Tailscale、Syncthing 等）无缝收拢进抽屉，保持右侧顶栏极致纯净。
- 🌈 **彩色应用保护白名单**：
  - 针对 Telegram、Obsidian、Joplin 等特定需要彩色辨识度的应用保留原生色彩，绝不粗暴强行压制。
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
