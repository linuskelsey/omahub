import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Ui
import qs.Commons

// Notification hub: a bell in the bar that slides a transparent right-hand
// panel out. Top of the panel: OS notifications from a longer archive than
// the stock daemon keeps (bin/archive.sh), stacked per app. Below: floating
// cards contributed by other plugins that declare `hubCard` in their
// manifest, in the order chosen in the settings overlay.
BarWidget {
  id: root
  moduleName: hubId

  readonly property string home: Quickshell.env("HOME")
  // Single source of truth for every name derived from the plugin id (must match manifest.json).
  readonly property string hubId: "io.github.linuskelsey.omahub"
  // Where this file lives (works however the plugin was installed or linked).
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  // Documented, stable location of the hub's config and archive (see README "Card contract").
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/" + hubId
  readonly property string archiveScript: pluginDir + "/bin/archive.sh"

  property bool panelOpen: false
  property double openedAt: 0
  property bool settingsOpen: false
  property var archive: ({ seen: 0, items: [] })
  property var available: []          // candidate cards found on disk
  property var cfg: ({ cards: [], toggleKey: "SUPER + N", settingsKey: "SUPER + ALT + N", hideBarWidgets: false, blurDesktop: false, clickRunsActions: false, knownCards: [], expandedCards: [] })
  property string bindStatus: ""

  // Highest hubCard contract this hub understands (see README "Card contract").
  readonly property int contractVersion: 1
  readonly property int maxCardHeight: 400
  readonly property int panelWidth: Style.space(380)
  readonly property int gap: Style.gapsOut
  // Extra breathing room between the cards and the screen's right edge.
  readonly property int edgeGap: Style.space(16)
  // Gap between the free-area edge (bar / screen edge) and the first/last card.
  // Deliberately raw logical pixels, NOT Style.space(): it must not grow or shrink
  // with the user's spacing or font scale.
  readonly property int vGap: 10
  // Breathing room between cards.
  readonly property int cardGap: Style.space(14)
  readonly property color surface: Color.popups.background
  readonly property color textColor: Color.popups.text
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.menuFamily

  // --- derived state ------------------------------------------------------
  readonly property int unread: {
    var n = 0, items = archive.items || []
    for (var i = 0; i < items.length; i++) if (items[i].timestamp > archive.seen) n++
    return n
  }
  property var cardBadges: ({})
  readonly property int cardBadgeTotal: {
    var t = 0
    for (var k in cardBadges) t += Number(cardBadges[k]) || 0
    return t
  }
  readonly property int totalBadge: unread + cardBadgeTotal

  readonly property var groups: {
    var order = [], map = {}, items = archive.items || []
    for (var i = 0; i < items.length; i++) {
      var app = items[i].app || "Notification"
      if (!map[app]) { map[app] = { app: app, items: [] }; order.push(map[app]) }
      map[app].items.push(items[i])
    }
    return order
  }

  readonly property var enabledCards: {
    var out = [], byId = {}
    for (var i = 0; i < available.length; i++) byId[available[i].id] = available[i]
    var ids = cfg.cards || []
    for (var j = 0; j < ids.length; j++) if (byId[ids[j]] && (byId[ids[j]].contract || 1) <= contractVersion) out.push(byId[ids[j]])
    return out
  }

  // --- actions ------------------------------------------------------------
  function open(useFocused) {
    pinScreen(useFocused === true)
    openedAt = Date.now()
    scroller.contentY = 0   // always open at the top, not where it was last left
    // The bar paints its own open-panel mark under a widget that is the active popout.
    if (root.bar) root.bar.requestPopout(root)
    registerBinds()
    closeTimer.stop()
    blurOn()
    cardsProc.running = true
    panelOpen = true
    markSeen()
  }
  property bool closing: false
  property var anchorScreen: null
  // The bell opens the hub on its own bar's screen; the shortcut (which only reaches one
  // bar instance) opens it on whichever monitor Hyprland has focused.
  function pinScreen(useFocused) {
    var chosen = null
    if (useFocused && Hyprland.focusedMonitor) {
      var want = Hyprland.focusedMonitor.name
      for (var i = 0; i < Quickshell.screens.length; i++)
        if (Quickshell.screens[i].name === want) { chosen = Quickshell.screens[i]; break }
    }
    if (!chosen) { var w = root.QsWindow.window; chosen = w ? w.screen : null }
    anchorScreen = chosen
  }
  function close() {
    if (panelOpen) { closing = true; closeTimer.restart() }
    panelOpen = false
    if (root.bar) root.bar.releasePopout(root)
  }
  function toggle(useFocused) { if (panelOpen) close(); else open(useFocused === true) }
  function openSettings(useFocused) { pinScreen(useFocused === true); cardsProc.running = true; close(); settingsOpen = true }
  function closeSettings() {
    settingsOpen = false
    // Everything currently discovered counts as seen once settings is dismissed.
    var known = (cfg.knownCards || []).slice(), changed = false
    for (var i = 0; i < available.length; i++)
      if (known.indexOf(available[i].id) < 0) { known.push(available[i].id); changed = true }
    if (changed) saveConfig(Object.assign({}, cfg, { knownCards: known }))
  }

  function run(args) { Quickshell.execDetached([archiveScript].concat(args)); reloadTimer.restart() }
  // Mirror the daemon's rule for a persisted click action: a JSON argv of non-empty
  // strings whose program does not start with '-'. Run without a shell, like the toasts.
  function parseExecArgv(value) {
    var text = String(value || "")
    if (!text) return null
    var parsed
    try { parsed = JSON.parse(text) } catch (e) { return null }
    if (!Array.isArray(parsed) || parsed.length === 0) return null
    for (var i = 0; i < parsed.length; i++) if (typeof parsed[i] !== "string") return null
    if (!parsed[0] || parsed[0].charAt(0) === "-") return null
    return parsed
  }
  // Click a notification: focus the sending app (the stock toasts' fallback), or, when the user has
  // opted in, run the action the sender stored with it, then drop it from the list and close the panel.
  function activateNotification(n) {
    if (!n) return
    // Running the sender's stored command is opt-in (it is data from another program, and the
    // archive keeps it for days); by default a click just takes you to the app.
    var argv = cfg.clickRunsActions === true ? parseExecArgv(n.execArgv) : null
    if (argv) {
      Quickshell.execDetached(["bash", "-lc", 'exec "$@"', "bash"].concat(argv))
    } else if (n.app) {
      var base = Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
      Quickshell.execDetached([base + "/bin/omarchy-hyprland-focus-app", String(n.app)])
    }
    remove(n.stem)
    close()
  }
  function markSeen() { run(["seen"]) }
  function remove(stem) { run(["remove", stem]) }
  function clearAll() { run(["clear"]) }
  function removeGroup(g) { for (var i = 0; i < g.items.length; i++) Quickshell.execDetached([archiveScript, "remove", g.items[i].stem]); reloadTimer.restart() }

  function saveConfig(next) {
    cfg = next
    cfgFile.setText(JSON.stringify(next, null, 2) + "\n")
    registerBinds()
  }
  function toggleCard(id, on) {
    var ids = (cfg.cards || []).filter(function(x) { return x !== id })
    if (on) ids.push(id)
    saveConfig(Object.assign({}, cfg, { cards: ids }))
  }
  // Expanded/collapsed is a view preference: written to config, but unlike saveConfig it does not re-register the binds.
  function setCardExpanded(id, on) {
    var ids = (cfg.expandedCards || []).filter(function(x) { return x !== id })
    if (on) ids.push(id)
    cfg = Object.assign({}, cfg, { expandedCards: ids })
    cfgFile.setText(JSON.stringify(cfg, null, 2) + "\n")
  }
  function moveCard(id, delta) {
    var ids = (cfg.cards || []).slice(), i = ids.indexOf(id), j = i + delta
    if (i < 0 || j < 0 || j >= ids.length) return
    ids.splice(i, 1); ids.splice(j, 0, id)
    saveConfig(Object.assign({}, cfg, { cards: ids }))
  }
  function setKey(which, text) {
    var o = {}; o[which] = text
    saveConfig(Object.assign({}, cfg, o))
  }

  // Binds are registered with Hyprland at runtime (never editing the user's
  // config), the same way Stage Control does it; a config reload drops them
  // and the hub registers them again when Hyprland reports the reload (rawEvent "configreloaded").
  // Each instance claims the Hyprland-side registration with a token; teardown only
  // undoes it if it still owns it, so a reload (new instance registers first) is safe.
  readonly property string ownerToken: String(Date.now()) + "-" + Math.floor(Math.random() * 1e9)
  function unregisterHyprland() {
    var lua = "if rawget(_G, '__omahub_owner') == '" + ownerToken + "' then "
      + "for _, b in ipairs(rawget(_G, '__omahub') or {}) do pcall(function() b:remove() end) end "
      + "for _, r in ipairs(rawget(_G, '__omahub_rules') or {}) do pcall(function() r:set_enabled(false) end) end "
      + "rawset(_G, '__omahub', {}) rawset(_G, '__omahub_rules', {}) rawset(_G, '__omahub_owner', nil) end return 'ok'"
    Quickshell.execDetached(["/usr/bin/hyprctl", "eval", lua])
  }

  function registerBinds() {
    var keyOk = /^[A-Za-z0-9_ +]{1,64}$/
    var lua = "local s = rawget(_G, '__omahub') or {} "
      + "for _, b in ipairs(s) do pcall(function() b:remove() end) end "
      + "s = {} rawset(_G, '__omahub', s) rawset(_G, '__omahub_owner', '" + ownerToken + "') "
      + "for _, r in ipairs(rawget(_G, '__omahub_rules') or {}) do pcall(function() r:set_enabled(false) end) end "
      + "local rules = {} rawset(_G, '__omahub_rules', rules) local problems = {} "
      + "do local ok, r = pcall(hl.layer_rule, { match = { namespace = '^linuskelsey-omahub$' }, blur = true, ignore_alpha = 0.05, no_anim = true }) if ok and r then rules[#rules+1] = r else problems[#problems+1] = 'layer rule: ' .. tostring(r) end end "
    var pairs = [[cfg.toggleKey, "toggle"], [cfg.settingsKey, "settings"]]
    for (var i = 0; i < pairs.length; i++) {
      if (!keyOk.test(pairs[i][0] || "")) {
        lua += "problems[#problems+1] = 'invalid shortcut for " + pairs[i][1] + "' "
        continue
      }
      lua += "do local ok, h = pcall(hl.bind, '" + pairs[i][0] + "', hl.dsp.exec_cmd('omarchy-shell " + root.hubId + " " + pairs[i][1]
        + "'), { description = 'Omahub' }) if ok and h then s[#s+1] = h else problems[#problems+1] = '" + pairs[i][0] + ": ' .. tostring(h or 'Hyprland did not accept it') end end "
    }
    lua += "if #problems > 0 then error(table.concat(problems, '; '), 0) end return 'ok'"
    bindProc.command = ["/usr/bin/hyprctl", "eval", lua]
    bindProc.running = true
  }

  // Clicking a card link or a notification action usually brings another window to the front
  // (the browser, the app that sent the notification). The hub is an overlay, so without this it
  // would stay on top of that window. Close it as soon as a different window becomes active.
  // Ignored for a moment after opening (the hub itself taking focus can shuffle the active
  // window), and when the active window goes away rather than being replaced.
  Connections {
    target: Hyprland
    function onActiveToplevelChanged() {
      if (!root.panelOpen || Date.now() - root.openedAt < 700) return
      if (Hyprland.activeToplevel) root.close()
    }
  }

  // A Hyprland config reload wipes runtime-registered binds. Anything can trigger one (another
  // plugin wiring its own bindings at shell start, a monitor-profile daemon, the user's own edits),
  // so re-register once the reload has settled instead of waiting for the next click or restart.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && String(event.name) === "configreloaded") rebindTimer.restart()
    }
  }
  Timer { id: rebindTimer; interval: 400; onTriggered: root.registerBinds() }

  // --- IPC ----------------------------------------------------------------
  IpcHandler {
    target: root.hubId
    function toggle(): void { root.toggle(true) }
    function open(): void { root.open(true) }
    function close(): void { root.close() }
    function settings(): void { if (root.settingsOpen) root.closeSettings(); else root.openSettings(true) }
  }

  // --- data ---------------------------------------------------------------
  Process {
    id: watcher
    running: true
    command: [root.archiveScript, "watch"]
    stdout: SplitParser { onRead: listProc.running = true }
    stderr: StdioCollector { id: watchErr }
    onExited: function(code) { root.missingDeps = code === 3 ? watchErr.text.trim() : "" }
  }
  property string missingDeps: ""
  Process {
    id: listProc
    command: [root.archiveScript, "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { root.archive = JSON.parse(text) } catch (e) {} }
    }
  }
  Process {
    id: cardsProc
    command: [root.pluginDir + "/bin/cards.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { root.available = JSON.parse(text) } catch (e) { root.available = [] } }
    }
  }
  Process {
    id: bindProc
    stdout: StdioCollector { id: bindOut }
    stderr: StdioCollector { id: bindErr }
    onExited: function(code) {
      // hyprctl reports Lua errors on stdout (exit 7), other failures on stderr.
      var msg = (bindOut.text.trim() || bindErr.text.trim()).replace(/^error:\s*/i, "")
      root.bindStatus = code === 0 ? "ok" : (msg || "Hyprland rejected the shortcut")
    }
  }
  Timer { id: closeTimer; interval: 240; onTriggered: { root.closing = false; if (!root.panelOpen) root.blurOff() } }

  // Hyprland only honours a layer's blur rule when blur is enabled globally. If
  // the user has it off, switch it on at runtime while the hub is open and put it
  // back afterwards (nothing is written to their Hyprland config).
  property bool blurForced: false
  function blurOn() {
    if (cfg.blurDesktop !== true || blurForced) return
    blurQuery.running = true
  }
  function blurOff() {
    if (!blurForced) return
    blurForced = false
    blurSet.command = ["/usr/bin/hyprctl", "eval", "hl.config({ decoration = { blur = { enabled = false } } }) return 'ok'"]
    blurSet.running = true
  }
  Process {
    id: blurQuery
    command: ["/usr/bin/hyprctl", "-j", "getoption", "decoration:blur:enabled"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var o; try { o = JSON.parse(text) } catch (e) { return }
        if (o && o.bool === false && root.panelOpen) {
          root.blurForced = true
          blurSet.command = ["/usr/bin/hyprctl", "eval", "hl.config({ decoration = { blur = { enabled = true } } }) return 'ok'"]
          blurSet.running = true
        }
      }
    }
  }
  Process { id: blurSet }
  Component.onDestruction: {
    if (blurForced) Quickshell.execDetached(["/usr/bin/hyprctl", "eval", "hl.config({ decoration = { blur = { enabled = false } } }) return 'ok'"])
    unregisterHyprland()
  }
  Timer { id: reloadTimer; interval: 200; onTriggered: listProc.running = true }
  Timer { interval: 60000; running: root.panelOpen; repeat: true; onTriggered: root.archive = Object.assign({}, root.archive) }

  FileView {
    id: cfgFile
    path: root.stateDir + "/config.json"
    printErrors: false
    onLoaded: {
      try {
        var saved = JSON.parse(text())
        // SUPER + SHIFT + N was the old default; Omarchy binds it to the editor.
        if (saved.settingsKey === "SUPER + SHIFT + N") delete saved.settingsKey
        root.cfg = Object.assign({}, root.cfg, saved)
      } catch (e) {}
      root.registerBinds()
    }
    onLoadFailed: root.registerBinds()
  }

  Component.onCompleted: { cardsProc.running = true; listProc.running = true }

  // --- bar button ---------------------------------------------------------
  implicitWidth: bell.implicitWidth + Style.space(12)
  implicitHeight: root.barSize

  Text {
    id: bell
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: ""
    color: root.bar ? root.bar.barForeground : "white"
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }
  Rectangle {
    id: countBadge
    visible: root.unread > 0
    anchors.right: bell.right
    anchors.top: bell.top
    anchors.rightMargin: -Style.space(5)
    anchors.topMargin: -Style.space(3)
    width: Math.max(height, badgeText.implicitWidth + Style.space(6))
    height: Style.space(13)
    radius: height / 2
    color: Color.accent
    Text {
      id: badgeText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.unread > 99 ? "99+" : root.unread
      color: Color.background
      font.family: root.fontFamily
      font.pixelSize: Math.max(8, Style.font.caption - 2)
      font.bold: true
    }
  }
  // Card news is a plain dot, not a number, so one event (a scan arriving AND its notification)
  // is never counted twice. With unread notifications too, the dot rides the number's corner.
  Rectangle {
    id: cardDot
    visible: root.cardBadgeTotal > 0
    width: Style.space(8)
    height: width
    radius: width / 2
    color: root.bar ? root.bar.barForeground : "white"
    border.width: 1
    border.color: Color.accent
    x: root.unread > 0 ? countBadge.x + countBadge.width - width * 0.6 : bell.x + bell.width - width * 0.5
    y: root.unread > 0 ? countBadge.y - height * 0.4 : bell.y - Style.space(2)
  }
  // The bar only shows a tooltip for a widget that reports `tooltipHovered` (same contract as
  // the shell's own buttons).
  readonly property bool tooltipHovered: visible && bellMouse.containsMouse

  MouseArea {
    id: bellMouse
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    onClicked: function(m) { if (m.button === Qt.RightButton) root.openSettings(); else root.toggle() }
    // The bar's own tooltip; says "Close" while the panel is already open.
    onEntered: if (root.bar) root.bar.showTooltip(root, root.panelOpen ? "Close Omahub" : "Open Omahub")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  // --- slide-out panel ----------------------------------------------------
  PanelWindow {
    id: win
    screen: root.anchorScreen
    visible: root.panelOpen || root.closing
    color: "transparent"
    // Normal (not Ignore): respect the bar's exclusive zone, so this full-screen
    // window is laid out in whatever space the user's bar leaves free, whatever its
    // size, position, gaps or spacing scale.
    exclusionMode: ExclusionMode.Normal
    WlrLayershell.namespace: "linuskelsey-omahub"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.panelOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }

    HyprlandFocusGrab {
      windows: [win]
      active: root.panelOpen
      onCleared: root.close()
    }

    // Translucent backdrop: Hyprland blurs whatever is behind its non-transparent
    // pixels (layer rule registered in registerBinds), which dims and softens the
    // desktop so the hub stands out. Clicking it closes the hub.
    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.28)
      opacity: root.panelOpen ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 200 } }
      MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    Item {
      id: slide
      width: root.panelWidth + root.gap + root.edgeGap
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.right: parent.right
      anchors.rightMargin: root.panelOpen ? 0 : -width
      Behavior on anchors.rightMargin { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
      focus: root.panelOpen
      Keys.onEscapePressed: root.close()

      // Wheel guard. While the panel is scrolling (and for a moment after) the wheel belongs to the
      // hub: a control that slides under a stationary pointer, such as a slider, would otherwise
      // swallow the wheel and change its value instead of letting the scroll carry on. When idle the
      // wheel passes through untouched, so a deliberate wheel over a slider still works. A card can opt
      // out with `hubWheelGuard: false`, and read `hubScrolling` to do its own thing.
      Timer { id: wheelGuard; interval: 250 }
      MouseArea {
        anchors.fill: scroller
        z: 10
        acceptedButtons: Qt.NoButton
        onWheel: function(w) {
          var p = mapToItem(col, w.x, w.y)
          var frame = col.childAt(p.x, p.y)
          var item = frame && frame.cardItem ? frame.cardItem : null
          if (!wheelGuard.running || (item && item.hubWheelGuard === false)) { w.accepted = false; return }
          var dy = w.pixelDelta.y !== 0 ? w.pixelDelta.y : w.angleDelta.y
          var target = scroller
          var inner = frame && frame.scrollArea ? frame.scrollArea : null
          if (inner && inner.visible && inner.interactive) {
            var q = mapToItem(inner, w.x, w.y)
            var canMove = dy > 0 ? inner.contentY > 0 : inner.contentY < inner.contentHeight - inner.height
            if (q.y >= 0 && q.y <= inner.height && canMove) target = inner
          }
          target.contentY = Math.max(0, Math.min(target.contentHeight - target.height, target.contentY - dy))
          wheelGuard.restart()
          w.accepted = true
        }
      }

      Flickable {
        id: scroller
        onContentYChanged: wheelGuard.restart()
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: root.vGap
        anchors.bottomMargin: root.edgeGap
        anchors.leftMargin: root.gap
        anchors.rightMargin: root.edgeGap
        contentWidth: width
        contentHeight: col.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: col
          width: scroller.width
          spacing: root.cardGap

          Text {
            visible: root.missingDeps !== ""
            width: parent.width
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: root.missingDeps
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          // header
          Rectangle {
            width: parent.width
            height: Style.space(28)
            radius: Style.cornerRadius
            color: root.surface
            visible: root.groups.length > 0
            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "Notifications"
              color: root.textColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "Clear all"
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.space(4)
                cursorShape: Qt.PointingHandCursor
                onClicked: root.clearAll()
              }
            }
          }

          Repeater {
            model: root.groups
            delegate: NotifGroup {
              required property var modelData
              model_: modelData
              surface: root.surface
              textColor: root.textColor
              fontFamily: root.fontFamily
              onDismissItem: function(stem) { root.remove(stem) }
              onActivate: function(n) { root.activateNotification(n) }
              onDismissGroup: root.removeGroup(modelData)
            }
          }

          Text {
            visible: root.groups.length === 0 && root.enabledCards.length === 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: "No notifications"
            color: root.textColor
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            topPadding: Style.space(20)
          }

          // Cards from other plugins.
          Repeater {
            model: root.enabledCards
            delegate: BorderSurface {
              id: cardFrame
              required property var modelData
              readonly property bool expanded: (root.cfg.expandedCards || []).indexOf(modelData.id) >= 0
              // A card whose own view draws a title can set `hubOwnTitle: true`: while expanded the hub
              // then drops its title and keeps only a small chevron in the corner (one title, not two).
              readonly property bool ownTitle: expanded && loader.item !== null && loader.item.hubOwnTitle === true
              readonly property int headerHeight: ownTitle ? 0 : Style.space(36)
              readonly property var cardItem: loader.item
              property alias scrollArea: cardScroll
              width: col.width
              height: headerHeight + (expanded ? Math.min(loader.height, root.maxCardHeight) + Style.space(24) : 0)
              radius: Style.cornerRadius
              color: root.surface
              borderSpec: Border.flat(Qt.alpha(Color.accent, 0.5), Math.max(1, Style.space(1)))
              clip: true

              Connections {
                target: root
                function onPanelOpenChanged() {
                  if (!root.panelOpen) return
                  cardScroll.contentY = 0
                  if (loader.item && typeof loader.item.markViewed === "function") loader.item.markViewed()
                }
              }

              // Header: title; click anywhere on it to expand or collapse. The card stays loaded
              // while collapsed so its badge and markViewed() keep working.
              Item {
                id: cardHeader
                width: parent.width
                height: cardFrame.headerHeight
                visible: !cardFrame.ownTitle
                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(36)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  text: cardFrame.modelData.title
                  color: root.textColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
                MouseArea {
                  id: headerHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setCardExpanded(cardFrame.modelData.id, !cardFrame.expanded)
                }
              }

              // Chevron: vertically centred in the header, or a corner overlay when the card has its own title.
              Text {
                id: chevron
                z: 2
                anchors.right: parent.right
                anchors.rightMargin: Style.space(12)
                y: cardFrame.ownTitle ? Style.space(8) : (cardFrame.headerHeight - height) / 2
                textFormat: Text.PlainText
                text: "\uf078"
                color: root.textColor
                opacity: (headerHover.containsMouse || chevronHover.containsMouse) ? 1 : 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                rotation: cardFrame.expanded ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: 120 } }
                MouseArea {
                  id: chevronHover
                  anchors.fill: parent
                  anchors.margins: -Style.space(6)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setCardExpanded(cardFrame.modelData.id, !cardFrame.expanded)
                }
              }

              // Cards taller than the cap scroll inside their frame.
              Flickable {
                id: cardScroll
                visible: cardFrame.expanded
                anchors.fill: parent
                anchors.topMargin: cardFrame.ownTitle ? Style.space(12) : cardFrame.headerHeight
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.bottomMargin: Style.space(12)
                contentWidth: width
                contentHeight: loader.height
                clip: true
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                onContentYChanged: wheelGuard.restart()

                Loader {
                  id: loader
                  width: cardScroll.width
                  height: item ? item.implicitHeight : Style.space(16)
                  source: "file://" + cardFrame.modelData.entry
                  onLoaded: {
                    if (item && "hubWidth" in item) item.hubWidth = Qt.binding(function() { return loader.width })
                    if (item && "shell" in item) item.shell = Qt.binding(function() { return root.bar ? root.bar.shell : null })
                    if (item && "hubScrolling" in item) item.hubScrolling = Qt.binding(function() { return wheelGuard.running })
                    if (item && "hubOpen" in item) item.hubOpen = Qt.binding(function() { return root.panelOpen && cardFrame.expanded })
                    if (item && "badge" in item) {
                      var id = cardFrame.modelData.id
                      var update = function() {
                        var b = Object.assign({}, root.cardBadges); b[id] = item.badge; root.cardBadges = b
                      }
                      item.badgeChanged.connect(update); update()
                    }
                  }
                }
              }
            }
          }

          // Last item in the scroll: opens the hub's settings (same as the settings shortcut).
          Rectangle {
            id: footer
            width: parent.width
            height: Style.space(32)
            radius: Style.cornerRadius
            color: footerHover.containsMouse ? Qt.lighter(root.surface, 1.25) : root.surface
            border.width: 1
            border.color: Qt.alpha(Color.accent, 0.5)

            Row {
              anchors.centerIn: parent
              spacing: Style.space(8)
              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "\uf013"
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "Omahub settings"
                color: root.textColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
            MouseArea {
              id: footerHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openSettings()
            }
          }
        }
      }
    }
  }

  // --- settings overlay ---------------------------------------------------
  // While settings are open, ask the compositor to deliver shortcuts to this overlay instead of
  // firing global binds. Otherwise Omarchy's SUPER+W ("close window") closes whatever window is
  // behind the overlay. Keys the overlay does not use are simply ignored.
  ShortcutInhibitor {
    window: settingsWin
    enabled: root.settingsOpen
  }

  // Does a key event match a shortcut written like "SUPER + ALT + N"? Letters and digits only.
  function shortcutMatches(event, spec) {
    if (!spec) return false
    var mods = 0, key = -1
    var parts = String(spec).split("+")
    for (var i = 0; i < parts.length; i++) {
      var t = parts[i].trim().toUpperCase()
      if (t === "SUPER" || t === "META" || t === "LOGO" || t === "MOD4") mods |= Qt.MetaModifier
      else if (t === "SHIFT") mods |= Qt.ShiftModifier
      else if (t === "CTRL" || t === "CONTROL") mods |= Qt.ControlModifier
      else if (t === "ALT") mods |= Qt.AltModifier
      else if (/^[A-Z]$/.test(t)) key = Qt.Key_A + (t.charCodeAt(0) - 65)
      else if (/^[0-9]$/.test(t)) key = Qt.Key_0 + (t.charCodeAt(0) - 48)
      else return false
    }
    var wanted = Qt.MetaModifier | Qt.ShiftModifier | Qt.ControlModifier | Qt.AltModifier
    return key !== -1 && event.key === key && (event.modifiers & wanted) === mods
  }
  // Shortcuts that should simply dismiss the settings overlay.
  function dismissesSettings(event) {
    return shortcutMatches(event, "SUPER + W") || shortcutMatches(event, cfg.settingsKey) || shortcutMatches(event, cfg.toggleKey)
  }

  PanelWindow {
    id: settingsWin
    screen: root.anchorScreen
    visible: root.settingsOpen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "linuskelsey-omahub-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.settingsOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }

    Rectangle { anchors.fill: parent; color: Color.menu.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.closeSettings() }

    BorderSurface {
      width: Math.min(Style.space(520), parent.width - root.gap * 2)
      height: Math.min(Style.space(600), parent.height - root.gap * 2)
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.flat(Color.accent, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }
      // Events not consumed by a field inside (e.g. a modifier shortcut) bubble up to here.
      Keys.onPressed: function(event) {
        if (root.dismissesSettings(event)) { root.closeSettings(); event.accepted = true }
      }
      Item {
        focus: true
        Keys.onEscapePressed: root.closeSettings()
        Component.onCompleted: forceActiveFocus()
      }

      Flickable {
        anchors.fill: parent
        anchors.margins: Style.spacing.panelPadding
        contentHeight: sCol.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: sCol
          width: parent.width
          spacing: Style.space(12)

          Text {
            textFormat: Text.PlainText
            text: "Omahub"
            color: Color.menu.text
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            text: "Cards"
            color: Color.menu.text
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
          Text {
            visible: root.available.length === 0
            width: parent.width
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: "No plugin declares a notification card yet. A plugin opts in with a \"hubCard\" entry in its manifest.json."
            color: Color.menu.text
            opacity: 0.65
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          // Enabled (ordered) first, then the rest.
          Repeater {
            model: {
              var ids = root.cfg.cards || [], out = [], seen = {}
              for (var i = 0; i < ids.length; i++) for (var k = 0; k < root.available.length; k++)
                if (root.available[k].id === ids[i]) { out.push({ c: root.available[k], on: true }); seen[ids[i]] = 1 }
              for (var j = 0; j < root.available.length; j++)
                if (!seen[root.available[j].id]) out.push({ c: root.available[j], on: false })
              return out
            }
            delegate: Rectangle {
              required property var modelData
              required property int index
              width: sCol.width
              height: Style.space(40)
              radius: Style.cornerRadius
              color: modelData.on ? Qt.alpha(Color.accent, 0.15) : "transparent"

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(10)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: modelData.on ? "" : ""
                  color: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                  MouseArea {
                    anchors.fill: parent
                    anchors.margins: -Style.space(6)
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleCard(modelData.c.id, !modelData.on)
                  }
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - Style.space(110)
                  textFormat: Text.PlainText
                  text: modelData.c.title + ((modelData.c.contract || 1) > root.contractVersion ? "   · needs a newer hub" : ((root.cfg.knownCards || []).indexOf(modelData.c.id) < 0 && !modelData.on ? "   · new" : ""))
                  elide: Text.ElideRight
                  color: Color.menu.text
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  visible: modelData.on
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: ""
                  color: Color.menu.text
                  font.family: root.fontFamily
                  MouseArea { anchors.fill: parent; anchors.margins: -Style.space(6); cursorShape: Qt.PointingHandCursor; onClicked: root.moveCard(modelData.c.id, -1) }
                }
                Text {
                  visible: modelData.on
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: ""
                  color: Color.menu.text
                  font.family: root.fontFamily
                  MouseArea { anchors.fill: parent; anchors.margins: -Style.space(6); cursorShape: Qt.PointingHandCursor; onClicked: root.moveCard(modelData.c.id, 1) }
                }
              }
            }
          }

          Row {
            spacing: Style.space(10)
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.cfg.hideBarWidgets === true ? "\uf205" : "\uf204"
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.space(6)
                cursorShape: Qt.PointingHandCursor
                onClicked: root.saveConfig(Object.assign({}, root.cfg, { hideBarWidgets: !(root.cfg.hideBarWidgets === true) }))
              }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              width: sCol.width - Style.space(40)
              wrapMode: Text.Wrap
              text: "Hide these cards' own bar icons"
              color: Color.menu.text
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          Row {
            spacing: Style.space(10)
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.cfg.blurDesktop === true ? "\uf205" : "\uf204"
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.space(6)
                cursorShape: Qt.PointingHandCursor
                onClicked: root.saveConfig(Object.assign({}, root.cfg, { blurDesktop: root.cfg.blurDesktop !== true }))
              }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              width: sCol.width - Style.space(40)
              wrapMode: Text.Wrap
              text: "Blur the desktop while open (switches Hyprland blur on temporarily)"
              color: Color.menu.text
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          Row {
            spacing: Style.space(10)
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.cfg.clickRunsActions === true ? "\uf205" : "\uf204"
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.space(6)
                cursorShape: Qt.PointingHandCursor
                onClicked: root.saveConfig(Object.assign({}, root.cfg, { clickRunsActions: root.cfg.clickRunsActions !== true }))
              }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: sCol.width - Style.space(40)
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
              text: "Clicking a notification may run the command its sender attached (otherwise it just focuses the app)"
              color: Color.menu.text
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          Column {
            spacing: Style.space(6)
            width: parent.width
            Rectangle {
              width: wipeText.implicitWidth + Style.space(24)
              height: Style.space(30)
              radius: Style.cornerRadius
              color: "transparent"
              border.width: 1
              border.color: wipeArea.containsMouse ? Color.urgent : Qt.alpha(Color.menu.text, 0.3)
              Text {
                id: wipeText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "Delete archived notifications"
                color: Color.menu.text
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              MouseArea { id: wipeArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.clearAll() }
            }
            Text {
              width: parent.width
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
              text: "Entries are also removed automatically after " + (root.cfg.retentionDays || 30) + " days."
              color: Color.menu.text
              opacity: 0.65
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            textFormat: Text.PlainText
            text: "Shortcuts"
            color: Color.menu.text
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
          Repeater {
            model: [["toggleKey", "Open / close"], ["settingsKey", "Settings"]]
            delegate: Row {
              required property var modelData
              spacing: Style.space(10)
              Text {
                width: Style.space(110)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: modelData[1]
                color: Color.menu.text
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Rectangle {
                width: Style.space(220); height: Style.space(30)
                radius: Style.cornerRadius
                color: "transparent"
                border.color: keyInput.activeFocus ? Color.accent : Qt.alpha(Color.menu.text, 0.3)
                border.width: 1
                TextInput {
                  id: keyInput
                  anchors.fill: parent
                  anchors.margins: Style.space(6)
                  verticalAlignment: TextInput.AlignVCenter
                  text: root.cfg[modelData[0]]
                  color: Color.menu.text
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  selectByMouse: true
                  onEditingFinished: if (text !== root.cfg[modelData[0]]) root.setKey(modelData[0], text)
                }
              }
            }
          }
          Text {
            width: parent.width
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: root.bindStatus === "ok" ? "Shortcuts registered with Hyprland. Format: SUPER + ALT + N."
                : (root.bindStatus ? "Hyprland: " + root.bindStatus + ". If shortcuts can't be registered (needs Hyprland's Lua config, 0.56+), bind a key yourself to: omarchy-shell " + root.hubId + " toggle" : "Format: SUPER + ALT + N. Registered at runtime; your Hyprland config is not edited.")
            color: root.bindStatus && root.bindStatus !== "ok" ? Color.urgent : Color.menu.text
            opacity: root.bindStatus && root.bindStatus !== "ok" ? 1 : 0.65
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
