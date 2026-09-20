import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

// Plugin-manager panel. Summoned/toggled through the shell host:
//   omarchy-shell shell toggle nosignal.plugin-manager
// The host calls open(payloadJson) / close() and reads `opened`.
//
// Lists installed shell plugins with an on/off switch each, grouped
// third-party first, then optional first-party bar widgets, alphabetical
// within groups. The first-party group is a twirl-down, folded away by
// default — it is long, rarely touched, and its rows would otherwise push
// the third-party plugins (the ones people actually came here for) off the
// top of the list. Folding it also keeps the card short on a stock box.
// The list scrolls when it genuinely overflows the capped card, with a
// scrollbar that appears only then. Deliberately hidden: core shell infrastructure
// (bar, polkit, lock, idle, notifications, osd, launcher, menu, background,
// clipboard, image-picker) and every first-party plugin without a
// "bar-widget" kind — the registry treats first-party services/overlays as
// always-enabled, so a switch for them would be a lie.
//
// Toggling calls `omarchy-shell shell setPluginEnabled <id> <bool>` — the
// exact operation `omarchy plugin enable/disable` performs. The CLI's extra
// rescanPlugins step is skipped on purpose: a rescan unloads every open
// panel, including this one. Toggles of plugins that themselves have a
// panel/overlay/menu kind still destroy this panel as a side effect (see
// the toggling section), so those run detached and re-summon the manager.
// State is re-read from the shell after every toggle rather than assumed;
// a failed toggle shows a brief error on the row.
Item {
  id: root

  property bool opened: false

  readonly property string selfId: "nosignal.plugin-manager"

  // Injected by the shell host right after the Loader resolves. Used to keep
  // the host's open-flag honest on close(), and to self-restore after the
  // host's panel Instantiator rebuild destroys a visibly-open instance —
  // the host's openPanelIds flag survives the rebuild; our `opened` does not.
  property var shell: null
  onShellChanged: {
    if (!root.opened && root.shell && root.shell.openPanelIds
        && root.shell.openPanelIds[root.selfId] === true)
      root.open("{}")
  }

  // Core shell plugins that must never appear in the list, even though some
  // carry a bar-widget kind (menu, notifications). Spacer is a structural
  // multi-instance layout tool, not a plugin you enable/disable.
  readonly property var hiddenFirstParty: ({
    "omarchy.bar": true,
    "omarchy.polkit": true,
    "omarchy.lock": true,
    "omarchy.idle": true,
    "omarchy.notifications": true,
    "omarchy.osd": true,
    "omarchy.launcher": true,
    "omarchy.menu": true,
    "omarchy.background": true,
    "omarchy.clipboard": true,
    "omarchy.image-picker": true,
    "omarchy.spacer": true
  })

  // Flat selectable model: { id, name, caption, enabled, locked, group }.
  // Headers live in `groups`, not here. Rows flow column-major into two
  // columns per group: flat order = read down the left column, then the
  // right — so alphabetical order reads downward like a directory listing.
  property var rows: []
  // Per group: { label, start, count, nRows, rows } where nRows is the
  // per-column row count (ceil(count / 2)) and start indexes into `rows`.
  property var groups: []
  property bool loaded: false

  // The first-party optional bar widgets start folded away. Click the group
  // header or press `f` to twirl it open. Collapsed rows are left out of
  // `rows` entirely rather than merely hidden, so selection, grid navigation
  // and the height math all keep working on exactly what is on screen.
  property bool firstPartyExpanded: false

  // Last fetch, kept so twirling a group open or shut can rebuild the model
  // without shelling out for state that hasn't changed.
  property var lastPlugins: []
  property var lastConfig: ({})

  // Selection cursor (flat index into rows).
  property int selectedIndex: -1
  property bool cursorActive: true

  // One toggle in flight at a time.
  property string busyId: ""
  property bool busyTarget: false

  // id -> short error message, cleared a few seconds after the last failure.
  property var rowErrors: ({})

  // "That's me" flash on the panel's own locked row. Holds the message so
  // it can name the action that was refused, not just the row.
  property string selfFlashMsg: ""

  // Row id awaiting a remove confirmation. Removal takes the plugin off
  // disk, so it never rides a single keystroke — the row turns into a
  // confirm strip and only Enter/y goes through.
  property string confirmRemoveId: ""

  // Transient footer line, e.g. what was just removed.
  property string noticeText: ""

  // Moving the cursor abandons a pending confirmation. Covers both the
  // keyboard and hover-selection, so the confirm can never outlive the row
  // it belongs to.
  onSelectedIndexChanged: {
    if (root.confirmRemoveId === "") return
    var i = root.selectedIndex
    if (i < 0 || i >= root.rows.length || root.rows[i].id !== root.confirmRemoveId)
      root.confirmRemoveId = ""
  }

  // Shares the [menu] surface tokens so themes that style the menu style
  // this panel too — same approach as the sibling panels.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color accent: Color.accent
  property color urgent: Color.urgent
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.md
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)

  // Row geometry — mirrors Ui/Toggle's implicit height formula so the list
  // height is deterministic.
  readonly property int rowGap: Style.spacing.xs
  readonly property int colGap: Style.spacing.md
  readonly property int pluginRowH: Math.max(54, Style.font.subtitle + Style.spacing.xs + Style.font.caption + Style.spacing.huge)
  readonly property int groupHeaderH: Style.font.caption + Style.spacing.md
  readonly property int footerH: Style.font.caption + Style.spacing.xs
  // Height of the on/off/remove control. Matches ToggleSwitch's track height
  // so swapping the switch for segments left row geometry — and therefore the
  // deterministic list height math — untouched.
  readonly property int segH: Math.max(22, Math.round(Style.spacing.controlHeight * 0.55))

  // A detached toggle runner re-summons us with {highlight: <id>} (and
  // optionally {error: <msg>}) so the reopened panel lands on the row that
  // was toggled instead of resetting to the top.
  property string pendingHighlight: ""

  function open(payloadJson) {
    root.opened = true
    root.ensureSelfReference()
    root.busyId = ""  // a detached toggle may have finished while we were down
    var payload = null
    try { payload = JSON.parse(String(payloadJson || "")) } catch (e) { payload = null }
    if (payload && payload.highlight) {
      root.pendingHighlight = String(payload.highlight)
      if (payload.error) {
        var errors = ({})
        for (var k in root.rowErrors) errors[k] = root.rowErrors[k]
        // Show what actually went wrong where the runner captured it — a
        // removal can fail for reasons a toggle never does.
        var msg = String(payload.error).trim().split("\n").pop()
        if (msg.length > 64) msg = msg.substring(0, 63) + "…"
        errors[root.pendingHighlight] = msg !== ""
          ? msg : "failed — try: omarchy plugin rescan"
        root.rowErrors = errors
        errorTimer.restart()
      }
    }
    if (payload && payload.notice) {
      root.noticeText = String(payload.notice)
      noticeTimer.restart()
    }
    root.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    if (!root.opened) return
    root.opened = false
    // Keep the host's openPanelIds in sync: without this, an Esc-closed
    // panel would wrongly self-restore on the next delegate rebuild. The
    // host's hide() calls close() again; the opened guard above breaks the
    // cycle.
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.selfId)
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  function refresh() {
    fetchProc.running = true
  }

  // ------------------------------------------------------------ state fetch

  // One shot: current plugin registry + effective shell.json, marker-framed
  // like the sibling panels' multi-blob fetches.
  readonly property string fetchScript: [
    "printf '##PLUGINS\\n%s\\n' \"$(omarchy-shell shell listPlugins 2>/dev/null)\"",
    "printf '##CONFIG\\n%s\\n' \"$(omarchy-shell shell listShellConfig 2>/dev/null)\""
  ].join("\n")

  function parseFetch(raw) {
    var plugins = null
    var config = null
    var lines = String(raw || "").split("\n")
    var pending = ""
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (line === "##PLUGINS") { pending = "plugins"; continue }
      if (line === "##CONFIG") { pending = "config"; continue }
      if (!line || !pending) continue
      try {
        var j = JSON.parse(line)
        if (pending === "plugins") plugins = j
        else config = j
      } catch (e) {}
      pending = ""
    }
    root.loaded = true
    root.lastPlugins = plugins || []
    root.lastConfig = config || {}
    root.rebuild()
    if (root.pendingHighlight !== "") {
      // A highlight for a folded-away row would land nowhere — twirl the
      // group open rather than silently dropping it.
      if (root.indexOfId(root.pendingHighlight) < 0 && !root.firstPartyExpanded) {
        root.firstPartyExpanded = true
        root.rebuild()
      }
      var r = root.indexOfId(root.pendingHighlight)
      if (r >= 0) {
        root.selectedIndex = r
        root.cursorActive = true
        root.scrollTo(r)
      }
      root.pendingHighlight = ""
    }
  }

  // Rebuilds the visible model from the last fetch. Cheap enough to run on
  // every twirl.
  function rebuild() {
    var built = root.buildRows(root.lastPlugins || [], root.lastConfig || {})
    root.rows = built.rows
    root.groups = built.groups
    hoverGate.reset()
    root.ensureSelection()
  }

  function indexOfId(id) {
    for (var i = 0; i < root.rows.length; i++)
      if (root.rows[i].id === id) return i
    return -1
  }

  // Twirls the first-party group. Collapsing can strand the cursor on a row
  // that no longer exists (ensureSelection clamps it); expanding scrolls the
  // revealed rows into view but deliberately leaves the selection alone, so
  // a stray `f` can't move the cursor under a pending Space.
  function toggleFirstParty() {
    root.firstPartyExpanded = !root.firstPartyExpanded
    root.rebuild()
    if (root.firstPartyExpanded) {
      for (var gi = 0; gi < root.groups.length; gi++) {
        if (root.groups[gi].collapsible && root.groups[gi].count > 0) {
          root.scrollTo(root.groups[gi].start)
          break
        }
      }
    } else {
      root.scrollTo(root.selectedIndex)
    }
  }

  // Enabled = referenced in shell.json, same rule as PluginRegistry
  // findEntryLocation: a bar.layout entry or a plugins[] entry. (listPlugins'
  // own `enabled` flag reports first-party plugins as always-enabled, so it
  // can't drive a switch.)
  function isReallyEnabled(config, id) {
    if (!config || typeof config !== "object") return false
    var bar = config.bar || {}
    var layout = bar.layout || {}
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var arr = layout[sections[s]]
      if (!Array.isArray(arr)) continue
      for (var i = 0; i < arr.length; i++) {
        var e = arr[i]
        if (typeof e === "string" ? e === id : (e && e.id === id)) return true
      }
    }
    var plugins = config.plugins
    if (Array.isArray(plugins)) {
      for (var p = 0; p < plugins.length; p++) {
        var pe = plugins[p]
        if (typeof pe === "string" ? pe === id : (pe && pe.id === id)) return true
      }
    }
    return false
  }

  function isShown(p) {
    var kinds = Array.isArray(p.kinds) ? p.kinds : []
    // Bar replacements are picked in bar settings, not switched on and off.
    if (kinds.indexOf("bar") !== -1) return false
    if (!p.firstParty) return true
    if (root.hiddenFirstParty[p.id]) return false
    // First-party services/overlays/panels are always-on infrastructure;
    // only their bar widgets are genuinely optional.
    if (kinds.indexOf("bar-widget") === -1) return false
    return true
  }

  function buildRows(plugins, config) {
    var third = []
    var first = []
    for (var i = 0; i < plugins.length; i++) {
      var p = plugins[i]
      if (!p || !p.id || !root.isShown(p)) continue
      var kinds = Array.isArray(p.kinds) ? p.kinds : []
      var locked = p.id === root.selfId
      var row = {
        id: p.id,
        name: p.name || p.id,
        caption: p.id + " · " + kinds.join(", ") + (locked ? " · always on" : ""),
        enabled: locked ? true : root.isReallyEnabled(config, p.id),
        locked: locked,
        // Only third-party plugins are removable: the first-party ones live
        // in the shell's own tree, not ~/.config/omarchy/plugins, and the
        // manager can't very well delete itself out from under the panel.
        removable: !p.firstParty && !locked,
        // Toggling a panelish plugin rebuilds the host's panel delegates and
        // destroys this panel mid-toggle — such rows take the detached path.
        panelish: kinds.indexOf("panel") !== -1
          || kinds.indexOf("overlay") !== -1
          || kinds.indexOf("menu") !== -1
      }
      if (p.firstParty) first.push(row)
      else third.push(row)
    }
    function byName(a, b) {
      var an = a.name.toLowerCase(), bn = b.name.toLowerCase()
      return an < bn ? -1 : an > bn ? 1 : 0
    }
    third.sort(byName)
    first.sort(byName)

    var rows = []
    var groups = []
    // A collapsed group keeps its header (that's the twirl) but contributes
    // no rows at all — `count` 0 is the single flag the layout, the height
    // math and the seam-crossing navigation all key off.
    function addGroup(label, groupRows, collapsible) {
      if (groupRows.length === 0) return
      var collapsed = collapsible === true && !root.firstPartyExpanded
      var shown = collapsed ? [] : groupRows
      var on = 0
      for (var c = 0; c < groupRows.length; c++) if (groupRows[c].enabled) on++
      var g = groups.length
      for (var r = 0; r < shown.length; r++) shown[r].group = g
      groups.push({
        label: label,
        start: rows.length,
        count: shown.length,
        nRows: Math.ceil(shown.length / 2),
        rows: shown,
        collapsible: collapsible === true,
        collapsed: collapsed,
        total: groupRows.length,
        enabledCount: on
      })
      rows = rows.concat(shown)
    }
    addGroup("Third-party", third, false)
    addGroup("First-party (optional bar widgets)", first, true)
    return { rows: rows, groups: groups }
  }

  // ------------------------------------------------------------- selection
  //
  // Grid navigation over the flat model. Each group is a column-major
  // 2-column grid: flat position pos in a group maps to
  // column = floor(pos / nRows), rowInColumn = pos % nRows.
  // Up/down move within a column (crossing into the neighbouring group's
  // same column at the seam), left/right cross columns within a group,
  // Tab/Backtab walk the flat (alphabetical) order.

  function isSelectable(i) {
    return i >= 0 && i < root.rows.length
  }

  function ensureSelection() {
    if (root.isSelectable(root.selectedIndex)) return
    root.selectedIndex = root.rows.length > 0 ? 0 : -1
  }

  function beginNav() {
    hoverGate.reset()
    root.cursorActive = true
    if (!root.isSelectable(root.selectedIndex)) {
      root.ensureSelection()
      root.scrollTo(root.selectedIndex)
      return false
    }
    return true
  }

  function moveVertical(dir) {
    if (!root.beginNav()) return
    var i = root.selectedIndex
    var g = root.rows[i].group
    var G = root.groups[g]
    var pos = i - G.start
    var col = Math.floor(pos / G.nRows)
    var rowIn = pos % G.nRows
    var target = -1
    if (dir > 0) {
      if (rowIn + 1 < G.nRows && pos + 1 < G.count) {
        target = i + 1
      } else {
        // Seam: top of the same column in the next group that actually has
        // rows (clamped when that column is shorter, or missing entirely).
        // Collapsed groups contribute none, so they are stepped over.
        for (var ng = g + 1; ng < root.groups.length; ng++) {
          var NG = root.groups[ng]
          if (NG.count === 0) continue
          target = NG.start + Math.min(col * NG.nRows, NG.count - 1)
          break
        }
      }
    } else {
      if (rowIn > 0) {
        target = i - 1
      } else {
        // Seam: bottom of the same column in the previous group with rows.
        for (var pg = g - 1; pg >= 0; pg--) {
          var PG = root.groups[pg]
          if (PG.count === 0) continue
          target = PG.start + Math.min(col * PG.nRows + PG.nRows - 1, PG.count - 1)
          break
        }
      }
    }
    if (target >= 0) {
      root.selectedIndex = target
      root.scrollTo(target)
    }
  }

  function moveHorizontal(dir) {
    if (!root.beginNav()) return
    var i = root.selectedIndex
    var G = root.groups[root.rows[i].group]
    if (G.count <= G.nRows) return  // group has no second column
    var pos = i - G.start
    var col = Math.floor(pos / G.nRows)
    var ncol = col + dir
    if (ncol < 0 || ncol > 1) return
    var target = Math.min(ncol * G.nRows + (pos % G.nRows), G.count - 1)
    if (target === pos) return
    root.selectedIndex = G.start + target
    root.scrollTo(root.selectedIndex)
  }

  function moveFlat(dir) {
    if (!root.beginNav()) return
    var i = root.selectedIndex + dir
    if (i < 0 || i >= root.rows.length) return
    root.selectedIndex = i
    root.scrollTo(i)
  }

  // Page keys matter once someone has enough plugins to overflow the card.
  // Reuses moveVertical so every seam and clamp rule stays in one place.
  function movePage(dir) {
    if (!root.beginNav()) return
    var step = Math.max(1, Math.floor(pluginList.height / (root.pluginRowH + root.rowGap)))
    for (var n = 0; n < step; n++) {
      var before = root.selectedIndex
      root.moveVertical(dir)
      if (root.selectedIndex === before) break  // hit the end of the column
    }
  }

  function selectEdge(fromEnd) {
    hoverGate.reset()
    root.cursorActive = true
    if (root.rows.length === 0) { root.selectedIndex = -1; return }
    root.selectedIndex = fromEnd ? root.rows.length - 1 : 0
    root.scrollTo(root.selectedIndex)
  }

  // Deterministic geometry (mirrors the layout below) so keyboard moves can
  // keep the selection visible without probing delegate positions.
  function groupHeight(gi) {
    var G = root.groups[gi]
    if (G.count === 0) return root.groupHeaderH  // twirled shut: header only
    return root.groupHeaderH + root.rowGap
      + G.nRows * root.pluginRowH + (G.nRows - 1) * root.rowGap
  }

  function rowY(i) {
    var g = root.rows[i].group
    var y = 0
    for (var gi = 0; gi < g; gi++) y += root.groupHeight(gi) + root.contentSpacing
    var G = root.groups[g]
    var rowIn = (i - G.start) % G.nRows
    return y + root.groupHeaderH + root.rowGap + rowIn * (root.pluginRowH + root.rowGap)
  }

  function scrollTo(i) {
    if (i < 0 || i >= root.rows.length) return
    if (pluginList.contentHeight <= pluginList.height) { pluginList.contentY = 0; return }
    var y = root.rowY(i)
    if (y < pluginList.contentY)
      pluginList.contentY = y
    else if (y + root.pluginRowH > pluginList.contentY + pluginList.height)
      pluginList.contentY = y + root.pluginRowH - pluginList.height
  }

  // --------------------------------------------------------------- toggling

  // Two toggle paths, chosen by whether the target plugin is "panelish"
  // (has a panel/overlay/menu kind):
  //
  // The shell host instantiates one panel Loader per enabled panelish plugin
  // from a computed entry list, and only rebuilds when that list actually
  // changes content. Toggling a pure bar widget leaves the list identical,
  // so THIS panel survives and a plain attached Process reports back.
  // Toggling a panelish plugin adds/removes an entry, the host regenerates
  // every panel delegate, and this panel is destroyed the instant the toggle
  // lands — taking any attached Process with it (which is also why the
  // shell's own state can be left half-changed if the operation needed more
  // than one call). Panelish toggles therefore run via
  // Quickshell.execDetached: the runner outlives the panel, finishes the
  // config change, and re-summons the manager with the toggled row id as a
  // pending highlight (plus an error marker if the CLI refused), so the
  // panel reappears on the row that was toggled instead of just vanishing.
  // Should the summon race the rebuild and get eaten by the dying instance,
  // the onShellChanged self-restore still brings the panel back.
  //
  // Disabling additionally has to clear EVERY shell.json reference: one
  // `setPluginEnabled <id> false` removes only ONE entry location per call,
  // and a plugin installed via `omarchy plugin install` is referenced twice
  // (plugins[] entry + bar widget) — a single call left it half-enabled and
  // the row snapped back on after the state re-read (the original "click
  // twice to switch off" bug). The CLI answers "ok" even when there is
  // nothing left to remove, so the loops check the effective config
  // themselves (same any-reference rule as isReallyEnabled) until the id is
  // gone (capped; two locations is the normal worst case).
  readonly property string refCheckFunction: [
    'anywhere() {',
    '  omarchy-shell shell listShellConfig 2>/dev/null | jq -e --arg id "$1" \'',
    '    [(.bar.layout[]?[]?), (.plugins[]?)]',
    '    | map(if type == "string" then . else (.id // empty) end)',
    '    | index($id) != null\' > /dev/null',
    '}'
  ].join("\n")

  // Attached path: sh -c script plugin-disable <id>
  readonly property string attachedDisableScript: [
    root.refCheckFunction,
    'id="$1"',
    'for i in 1 2 3 4 5; do',
    '  out="$(omarchy-shell shell setPluginEnabled "$id" false 2>&1)"',
    '  [ "$out" = "ok" ] || { printf \'%s\\n\' "${out:-setPluginEnabled produced no output}"; exit 1; }',
    '  anywhere "$id" || { echo ok; exit 0; }',
    'done',
    'echo "still referenced after 5 attempts"',
    'exit 1'
  ].join("\n")

  // Detached runner: sh -c script plugin-toggle <id> <selfId> <true|false>
  readonly property string detachedToggleScript: [
    root.refCheckFunction,
    'id="$1"; self="$2"; want="$3"; err=""',
    'if [ "$want" = "true" ]; then',
    '  out="$(omarchy-shell shell setPluginEnabled "$id" true 2>&1)"',
    '  [ "$out" = "ok" ] || err="${out:-setPluginEnabled produced no output}"',
    'else',
    '  for i in 1 2 3 4 5; do',
    '    anywhere "$id" || break',
    '    out="$(omarchy-shell shell setPluginEnabled "$id" false 2>&1)"',
    '    [ "$out" = "ok" ] || { err="${out:-setPluginEnabled produced no output}"; break; }',
    '  done',
    '  if [ -z "$err" ] && anywhere "$id"; then err="still referenced"; fi',
    'fi',
    '# Let the panel-delegate teardown/rebuild settle so the summon payload',
    '# is queued for the NEW panel instance, not eaten by the dying one.',
    'sleep 0.4',
    'payload="$(jq -cn --arg h "$id" --arg e "$err" \'',
    '  {highlight: $h} + (if $e == "" then {} else {error: $e} end)\')"',
    'for i in 1 2 3 4 5; do',
    '  [ "$(omarchy-shell shell summon "$self" "$payload" 2>/dev/null)" = "ok" ] && exit 0',
    '  sleep 0.4',
    'done'
  ].join("\n")

  // ------------------------------------------------------- self-registration

  // Keep the keyboard shortcut working with the bar on, off, or absent.
  //
  // `omarchy plugin enable` writes only the `bar.layout` entry for a plugin
  // that is both a panel and a bar widget: PluginRegistry.setEnabled picks the
  // bar branch of an if/else chain, so the `plugins[]` push below it is never
  // reached. The panel is then enabled only for as long as its icon sits in
  // the bar — take the icon out, or never want one, and the shell stops
  // instantiating the panel. `omarchy-shell shell toggle` exits 0 and does
  // nothing, which is what "SUPER+ALT+P doesn't work" turned out to be.
  //
  // So the first time we open, claim a `plugins[]` reference of our own. That
  // reference is enough on its own, so from then on the shortcut survives the
  // icon being removed. Idempotent, writes through a temp file, and it does
  // nothing once a shell that writes both references itself has landed.
  //
  // This cannot repair an install that is already switched off: with no
  // reference at all the shell never loads this panel, so none of this runs.
  // That case needs `omarchy plugin enable nosignal.plugin-manager` once.
  //
  // Harness: sh -c <script> plugin-selfref <id>  — so $0 is the label, $1 the id.
  property bool selfRefEnsured: false
  readonly property string ensureSelfRefScript: [
    'id="$1"',
    'f="$HOME/.config/omarchy/shell.json"',
    '[ -f "$f" ] || exit 0',
    'jq -e --arg id "$id" \'any(.plugins[]?; (.id // empty) == $id)\' "$f" >/dev/null && exit 0',
    'tmp="$f.plugin-manager.$$"',
    'jq --arg id "$id" \'.plugins = ((.plugins // []) + [{id: $id}])\' "$f" > "$tmp" || {',
    '  rm -f "$tmp"; exit 1;',
    '}',
    '[ -s "$tmp" ] || { rm -f "$tmp"; exit 1; }',
    'mv "$tmp" "$f"'
  ].join("\n")

  function ensureSelfReference() {
    if (root.selfRefEnsured) return
    root.selfRefEnsured = true
    Quickshell.execDetached(["sh", "-c", root.ensureSelfRefScript, "plugin-selfref", root.selfId])
  }

  // ---------------------------------------------------------------- removal

  // Detached runner: sh -c script plugin-remove <id> <self>
  //
  // Always detached, unlike toggling, and not because of the panel kinds:
  // `omarchy plugin remove` finishes with its own `omarchy-shell shell
  // rescanPlugins`, and a rescan unloads every open panel — this one
  // included. An attached Process would be killed partway through the
  // removal no matter what kinds the target declares.
  //
  // Every shell.json reference is cleared BEFORE handing over to the CLI.
  // The CLI's own cleanup is a single `setPluginEnabled <id> false`, which
  // removes one entry location per call (see the toggling notes above), so a
  // plugin referenced twice — the normal case for anything installed with
  // `omarchy plugin add` — would leave an orphan entry behind pointing at a
  // directory that no longer exists.
  //
  // The CLI decides how the files go: a symlinked plugin is unlinked and the
  // source tree left alone, a git clone is deleted, and anything else is
  // moved to a timestamped backup beside it. Nothing here follows a symlink.
  readonly property string detachedRemoveScript: [
    root.refCheckFunction,
    'id="$1"; self="$2"; err=""',
    'for i in 1 2 3 4 5; do',
    '  anywhere "$id" || break',
    '  out="$(omarchy-shell shell setPluginEnabled "$id" false 2>&1)"',
    '  [ "$out" = "ok" ] || { err="${out:-setPluginEnabled produced no output}"; break; }',
    'done',
    'if [ -z "$err" ] && anywhere "$id"; then err="still referenced"; fi',
    'if [ -z "$err" ]; then',
    '  # Failure is the exit status, never "did it print anything": a CLI that',
    '  # dies silently (its own set -e tripping, a signal) produces no output,',
    '  # and keying off the message alone reported those as a clean removal.',
    '  if out="$(omarchy plugin remove "$id" --yes 2>&1)"; then :; else',
    '    err="$(printf \'%s\' "$out" | tail -n 1)"',
    '    [ -n "$err" ] || err="omarchy plugin remove failed"',
    '  fi',
    'fi',
    '# Let the delegate teardown settle so the summon lands on the NEW panel.',
    'sleep 0.4',
    'if [ -z "$err" ]; then',
    '  payload="$(jq -cn --arg n "Removed $id" \'{notice: $n}\')"',
    'else',
    '  payload="$(jq -cn --arg h "$id" --arg e "$err" \'{highlight: $h, error: $e}\')"',
    'fi',
    'for i in 1 2 3 4 5; do',
    '  [ "$(omarchy-shell shell summon "$self" "$payload" 2>/dev/null)" = "ok" ] && exit 0',
    '  sleep 0.4',
    'done'
  ].join("\n")

  // First press arms the confirmation; it does not remove anything.
  function askRemove(i) {
    if (!root.isSelectable(i)) return
    var row = root.rows[i]
    if (row.locked) {
      root.selfFlashMsg = "that's me — I can't remove myself"
      selfFlashTimer.restart()
      return
    }
    if (!row.removable) {
      root.noticeText = "first-party widgets can't be removed — switch them off instead"
      noticeTimer.restart()
      return
    }
    if (root.busyId !== "") { root.busyNotice(); return }
    root.confirmRemoveId = row.id
  }

  // Refusing an action because another one is still running used to be a
  // silent no-op — you clicked and nothing happened, with nothing to read.
  function busyNotice() {
    root.noticeText = "still working on " + root.busyId + " — try again in a moment"
    noticeTimer.restart()
  }

  function removeConfirmed() {
    // Check busy BEFORE consuming the confirmation, or a refused confirm
    // silently disarms the row and the second press does nothing either.
    if (root.busyId !== "") { root.busyNotice(); return }
    var id = root.confirmRemoveId
    root.confirmRemoveId = ""
    if (id === "") return
    root.busyId = id
    Quickshell.execDetached(["sh", "-c", root.detachedRemoveScript,
      "plugin-remove", id, root.selfId])
  }

  Timer {
    id: noticeTimer
    interval: 5000
    onTriggered: root.noticeText = ""
  }

  // Segment clicks name the state they want rather than flipping, so "on" on
  // an already-on row is a no-op instead of a switch-off. Picking either
  // state also abandons a pending remove confirmation on the same row.
  function setRowEnabled(i, want) {
    if (!root.isSelectable(i)) return
    var row = root.rows[i]
    if (row.locked) {
      if (!want) {
        root.selfFlashMsg = "that's me — I can't disable myself"
        selfFlashTimer.restart()
      }
      return
    }
    root.confirmRemoveId = ""
    if (row.enabled === want) return
    if (root.busyId !== "") { root.busyNotice(); return }
    root.toggleRow(i)
  }

  function toggleRow(i) {
    if (!root.isSelectable(i)) return
    var row = root.rows[i]
    if (row.locked) {
      root.selfFlashMsg = "that's me — I can't disable myself"
      selfFlashTimer.restart()
      return
    }
    if (root.busyId !== "") return
    root.busyId = row.id
    root.busyTarget = !row.enabled
    if (row.panelish) {
      // This instance is about to be destroyed by the host's delegate
      // rebuild; the detached runner finishes the job and re-summons us.
      // (If the toggle fails without a config change, nothing is destroyed
      // and the runner's summon lands on THIS instance — open() clears the
      // busy state and surfaces the error.)
      Quickshell.execDetached(["sh", "-c", root.detachedToggleScript,
        "plugin-toggle", row.id, root.selfId, row.enabled ? "false" : "true"])
      return
    }
    toggleProc.command = row.enabled
      ? ["sh", "-c", root.attachedDisableScript, "plugin-disable", row.id]
      : ["omarchy-shell", "shell", "setPluginEnabled", row.id, "true"]
    toggleProc.running = true
  }

  function toggleFinished(exitCode, stdoutText) {
    var id = root.busyId
    root.busyId = ""
    var ok = exitCode === 0 && String(stdoutText || "").trim() === "ok"
    if (!ok && id) {
      var errors = ({})
      for (var k in root.rowErrors) errors[k] = root.rowErrors[k]
      errors[id] = "failed — try: omarchy plugin rescan"
      root.rowErrors = errors
      errorTimer.restart()
    }
    // Re-read actual state rather than assuming the toggle stuck.
    root.refresh()
  }

  Timer {
    id: errorTimer
    interval: 4000
    onTriggered: root.rowErrors = ({})
  }

  Timer {
    id: selfFlashTimer
    interval: 2500
    onTriggered: root.selfFlashMsg = ""
  }

  // Only a genuine pointer move may steal the selection cursor — delegates
  // created or refreshed under a stationary mouse must not hijack keyboard
  // navigation (same pattern as the launcher).
  PointerMoveGate {
    id: hoverGate
    referenceItem: pluginList
  }

  // One plugin row: a Toggle plus the gated hover-selection overlay.
  // One segment of the row's on/off/remove control.
  component Seg: Item {
    id: seg

    property string label: ""
    property bool active: false     // this segment is the current state
    property bool danger: false     // the remove segment
    property bool first: false      // no divider on the leading segment
    property color fg: root.foreground

    signal activated()

    width: segText.implicitWidth + Style.spacing.sm * 2
    height: root.segH

    Rectangle {
      anchors.fill: parent
      color: seg.active ? (seg.danger ? root.urgent : root.accent)
        : segMouse.containsMouse
          ? Qt.rgba(seg.fg.r, seg.fg.g, seg.fg.b, 0.12) : "transparent"
      Behavior on color { ColorAnimation { duration: 100 } }
    }

    Rectangle {
      visible: !seg.first
      width: Math.max(1, Style.space(1))
      height: parent.height
      color: Qt.rgba(seg.fg.r, seg.fg.g, seg.fg.b, 0.2)
    }

    Text {
      id: segText
      anchors.centerIn: parent
      text: seg.label
      color: seg.active ? root.background : seg.danger ? root.urgent : seg.fg
      opacity: seg.active || segMouse.containsMouse ? 1 : 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: seg.active || seg.danger
    }

    MouseArea {
      id: segMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: seg.activated()
    }
  }

  component PluginRow: Item {
    id: rowItem

    property int flatIndex: -1
    property var rowData: null

    readonly property bool errored: rowData !== null && root.rowErrors[rowData.id] !== undefined
    readonly property bool busy: rowData !== null && root.busyId === rowData.id
    readonly property bool removable: rowData !== null && rowData.removable === true
    readonly property bool confirming: rowData !== null && root.confirmRemoveId === rowData.id
    readonly property bool selected: root.cursorActive && flatIndex === root.selectedIndex
    // Mid-toggle the switch should already read the state being moved to.
    readonly property bool isOn: busy ? root.busyTarget
      : (rowData ? rowData.enabled : false)
    readonly property color fg: errored || confirming ? root.urgent : root.foreground

    width: parent ? parent.width : 0
    height: root.pluginRowH

    // Same surface treatment Ui/Toggle gives its rows — this panel drives the
    // cursor itself, so `hot` comes from the panel cursor or a real hover
    // rather than activeFocus (the keyCatcher holds focus, never the row).
    BorderSurface {
      id: surface
      anchors.fill: parent
      radius: Style.cornerRadius
      readonly property bool hot: rowItem.selected || rowHover.containsMouse
      color: Style.controlFill(false, hot, rowItem.fg, root.accent)
      borderSpec: Border.controlSpec(hot ? "hover-cursor" : "normal",
        rowItem.fg, root.accent)
      opacity: rowItem.busy ? 0.6
        : (rowItem.rowData && rowItem.rowData.locked ? 0.75 : 1)

      Behavior on color { ColorAnimation { duration: 100 } }

      Column {
        anchors.left: parent.left
        anchors.leftMargin: surface.borderLeft + Style.spacing.rowPaddingX
        anchors.right: control.left
        anchors.rightMargin: Style.spacing.rowPaddingX
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xs

        Text {
          width: parent.width
          text: rowItem.rowData ? rowItem.rowData.name : ""
          color: rowItem.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: !rowItem.rowData ? ""
            : rowItem.errored ? root.rowErrors[rowItem.rowData.id]
            : rowItem.confirming ? "remove — click again or press enter · esc cancels"
            : (rowItem.rowData.locked && root.selfFlashMsg !== "") ? root.selfFlashMsg
            : rowItem.rowData.caption
          color: rowItem.errored || rowItem.confirming
            ? root.urgent : Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      // on | off | remove. The lit segment is the current state; remove is
      // an action rather than a state, so it only ever lights up while armed.
      // First-party rows omit it entirely — nothing there is removable.
      Rectangle {
        id: control
        anchors.right: parent.right
        anchors.rightMargin: surface.borderRight + Style.spacing.rowPaddingX
        anchors.verticalCenter: parent.verticalCenter
        width: segRow.width
        height: root.segH
        radius: Style.cornerRadius > 0 ? height / 2 : 0
        color: "transparent"
        border.width: Math.max(1, Style.space(1))
        border.color: Qt.rgba(rowItem.fg.r, rowItem.fg.g, rowItem.fg.b, 0.25)
        clip: true

        Row {
          id: segRow
          spacing: 0

          Seg {
            label: "on"
            first: true
            active: rowItem.isOn
            fg: rowItem.fg
            onActivated: {
              root.cursorActive = true
              root.selectedIndex = rowItem.flatIndex
              root.setRowEnabled(rowItem.flatIndex, true)
            }
          }

          Seg {
            label: "off"
            active: !rowItem.isOn
            fg: rowItem.fg
            onActivated: {
              root.cursorActive = true
              root.selectedIndex = rowItem.flatIndex
              root.setRowEnabled(rowItem.flatIndex, false)
            }
          }

          Seg {
            visible: rowItem.removable
            label: rowItem.confirming ? "sure?" : "remove"
            danger: true
            active: rowItem.confirming
            fg: rowItem.fg
            onActivated: {
              root.cursorActive = true
              root.selectedIndex = rowItem.flatIndex
              if (rowItem.confirming) root.removeConfirmed()
              else root.askRemove(rowItem.flatIndex)
            }
          }
        }
      }
    }

    // Hover-selects the row, but only on real pointer movement — hoverGate
    // filters the synthetic hover a freshly created delegate (or one that
    // scrolled under a stationary mouse) receives. NoButton lets clicks
    // fall through to the segments above.
    MouseArea {
      id: rowHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      cursorShape: Qt.PointingHandCursor
      onPositionChanged: function(mouse) {
        if (!hoverGate.moved(this, mouse)) return
        root.cursorActive = true
        root.selectedIndex = rowItem.flatIndex
      }
    }
  }


  Process {
    id: fetchProc
    command: ["sh", "-c", root.fetchScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseFetch(text)
    }
  }

  Process {
    id: toggleProc
    stdout: StdioCollector { id: toggleOut; waitForEnd: true }
    onExited: function(exitCode) { root.toggleFinished(exitCode, toggleOut.text) }
  }

  // ------------------------------------------------------------------- UI

  function listContentH() {
    if (root.groups.length === 0) return root.pluginRowH
    var h = 0
    for (var gi = 0; gi < root.groups.length; gi++) h += root.groupHeight(gi)
    return h + (root.groups.length - 1) * root.contentSpacing
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-plugin-manager"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      // Two columns of rows side by side; height capped at 80% of the
      // screen — the list scrolls only if it genuinely overflows that.
      // 960, not 880: the on/off/remove control is wider than the switch it
      // replaced, and the extra width is what keeps the id+kinds caption from
      // eliding on longer plugin names.
      width: Math.min(Style.space(960), panel.width - Style.gapsOut * 2)
      height: Math.min(
        card.contentTopInset + card.contentBottomInset
          + root.headerHeight + root.contentSpacing
          + root.listContentH() + root.contentSpacing + root.footerH,
        Math.min(panel.height * 0.8, panel.height - Style.gapsOut * 2))
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin
      clip: true

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
          // A pending remove confirmation swallows the whole keyboard: only
          // Enter/y proceeds and every other key backs out, so a destructive
          // action stays hard to trigger by accident and trivial to escape
          // (Esc cancels the confirm here rather than closing the panel).
          if (root.confirmRemoveId !== "") {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Y) root.removeConfirmed()
            else root.confirmRemoveId = ""
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
            root.close()
            event.accepted = true
          } else if (event.key === Qt.Key_R || event.key === Qt.Key_F5) {
            root.refresh()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.moveVertical(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.moveVertical(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.moveHorizontal(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            root.moveHorizontal(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Backtab) {
            root.moveFlat(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Tab) {
            root.moveFlat(1)
            event.accepted = true
          } else if (event.key === Qt.Key_X || event.key === Qt.Key_Delete) {
            root.askRemove(root.selectedIndex)
            event.accepted = true
          } else if (event.key === Qt.Key_F) {
            root.toggleFirstParty()
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.movePage(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.movePage(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.selectEdge(false)
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.selectEdge(true)
            event.accepted = true
          } else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.toggleRow(root.selectedIndex)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Item {
          width: parent.width
          height: root.headerHeight

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "󰐱  Plugin manager"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "esc close · space toggle · x remove · f first-party · r refresh"
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - root.footerH - root.contentSpacing * 2

          Text {
            // Keyed off groups, not rows: with every group twirled shut the
            // row count is legitimately zero and the headers are the content.
            visible: root.groups.length === 0
            anchors.top: parent.top
            text: root.loaded ? "No plugins found" : "Reading plugins…"
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }

          // Group headers span the card; each group's rows flow column-major
          // into two side-by-side columns. Scrolls only on real overflow
          // (the card is capped at 80% of screen height).
          Flickable {
            id: pluginList
            anchors.fill: parent
            // Leave room for the scrollbar only while it's showing, so rows
            // never run underneath it. Row heights are fixed, so contentHeight
            // doesn't depend on this width — no binding loop.
            anchors.rightMargin: scrollTrack.visible
              ? scrollTrack.width + Style.spacing.xs : 0
            clip: true
            contentWidth: width
            contentHeight: groupsCol.implicitHeight
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: groupsCol
              width: pluginList.width
              spacing: root.contentSpacing

              Repeater {
                model: root.groups

                delegate: Column {
                  id: groupItem
                  required property var modelData
                  width: groupsCol.width
                  spacing: root.rowGap

                  // Group header. On the collapsible group it doubles as the
                  // twirl control: a disclosure arrow, the label, and an
                  // on/total tally so the fold still says what's inside.
                  Item {
                    width: parent.width
                    height: root.groupHeaderH

                    Text {
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.bottom: parent.bottom
                      text: (groupItem.modelData.collapsible
                              ? (groupItem.modelData.collapsed ? "▸  " : "▾  ") : "")
                            + groupItem.modelData.label
                            + (groupItem.modelData.collapsible
                              ? "  ·  " + groupItem.modelData.enabledCount
                                + " of " + groupItem.modelData.total + " on" : "")
                      color: root.foreground
                      opacity: groupHeaderArea.containsMouse ? 0.85 : 0.5
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      elide: Text.ElideRight
                    }

                    MouseArea {
                      id: groupHeaderArea
                      anchors.fill: parent
                      enabled: groupItem.modelData.collapsible
                      hoverEnabled: groupItem.modelData.collapsible
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.toggleFirstParty()
                    }
                  }

                  Row {
                    width: parent.width
                    spacing: root.colGap
                    // Twirled shut: drop the row block out of the layout
                    // entirely, so the Column contributes only the header
                    // and matches groupHeight().
                    visible: groupItem.modelData.count > 0

                    Column {
                      width: (parent.width - root.colGap) / 2
                      spacing: root.rowGap
                      Repeater {
                        model: groupItem.modelData.nRows
                        delegate: PluginRow {
                          required property int index
                          flatIndex: groupItem.modelData.start + index
                          rowData: groupItem.modelData.rows[index]
                        }
                      }
                    }

                    Column {
                      width: (parent.width - root.colGap) / 2
                      spacing: root.rowGap
                      Repeater {
                        model: groupItem.modelData.count - groupItem.modelData.nRows
                        delegate: PluginRow {
                          required property int index
                          flatIndex: groupItem.modelData.start + groupItem.modelData.nRows + index
                          rowData: groupItem.modelData.rows[groupItem.modelData.nRows + index]
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          // Scroll affordance. The card is capped at 80% of the screen, so
          // this appears only when someone has genuinely more plugins than
          // fit — otherwise there's nothing to scroll and no track to draw.
          Rectangle {
            id: scrollTrack
            visible: pluginList.contentHeight > pluginList.height
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.max(2, Style.space(3))
            radius: width / 2
            color: root.foreground
            opacity: 0.1

            Rectangle {
              width: parent.width
              radius: parent.radius
              color: root.foreground
              opacity: 0.45
              height: Math.max(Style.space(24),
                parent.height * (pluginList.height / Math.max(1, pluginList.contentHeight)))
              y: (parent.height - height)
                * Math.max(0, Math.min(1, pluginList.contentY
                  / Math.max(1, pluginList.contentHeight - pluginList.height)))
            }
          }
        }

        Text {
          width: parent.width
          height: root.footerH
          text: root.noticeText !== "" ? root.noticeText
            : "core shell plugins aren't listed — manage them with the omarchy CLI"
          color: root.noticeText !== "" ? root.accent : root.foreground
          opacity: root.noticeText !== "" ? 0.95 : 0.4
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }
}
