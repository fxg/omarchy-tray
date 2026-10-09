function text(value) {
  return String(value || "").toLowerCase()
}

function itemNamed(item, name) {
  if (!item) return false
  return text(item.id).indexOf(name) !== -1
    || text(item.title).indexOf(name) !== -1
    || text(item.tooltipTitle).indexOf(name) !== -1
}

function entryId(entry) {
  if (typeof entry === "string") return entry
  if (entry && typeof entry === "object") {
    var id = entry.id
    if (id !== undefined && id !== null && String(id) !== "") return String(id)
  }
  return ""
}

function layoutHasWidget(layout, id) {
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var entries = layout && layout[sections[s]]
    if (!Array.isArray(entries)) continue
    for (var i = 0; i < entries.length; i++) {
      if (entryId(entries[i]) === id) return true
    }
  }
  return false
}

// LocalSend's item shows no state, offers only Open and Quit, and its primary
// click is a no-op, so Share > Receive is the whole surface. Hiding it by hand
// doesn't stick either: LocalSend picks a fresh tray id every launch.
function ownedByOmarchy(item, layout) {
  return itemNamed(item, "localsend")
    || (layoutHasWidget(layout, "omarchy.dropbox") && itemNamed(item, "dropbox"))
}

var SYSTEM_INFRA = {
  "omarchy.bar": true,
  "omarchy.background": true,
  "omarchy.idle": true,
  "omarchy.lock": true,
  "omarchy.polkit": true,
  "omarchy.osd": true,
  "omarchy.notifications": true,
  "omarchy.nightlight": true,
  "omarchy.clipboard": true,
  "omarchy.emojis": true,
  "omarchy.image-picker": true,
  "omarchy.reminders": true,
  "omarchy.wifiqr": true,
  "omarchy.dev-gallery": true,
  "omarchy.disk-speedtest": true,
  "omarchy.speedtest": true,
  "omarchy.spacer": true
}

function isSystemInfra(id) {
  return !!SYSTEM_INFRA[String(id || "")]
}

function extractShortName(id) {
  var s = String(id || "").toLowerCase()
  var lastDot = s.lastIndexOf(".")
  return lastDot !== -1 ? s.substring(lastDot + 1) : s
}

function resolveCategoryGlyph(category) {
  var c = String(category || "").toLowerCase()
  if (c === "time" || c === "date" || c === "calendar") return "\uf073"
  if (c === "weather") return "\uf0c2"
  if (c === "audio" || c === "media" || c === "music") return "\uf001"
  if (c === "system" || c === "settings" || c === "config") return "\uf013"
  if (c === "network" || c === "wifi" || c === "status") return "\uf05a"
  if (c === "utilities" || c === "tools") return "\uf0ad"
  if (c === "chat" || c === "social" || c === "messaging") return "\uf0e6"
  if (c === "development" || c === "developer") return "\uf120"
  return ""
}

function resolvePluginGlyph(manifest, pluginId) {
  if (!manifest && !pluginId) return "\uf12e"

  if (manifest && typeof manifest.glyph === "string" && manifest.glyph) {
    return manifest.glyph
  }
  var bw = manifest && manifest.barWidget ? manifest.barWidget : null
  if (bw && typeof bw.glyph === "string" && bw.glyph) {
    return bw.glyph
  }

  var lower = String(pluginId || "").toLowerCase()
  if (lower.indexOf("bing-wallpaper") !== -1 || lower.indexOf("wallpaper") !== -1) return "\uf1c5"
  if (lower.indexOf("agenda") !== -1 || lower.indexOf("calendar") !== -1) return "󰃭"
  if (lower.indexOf("weather") !== -1) return "\uf0c2"
  if (lower.indexOf("music") !== -1 || lower.indexOf("audio") !== -1) return "\uf001"
  if (lower.indexOf("mail") !== -1) return "\uf0e0"

  if (bw && bw.category) {
    var catGlyph = resolveCategoryGlyph(bw.category)
    if (catGlyph) return catGlyph
  }

  return "\uf12e"
}

function resolvePluginIconName(manifest, pluginId) {
  if (!manifest && !pluginId) return "plugin-generic.svg"
  var bw = manifest && manifest.barWidget ? manifest.barWidget : null
  if (bw && bw.icon && typeof bw.icon === "string") return bw.icon
  if (manifest && manifest.icon && typeof manifest.icon === "string") return manifest.icon
  var shortName = extractShortName(pluginId)
  return shortName || "plugin-generic.svg"
}

if (typeof module !== "undefined") {
  module.exports = {
    itemNamed: itemNamed,
    entryId: entryId,
    layoutHasWidget: layoutHasWidget,
    ownedByOmarchy: ownedByOmarchy,
    isSystemInfra: isSystemInfra,
    extractShortName: extractShortName,
    resolveCategoryGlyph: resolveCategoryGlyph,
    resolvePluginGlyph: resolvePluginGlyph,
    resolvePluginIconName: resolvePluginIconName
  }
}
