import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell.Services.SystemTray
import qs.Commons
import qs.Ui
import "TrayModel.js" as TrayModel

BarWidget {
  id: root
  moduleName: "fxg.tray"

  property bool expanded: false
  property bool managePopupOpen: false
  property bool trayMenuOpen: false
  property var activeTrayItem: null
  property var activeTrayAnchor: null
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var pinnedIds: settings.pinned instanceof Array ? settings.pinned : []
  readonly property var hiddenIds: settings.hidden instanceof Array ? settings.hidden : []
  readonly property var pinnedItems: bucket("pinned")
  readonly property var drawerItems: bucket("drawer")
  readonly property var allItems: bucket("all")
  readonly property int drawerCount: drawerItems.length
  readonly property int trayItemExtent: Style.bar.iconSlot
  readonly property int trayItemGap: 0
  readonly property int trayJoinGap: 0
  readonly property int drawerExtent: drawerCount > 0 ? drawerCount * trayItemExtent + (drawerCount - 1) * trayItemGap : 0
  // Match Waybar's group/tray-expander drawer transition-duration.
  readonly property int animationDuration: 600
  readonly property bool panelOpen: pluginPanelLoader.item ? pluginPanelLoader.item.opened === true : false
  readonly property bool panelOpenInDrawer: panelOpen && activePanelServiceItem !== null && classifyItem(activePanelServiceItem) === "drawer"
  readonly property bool menuOpenInDrawer: trayMenuOpen && activeTrayItem !== null && classifyItem(activeTrayItem) === "drawer"
  readonly property bool drawerActive: expanded || managePopupOpen || menuOpenInDrawer || panelOpenInDrawer
  property real revealProgress: drawerActive ? 1 : 0
  readonly property real revealExtent: drawerExtent * revealProgress

  // Submenu drill-down state. QsMenuEntry.display() renders a *platform* menu,
  // which Quickshell refuses unless the shell root sets `//@ pragma
  // UseQApplication` - omarchy's shell.qml does not, so every submenu click was
  // a silent no-op ("Cannot display PlatformMenuEntry as quickshell was not
  // started in QApplication mode" in the shell log) and apps whose whole UI is
  // submenus, e.g. radiotray-ng's station list, were unusable. QsMenuEntry
  // inherits QsMenuHandle, so a child entry can feed a nested QsMenuOpener and
  // render inside this popup instead of going through the platform. Each level
  // keeps its own live opener: a child entry is owned by its parent opener's
  // model, so collapsing the stack to a single opener would destroy the very
  // entry being displayed (submenu turns up empty).
  property var submenuStack: []
  readonly property int submenuDepth: submenuStack.length
  readonly property string currentTitle: submenuDepth > 0 ? submenuStack[submenuDepth - 1].title : ""
  readonly property var currentChildren: submenuDepth > 0
    ? submenuStack[submenuDepth - 1].opener.children
    : trayMenuOpener.children

  // Changing level rebuilds the row delegates synchronously, so the next
  // row lands under a cursor that hasn't moved. Submenu clicks used to be
  // silent no-ops, which trained users to click them twice, and that second
  // click would now fire whatever entry took the spot. Ignore row clicks for
  // a beat after each level change; a deliberate follow-up click is slower.
  property bool menuLevelSettling: false

  Component {
    id: submenuOpenerComponent
    QsMenuOpener {}
  }

  Timer {
    id: menuLevelSettleTimer
    interval: 250
    onTriggered: root.menuLevelSettling = false
  }

  function settleMenuLevel() {
    menuLevelSettling = true
    menuLevelSettleTimer.restart()
  }

  function resetTrayMenu() {
    menuLevelSettling = false
    menuLevelSettleTimer.stop()
    // Flickable keeps its offset across a model swap whenever the new content
    // is still tall enough to hold it, so a menu dismissed while scrolled
    // would otherwise reopen part-way down with its first entries off screen.
    trayMenuFlick.contentY = 0
    // Clear the reactive stack before tearing anything down, so no binding can
    // read a partially-destroyed opener while this runs. Then destroy deepest
    // first: an inner opener's menu entry is owned by its parent's children
    // model, so destroying a parent first would invalidate an entry a still-
    // live child opener references.
    var openers = submenuStack
    submenuStack = []
    for (var i = openers.length - 1; i >= 0; i--) openers[i].opener.destroy()
  }

  function enterSubmenu(entry, title) {
    var opener = submenuOpenerComponent.createObject(root, { menu: entry })
    if (!opener) return
    var stack = submenuStack.slice()
    stack.push({ opener: opener, title: title })
    submenuStack = stack
    settleMenuLevel()
  }

  function leaveSubmenu() {
    if (submenuStack.length === 0) return
    var stack = submenuStack.slice()
    var top = stack.pop()
    submenuStack = stack
    top.opener.destroy()
    settleMenuLevel()
  }

  function close() {
    managePopupOpen = false
    trayMenuOpen = false
    if (pluginPanelLoader.item && typeof pluginPanelLoader.item.close === "function") {
      pluginPanelLoader.item.close()
    }
  }

  property var activePanelServiceItem: null
  property var activePanelAnchorItem: null

  function resolvePluginFile(pluginId, fileName) {
    if (!pluginId || !fileName) return ""
    if (fileName.indexOf("file://") === 0 || fileName.indexOf("qrc:/") === 0) return fileName

    if (root.bar && root.bar.shell && root.bar.shell.pluginRegistry) {
      var registry = root.bar.shell.pluginRegistry
      var manifest = registry.installedPlugins ? registry.installedPlugins[pluginId] : null
      if (manifest) {
        var url = (typeof registry.entryPointUrl === "function")
          ? (registry.entryPointUrl(manifest, "barWidget") || registry.entryPointUrl(manifest, "service") || registry.entryPointUrl(manifest, "panel"))
          : ""
        if (url) {
          var lastSlash = url.lastIndexOf("/")
          if (lastSlash !== -1) {
            return url.substring(0, lastSlash + 1) + fileName
          }
        }
        if (manifest.__sourceDir) {
          var sDir = String(manifest.__sourceDir).replace(/\/+$/, "")
          return "file://" + sDir + "/" + fileName
        }
      } else {
        return ""
      }
    }

    return ""
  }

  property var hostBar: null

  function findHostBar() {
    if (hostBar) return hostBar

    function isBar(obj) {
      if (!obj) return false
      // Exclude scoped PluginBarApi instances which have pluginId
      if ("pluginId" in obj) return false
      return !!(obj.barWidgetRegistry && obj.shell && typeof obj.shell.serviceFor === "function")
    }
    // 1. Inspect sibling slots in the current section
    try {
      var mySlot = root.parent ? root.parent.parent : null
      var sectionRow = mySlot ? mySlot.parent : null
      if (sectionRow && sectionRow.children) {
        for (var i = 0; i < sectionRow.children.length; i++) {
          var siblingSlot = sectionRow.children[i]
          var activeIt = siblingSlot ? siblingSlot.activeItem : null
          var activeBar = activeIt ? activeIt.bar : null
          if (isBar(activeBar)) {
            hostBar = activeBar
            return hostBar
          }
        }
      }
    } catch (e1) {}

    // 2. Traverse up through section loaders to horizontalBar / verticalBar
    try {
      var p = root.parent
      while (p) {
        if (isBar(p)) { hostBar = p; return hostBar }
        if (isBar(p.bar)) { hostBar = p.bar; return hostBar }
        if (p.children) {
          for (var c = 0; c < p.children.length; c++) {
            var ch = p.children[c]
            if (!ch) continue
            if (isBar(ch.bar)) { hostBar = ch.bar; return hostBar }
            if (ch.activeItem && isBar(ch.activeItem.bar)) { hostBar = ch.activeItem.bar; return hostBar }
            if (ch.children) {
              for (var gc = 0; gc < ch.children.length; gc++) {
                var gch = ch.children[gc]
                if (gch && gch.activeItem && isBar(gch.activeItem.bar)) {
                  hostBar = gch.activeItem.bar
                  return hostBar
                }
              }
            }
          }
        }
        p = p.parent
      }
    } catch (e2) {}

    return null
  }

  function isPluginRunning(pluginId) {
    if (!pluginId) return false
    var hb = findHostBar()
    var shellObj = (hb && hb.shell) ? hb.shell : (root.bar ? root.bar.shell : null)
    var reg = shellObj ? shellObj.pluginRegistry : null
    if (!reg || !reg.installedPlugins) return false
    var manifest = reg.installedPlugins[pluginId]
    if (!manifest) return false
    if (typeof reg.isEnabled === "function" && !reg.isEnabled(pluginId)) return false
    if (Array.isArray(manifest.kinds) && manifest.kinds.indexOf("service") !== -1) {
      if (shellObj && typeof shellObj.serviceFor === "function") {
        return shellObj.serviceFor(pluginId) !== null
      }
    }
    return true
  }

  function resolvePluginService(pluginId) {
    if (!pluginId) return null
    var hb = findHostBar()
    if (hb && hb.shell && typeof hb.shell.serviceFor === "function") {
      try {
        var s = hb.shell.serviceFor(pluginId)
        if (s) return s
      } catch (e) {
        console.warn("fxg.tray: hb.shell.serviceFor error:", e)
      }
    }

    if (root.bar && root.bar.shell && typeof root.bar.shell.serviceFor === "function") {
      try {
        var svc = root.bar.shell.serviceFor(pluginId)
        if (svc) return svc
      } catch (e) {}
    }
    return null
  }

  function resolvePluginSettings(pluginId) {
    if (!pluginId) return { id: "" }
    var hb = root.findHostBar()
    var cfg = hb && hb.shell && hb.shell.shellConfig ? hb.shell.shellConfig : null
    if (cfg && Array.isArray(cfg.plugins)) {
      for (var i = 0; i < cfg.plugins.length; i++) {
        if (cfg.plugins[i] && cfg.plugins[i].id === pluginId) {
          return cfg.plugins[i]
        }
      }
    }
    return { id: pluginId }
  }

  function updatePanelAnchor(anchorItem) {
    if (!anchorItem) return
    try {
      var pt = root.mapFromItem(anchorItem, 0, 0)
      panelAnchor.x = Math.round(pt.x)
      panelAnchor.y = Math.round(pt.y)
      panelAnchor.width = anchorItem.width > 0 ? anchorItem.width : root.trayItemExtent
      panelAnchor.height = anchorItem.height > 0 ? anchorItem.height : root.trayItemExtent
    } catch (e) {
      console.warn("fxg.tray: updatePanelAnchor error:", e)
    }
  }

  function togglePluginPanel(serviceItem, anchorItem) {
    if (!serviceItem) return
    var pluginId = serviceItem.pluginId || ""
    var panelSource = serviceItem.panelSource || "Panel.qml"
    var panelUrl = resolvePluginFile(pluginId, panelSource)

    if (!panelUrl) {
      console.warn("fxg.tray: unable to resolve panel for", serviceItem.id || pluginId)
      if (typeof serviceItem.activate === "function") serviceItem.activate()
      return
    }

    root.managePopupOpen = false
    root.trayMenuOpen = false
    unloadPanelTimer.stop()

    // If currently open for this same service, toggle it closed
    if (pluginPanelLoader.active && pluginPanelLoader.item && activePanelServiceItem === serviceItem && pluginPanelLoader.item.opened) {
      pluginPanelLoader.item.close()
      return
    }

    // Close any existing open panel first
    if (pluginPanelLoader.item && pluginPanelLoader.item.opened && typeof pluginPanelLoader.item.close === "function") {
      pluginPanelLoader.item.close()
    }

    activePanelAnchorItem = anchorItem
    activePanelServiceItem = serviceItem
    updatePanelAnchor(anchorItem)

    pluginPanelLoader.targetPluginId = pluginId
    pluginPanelLoader.targetService = resolvePluginService(pluginId)
    pluginPanelLoader.targetItem = serviceItem

    // Re-instantiate cleanly to guarantee pristine layer-shell surface lifecycle
    pluginPanelLoader.active = false
    pluginPanelLoader.source = panelUrl
    pluginPanelLoader.active = true
  }

  function openTrayMenu(item, anchorItem, mouse) {
    if (pluginPanelLoader.item && typeof pluginPanelLoader.item.close === "function") {
      pluginPanelLoader.item.close()
    }
    if (!item || !item.menu) {
      if (item && typeof item.display === "function") {
        var point = anchorItem.QsWindow.contentItem.mapFromItem(anchorItem, mouse.x, mouse.y)
        item.display(anchorItem.QsWindow.window, point.x, point.y)
      }
      return
    }

    // Reset before switching items: trayMenuOpener.menu binds to
    // activeTrayItem.menu, so assigning a new item invalidates the old root's
    // children immediately, before any nested opener referencing them would
    // otherwise get torn down.
    resetTrayMenu()
    activeTrayItem = item
    activeTrayAnchor = anchorItem
    trayMenuOpen = true
  }

  function pluginIcon(name) {
    return Qt.resolvedUrl("icons/" + name).toString()
  }

  function trayIconSource(icon, item) {
    var s = String(icon || "").toLowerCase()
    var iid = item ? String(item.id || "").toLowerCase() : ""
    var title = item ? String(item.title || "").toLowerCase() : ""

    if (s.indexOf("input-keyboard") !== -1 || (s.indexOf("keyboard") !== -1 && s.indexOf("fcitx") !== -1)) {
      return pluginIcon("fcitx-en.svg")
    }
    if (s.indexOf("fcitx-pinyin") !== -1 || s.indexOf("pinyin") !== -1) {
      return pluginIcon("fcitx-pinyin.svg")
    }
    if (s.indexOf("clash") !== -1 || iid.indexOf("clash") !== -1 || title.indexOf("clash") !== -1) {
      return pluginIcon("clash-verge.svg")
    }
    if (s.indexOf("antigravity") !== -1 || iid.indexOf("antigravity") !== -1 || title.indexOf("antigravity") !== -1) {
      return pluginIcon("antigravity.svg")
    }
    if (s.indexOf("tailscale") !== -1 || iid.indexOf("tailscale") !== -1 || title.indexOf("tailscale") !== -1) {
      return pluginIcon("tailscale.svg")
    }
    if (s.indexOf("syncthing") !== -1 || iid.indexOf("syncthing") !== -1 || title.indexOf("syncthing") !== -1) {
      return pluginIcon("syncthing.svg")
    }
    if (s.indexOf("wechat") !== -1 || iid.indexOf("wechat") !== -1 || title.indexOf("wechat") !== -1 || s.indexOf("微信") !== -1 || title.indexOf("微信") !== -1) {
      return pluginIcon("wechat.svg")
    }
    if (s.indexOf("telegram") !== -1 || iid.indexOf("telegram") !== -1 || title.indexOf("telegram") !== -1) {
      return pluginIcon("telegram.svg")
    }
    if (s.indexOf("wallpaper") !== -1 || iid.indexOf("wallpaper") !== -1 || title.indexOf("wallpaper") !== -1 || s.indexOf("bing") !== -1) {
      return pluginIcon("bing-wallpaper.svg")
    }

    return String(icon || "")
  }

  // Symbolic icons ship a fixed fill (often near-white) that the host is meant
  // to recolor to its foreground; detect them by the freedesktop "-symbolic"
  // name suffix so they can be tinted instead of rendered as-is.
  function iconIsSymbolic(icon, item) {
    var s = String(icon || "").toLowerCase()
    var iid = item ? String(item.id || "").toLowerCase() : ""
    var title = item ? String(item.title || "").toLowerCase() : ""

    // 自定义单色透明矢量应用：纳管至系统主题动态着色通道 (MultiEffect)
    if (s.indexOf("input-keyboard") !== -1 || s.indexOf("fcitx") !== -1 || s.indexOf("pinyin") !== -1) {
      return true
    }
    if (s.indexOf("clash") !== -1 || iid.indexOf("clash") !== -1 || title.indexOf("clash") !== -1) {
      return true
    }
    if (s.indexOf("antigravity") !== -1 || iid.indexOf("antigravity") !== -1 || title.indexOf("antigravity") !== -1) {
      return true
    }
    if (s.indexOf("tailscale") !== -1 || iid.indexOf("tailscale") !== -1 || title.indexOf("tailscale") !== -1) {
      return true
    }
    if (s.indexOf("syncthing") !== -1 || iid.indexOf("syncthing") !== -1 || title.indexOf("syncthing") !== -1) {
      return true
    }
    if (s.indexOf("wechat") !== -1 || iid.indexOf("wechat") !== -1 || title.indexOf("wechat") !== -1 || s.indexOf("微信") !== -1 || title.indexOf("微信") !== -1) {
      return true
    }
    if (s.indexOf("telegram") !== -1 || iid.indexOf("telegram") !== -1 || title.indexOf("telegram") !== -1) {
      return true
    }
    if (s.indexOf("wallpaper") !== -1 || iid.indexOf("wallpaper") !== -1 || title.indexOf("wallpaper") !== -1 || s.indexOf("bing") !== -1) {
      return true
    }

    // 原生彩色应用图标白名单：保持原生彩色，防止被 MultiEffect 强行覆色
    if (s.indexOf("joplin") !== -1 || iid.indexOf("joplin") !== -1 || title.indexOf("joplin") !== -1) {
      return false
    }
    if (s.indexOf("obsidian") !== -1 || iid.indexOf("obsidian") !== -1 || title.indexOf("obsidian") !== -1) {
      return false
    }

    var name = s.split("?")[0]
    return name.slice(-9) === "-symbolic"
  }

  function trayTooltip(item) {
    return item.tooltipTitle || item.title || item.id || ""
  }

  property bool tailscaleRunning: false
  property bool syncthingRunning: false
  property int serviceProbeRevision: 0

  readonly property bool bingWallpaperRunning: {
    var _rev = root.serviceProbeRevision
    return root.isPluginRunning("io.github.odessa2.bing-wallpaper")
  }

  Connections {
    target: {
      var hb = root.findHostBar()
      return (hb && hb.shell) ? hb.shell.pluginRegistry : (root.bar && root.bar.shell ? root.bar.shell.pluginRegistry : null)
    }
    ignoreUnknownSignals: true
    function onPluginsChanged() {
      root.serviceProbeRevision++
    }
  }

  Process {
    id: serviceProbeProcess
    running: false
    command: ["sh", "-c", "echo \"tailscale:$([ -S /run/tailscale/tailscaled.sock ] || pgrep -f tailscaled >/dev/null && echo 1 || echo 0)\"; echo \"syncthing:$(pgrep -x syncthing >/dev/null && echo 1 || echo 0)\""]
    stdout: StdioCollector {
      id: probeStdout
      waitForEnd: true
      onStreamFinished: {
        var lines = (text || "").trim().split("\n")
        for (var i = 0; i < lines.length; i++) {
          var parts = lines[i].split(":")
          if (parts[0] === "tailscale") {
            root.tailscaleRunning = (parts[1] === "1")
          } else if (parts[0] === "syncthing") {
            root.syncthingRunning = (parts[1] === "1")
          }
        }
        root.serviceProbeRevision++
      }
    }
  }

  Timer {
    id: serviceProbeTimer
    interval: 10000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!serviceProbeProcess.running) {
        serviceProbeProcess.running = true
      }
      root.serviceProbeRevision++
    }
  }

  readonly property var extraServices: {
    var _rev = root.serviceProbeRevision
    var list = []

    if (root.bingWallpaperRunning) {
      list.push({
        id: "bing-wallpaper",
        title: "Bing Wallpaper",
        tooltipTitle: "Bing Wallpaper",
        icon: "bing-wallpaper",
        glyph: "\uf1c5",
        pluginId: "io.github.odessa2.bing-wallpaper",
        panelSource: "Panel.qml",
        status: Status.Active,
        activate: function() {
          Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "io.github.odessa2.bing-wallpaper"])
        },
        secondaryActivate: function() {
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
      })
    }

    if (root.tailscaleRunning) {
      list.push({
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
      })
    }

    if (root.syncthingRunning) {
      list.push({
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
      })
    }

    return list
  }

  function classifyItem(item) {
    var iid = String(item.id || "")
    if (hiddenIds.indexOf(iid) !== -1) return "hidden"
    if (pinnedIds.indexOf(iid) !== -1) return "pinned"
    var lower = iid.toLowerCase()
    for (var i = 0; i < pinnedIds.length; i++) {
      var p = String(pinnedIds[i]).toLowerCase()
      if (p.length > 0 && lower.indexOf(p) !== -1) return "pinned"
    }
    return "drawer"
  }

  function ownedByOmarchy(item) {
    var iid = item ? String(item.id || "").toLowerCase() : ""
    if (iid === "fcitx" || iid.indexOf("fcitx") !== -1) return true
    var layout = root.bar && root.bar.layoutConfig ? root.bar.layoutConfig : null
    return TrayModel.ownedByOmarchy(item, layout)
  }

  function bucket(category) {
    var values = SystemTray.items.values
    var result = []
    var seen = ({})
    for (var i = 0; i < values.length; i++) {
      var item = values[i]
      if (!item || item.status === Status.Passive) continue
      if (ownedByOmarchy(item)) continue
      var iid = String(item.id || item.title || "").toLowerCase()
      if (iid) seen[iid] = true
      if (category === "all") {
        result.push(item)
        continue
      }
      if (classifyItem(item) === category) result.push(item)
    }

    for (var j = 0; j < extraServices.length; j++) {
      var sItem = extraServices[j]
      if (!sItem || sItem.status === Status.Passive) continue
      var sid = String(sItem.id || sItem.title || "").toLowerCase()
      if (seen[sid]) continue
      if (category === "all") {
        result.push(sItem)
        continue
      }
      if (classifyItem(sItem) === category) result.push(sItem)
    }

    return result
  }

  function persistTrayState(pinned, hidden) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var id = root.moduleName || "omarchy.tray"
    root.bar.shell.updateEntryInline(id, { id: id, pinned: pinned, hidden: hidden })
  }

  function togglePin(iid) {
    var p = pinnedIds.slice(), h = hiddenIds.slice()
    var idx = p.indexOf(iid)
    if (idx !== -1) p.splice(idx, 1)
    else {
      p.push(iid)
      var hi = h.indexOf(iid)
      if (hi !== -1) h.splice(hi, 1)
    }
    persistTrayState(p, h)
  }

  function toggleHide(iid) {
    var p = pinnedIds.slice(), h = hiddenIds.slice()
    var idx = h.indexOf(iid)
    if (idx !== -1) h.splice(idx, 1)
    else {
      h.push(iid)
      var pi = p.indexOf(iid)
      if (pi !== -1) p.splice(pi, 1)
    }
    persistTrayState(p, h)
  }

  visible: pinnedItems.length > 0 || drawerCount > 0
  clip: false
  implicitWidth: root.vertical ? root.barSize : trayContent.implicitWidth
  implicitHeight: root.vertical ? trayContent.implicitHeight : root.barSize

  Behavior on revealProgress {
    NumberAnimation { duration: root.animationDuration; easing.type: Easing.OutCubic }
  }

  Loader {
    id: trayContent
    anchors.fill: parent
    sourceComponent: root.vertical ? verticalTray : horizontalTray
  }

  Component {
    id: horizontalTray

    Item {
      id: horizontalTrayRoot

      readonly property int pinnedWidth: pinnedRow.implicitWidth
      readonly property int drawerBlockWidth: root.allItems.length > 0 ? expandIcon.implicitWidth + root.drawerExtent : 0

      implicitWidth: pinnedWidth + drawerBlockWidth
      implicitHeight: root.barSize

      // Mask out the empty area the collapsed drawer reserves for its slide-in,
      // so hovering it doesn't trigger expand and clicks pass through.
      containmentMask: QtObject {
        function contains(point: point): bool {
          if (point.y < 0 || point.y > horizontalTrayRoot.height) return false
          // Drawer reveals leftward; chevron sits at the right end when collapsed
          // and slides left as it opens. The visible region starts at the chevron.
          var chevronX = root.drawerExtent - root.revealExtent
          if (point.x >= chevronX && point.x <= horizontalTrayRoot.drawerBlockWidth) return true
          // Pinned items, placed to the right of the drawer block.
          var pinnedStart = horizontalTrayRoot.drawerBlockWidth
          return point.x >= pinnedStart && point.x <= horizontalTrayRoot.implicitWidth
        }
      }

      Item {
        id: drawerArea
        x: 0
        width: horizontalTrayRoot.drawerBlockWidth
        height: root.barSize
        visible: root.allItems.length > 0

        HoverHandler {
          onHoveredChanged: root.expanded = hovered
        }

        BarIconButton {
          id: expandIcon
          bar: root.bar
          width: implicitWidth
          height: implicitHeight
          x: root.drawerExtent - root.revealExtent
          text: "\uf053"
          onPressed: function(button) {
            if (button === Qt.RightButton) {
              if (pluginPanelLoader.item && typeof pluginPanelLoader.item.close === "function") {
                pluginPanelLoader.item.close()
              }
              root.managePopupOpen = !root.managePopupOpen
            }
          }
        }

        Item {
          id: trayClip
          x: expandIcon.width
          anchors.verticalCenter: parent.verticalCenter
          width: root.drawerExtent
          height: root.barSize
          clip: true

          Row {
            id: trayIcons
            x: root.drawerExtent - root.revealExtent
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.trayItemGap
            layer.enabled: true

            Repeater {
              model: root.drawerItems
              TrayItem {}
            }
          }
        }
      }

      Row {
        id: pinnedRow
        x: drawerArea.x + horizontalTrayRoot.drawerBlockWidth
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.trayItemGap
        leftPadding: root.pinnedItems.length > 0 && root.allItems.length > 0 ? root.trayJoinGap : 0
        Repeater {
          model: root.pinnedItems
          TrayItem {}
        }
      }
    }
  }

  Component {
    id: verticalTray

    Item {
      id: verticalTrayRoot

      readonly property int pinnedHeight: pinnedCol.implicitHeight
      readonly property int drawerBlockHeight: root.allItems.length > 0 ? expandIcon.implicitHeight + root.drawerExtent : 0

      implicitWidth: root.barSize
      implicitHeight: pinnedHeight + drawerBlockHeight

      containmentMask: QtObject {
        function contains(point: point): bool {
          if (point.x < 0 || point.x > verticalTrayRoot.width) return false
          var chevronY = root.drawerExtent - root.revealExtent
          if (point.y >= chevronY && point.y <= verticalTrayRoot.drawerBlockHeight) return true
          var pinnedStart = verticalTrayRoot.drawerBlockHeight
          return point.y >= pinnedStart && point.y <= verticalTrayRoot.implicitHeight
        }
      }

      Item {
        id: drawerArea
        y: 0
        width: root.barSize
        height: verticalTrayRoot.drawerBlockHeight
        visible: root.allItems.length > 0

        HoverHandler {
          onHoveredChanged: root.expanded = hovered
        }

        BarIconButton {
          id: expandIcon
          bar: root.bar
          width: implicitWidth
          height: implicitHeight
          y: root.drawerExtent - root.revealExtent
          text: "\uf053"
          textRotation: 90
          onPressed: function(button) {
            if (button === Qt.RightButton) {
              if (pluginPanelLoader.item && typeof pluginPanelLoader.item.close === "function") {
                pluginPanelLoader.item.close()
              }
              root.managePopupOpen = !root.managePopupOpen
            }
          }
        }

        Item {
          id: trayClip
          y: expandIcon.height
          anchors.horizontalCenter: parent.horizontalCenter
          width: root.barSize
          height: root.drawerExtent
          clip: true

          Column {
            id: trayIcons
            y: root.drawerExtent - root.revealExtent
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: root.trayItemGap
            layer.enabled: true

            Repeater {
              model: root.drawerItems
              TrayItem {}
            }
          }
        }
      }

      Column {
        id: pinnedCol
        y: drawerArea.y + verticalTrayRoot.drawerBlockHeight
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.trayItemGap
        topPadding: root.pinnedItems.length > 0 && root.allItems.length > 0 ? root.trayJoinGap : 0
        Repeater {
          model: root.pinnedItems
          TrayItem {}
        }
      }
    }
  }

  PopupCard {
    id: managePopup
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.managePopupOpen
    contentWidth: managePopup.fittedContentWidth(Style.space(300))
    contentHeight: managePopup.fittedContentHeight(manageColumn.implicitHeight)

    Column {
      id: manageColumn
      anchors.fill: parent
      spacing: Style.space(8)

      Text {
        text: "Tray icons"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Text {
        text: "Pinned icons stay visible. Hidden icons never show."
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        width: parent.width
      }

      Text {
        visible: root.allItems.length === 0
        text: "No tray items reporting."
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.italic: true
      }

      Repeater {
        model: root.allItems
        delegate: Item {
          id: rowRoot
          required property var modelData
          required property int index
          width: manageColumn.width
          implicitHeight: 28

          readonly property string itemId: String(modelData.id || "")
          readonly property string displayName: {
            var t = String(modelData.title || "").trim()
            if (t) return t
            var tt = String(modelData.tooltipTitle || "").trim()
            if (tt) return tt
            var id = String(modelData.id || "")
            var slash = id.lastIndexOf("/")
            return slash !== -1 ? id.substring(slash + 1) : (id || "Unknown")
          }
          readonly property bool isPinned: root.pinnedIds.indexOf(itemId) !== -1
          readonly property bool isHidden: root.hiddenIds.indexOf(itemId) !== -1

          TrayIcon {
            id: rowIcon
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            width: 16
            height: 16
            icon: rowRoot.modelData.icon
            item: rowRoot.modelData
          }

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: rowIcon.right
            anchors.leftMargin: Style.space(10)
            anchors.right: rowHideBtn.left
            anchors.rightMargin: Style.space(8)
            text: rowRoot.displayName
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Button {
            id: rowPinBtn
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            iconText: "\uf08d"
            text: rowRoot.isPinned ? "Unpin" : "Pin"
            foreground: root.foreground
            horizontalPadding: 8
            verticalPadding: 3
            iconSize: Style.font.bodySmall
            fontSize: Style.font.bodySmall
            onClicked: root.togglePin(rowRoot.itemId)
          }

          Button {
            id: rowHideBtn
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: rowPinBtn.left
            anchors.rightMargin: Style.space(6)
            iconText: "\uf06e"
            text: rowRoot.isHidden ? "Show" : "Hide"
            foreground: root.foreground
            horizontalPadding: 8
            verticalPadding: 3
            iconSize: Style.font.bodySmall
            fontSize: Style.font.bodySmall
            onClicked: root.toggleHide(rowRoot.itemId)
          }
        }
      }
    }
  }

  Item {
    id: panelAnchor
    visible: true
    opacity: 0
    width: root.trayItemExtent
    height: root.trayItemExtent
    x: 0
    y: 0
  }

  function syncBingWallpaperConfigFile(settings) {
    if (!settings || typeof settings !== "object") return
    var market = String(settings.market || "auto")
    var setWallpaper = settings.setWallpaper !== false
    var payload = JSON.stringify({ market: market, setWallpaper: setWallpaper }, null, 2)
    var targetPath = Quickshell.env("HOME") + "/.config/omarchy/bing-wallpaper.json"
    Quickshell.execDetached(["bash", "-c", "cat << 'EOF' > \"" + targetPath + "\"\n" + payload + "\nEOF"])
  }

  Loader {
    id: pluginPanelLoader
    active: false
    visible: false
    property string targetPluginId: ""
    property var targetService: null
    property var targetItem: null

    function injectProperties() {
      if (!item) return
      var hb = root.findHostBar()
      if ("bar" in item) item.bar = hb || root.bar
      if ("anchorItem" in item) item.anchorItem = panelAnchor
      if ("hostWidget" in item) item.hostWidget = null
      var svc = targetService || root.resolvePluginService(targetPluginId)
      if ("service" in item && svc) item.service = svc
      var pluginSettings = root.resolvePluginSettings(targetPluginId)
      if ("settings" in item) item.settings = pluginSettings
      if (svc && pluginSettings && targetPluginId === "io.github.odessa2.bing-wallpaper") {
        if (pluginSettings.market) {
          if ("legacyMarket" in svc) svc.legacyMarket = pluginSettings.market
          if ("legacySetWallpaper" in svc) svc.legacySetWallpaper = pluginSettings.setWallpaper !== false
          if ("legacyConfigFound" in svc) svc.legacyConfigFound = true
          if ("legacyConfigurationLoaded" in svc) svc.legacyConfigurationLoaded = true
          if (typeof svc.setConfiguration === "function") {
            svc.setConfiguration(pluginSettings.market, pluginSettings.setWallpaper !== false)
          }
        }
      }
    }

    onLoaded: {
      injectProperties()
      Qt.callLater(function() {
        if (!item) return
        injectProperties()
        if (typeof item.open === "function") item.open()
        else if (typeof item.toggle === "function") item.toggle()
      })
    }
  }

  Connections {
    target: pluginPanelLoader.item
    ignoreUnknownSignals: true
    function onOpenedChanged() {
      if (pluginPanelLoader.item && !pluginPanelLoader.item.opened) {
        unloadPanelTimer.restart()
      }
    }
    function onSettingsChanged() {
      if (pluginPanelLoader.item && pluginPanelLoader.targetPluginId === "io.github.odessa2.bing-wallpaper") {
        var s = pluginPanelLoader.item.settings
        root.syncBingWallpaperConfigFile(s)
        var svc = pluginPanelLoader.targetService || root.resolvePluginService("io.github.odessa2.bing-wallpaper")
        if (svc && s && s.market) {
          if ("legacyMarket" in svc) svc.legacyMarket = s.market
          if ("legacySetWallpaper" in svc) svc.legacySetWallpaper = s.setWallpaper !== false
          if ("legacyConfigFound" in svc) svc.legacyConfigFound = true
          if ("legacyConfigurationLoaded" in svc) svc.legacyConfigurationLoaded = true
          if (typeof svc.setConfiguration === "function") {
            svc.setConfiguration(s.market, s.setWallpaper !== false)
          }
          if (typeof svc.refresh === "function") {
            svc.refresh()
          }
        }
      }
    }
  }

  Timer {
    id: unloadPanelTimer
    interval: 200
    onTriggered: {
      if (pluginPanelLoader.item && !pluginPanelLoader.item.opened) {
        pluginPanelLoader.active = false
      }
    }
  }

  Component.onCompleted: {
    Qt.callLater(function() {
      var s = root.resolvePluginSettings("io.github.odessa2.bing-wallpaper")
      if (s && s.market) {
        root.syncBingWallpaperConfigFile(s)
      }
    })
  }

  QsMenuOpener {
    id: trayMenuOpener
    menu: root.activeTrayItem ? root.activeTrayItem.menu : null
  }

  PopupCard {
    id: trayMenuPopup
    anchorItem: root.activeTrayAnchor || root
    owner: root
    bar: root.bar
    open: root.trayMenuOpen
    // The card fades out over 140ms (visible stays true for that whole time --
    // see PopupCard's own visible: open || card.opacity > 0), so resetting on
    // "open" would swap a live submenu for the root menu mid-fade: a visible
    // flash, and a resize/reposition if the two have different geometry. Wait
    // for the fade to actually finish. Switching to a different tray item
    // still resets immediately, from openTrayMenu() itself.
    onVisibleChanged: if (!visible) root.resetTrayMenu()
    padding: Style.space(8)
    borderColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45)
    contentWidth: trayMenuPopup.fittedContentWidth(Style.space(232))
    contentHeight: trayMenuPopup.fittedContentHeight(menuHeaderHeight + trayMenuColumn.implicitHeight, Style.space(420))

    // Column skips invisible children but keeps reporting their height, so
    // read the header's extent through its own visibility.
    readonly property int menuHeaderHeight: menuHeader.visible ? menuHeader.implicitHeight : 0

    Column {
      id: trayMenuLayout
      anchors.fill: parent
      spacing: 0

      // Header for a drilled-into submenu: names where we are and walks back
      // out. Pinned above the Flickable rather than scrolling with the rows,
      // so the way back stays reachable in a submenu taller than the card.
      // Only present below the root level, so the root menu is unchanged.
      Column {
        id: menuHeader
        visible: root.submenuDepth > 0
        width: trayMenuLayout.width
        spacing: 0

        Item {
          id: menuBackRow
          width: menuHeader.width
          implicitHeight: Style.space(30)

          Rectangle {
            anchors.fill: parent
            radius: Math.max(2, Style.cornerRadius)
            color: backMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            width: Style.space(22)
            horizontalAlignment: Text.AlignHCenter
            text: "\u2039"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.space(28)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            text: root.currentTitle
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          MouseArea {
            id: backMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.menuLevelSettling) return
              // Reset before the model swap so the parent level shows from
              // the top (same ordering as the row delegate below).
              trayMenuFlick.contentY = 0
              root.leaveSubmenu()
            }
          }
        }

        Item {
          width: menuHeader.width
          implicitHeight: Style.space(11)

          Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            height: 1
            color: Color.popups.border
            opacity: 0.45
          }
        }
      }

      Flickable {
        id: trayMenuFlick
        width: trayMenuLayout.width
        height: trayMenuLayout.height - trayMenuPopup.menuHeaderHeight
        contentWidth: width
        contentHeight: trayMenuColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: trayMenuColumn
          width: trayMenuFlick.width
          spacing: 0

          Repeater {
            model: root.currentChildren

            delegate: Item {
              id: menuRow
              required property var modelData
              required property int index

              readonly property string rowText: String(modelData.text || "")
              readonly property string activeTitle: root.activeTrayItem ? String(root.activeTrayItem.title || root.activeTrayItem.id || "") : ""
              // Both only ever describe the root menu; inside a submenu the first
              // rows are real entries and must not be swallowed.
              readonly property bool atRoot: root.submenuDepth === 0
              readonly property bool rootTitleEntry: atRoot && index === 0 && modelData.hasChildren && rowText.toLowerCase() === activeTitle.toLowerCase()
              readonly property bool leadingSeparator: atRoot && modelData.isSeparator && index <= 1
              readonly property bool hiddenRow: rootTitleEntry || leadingSeparator

              visible: !hiddenRow
              width: trayMenuColumn.width
              implicitHeight: hiddenRow ? 0 : (modelData.isSeparator ? Style.space(11) : Style.space(30))
              opacity: modelData.enabled ? 1.0 : 0.45

              Rectangle {
                visible: menuRow.modelData.isSeparator
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                height: 1
                color: Color.popups.border
                opacity: 0.45
              }

              Rectangle {
                visible: !menuRow.modelData.isSeparator
                anchors.fill: parent
                radius: Math.max(2, Style.cornerRadius)
                color: rowMouse.containsMouse && menuRow.modelData.enabled ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
              }

              Text {
                textFormat: Text.PlainText
                visible: !menuRow.modelData.isSeparator && menuRow.modelData.buttonType !== QsMenuButtonType.None
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                width: Style.space(22)
                horizontalAlignment: Text.AlignHCenter
                text: menuRow.modelData.checkState === Qt.Checked ? "\uf00c" : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Image {
                id: menuIcon
                visible: !menuRow.modelData.isSeparator && String(menuRow.modelData.icon || "") !== ""
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.space(24)
                width: Style.space(16)
                height: Style.space(16)
                fillMode: Image.PreserveAspectFit
                // Decode at physical pixels: IconImage uses the logical size,
                // which leaves PNG icons upscaled and blurry on HiDPI displays.
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: root.trayIconSource(menuRow.modelData.icon, null)
              }

              Text {
                textFormat: Text.PlainText
                visible: !menuRow.modelData.isSeparator
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: menuIcon.visible ? Style.space(46) : Style.space(28)
                anchors.right: submenuGlyph.left
                anchors.rightMargin: Style.space(8)
                text: menuRow.rowText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                id: submenuGlyph
                visible: !menuRow.modelData.isSeparator && menuRow.modelData.hasChildren
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                text: "\u203a"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: !menuRow.modelData.isSeparator && menuRow.modelData.enabled
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                  if (root.menuLevelSettling) return
                  if (menuRow.modelData.hasChildren) {
                    // Reset scroll BEFORE swapping the model: the swap destroys
                    // this delegate synchronously and ids stop resolving after.
                    trayMenuFlick.contentY = 0
                    root.enterSubmenu(menuRow.modelData, menuRow.rowText)
                  } else {
                    menuRow.modelData.triggered()
                    root.close()
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // Renders a tray icon, recoloring symbolic icons to the bar foreground so
  // they stay visible on any theme (a raw symbolic icon keeps its baked-in
  // fill and disappears against a matching background).
  component TrayIcon: Item {
    id: trayIconRoot
    required property var icon
    property var item: null
    readonly property bool symbolic: root.iconIsSymbolic(icon, item)

    Image {
      id: trayIconImage
      anchors.fill: parent
      fillMode: Image.PreserveAspectFit
      sourceSize.width: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      sourceSize.height: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      source: root.trayIconSource(trayIconRoot.icon, trayIconRoot.item)
      visible: !trayIconRoot.symbolic
      layer.enabled: trayIconRoot.symbolic
    }

    MultiEffect {
      anchors.fill: trayIconImage
      source: trayIconImage
      visible: trayIconRoot.symbolic
      colorization: 1.0
      colorizationColor: root.foreground
    }
  }

  component TrayItem: Item {
    id: trayItemRoot

    required property var modelData
    readonly property bool hasGlyph: !!modelData.glyph && String(modelData.glyph) !== ""

    visible: modelData.status !== Status.Passive
    implicitWidth: visible ? root.trayItemExtent : 0
    implicitHeight: visible ? root.trayItemExtent : 0
    width: implicitWidth
    height: implicitHeight

    function displayMenu(mouse) {
      root.openTrayMenu(trayItemRoot.modelData, trayItemRoot, mouse)
    }

    // 插件自身字形图标：直接采用插件定义的原生字形，并 100% 绑定系统 Theme 前景色
    Text {
      visible: trayItemRoot.hasGlyph
      anchors.centerIn: parent
      text: trayItemRoot.hasGlyph ? trayItemRoot.modelData.glyph : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.bar ? Style.bar.iconCanvas : Style.space(16)
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }

    // 外部应用矢量/位图图标：走单色拦截与 MultiEffect 着色
    TrayIcon {
      visible: !trayItemRoot.hasGlyph
      anchors.centerIn: parent
      width: Style.bar ? Style.bar.iconCanvas : Style.space(16)
      height: Style.bar ? Style.bar.iconCanvas : Style.space(16)
      icon: trayItemRoot.modelData.icon
      item: trayItemRoot.modelData
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (root.bar) root.bar.showTooltip(trayItemRoot, root.trayTooltip(modelData))
      onExited: if (root.bar) root.bar.hideTooltip(trayItemRoot)
      onPressed: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          if (trayItemRoot.modelData.menu) {
            trayItemRoot.displayMenu(mouse)
            mouse.accepted = true
          } else if (typeof trayItemRoot.modelData.secondaryActivate === "function") {
            trayItemRoot.modelData.secondaryActivate()
            mouse.accepted = true
          }
        }
      }
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          mouse.accepted = true
        } else if (mouse.button === Qt.MiddleButton) {
          if (typeof trayItemRoot.modelData.secondaryActivate === "function") {
            trayItemRoot.modelData.secondaryActivate()
          }
        } else if (trayItemRoot.modelData.onlyMenu) {
          trayItemRoot.displayMenu(mouse)
        } else if (trayItemRoot.modelData.pluginId || trayItemRoot.modelData.panelSource) {
          root.togglePluginPanel(trayItemRoot.modelData, trayItemRoot)
        } else if (typeof trayItemRoot.modelData.activate === "function") {
          trayItemRoot.modelData.activate()
        }
      }
      onWheel: function(wheel) {
        if (typeof trayItemRoot.modelData.scroll === "function") {
          trayItemRoot.modelData.scroll(wheel.angleDelta.y, false)
        }
      }
    }

    readonly property bool tooltipHovered: visible && opacity > 0 && mouseArea.containsMouse
  }
}
