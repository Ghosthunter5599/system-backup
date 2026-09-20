import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui

import "Api.js" as Api

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false
  property bool closingFromHost: false
  property bool escapeCloseArmed: false
  property real volumeBeforeMute: 0.5
  property string currentTab: "home"
  property bool openedForLogin: false

  property string searchText: ""
  property string searchType: "track"
  property string libraryType: "tracks"
  property string homeType: "recent"
  property string libraryFilter: ""
  property string librarySort: "default"
  property string playlistFilter: ""
  property string playlistSort: "default"
  property string detailFilter: ""
  property string detailSort: "default"
  property string homeFilter: ""
  property string discoverFilter: ""
  property string queueFilter: ""
  property string artistSearchText: ""
  property bool searchInContext: true
  property bool universalSearchActive: false
  property var scrollPositions: ({})
  property var scrollPositionOrder: []
  readonly property int scrollPositionLimit: 128
  property var navigationStack: []
  property string restoredPlaylistId: ""

  property string draftDeviceName: "Omarchy Spotify"
  property string draftIdleMinutes: "15"
  property bool draftShowMiniPlayer: true
  property string draftShortcutPlayer: "Omarchy default"
  property bool draftShowTitle: true
  property bool draftShowArtist: false
  property bool draftScrollBarText: false
  property real draftScrollSpeed: 1
  property string draftAudioQuality: "320 kbps"
  property var contextItem: null
  property var contextSourceItems: []
  property string contextSourceUri: ""
  property int contextSourceIndex: -1
  property var contextPlaylist: null
  property var pendingPlaylistItem: null
  property string newPlaylistName: ""
  property string createPlaylistName: ""

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "quickshell.spotify"
  readonly property string lyricsRequestKey: "spotify-panel-lyrics"
  readonly property color foreground: Color.foreground
  readonly property color background: Color.background
  readonly property color accent: Color.accent
  readonly property color popupBackground: Color.popups.background
  readonly property var popupBorderSpec: Border.flat(Color.popups.border,
    Math.max(1, Style.normalBorderWidth))
  readonly property int popupScrollbarGutter: Style.space(14)
  readonly property string fontFamily: Style.font.family
  readonly property bool fullyConnected: service && service.fullyConnected
  readonly property bool compactHeight: window.height < Style.space(620)
  readonly property bool compactWidth: window.width < Style.space(760)
  readonly property var activeSearchScope: Api.searchScope(currentTab,
    service ? service.detailItem : null,
    service ? service.selectedPlaylist : null, homeType, libraryType)
  readonly property bool showingUniversalSearch: Api.universalSearchVisible(
    currentTab, universalSearchActive)
  readonly property bool artistScopedSearchActive: currentTab === "detail"
    && service && service.detailItem && service.detailItem.type === "artist"
    && artistSearchText.trim() !== ""
  readonly property bool shortcutsBlocked: mediaContextMenu.opened
    || playlistPicker.opened || createPlaylistPopup.opened || sleepPopup.opened
    || shortcutHelpPopup.opened || lyricsInstallPopup.opened
  readonly property var panelBar: QtObject {
    readonly property color foreground: root.foreground
    readonly property color background: root.background
    readonly property color urgent: Color.urgent
    readonly property string fontFamily: root.fontFamily
    readonly property string position: "top"
    readonly property bool vertical: false
    readonly property int barSize: 28
  }

  function syncDraftSettings() {
    if (!service) return
    draftDeviceName = service.deviceName
    draftIdleMinutes = String(service.idleShutdownMinutes)
    draftShowMiniPlayer = service.showMiniPlayer
    draftShortcutPlayer = service.shortcutPlayer
    draftShowTitle = service.showTrackTitle
    draftShowArtist = service.showArtistName
    draftScrollBarText = service.scrollBarText
    draftScrollSpeed = service.scrollSpeed
    draftAudioQuality = service.audioQuality
  }

  function saveSettings() {
    if (!service) return
    var values = {
      deviceName: String(draftDeviceName || "").trim() || "Omarchy Spotify",
      idleShutdownMinutes: Math.max(0, Math.min(1440,
        Math.floor(Number(draftIdleMinutes) || 0))),
      showMiniPlayer: draftShowMiniPlayer ? "On" : "Off",
      shortcutPlayer: draftShortcutPlayer,
      showTrackTitle: draftShowTitle ? "On" : "Off",
      showArtistName: draftShowArtist ? "On" : "Off",
      scrollBarText: draftScrollBarText ? "On" : "Off",
      scrollSpeed: Api.normalizedScrollSpeed(draftScrollSpeed),
      audioQuality: draftAudioQuality
    }
    service.persistSettings(values)
    syncDraftSettings()
    service.succeed("Settings saved")
  }

  function cycleAudioQuality() {
    draftAudioQuality = draftAudioQuality === "96 kbps" ? "160 kbps"
      : (draftAudioQuality === "160 kbps" ? "320 kbps" : "96 kbps")
  }

  function cycleShortcutPlayer() {
    draftShortcutPlayer = draftShortcutPlayer === "Omarchy default"
      ? "Full player"
      : (draftShortcutPlayer === "Full player"
        ? "Mini player" : "Omarchy default")
  }

  function audioQualityLabel() {
    if (draftAudioQuality === "96 kbps") return "Standard · 96 kbps"
    if (draftAudioQuality === "320 kbps") return "Very high · 320 kbps"
    return "High · 160 kbps"
  }

  function scrollSpeedLabel() {
    var value = Api.normalizedScrollSpeed(draftScrollSpeed)
    return value.toFixed(2).replace(/\.00$/, "").replace(/0$/, "") + "×"
  }

  function enforceScrollAvailability() {
    if (!Api.canScrollBarText(draftShowTitle, draftShowArtist))
      draftScrollBarText = false
  }

  function connectionButtonText() {
    if (!service) return "Spotify unavailable"
    if (service.loginBusy) return service.loginProgress + "…"
    if (fullyConnected) return "Connected"
    if (!service.daemon.playbackReady) return "Set up and continue"
    return "Continue with Spotify"
  }

  function connectionHeadline() {
    if (!service) return "Spotify is unavailable"
    if (service.daemon.setupBusy) return "Setting up playback"
    if (fullyConnected) return "You're connected"
    if (!service.daemon.playbackReady) return "One quick setup, then Spotify"
    return "Continue with Spotify"
  }

  function connectionErrorText() {
    if (!service) return "Omarchy Spotify is unavailable"
    return service.lastError || service.auth.lastError || service.daemon.lastError
  }

  function playbackStatusText() {
    if (!service) return "Playback is unavailable"
    if (!service.daemon.requirementsChecked) return "Checking playback support…"
    if (service.daemon.setupBusy) return "Preparing playback on this computer…"
    if (!service.daemon.playbackReady) return "A quick one-time setup is needed"
    if (!service.daemon.credentialsChecked) return "Checking your Spotify connection…"
    if (!service.daemon.credentialsAvailable) return "Ready for Spotify sign-in"
    if (service.daemon.running) return "Active on this computer"
    return "Ready — starts automatically when you play music"
  }

  function openMediaContext(item, sceneX, sceneY, sourceItems, contextUri, index) {
    if (!item) return
    contextItem = item
    contextSourceItems = Array.isArray(sourceItems) ? sourceItems : []
    contextSourceUri = String(contextUri || "")
    contextSourceIndex = index === undefined ? -1 : Math.floor(Number(index))
    contextPlaylist = playlistForContext(contextSourceUri)
    mediaContextMenu.x = Math.max(Style.space(6), Math.min(
      window.width - mediaContextMenu.width - Style.space(6), Number(sceneX) || 0))
    mediaContextMenu.y = Math.max(Style.space(6), Math.min(
      window.height - mediaContextMenu.height - Style.space(6), Number(sceneY) || 0))
    mediaContextMenu.open()
  }

  function dismissTransientPopup() {
    if (lyricsInstallPopup.opened && (!service || !service.lyricsPluginBusy)) {
      lyricsInstallPopup.close()
      return true
    }
    if (shortcutHelpPopup.opened) {
      shortcutHelpPopup.close()
      return true
    }
    if (mediaContextMenu.opened) {
      mediaContextMenu.close()
      return true
    }
    if (playlistPicker.opened) {
      playlistPicker.close()
      return true
    }
    if (createPlaylistPopup.opened) {
      createPlaylistPopup.close()
      return true
    }
    if (sleepPopup.opened) {
      sleepPopup.close()
      return true
    }
    return false
  }

  function disarmEscapeClose() {
    escapeCloseTimer.stop()
    escapeCloseArmed = false
  }

  function armEscapeClose() {
    escapeCloseArmed = true
    escapeCloseTimer.restart()
  }

  function clearVisibleSearchForEscape() {
    if (!unifiedSearchBar.visible || unifiedSearchText().trim() === "") return false
    clearUnifiedSearch()
    disarmEscapeClose()
    return true
  }

  function turnPlaylistIntoOwn(playlist) {
    if (!service || !playlist) return
    service.makePlaylistYourOwn(playlist, function(copy) {
      if (!copy) return
      root.chooseTab("playlists")
      root.service.openPlaylist(copy)
    })
  }

  function playlistForContext(uri) {
    var value = String(uri || "")
    if (!service || !value) return null
    if (service.selectedPlaylist && service.selectedPlaylist.uri === value)
      return service.selectedPlaylist
    if (service.detailItem && service.detailItem.type === "playlist"
        && service.detailItem.uri === value) return service.detailItem
    return null
  }

  function rememberScroll(key, value) {
    var name = String(key || currentTab)
    var position = Math.max(0, Number(value) || 0)
    if (!scrollPositions || typeof scrollPositions !== "object")
      scrollPositions = ({})
    if (!Array.isArray(scrollPositionOrder)) scrollPositionOrder = []
    scrollPositions[name] = position
    var evicted = Api.touchBoundedOrder(scrollPositionOrder, name,
      scrollPositionLimit)
    if (evicted) delete scrollPositions[evicted]
  }

  function scrollFor(key) {
    return Math.max(0, Number(scrollPositions[String(key || currentTab)]) || 0)
  }

  function restoreScrollPositions(values) {
    var source = values && typeof values === "object" ? values : ({})
    var keys = Object.keys(source)
    var start = Math.max(0, keys.length - scrollPositionLimit)
    var next = ({})
    var order = []
    for (var i = start; i < keys.length; i++) {
      var name = keys[i]
      next[name] = Math.max(0, Number(source[name]) || 0)
      order.push(name)
    }
    scrollPositions = next
    scrollPositionOrder = order
  }

  function restoreUiState(restoreDetail) {
    if (!service) return
    var state = service.sessionState || ({})
    service.restoreLastRadioPlaylist(state.lastRadioPlaylist)
    searchText = String(state.searchText || service.searchQuery || "")
    searchType = Api.SEARCH_TYPES.indexOf(String(state.searchType || "")) >= 0
      ? String(state.searchType) : "track"
    libraryType = ["tracks", "albums", "artists", "shows", "episodes", "audiobooks"]
      .indexOf(String(state.libraryType || "")) >= 0 ? String(state.libraryType) : "tracks"
    homeType = ["recent", "tracks", "artists"].indexOf(String(state.homeType || "")) >= 0
      ? String(state.homeType) : "recent"
    libraryFilter = String(state.libraryFilter || "")
    librarySort = String(state.librarySort || "default")
    playlistFilter = String(state.playlistFilter || "")
    playlistSort = String(state.playlistSort || "default")
    detailFilter = String(state.detailFilter || "")
    detailSort = String(state.detailSort || "default")
    homeFilter = String(state.homeFilter || "")
    discoverFilter = String(state.discoverFilter || "")
    queueFilter = String(state.queueFilter || "")
    artistSearchText = String(state.artistSearchText || "")
    searchInContext = true
    universalSearchActive = false
    restoreScrollPositions(state.scrollPositions)
    restoredPlaylistId = String(state.selectedPlaylistId || "")
    var restoredTab = String(state.tab || "home")
    if (["home", "discover", "search", "library", "playlists", "detail", "queue", "devices", "setup"]
        .indexOf(restoredTab) >= 0) currentTab = restoredTab
    if (restoreDetail !== false && currentTab === "detail" && state.detailItem)
      service.openDetail(state.detailItem, artistSearchText)
  }

  function persistUiState() {
    if (!service) return
    service.persistSession({
      tab: currentTab === "login" ? "home" : currentTab,
      searchText: searchText,
      searchType: searchType,
      libraryType: libraryType,
      homeType: homeType,
      libraryFilter: libraryFilter,
      librarySort: librarySort,
      playlistFilter: playlistFilter,
      playlistSort: playlistSort,
      detailFilter: detailFilter,
      detailSort: detailSort,
      homeFilter: homeFilter,
      discoverFilter: discoverFilter,
      queueFilter: queueFilter,
      artistSearchText: currentTab === "detail" && service.detailItem
        && service.detailItem.type === "artist" ? artistSearchText : "",
      scrollPositions: scrollPositions,
      detailItem: currentTab === "detail" && service.detailItem ? service.detailItem : null,
      selectedPlaylistId: service.selectedPlaylist ? service.selectedPlaylist.id : restoredPlaylistId,
      lastRadioPlaylist: service.lastRadioPlaylist
    })
  }

  function restorePlaylistSelection() {
    if (!service || !restoredPlaylistId || service.selectedPlaylist) return
    var playlist = service.playlistById(restoredPlaylistId)
    if (playlist) service.openPlaylist(playlist)
  }

  function openItem(item) {
    if (!item) return
    if (item.type === "artist" && !item.id) {
      if (service) service.resolveArtist(item.name, function(resolved) {
        root.openItem(resolved)
      })
      return
    }
    if (item.kind !== "context") {
      activateMedia(item, [item], "")
      return
    }
    var stack = navigationStack.slice()
    stack.push({
      tab: currentTab,
      item: currentTab === "detail" && service ? service.detailItem : null,
      universalSearchActive: universalSearchActive,
      searchInContext: searchInContext,
      artistSearchText: currentTab === "detail" && service && service.detailItem
        && service.detailItem.type === "artist" ? artistSearchText : "",
      detailFilter: currentTab === "detail" && service && service.detailItem
        && service.detailItem.type !== "artist" ? detailFilter : ""
    })
    navigationStack = stack
    unifiedSearchDelay.stop()
    searchInContext = true
    universalSearchActive = false
    if (service) service.cancelSearch(false)
    currentTab = "detail"
    if (item.type === "artist") artistSearchText = ""
    else detailFilter = ""
    if (service) service.openDetail(item)
  }

  function goBack() {
    if (!navigationStack.length) {
      chooseTab("search")
      return
    }
    var stack = navigationStack.slice()
    var destination = stack.pop()
    navigationStack = stack
    unifiedSearchDelay.stop()
    if (service) service.cancelSearch(false)
    currentTab = destination.tab || "search"
    universalSearchActive = destination.universalSearchActive === true
    searchInContext = destination.searchInContext === undefined
      ? !universalSearchActive : destination.searchInContext === true
    if (currentTab === "detail" && destination.item && service) {
      artistSearchText = destination.item.type === "artist"
        ? String(destination.artistSearchText || "") : ""
      detailFilter = destination.item.type === "artist"
        ? "" : String(destination.detailFilter || "")
      service.openDetail(destination.item, artistSearchText)
    }
    if (service && (currentTab === "search" || universalSearchActive)) {
      if (searchText.trim() === "") service.clearSearch()
      else service.search(searchText)
    }
    else if (service && currentTab !== "detail") service.openView(currentTab, false)
  }

  function activateMedia(item, sourceItems, contextUri) {
    if (!item || !service) return
    if (unifiedSearchField.activeFocus) focusScope.forceActiveFocus()
    service.playItem(item, sourceItems, contextUri)
  }

  function textInputFocused() {
    var item = window.activeFocusItem
    return !!item && ("acceptableInput" in item || "echoMode" in item)
  }

  function shortcutHint(label, keys) {
    var text = String(label || "")
    var shortcut = String(keys || "")
    return shortcut ? text + " · " + shortcut : text
  }

  function primaryNavigationShortcut(id) {
    if (id === "home") return "Alt+Shift+H"
    if (id === "queue") return "Alt+Shift+Q"
    return ""
  }

  function shortcutRows() {
    return [
      { section: "SEARCH", action: "Focus search", keys: "Ctrl+K or /" },
      { action: "Search in the current area", keys: "Ctrl+F" },
      { action: "Search all of Spotify", keys: "Ctrl+L" },
      { action: "Clear search", keys: "Esc" },
      { section: "NAVIGATION", action: "Go back", keys: "Alt+Left" },
      { action: "Open Settings", keys: "Ctrl+," },
      { action: "Open For You", keys: "Alt+Shift+H" },
      { action: "Open Queue", keys: "Alt+Shift+Q" },
      { action: "Open Devices", keys: "Alt+Shift+D" },
      { action: "Move through lists", keys: "Arrow keys" },
      { action: "Open the selected item", keys: "Enter" },
      { section: "PLAYBACK", action: "Play or pause", keys: "Space" },
      { action: "Previous item", keys: "Ctrl+Left" },
      { action: "Next item", keys: "Ctrl+Right" },
      { action: "Mute or restore volume", keys: "M" },
      { action: "Toggle shuffle", keys: "Ctrl+S" },
      { action: "Cycle repeat", keys: "Ctrl+R" },
      { action: "Seek back 10 seconds", keys: "Shift+Left" },
      { action: "Seek forward 10 seconds", keys: "Shift+Right" },
      { action: "Raise volume 5%", keys: "Ctrl+Up" },
      { action: "Lower volume 5%", keys: "Ctrl+Down" },
      { section: "WINDOW", action: "Arm close / close", keys: "Esc, Esc" },
      { action: "Show this reference", keys: "Ctrl+/" }
    ]
  }

  function scopedSearchText() {
    if (currentTab === "home") return homeFilter
    if (currentTab === "discover") return discoverFilter
    if (currentTab === "library") return libraryFilter
    if (currentTab === "playlists") return playlistFilter
    if (currentTab === "queue") return queueFilter
    if (currentTab === "detail") return activeSearchScope.mode === "artist"
      ? artistSearchText : detailFilter
    return ""
  }

  function setScopedSearchText(value) {
    var text = String(value || "")
    if (currentTab === "home") homeFilter = text
    else if (currentTab === "discover") discoverFilter = text
    else if (currentTab === "library") libraryFilter = text
    else if (currentTab === "playlists") playlistFilter = text
    else if (currentTab === "queue") queueFilter = text
    else if (currentTab === "detail") {
      if (activeSearchScope.mode === "artist") artistSearchText = text
      else detailFilter = text
    }
  }

  function unifiedSearchText() {
    return activeSearchScope.available && searchInContext
      ? scopedSearchText() : searchText
  }

  function searchScopeButtonText() {
    var label = activeSearchScope && activeSearchScope.label
      ? String(activeSearchScope.label) : "this area"
    if (label.length > 24) label = label.substring(0, 23) + "…"
    return "In " + label
  }

  function runUnifiedSearch() {
    unifiedSearchDelay.stop()
    if (!service) return
    if (activeSearchScope.available && searchInContext) {
      if (activeSearchScope.mode === "artist")
        service.findArtistMusic(artistSearchText)
      return
    }
    if (currentTab !== "search" && searchText.trim() !== "")
      universalSearchActive = true
    if (searchText.trim() === "") service.clearSearch()
    else service.search(searchText)
  }

  function editUnifiedSearch(value) {
    unifiedSearchDelay.stop()
    var text = String(value || "")
    if (activeSearchScope.available && searchInContext) {
      setScopedSearchText(text)
      if (activeSearchScope.mode === "artist") {
        if (text.trim() === "" && service) service.findArtistMusic("")
        else unifiedSearchDelay.restart()
      }
      return
    }
    searchText = text
    if (currentTab !== "search" && !activeSearchScope.available)
      universalSearchActive = text.trim() !== ""
    if (!service) return
    if (text.trim() === "") service.clearSearch()
    else unifiedSearchDelay.restart()
  }

  function clearUnifiedSearch() {
    unifiedSearchDelay.stop()
    if (activeSearchScope.available && searchInContext) {
      setScopedSearchText("")
      if (activeSearchScope.mode === "artist" && service)
        service.findArtistMusic("")
    } else {
      searchText = ""
      if (service) service.clearSearch()
      if (currentTab !== "search") {
        universalSearchActive = false
        if (activeSearchScope.available) {
          searchInContext = true
          setScopedSearchText("")
          if (activeSearchScope.mode === "artist" && service)
            service.findArtistMusic("")
        }
      }
    }
    Qt.callLater(function() { unifiedSearchField.forceActiveFocus() })
  }

  function toggleSearchScope() {
    if (!activeSearchScope.available) return
    unifiedSearchDelay.stop()
    var text = unifiedSearchText()
    if (searchInContext) {
      searchText = text
      searchInContext = false
      universalSearchActive = true
      if (service) {
        if (searchText.trim() === "") service.clearSearch()
        else service.search(searchText)
      }
    } else {
      searchInContext = true
      universalSearchActive = false
      setScopedSearchText(text)
      if (service) {
        service.cancelSearch(false)
        if (activeSearchScope.mode === "artist")
          service.findArtistMusic(text)
      }
    }
    Qt.callLater(function() {
      unifiedSearchField.selectAll()
      unifiedSearchField.forceActiveFocus()
    })
  }

  function focusSearch() {
    if (!unifiedSearchBar.visible) return
    unifiedSearchField.selectAll()
    unifiedSearchField.forceActiveFocus()
  }

  function focusContextSearch() {
    if (!unifiedSearchBar.visible || !activeSearchScope.available) return
    if (!searchInContext) toggleSearchScope()
    else focusSearch()
  }

  function focusUniversalSearch() {
    if (!unifiedSearchBar.visible) return
    if (activeSearchScope.available && searchInContext) toggleSearchScope()
    else {
      if (currentTab !== "search") universalSearchActive = true
      searchInContext = false
      focusSearch()
    }
  }

  function seekBy(seconds) {
    if (!service || !service.playbackControllable) return
    service.seekSeconds(service.positionSeconds + Number(seconds || 0))
  }

  function setPanelVolume(value) {
    if (!service || !service.volumeSupported) return
    var next = Math.max(0, Math.min(1, Number(value) || 0))
    if (next > 0.001) volumeBeforeMute = next
    service.setVolume(next)
  }

  function adjustVolume(delta) {
    if (!service) return
    setPanelVolume(service.volume + Number(delta || 0))
  }

  function toggleMute() {
    if (!service || !service.volumeSupported) return
    var current = Math.max(0, Math.min(1, Number(service.volume) || 0))
    if (current > 0.001) {
      volumeBeforeMute = current
      service.setVolume(0)
    } else service.setVolume(Math.max(0.05, volumeBeforeMute))
  }

  function toggleShortcutHelp() {
    disarmEscapeClose()
    if (shortcutHelpPopup.opened) shortcutHelpPopup.close()
    else shortcutHelpPopup.open()
  }

  function openLyrics() {
    if (!service || !service.currentLyricsSong) return
    var result = service.requestLyrics(lyricsRequestKey)
    if (result !== "opening") lyricsInstallPopup.open()
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(String(payloadJson || "{}")) || ({}) } catch (e) {}
    if (shell && shell.bar
        && typeof shell.bar.hideBarWidget === "function")
      shell.bar.hideBarWidget(pluginId)
    var requestedTab = String(payload.tab || "")
    var requestedDetail = requestedTab === "detail" && payload.detailItem
      ? payload.detailItem : null
    restoreUiState(!requestedDetail)
    if (requestedDetail) {
      currentTab = "detail"
      navigationStack = []
      searchInContext = true
      universalSearchActive = false
      artistSearchText = ""
      detailFilter = ""
    } else if (["home", "discover", "search", "library", "playlists", "queue", "devices", "setup"].indexOf(requestedTab) >= 0)
      currentTab = requestedTab
    if (!fullyConnected) {
      currentTab = "login"
      universalSearchActive = false
      searchInContext = true
      openedForLogin = true
    } else {
      openedForLogin = false
    }
    closingFromHost = false
    opened = true
    syncDraftSettings()
    if (service) {
      service.setUiVisible("full-panel", true)
      service.activate(currentTab)
      if (currentTab === "detail" && requestedDetail)
        service.openDetail(requestedDetail)
      if (currentTab === "search" && searchText && service.searchQuery !== searchText)
        service.search(searchText)
    }
    Qt.callLater(function() {
      focusScope.forceActiveFocus()
    })
  }

  function close() {
    persistUiState()
    closingFromHost = true
    opened = false
    if (service) {
      service.setUiVisible("full-panel", false)
      service.cancelSearch(false)
    }
    closingFromHost = false
  }

  function requestClose() {
    disarmEscapeClose()
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  function chooseTab(tab) {
    if (!fullyConnected) {
      currentTab = "login"
      openedForLogin = true
      return
    }
    disarmEscapeClose()
    unifiedSearchDelay.stop()
    if (showingUniversalSearch && tab !== "search" && service) service.cancelSearch(false)
    searchInContext = true
    universalSearchActive = false
    currentTab = tab
    if (tab !== "detail") navigationStack = []
    openedForLogin = false
    if (service) service.openView(tab, false)
  }

  function openLastRadio() {
    if (!service || !service.lastRadioPlaylist) return
    chooseTab("playlists")
    service.openPlaylist(service.lastRadioPlaylist)
  }

  function primaryNavigationItems() {
    var items = [
      { id: "home", label: "For you", icon: "󰎆" },
      { id: "discover", label: "Discover", icon: "󰲸" }
    ]
    if (service && service.lastRadioPlaylist) items.push({
      id: "radio",
      label: service.lastRadioPlaying ? "Current radio" : "Last radio",
      icon: "󰎆"
    })
    items.push({ id: "queue", label: "Queue", icon: "󰐕" })
    return items
  }

  function radioNavigationSelected() {
    return currentTab === "playlists" && service && service.lastRadioPlaylist
      && service.selectedPlaylist
      && String(service.selectedPlaylist.id) === String(service.lastRadioPlaylist.id)
  }

  function updateLoginGate() {
    if (!opened) return
    if (!fullyConnected) {
      currentTab = "login"
      universalSearchActive = false
      searchInContext = true
      openedForLogin = true
      return
    }
    if (openedForLogin || currentTab === "login") {
      openedForLogin = false
      currentTab = "home"
      universalSearchActive = false
      searchInContext = true
      if (service) service.openView("home", false)
    }
  }

  // Track the combined service state directly. During the first login, the
  // Web API token and spotifyd credential finish in separate event turns;
  // listening only to those nested objects can miss the final combined edge
  // while the panel loader is being remapped by the browser.
  onFullyConnectedChanged: Qt.callLater(function() { root.updateLoginGate() })
  onServiceChanged: Qt.callLater(function() { root.updateLoginGate() })

  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onPlaylistsChanged() { root.restorePlaylistSelection() }
    function onRadioPlaylistReady(playlist) {
      if (!playlist || !root.service) return
      root.openLastRadio()
    }
  }

  function pageComponent() {
    if (currentTab === "login") return loginPage
    if (showingUniversalSearch) return searchPage
    if (currentTab === "setup") return setupPage
    if (currentTab === "home") return homePage
    if (currentTab === "discover") return discoverPage
    if (currentTab === "library") return libraryPage
    if (currentTab === "playlists") return playlistsPage
    if (currentTab === "detail") return detailPage
    if (currentTab === "queue") return queuePage
    if (currentTab === "devices") return devicesPage
    return searchPage
  }

  function pageTitle() {
    if (currentTab === "login") return "Log in to Spotify"
    if (showingUniversalSearch) return "Search Spotify"
    if (currentTab === "home") return "For you"
    if (currentTab === "discover") return "Discover"
    if (currentTab === "library") return "Your Library"
    if (currentTab === "playlists") return "Playlists"
    if (currentTab === "queue") return "Queue"
    if (currentTab === "devices") return "Spotify Connect"
    if (currentTab === "setup") return "Settings"
    if (currentTab === "detail") {
      if (artistScopedSearchActive) return "Search in " + service.detailItem.name
      return service && service.detailItem ? service.detailItem.name : "Loading…"
    }
    return "Search"
  }

  function pageSubtitle() {
    if (currentTab === "login") return "Connect your Spotify account to get started"
    if (showingUniversalSearch) return activeSearchScope.available
      ? "Searching everywhere — enable the area checkmark to narrow the results"
      : "Songs, artists, albums, playlists, podcasts and audiobooks"
    if (currentTab === "home") return "Recently played and your personal favorites"
    if (currentTab === "discover") return "Personal mixes and fresh music from Spotify"
    if (currentTab === "library") return "Songs, albums, artists, podcasts and audiobooks"
    if (currentTab === "playlists") return "Your Spotify playlists"
    if (currentTab === "queue") return "What plays next"
    if (currentTab === "devices") return "Speakers and players"
    if (currentTab === "setup") return "Account, playback and app preferences"
    if (currentTab === "detail") {
      if (artistScopedSearchActive)
        return "Songs, albums and playlists matching “" + artistSearchText.trim() + "”"
      return service && service.detailItem
        ? String(service.detailItem.type || "Spotify item") : "Spotify item"
    }
    return "Songs, artists, albums, playlists, podcasts and audiobooks"
  }

  function sidebarPlaylistName(item) {
    var name = item && item.name ? String(item.name) : "Playlist"
    return name.length > 22 ? name.substring(0, 21) + "…" : name
  }

  function playlistOptions() {
    var playlists = service ? service.sidebarPlaylists() : []
    var options = []
    for (var i = 0; i < playlists.length; i++) {
      var playlist = playlists[i]
      if (!playlist || !playlist.id) continue
      options.push({
        value: String(playlist.id),
        label: String(playlist.name || "Playlist"),
        description: String(playlist.ownerName || "")
      })
    }
    return options
  }

  function openExternal(item) {
    if (item && item.externalUrl) Qt.openUrlExternally(item.externalUrl)
  }

  function copyExternal(item) {
    if (!item || !item.externalUrl) return
    Quickshell.execDetached(["wl-copy", String(item.externalUrl)])
    if (service) service.succeed("Spotify link copied")
  }

  function playlistPosition(item) {
    if (!service || !item || !contextPlaylist) return -1
    var source = service.selectedPlaylist && service.selectedPlaylist.id === contextPlaylist.id
      ? service.playlistItems : service.detailItems
    var occurrence = 0
    for (var shown = 0; shown < contextSourceIndex; shown++)
      if (contextSourceItems[shown] && contextSourceItems[shown].uri === item.uri) occurrence++
    for (var i = 0; i < source.length; i++) {
      if (source[i] && source[i].uri === item.uri) {
        if (occurrence === 0) return i
        occurrence--
      }
    }
    return -1
  }

  function openPlaylistPicker(item) {
    if (!item || item.kind !== "item") return
    pendingPlaylistItem = item
    playlistPicker.open()
  }

  function openCreatePlaylistPopup() {
    if (!service || !fullyConnected) return
    createPlaylistName = ""
    createPlaylistPopup.open()
  }

  function createNamedPlaylist() {
    var name = String(createPlaylistName || "").trim()
    if (!service || !name || service.playlistActionBusy) return
    service.createPlaylist(name, function(playlist) {
      createPlaylistPopup.close()
      createPlaylistName = ""
      if (!playlist) return
      root.chooseTab("playlists")
      root.service.openPlaylist(playlist)
    })
  }

  Component.onDestruction: {
    if (service) {
      persistUiState()
      service.setUiVisible("full-panel", false)
      service.cancelSearch(false)
    }
  }

  Popup {
    id: shortcutHelpPopup
    parent: window.contentItem
    x: Math.max(Style.space(8), (window.width - width) / 2)
    y: Math.max(Style.space(8), (window.height - height) / 2)
    width: Math.min(Style.space(640), window.width - Style.space(32))
    height: Math.min(Style.space(560), window.height - Style.space(24))
    padding: Style.space(12)
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    onOpened: root.disarmEscapeClose()
    onClosed: Qt.callLater(function() { focusScope.forceActiveFocus() })

    background: BorderSurface {
      color: root.popupBackground
      radius: Style.cornerRadius
      borderSpec: root.popupBorderSpec
    }

    contentItem: Column {
      id: shortcutHelpContent
      spacing: Style.space(7)

      Row {
        id: shortcutHelpHeader
        width: parent.width
        spacing: Style.space(6)

        Column {
          width: Math.max(80, parent.width - shortcutHelpClose.width - parent.spacing)
          spacing: Style.space(1)

          Text {
            width: parent.width
            text: "Keyboard shortcuts"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            text: "Playback shortcuts pause while you are typing."
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
        }

        Button {
          id: shortcutHelpClose
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰅖"
          foreground: root.foreground
          tooltipText: root.shortcutHint("Close", "Esc")
          focusable: true
          onClicked: shortcutHelpPopup.close()
        }
      }

      PanelSeparator {
        id: shortcutHelpSeparator
        width: parent.width
        foreground: root.foreground
      }

      ScrollView {
        id: shortcutHelpScroll
        width: parent.width
        height: Math.max(80, parent.height - shortcutHelpHeader.height
          - shortcutHelpSeparator.height - parent.spacing * 2)
        rightPadding: root.popupScrollbarGutter
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AsNeeded

        Column {
          id: shortcutHelpList
          width: shortcutHelpScroll.availableWidth
          spacing: Style.space(3)

          Repeater {
            model: root.shortcutRows()

            delegate: Column {
              id: shortcutRow
              required property var modelData
              width: shortcutHelpList.width
              spacing: Style.space(2)

              Text {
                width: parent.width
                visible: String(shortcutRow.modelData.section || "") !== ""
                topPadding: visible ? Style.space(3) : 0
                text: String(shortcutRow.modelData.section || "")
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Row {
                width: parent.width
                spacing: Style.space(6)

                Text {
                  width: Math.max(80, parent.width - shortcutKey.width - parent.spacing)
                  anchors.verticalCenter: parent.verticalCenter
                  text: String(shortcutRow.modelData.action || "")
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                BorderSurface {
                  id: shortcutKey
                  width: shortcutKeyText.implicitWidth + Style.space(12)
                  height: shortcutKeyText.implicitHeight + Style.space(6)
                  radius: Style.cornerRadius
                  color: Style.normalFillFor(root.foreground, root.accent)
                  borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

                  Text {
                    id: shortcutKeyText
                    anchors.centerIn: parent
                    text: String(shortcutRow.modelData.keys || "")
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  Popup {
    id: lyricsInstallPopup
    parent: window.contentItem
    x: Math.max(Style.space(8), (window.width - width) / 2)
    y: Math.max(Style.space(8), (window.height - height) / 2)
    width: Math.min(Style.space(400), window.width - Style.space(32))
    height: lyricsInstallContent.implicitHeight + padding * 2
    padding: Style.space(10)
    modal: true
    focus: true
    closePolicy: root.service && root.service.lyricsPluginBusy
      ? Popup.NoAutoClose
      : Popup.CloseOnEscape | Popup.CloseOnPressOutside

    onOpened: root.disarmEscapeClose()
    onClosed: {
      if (root.service && !root.service.lyricsPluginBusy)
        root.service.cancelLyricsPlugin(root.lyricsRequestKey)
      Qt.callLater(function() { focusScope.forceActiveFocus() })
    }

    background: BorderSurface {
      color: root.popupBackground
      radius: Style.cornerRadius
      borderSpec: root.popupBorderSpec
    }

    contentItem: LyricsInstallPrompt {
      id: lyricsInstallContent
      width: parent.width
      service: root.service
      foreground: root.foreground
      surfaceKey: root.lyricsRequestKey
      onCanceled: lyricsInstallPopup.close()
    }
  }

  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onLyricsPluginPromptRequested(surface, availability) {
      if (String(surface) === root.lyricsRequestKey) lyricsInstallPopup.open()
    }
    function onLyricsPluginOpened(surface) {
      if (String(surface) === root.lyricsRequestKey) lyricsInstallPopup.close()
    }
  }

  Popup {
    id: mediaContextMenu
    parent: window.contentItem
    width: Math.min(Style.space(310), window.width - Style.space(24))
    height: Math.min(window.height - Style.space(24),
      contextMenuContent.implicitHeight + padding * 2)
    padding: Style.space(6)
    modal: true
    dim: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    background: BorderSurface {
      color: root.popupBackground
      radius: Style.cornerRadius
      borderSpec: root.popupBorderSpec
    }

    contentItem: ScrollView {
      id: contextMenuScroll
      clip: true
      rightPadding: contextMenuContent.implicitHeight > height
        ? root.popupScrollbarGutter : 0
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
      ScrollBar.vertical.policy: ScrollBar.AsNeeded

      Column {
        id: contextMenuContent
        width: contextMenuScroll.availableWidth
        spacing: Style.space(3)

      Text {
        width: parent.width
        leftPadding: Style.space(8)
        rightPadding: Style.space(8)
        topPadding: Style.space(4)
        bottomPadding: Style.space(4)
        text: root.contextItem ? String(root.contextItem.name || "Spotify item") : "Spotify item"
        color: Qt.darker(root.foreground, 1.25)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        leftPadding: Style.space(8)
        rightPadding: Style.space(8)
        text: "Press Esc to close"
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      PanelSeparator { width: parent.width; foreground: root.foreground }

      Button {
        width: parent.width
        visible: root.contextItem
          && ["show", "audiobook"].indexOf(root.contextItem.type) < 0
        text: "Play"
        iconText: "󰐊"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          mediaContextMenu.close()
          root.activateMedia(root.contextItem, root.contextSourceItems,
            root.contextSourceUri)
        }
      }

      Button {
        width: parent.width
        visible: root.contextItem && root.contextItem.type === "track"
        text: "Start track radio"
        iconText: "󰎆"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          mediaContextMenu.close()
          if (root.service) root.service.startRadio(root.contextItem)
        }
      }

      Button {
        width: parent.width
        visible: root.contextItem
          && ["track", "episode"].indexOf(root.contextItem.type) >= 0
        text: "Add to queue"
        iconText: "󰐕"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          mediaContextMenu.close()
          if (root.service) root.service.addToQueue(root.contextItem)
        }
      }

      Button {
        width: parent.width
        visible: root.contextItem
          && ["track", "episode"].indexOf(root.contextItem.type) >= 0
        text: "Add to playlist…"
        iconText: "󱁐"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          mediaContextMenu.close()
          root.openPlaylistPicker(root.contextItem)
        }
      }

      Button {
        width: parent.width
        visible: root.contextItem && root.contextItem.kind === "context"
        text: "Open details"
        iconText: "󰋼"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          mediaContextMenu.close()
          root.openItem(root.contextItem)
        }
      }

      Button {
        width: parent.width
        visible: root.contextItem && root.contextItem.type === "playlist"
          && root.service && root.service.currentUserId !== ""
          && !root.service.playlistOwned(root.contextItem)
        text: root.service && root.service.playlistConversionBusy
          ? "Making your copy…" : "Turn into your own playlist"
        iconText: "󰒍"
        foreground: root.foreground
        leftAlign: true
        enabled: root.service && !root.service.playlistActionBusy
        onClicked: {
          var playlist = root.contextItem
          mediaContextMenu.close()
          root.turnPlaylistIntoOwn(playlist)
        }
      }

      Button {
        width: parent.width
        visible: root.contextItem && root.contextItem.type === "track"
          && root.contextItem.artists && root.contextItem.artists.length
        text: "Go to artist"
        iconText: "󰠃"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          mediaContextMenu.close()
          root.openItem(root.contextItem.artists[0])
        }
      }

      Button {
        width: parent.width
        visible: root.contextItem && !!root.contextItem.albumItem
        text: "Go to album"
        iconText: "󰀥"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          mediaContextMenu.close()
          root.openItem(root.contextItem.albumItem)
        }
      }

      Button {
        width: parent.width
        visible: root.contextItem && !!root.contextItem.uri
          && root.contextItem.type !== "chapter"
        text: root.service && root.service.isSaved(root.contextItem)
          ? "Remove from library" : "Save to library"
        iconText: root.service && root.service.isSaved(root.contextItem) ? "󰓎" : "󰋑"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          mediaContextMenu.close()
          if (root.service) root.service.toggleSaved(root.contextItem)
        }
      }

      Button {
        width: parent.width
        visible: root.contextPlaylist && root.service
          && root.service.playlistEditable(root.contextPlaylist)
          && root.contextItem && root.contextItem.kind === "item"
        text: "Move up"
        iconText: "󰁝"
        foreground: root.foreground
        leftAlign: true
        enabled: root.playlistPosition(root.contextItem) > 0
        onClicked: {
          var position = root.playlistPosition(root.contextItem)
          mediaContextMenu.close()
          root.service.movePlaylistItem(position, -1, root.contextPlaylist,
            root.contextPlaylist === root.service.selectedPlaylist
              ? root.service.playlistItems.length : root.service.detailItems.length)
        }
      }

      Button {
        width: parent.width
        visible: root.contextPlaylist && root.service
          && root.service.playlistEditable(root.contextPlaylist)
          && root.contextItem && root.contextItem.kind === "item"
        text: "Move down"
        iconText: "󰁅"
        foreground: root.foreground
        leftAlign: true
        enabled: root.playlistPosition(root.contextItem) >= 0
          && root.playlistPosition(root.contextItem) < (root.contextPlaylist
            === (root.service ? root.service.selectedPlaylist : null)
              ? root.service.playlistItems.length - 1
              : (root.service ? root.service.detailItems.length - 1 : -1))
        onClicked: {
          var position = root.playlistPosition(root.contextItem)
          mediaContextMenu.close()
          root.service.movePlaylistItem(position, 1, root.contextPlaylist,
            root.contextPlaylist === root.service.selectedPlaylist
              ? root.service.playlistItems.length : root.service.detailItems.length)
        }
      }

      Button {
        width: parent.width
        visible: root.contextPlaylist && root.service
          && root.service.playlistEditable(root.contextPlaylist)
          && root.contextItem && root.contextItem.kind === "item"
        text: "Remove from playlist"
        iconText: "󰅖"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          var position = root.playlistPosition(root.contextItem)
          mediaContextMenu.close()
          root.service.removePlaylistItem(root.contextItem, position, root.contextPlaylist)
        }
      }

      PanelSeparator {
        width: parent.width
        visible: root.contextItem && root.contextItem.externalUrl
        foreground: root.foreground
      }

      Button {
        width: parent.width
        visible: root.contextItem && root.contextItem.externalUrl
        text: "Copy Spotify link"
        iconText: "󰌷"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          mediaContextMenu.close()
          root.copyExternal(root.contextItem)
        }
      }

      Button {
        width: parent.width
        visible: root.contextItem && root.contextItem.externalUrl
        text: "Open in Spotify"
        iconText: "󰏌"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          mediaContextMenu.close()
          root.openExternal(root.contextItem)
        }
      }
      }
    }
  }

  Popup {
    id: playlistPicker
    parent: window.contentItem
    x: Math.max(Style.space(8), (window.width - width) / 2)
    y: Math.max(Style.space(8), (window.height - height) / 2)
    width: Math.min(Style.space(410), window.width - Style.space(32))
    height: Math.min(Style.space(520), pickerContent.implicitHeight + padding * 2)
    padding: Style.space(8)
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    background: BorderSurface {
      color: root.popupBackground
      radius: Style.cornerRadius
      borderSpec: root.popupBorderSpec
    }

    contentItem: Column {
      id: pickerContent
      spacing: Style.space(7)

      Text {
        width: parent.width
        text: root.pendingPlaylistItem
          ? "Add “" + String(root.pendingPlaylistItem.name || "song") + "” to a playlist"
          : "Add to playlist"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: "Choose one of your playlists, or create a new private playlist."
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Row {
        width: parent.width
        spacing: Style.space(6)

        TextField {
          id: newPlaylistField
          width: Math.max(80, parent.width - createPlaylistButton.width - parent.spacing)
          foreground: root.foreground
          placeholderText: "Name a new playlist"
          text: root.newPlaylistName
          onTextEdited: root.newPlaylistName = text
          onAccepted: createPlaylistButton.clicked()
        }

        Button {
          id: createPlaylistButton
          text: "Create"
          iconText: "󰐕"
          foreground: root.foreground
          enabled: root.service && root.newPlaylistName.trim() !== ""
            && !root.service.playlistActionBusy
          onClicked: {
            if (!root.service) return
            root.service.createPlaylist(root.newPlaylistName, function(playlist) {
              if (root.pendingPlaylistItem) root.service.addItemToPlaylist(
                root.pendingPlaylistItem, playlist)
              root.newPlaylistName = ""
              playlistPicker.close()
            })
          }
        }
      }

      PanelSeparator { width: parent.width; foreground: root.foreground }

      ListView {
        id: playlistPickerList
        width: parent.width
        height: Math.min(Style.space(340), Math.max(Style.space(80), contentHeight))
        model: root.service ? root.service.editablePlaylists() : []
        clip: true
        spacing: Style.space(2)
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        FastScrollHandler { parent: playlistPickerList; flickable: playlistPickerList }

        delegate: Button {
          required property var modelData
          width: Math.max(80, ListView.view.width
            - (playlistPickerList.contentHeight > playlistPickerList.height
              ? root.popupScrollbarGutter : 0))
          text: modelData.name || "Playlist"
          iconText: "󰲸"
          foreground: root.foreground
          leftAlign: true
          onClicked: {
            if (root.service && root.pendingPlaylistItem)
              root.service.addItemToPlaylist(root.pendingPlaylistItem, modelData)
            playlistPicker.close()
          }
        }
      }
    }
  }

  Popup {
    id: createPlaylistPopup
    parent: window.contentItem
    x: Math.max(Style.space(8), (window.width - width) / 2)
    y: Math.max(Style.space(8), (window.height - height) / 2)
    width: Math.min(Style.space(400), window.width - Style.space(24))
    height: createPlaylistContent.implicitHeight + padding * 2
    padding: Style.space(9)
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    onOpened: Qt.callLater(function() {
      createPlaylistNameField.selectAll()
      createPlaylistNameField.forceActiveFocus()
    })
    onClosed: root.createPlaylistName = ""

    background: BorderSurface {
      color: root.popupBackground
      radius: Style.cornerRadius
      borderSpec: root.popupBorderSpec
    }

    contentItem: Column {
      id: createPlaylistContent
      spacing: Style.space(8)

      Text {
        width: parent.width
        text: "Create a new playlist"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Text {
        width: parent.width
        text: "Give your new private playlist a name."
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      TextField {
        id: createPlaylistNameField
        width: parent.width
        foreground: root.foreground
        placeholderText: "Playlist name"
        text: root.createPlaylistName
        maximumLength: 100
        onTextEdited: root.createPlaylistName = text
        onAccepted: root.createNamedPlaylist()
      }

      Row {
        width: parent.width
        spacing: Style.space(6)

        Button {
          width: (parent.width - parent.spacing) / 2
          text: "Cancel"
          foreground: root.foreground
          focusable: true
          enabled: !root.service || !root.service.playlistActionBusy
          onClicked: createPlaylistPopup.close()
        }

        Button {
          id: confirmNewPlaylistButton
          width: (parent.width - parent.spacing) / 2
          text: root.service && root.service.playlistActionBusy ? "Creating…" : "Create"
          iconText: "󰐕"
          foreground: root.foreground
          selected: true
          focusable: true
          enabled: root.service && root.createPlaylistName.trim() !== ""
            && !root.service.playlistActionBusy
          onClicked: root.createNamedPlaylist()
        }
      }
    }
  }

  Popup {
    id: sleepPopup
    parent: window.contentItem
    x: Math.max(Style.space(8), window.width - width - Style.space(24))
    y: Math.max(Style.space(8), window.height - height - Style.space(130))
    width: Math.min(Style.space(270), window.width - Style.space(24))
    height: sleepContent.implicitHeight + padding * 2
    padding: Style.space(7)
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    background: BorderSurface {
      color: root.popupBackground
      radius: Style.cornerRadius
      borderSpec: root.popupBorderSpec
    }

    contentItem: Column {
      id: sleepContent
      spacing: Style.space(3)

      Text {
        width: parent.width
        text: root.service ? root.service.sleepStatusText() : "Sleep timer"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        leftPadding: Style.space(7)
      }
      PanelSeparator { width: parent.width; foreground: root.foreground }
      Repeater {
        model: [15, 30, 60, 120]
        Button {
          required property int modelData
          width: sleepContent.width
          text: modelData + " minutes"
          iconText: "󰔛"
          foreground: root.foreground
          leftAlign: true
          onClicked: {
            if (root.service) root.service.setSleepMinutes(modelData)
            sleepPopup.close()
          }
        }
      }
      Button {
        width: parent.width
        text: "After this item"
        iconText: "󰐾"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          if (root.service) root.service.sleepAfterTrack()
          sleepPopup.close()
        }
      }
      Button {
        width: parent.width
        text: "After this context"
        iconText: "󰓛"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          if (root.service) root.service.sleepAfterContext()
          sleepPopup.close()
        }
      }
      Button {
        width: parent.width
        visible: root.service && root.service.sleepActive
        text: "Cancel timer"
        iconText: "󰅖"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          root.service.cancelSleepTimer(true)
          sleepPopup.close()
        }
      }
    }
  }

  FloatingWindow {
    id: window
    visible: root.opened
    title: "Omarchy Spotify"
    color: root.background
    implicitWidth: 980
    implicitHeight: 720
    minimumSize: Qt.size(700, 560)

    onVisibleChanged: {
      if (!visible && root.opened && !root.closingFromHost) root.requestClose()
    }
    FocusScope {
      id: focusScope
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: function(event) {
        if (root.dismissTransientPopup()) {
          root.disarmEscapeClose()
          event.accepted = true
          return
        }
        if (root.clearVisibleSearchForEscape()) {
          event.accepted = true
          return
        }
        if (root.showingUniversalSearch && root.currentTab !== "search") {
          if (root.activeSearchScope.available && !root.searchInContext)
            root.toggleSearchScope()
          else root.clearUnifiedSearch()
          root.disarmEscapeClose()
          event.accepted = true
          return
        }
        if (root.currentTab === "detail" || root.navigationStack.length) {
          root.disarmEscapeClose()
          root.goBack()
        } else if (root.escapeCloseArmed) root.requestClose()
        else root.armEscapeClose()
        event.accepted = true
      }

      Shortcut {
        sequence: "Ctrl+K"
        enabled: unifiedSearchBar.visible && !root.shortcutsBlocked
        onActivated: root.focusSearch()
      }
      Shortcut {
        sequence: "/"
        enabled: unifiedSearchBar.visible && !root.shortcutsBlocked
          && !root.textInputFocused()
        onActivated: root.focusSearch()
      }
      Shortcut {
        sequence: "Ctrl+F"
        enabled: unifiedSearchBar.visible && root.activeSearchScope.available
          && !root.shortcutsBlocked
        onActivated: root.focusContextSearch()
      }
      Shortcut {
        sequence: "Ctrl+L"
        enabled: unifiedSearchBar.visible && !root.shortcutsBlocked
        onActivated: root.focusUniversalSearch()
      }
      Shortcut {
        sequence: "Alt+Left"
        enabled: !root.shortcutsBlocked
          && (root.currentTab === "detail" || root.navigationStack.length > 0)
        onActivated: root.goBack()
      }
      Shortcut {
        sequence: "Ctrl+,"
        enabled: root.fullyConnected && !root.shortcutsBlocked
        onActivated: root.chooseTab("setup")
      }
      Shortcut {
        sequence: "Alt+Shift+H"
        enabled: root.fullyConnected && !root.shortcutsBlocked
        onActivated: root.chooseTab("home")
      }
      Shortcut {
        sequence: "Alt+Shift+Q"
        enabled: root.fullyConnected && !root.shortcutsBlocked
        onActivated: root.chooseTab("queue")
      }
      Shortcut {
        sequence: "Alt+Shift+D"
        enabled: root.fullyConnected && !root.shortcutsBlocked
        onActivated: root.chooseTab("devices")
      }
      Shortcut {
        sequence: "Space"
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
          && root.service && root.service.playbackControllable
        onActivated: if (root.service) root.service.togglePlayback()
      }
      Shortcut {
        sequence: "Ctrl+Right"
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
          && root.service && root.service.playbackControllable
        onActivated: if (root.service) root.service.next()
      }
      Shortcut {
        sequence: "Ctrl+Left"
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
          && root.service && root.service.playbackControllable
        onActivated: if (root.service) root.service.previous()
      }
      Shortcut {
        sequence: "M"
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
          && root.service && root.service.volumeSupported
        onActivated: root.toggleMute()
      }
      Shortcut {
        sequence: "Ctrl+S"
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
          && root.service && root.service.playbackControllable
        onActivated: root.service.setShuffle(!root.service.shuffle)
      }
      Shortcut {
        sequence: "Ctrl+R"
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
          && root.service && root.service.playbackControllable
        onActivated: root.service.cycleRepeat()
      }
      Shortcut {
        sequence: "Shift+Left"
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
          && root.service && root.service.playbackControllable
        onActivated: root.seekBy(-10)
      }
      Shortcut {
        sequence: "Shift+Right"
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
          && root.service && root.service.playbackControllable
        onActivated: root.seekBy(10)
      }
      Shortcut {
        sequence: "Ctrl+Up"
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
          && root.service && root.service.volumeSupported
        onActivated: root.adjustVolume(0.05)
      }
      Shortcut {
        sequence: "Ctrl+Down"
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
          && root.service && root.service.volumeSupported
        onActivated: root.adjustVolume(-0.05)
      }
      Shortcut {
        sequence: "Ctrl+/"
        enabled: !root.textInputFocused()
          && (!root.shortcutsBlocked || shortcutHelpPopup.opened)
        onActivated: root.toggleShortcutHelp()
      }

      Item {
        anchors.fill: parent
        anchors.margins: Style.space(14)

        Row {
          id: workspace
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: footerSeparator.top
          anchors.bottomMargin: Style.space(10)
          spacing: sidebar.visible ? Style.space(10) : 0

          BorderSurface {
            id: sidebar
            visible: root.currentTab !== "login"
            width: visible
              ? (root.compactWidth ? Style.space(54)
                : Math.min(Style.space(214), Math.max(Style.space(176), workspace.width * 0.225)))
              : 0
            height: parent.height
            radius: Style.cornerRadius
            color: Style.normalFillFor(root.foreground, root.accent)
            borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

            Row {
              id: brandRow
              visible: !root.compactHeight
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: visible ? Style.space(11) : 0
              height: visible ? Style.space(42) : 0
              spacing: Style.space(9)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ""
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.iconLarge
              }

              Column {
                visible: !root.compactWidth
                width: Math.max(40, parent.width - Style.space(38))
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Text {
                  width: parent.width
                  text: "Music"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  text: "for Spotify"
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
            }

            Column {
              id: primaryNavigation
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: brandRow.visible ? brandRow.bottom : parent.top
              anchors.margins: Style.space(8)
              spacing: Style.space(2)

              PanelSeparator {
                width: parent.width
                foreground: root.foreground
              }

              Repeater {
                model: root.primaryNavigationItems()

                Button {
                  required property var modelData
                  readonly property bool radioEntry: modelData.id === "radio"
                  width: primaryNavigation.width
                  text: root.compactWidth ? "" : modelData.label
                  iconText: modelData.icon
                  foreground: root.foreground
                  selected: radioEntry ? root.radioNavigationSelected()
                    : root.currentTab === modelData.id
                  leftAlign: !root.compactWidth
                  focusable: true
                  tooltipText: radioEntry && root.service && root.service.lastRadioPlaylist
                    ? modelData.label + " · " + root.service.lastRadioPlaylist.name
                    : root.shortcutHint(modelData.label,
                      root.primaryNavigationShortcut(modelData.id))
                  onClicked: {
                    if (radioEntry) root.openLastRadio()
                    else root.chooseTab(modelData.id)
                  }
                }
              }

              PanelSeparator {
                width: parent.width
                foreground: root.foreground
              }
            }

            Text {
              id: playlistShortcutsHeading
              visible: !root.compactWidth
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: primaryNavigation.bottom
              anchors.leftMargin: Style.space(13)
              anchors.rightMargin: Style.space(13)
              anchors.topMargin: Style.space(9)
              height: visible ? implicitHeight : 0
              text: "YOUR LIBRARY"
              color: Qt.darker(root.foreground, 1.35)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Column {
              id: libraryNavigation
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: playlistShortcutsHeading.visible
                ? playlistShortcutsHeading.bottom : primaryNavigation.bottom
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              anchors.topMargin: Style.space(6)
              spacing: Style.space(2)

              Button {
                width: parent.width
                text: root.compactWidth ? "" : "Liked Songs"
                iconText: "󰋑"
                foreground: root.foreground
                selected: root.currentTab === "library"
                leftAlign: !root.compactWidth
                focusable: true
                tooltipText: "Liked Songs"
                onClicked: root.chooseTab("library")
              }

              Row {
                width: parent.width
                spacing: Style.space(2)

                Button {
                  width: Math.max(20, parent.width - createPlaylistShortcut.width
                    - parent.spacing)
                  text: root.compactWidth ? "" : "Playlists"
                  iconText: "󱁐"
                  foreground: root.foreground
                  selected: root.currentTab === "playlists"
                  leftAlign: !root.compactWidth
                  focusable: true
                  tooltipText: "Playlists"
                  onClicked: root.chooseTab("playlists")
                }

                Button {
                  id: createPlaylistShortcut
                  width: root.compactWidth
                    ? Math.max(20, (parent.width - parent.spacing) / 2) : implicitWidth
                  text: "+"
                  foreground: root.foreground
                  fontSize: Style.font.subtitle
                  horizontalPadding: Style.space(7)
                  focusable: true
                  tooltipText: "Create a new playlist"
                  enabled: root.fullyConnected && root.service
                    && !root.service.playlistActionBusy
                  onClicked: root.openCreatePlaylistPopup()
                }
              }
            }

            ListView {
              id: playlistShortcuts
              visible: !root.compactWidth
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: libraryNavigation.bottom
              anchors.bottom: setupNavButton.top
              anchors.margins: Style.space(8)
              model: root.service ? root.service.sidebarPlaylists() : []
              clip: true
              spacing: Style.space(1)
              reuseItems: true

              FastScrollHandler {
                parent: playlistShortcuts
                flickable: playlistShortcuts
                onScrolled: {
                  if (playlistShortcuts.atYEnd && root.service
                      && root.service.playlistsNext
                      && !root.service.playlistsLoading)
                    root.service.loadMorePlaylists()
                }
              }

              onMovementEnded: {
                if (atYEnd && root.service && root.service.playlistsNext
                    && !root.service.playlistsLoading) root.service.loadMorePlaylists()
              }

              delegate: Button {
                required property var modelData
                width: ListView.view.width
                text: root.sidebarPlaylistName(modelData)
                iconText: "󰲸"
                foreground: root.foreground
                leftAlign: true
                focusable: true
                selected: root.currentTab === "playlists" && root.service
                  && root.service.selectedPlaylist
                  && root.service.selectedPlaylist.id === modelData.id
                tooltipText: modelData.name || "Playlist"
                onClicked: {
                  root.chooseTab("playlists")
                  if (root.service) root.service.openPlaylist(modelData)
                }
              }
            }

            Button {
              id: setupNavButton
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(8)
              text: root.compactWidth ? "" : "Settings"
              iconText: root.service && root.service.auth.loggedIn ? "󰀄" : "󰒓"
              foreground: root.foreground
              selected: root.currentTab === "setup"
              leftAlign: !root.compactWidth
              focusable: true
              tooltipText: root.shortcutHint("Settings", "Ctrl+,")
              onClicked: root.chooseTab("setup")
            }
          }

          Item {
            id: contentPane
            width: Math.max(220, parent.width - sidebar.width - workspace.spacing)
            height: parent.height

            Row {
              id: pageHeader
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              height: Style.space(52)
              spacing: Style.space(5)

              Button {
                id: backButton
                visible: root.currentTab === "detail" || root.navigationStack.length > 0
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰁍"
                foreground: root.foreground
                tooltipText: root.shortcutHint("Back", "Alt+Left")
                focusable: true
                onClicked: root.goBack()
              }

              Column {
                width: Math.max(80, parent.width
                  - (backButton.visible ? backButton.width + parent.spacing : 0)
                  - shortcutHelpButton.width - refreshButton.width - closeButton.width
                  - parent.spacing * 3)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(1)

                Text {
                  width: parent.width
                  text: root.pageTitle()
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: root.pageSubtitle()
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              Button {
                id: shortcutHelpButton
                anchors.verticalCenter: parent.verticalCenter
                text: "?"
                foreground: root.foreground
                fontSize: Style.font.subtitle
                tooltipText: root.shortcutHint("Keyboard shortcuts", "Ctrl+/")
                focusable: true
                onClicked: root.toggleShortcutHelp()
              }

              Button {
                id: refreshButton
                visible: root.currentTab !== "login" && root.currentTab !== "setup"
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰑐"
                foreground: root.foreground
                tooltipText: "Refresh"
                focusable: true
                onClicked: {
                  if (!root.service) return
                  if (root.showingUniversalSearch) root.runUnifiedSearch()
                  else if (root.currentTab === "detail" && root.service.detailItem)
                    root.service.openDetail(root.service.detailItem,
                      root.service.detailItem.type === "artist"
                        ? root.artistSearchText : "")
                  else if (root.currentTab === "library")
                    root.service.loadLibrary(root.libraryType, false, true)
                  else root.service.refreshView(root.currentTab)
                }
              }

              Button {
                id: closeButton
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅖"
                foreground: root.escapeCloseArmed ? Color.urgent : root.foreground
                bordered: root.escapeCloseArmed
                borderSpec: root.escapeCloseArmed
                  ? Border.flat(Color.urgent, Math.max(1, Style.normalBorderWidth))
                  : closeButton._borderSpec
                tooltipText: root.escapeCloseArmed
                  ? "Press Esc again to close"
                  : root.shortcutHint("Close", "Esc, Esc")
                focusable: true
                onClicked: root.requestClose()
              }
            }

            BorderSurface {
              id: statusBanner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: pageHeader.bottom
              anchors.topMargin: visible ? Style.space(6) : 0
              implicitHeight: visible ? messageText.implicitHeight + Style.space(12) : 0
              height: implicitHeight
              visible: root.service && (root.service.lastError !== "" || root.service.statusMessage !== "")
              color: root.service && root.service.lastError !== ""
                ? Style.selectedFillFor(root.foreground, Color.urgent)
                : Style.normalFillFor(root.foreground, root.accent)
              borderSpec: Border.controlSpec("normal", root.foreground,
                root.service && root.service.lastError !== "" ? Color.urgent : root.accent)
              radius: Style.cornerRadius

              Text {
                id: messageText
                anchors.fill: parent
                anchors.margins: Style.space(6)
                text: !root.service ? "" : (root.service.lastError || root.service.statusMessage)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
            }

            Row {
              id: unifiedSearchBar
              visible: root.currentTab !== "login" && root.currentTab !== "devices"
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: statusBanner.visible ? statusBanner.bottom : pageHeader.bottom
              anchors.topMargin: visible ? Style.space(8) : 0
              height: visible ? Style.space(38) : 0
              spacing: Style.space(6)

              TextField {
                id: unifiedSearchField
                width: searchScopeButton.visible
                  ? Math.max(0, parent.width - searchScopeButton.width
                    - parent.spacing)
                  : parent.width
                height: parent.height
                foreground: root.foreground
                placeholderText: root.activeSearchScope.available && root.searchInContext
                  ? "Search in " + root.activeSearchScope.label : "Search Spotify"
                text: root.unifiedSearchText()
                enabled: root.service && root.service.auth.loggedIn
                onTextEdited: root.editUnifiedSearch(text)
                onAccepted: root.runUnifiedSearch()

                PanelToolTip {
                  visible: unifiedSearchField.hovered
                  text: root.activeSearchScope.available
                    ? "Focus search · Ctrl+K or /\nCurrent area · Ctrl+F    All Spotify · Ctrl+L"
                    : "Focus search · Ctrl+K or /\nAll Spotify · Ctrl+L"
                }
              }

              Button {
                id: searchScopeButton
                visible: root.activeSearchScope.available
                width: visible ? Math.min(parent.width * 0.4,
                  Math.max(parent.width * 0.2, implicitWidth)) : 0
                height: parent.height
                clip: true
                anchors.verticalCenter: parent.verticalCenter
                text: root.searchScopeButtonText()
                iconText: root.searchInContext ? "󰄬" : "󰄱"
                foreground: root.foreground
                selected: root.searchInContext
                bordered: true
                focusable: true
                horizontalPadding: Style.space(8)
                tooltipText: root.searchInContext
                  ? root.shortcutHint("Search all of Spotify", "Ctrl+L")
                  : root.shortcutHint("Search only in "
                    + root.activeSearchScope.label, "Ctrl+F")
                onClicked: root.toggleSearchScope()
              }
            }

            Loader {
              id: pageLoader
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: unifiedSearchBar.visible ? unifiedSearchBar.bottom
                : (statusBanner.visible ? statusBanner.bottom : pageHeader.bottom)
              anchors.topMargin: Style.space(8)
              anchors.bottom: parent.bottom
              sourceComponent: root.pageComponent()
            }
          }
        }

        PanelSeparator {
          id: footerSeparator
          visible: root.currentTab !== "login"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: playerFooter.top
          anchors.bottomMargin: Style.space(10)
          foreground: root.foreground
        }

        BorderSurface {
          id: playerFooter
          visible: root.currentTab !== "login"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: visible ? Style.space(root.compactHeight ? 88 : 104) : 0
          radius: Style.cornerRadius
          color: Style.normalFillFor(root.foreground, root.accent)
          borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

          Row {
            id: playerRow
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(12)

            Row {
              id: nowPlaying
              width: Math.max(Style.space(170), Math.min(Style.space(240), playerRow.width * 0.29))
              height: parent.height
              spacing: Style.space(9)

              BorderSurface {
                width: Math.min(parent.height, Style.space(68))
                height: width
                anchors.verticalCenter: parent.verticalCenter
                radius: Style.cornerRadius
                color: Style.selectedFillFor(root.foreground, root.accent)
                borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

                Image {
                  anchors.fill: parent
                  anchors.margins: Style.space(2)
                  source: root.service ? root.service.artUrl : ""
                  sourceSize.width: 136
                  sourceSize.height: 136
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                  cache: true
                  visible: status === Image.Ready
                }

                Text {
                  anchors.centerIn: parent
                  visible: !root.service || root.service.artUrl === ""
                  text: "󰎈"
                  color: Qt.darker(root.foreground, 1.3)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.iconLarge
                }

              }

              Column {
                width: Math.max(40, parent.width - parent.height - parent.spacing)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)

                Row {
                  width: parent.width
                  spacing: Style.space(3)

                  Text {
                    width: Math.max(20, parent.width
                      - (currentTrackLikeButton.visible
                        ? currentTrackLikeButton.width + parent.spacing : 0))
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.service && root.service.title
                      ? root.service.title : "Nothing playing"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Button {
                    id: currentTrackLikeButton
                    objectName: "current-track-like"
                    visible: root.service && !!root.service.currentTrackItem
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: root.service && root.service.currentTrackSaved
                      ? "󰋑" : "󰋕"
                    iconSize: Style.font.body
                    foreground: root.foreground
                    selected: root.service && root.service.currentTrackSaved
                    enabled: root.service && root.service.currentTrackSaveAvailable
                    horizontalPadding: Style.space(4)
                    verticalPadding: Style.space(2)
                    tooltipText: root.service && root.service.currentTrackSaveChecking
                      ? "Checking liked status…"
                      : (root.service && root.service.currentTrackSaveBusy
                        ? "Updating liked status…"
                        : (root.service && root.service.currentTrackSaved
                          ? "Remove like" : "Like this song"))
                    onClicked: if (root.service)
                      root.service.toggleCurrentTrackSaved()
                  }
                }

                ArtistLinks {
                  width: parent.width
                  artists: root.service ? root.service.currentArtists : []
                  fallbackText: root.service && root.service.artist
                    ? root.service.artist : "Choose something to play"
                  fallbackClickable: root.service && root.service.artist !== ""
                    && root.service.currentArtistContextAvailable
                    && artists.length === 0
                  color: root.service && root.service.artist
                    && root.service.currentArtistContextAvailable ? root.accent
                    : Qt.darker(root.foreground, 1.38)
                  accent: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  onArtistRequested: function(item) { root.openItem(item) }
                  onFallbackRequested: if (root.service)
                    root.service.currentContext("artist", function(item) {
                      root.openItem(item)
                    })
                }

                Text {
                  width: parent.width
                  visible: root.service && root.service.album !== ""
                    && root.service.currentTrackId() !== ""
                  text: root.service ? root.service.album : ""
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.service.currentContext("album", function(item) {
                      root.openItem(item)
                    })
                  }
                }
              }
            }

            Column {
              id: transport
              width: Math.max(120, parent.width - nowPlaying.width - outputControls.width - parent.spacing * 2)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(3)

                Button {
                  iconText: "󰒟"
                  foreground: root.foreground
                  selected: root.service && root.service.shuffle
                  tooltipText: root.shortcutHint("Shuffle", "Ctrl+S")
                  enabled: root.service && root.service.playbackControllable
                  onClicked: if (root.service) root.service.setShuffle(!root.service.shuffle)
                }
                Button {
                  iconText: "󰒮"
                  foreground: root.foreground
                  tooltipText: root.shortcutHint("Previous", "Ctrl+Left")
                  enabled: root.service && root.service.playbackControllable
                  onClicked: if (root.service) root.service.previous()
                }
                Button {
                  iconText: root.service && root.service.playing ? "󰏤" : "󰐊"
                  iconSize: Style.font.iconLarge
                  foreground: root.foreground
                  tooltipText: root.shortcutHint(
                    root.service && root.service.playing ? "Pause" : "Play", "Space")
                  enabled: root.service && root.service.playbackControllable
                  onClicked: if (root.service) root.service.togglePlayback()
                }
                Button {
                  iconText: "󰒭"
                  foreground: root.foreground
                  tooltipText: root.shortcutHint("Next", "Ctrl+Right")
                  enabled: root.service && root.service.playbackControllable
                  onClicked: if (root.service) root.service.next()
                }
                Button {
                  iconText: root.service && root.service.repeatMode === "track" ? "󰑘" : "󰑖"
                  foreground: root.foreground
                  selected: root.service && root.service.repeatMode !== "off"
                  tooltipText: root.shortcutHint("Repeat: "
                    + (root.service ? root.service.repeatMode : "off"), "Ctrl+R")
                  enabled: root.service && root.service.playbackControllable
                  onClicked: if (root.service) root.service.cycleRepeat()
                }
                Button {
                  iconText: "󰎈"
                  foreground: root.foreground
                  tooltipText: "Open lyrics in Omasing"
                  enabled: root.service && root.service.lyricsAvailable
                  onClicked: root.openLyrics()
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(6)

                Text {
                  id: positionFooterTime
                  anchors.verticalCenter: parent.verticalCenter
                  text: Api.millisecondsToClock((root.service ? root.service.positionSeconds : 0) * 1000)
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                PlaybackSlider {
                  id: positionSlider
                  width: Math.max(30, parent.width - positionFooterTime.implicitWidth
                    - durationFooterTime.implicitWidth - Style.space(12))
                  anchors.verticalCenter: parent.verticalCenter
                  bar: root.panelBar
                  minimum: 0
                  maximum: Math.max(1, root.service ? root.service.lengthSeconds : 1)
                  step: 5
                  sourceValue: root.service ? root.service.positionSeconds : 0
                  sourcePending: root.service && root.service.pendingRemoteSeek !== null
                  acknowledgeTolerance: 2
                  contextKey: root.service
                    ? root.service.currentUri + "|" + root.service.playbackDeviceName : ""
                  onCommitted: function(value) {
                    if (root.service) root.service.seekSeconds(value)
                  }

                  HoverHandler { id: positionSliderHover }
                  PanelToolTip {
                    visible: positionSliderHover.hovered
                    text: "Seek 10 seconds · Shift+Left / Shift+Right"
                  }
                }

                Text {
                  id: durationFooterTime
                  anchors.verticalCenter: parent.verticalCenter
                  text: Api.millisecondsToClock((root.service ? root.service.lengthSeconds : 0) * 1000)
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Column {
              id: outputControls
              width: Math.max(Style.space(128), Math.min(Style.space(170), playerRow.width * 0.22))
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)

              Row {
                width: parent.width
                spacing: Style.space(5)

                Button {
                  iconText: "󰋋"
                  foreground: root.foreground
                  tooltipText: root.shortcutHint("Devices", "Alt+Shift+D")
                  onClicked: root.chooseTab("devices")
                }

                Button {
                  iconText: "󰔛"
                  foreground: root.foreground
                  selected: root.service && root.service.sleepActive
                  tooltipText: root.service ? root.service.sleepStatusText() : "Sleep timer"
                  onClicked: sleepPopup.open()
                }

                PlaybackSlider {
                  id: volumeSlider
                  width: Math.max(35, parent.width - Style.space(74))
                  anchors.verticalCenter: parent.verticalCenter
                  enabled: root.service && root.service.volumeSupported
                  bar: root.panelBar
                  minimum: 0
                  maximum: 1
                  step: 0.05
                  sourceValue: root.service ? root.service.volume : 0
                  sourcePending: root.service && root.service.pendingRemoteVolume !== null
                  contextKey: root.service ? root.service.playbackDeviceName : ""
                  onCommitted: function(value) { root.setPanelVolume(value) }
                  onRightClicked: root.toggleMute()

                  HoverHandler { id: volumeSliderHover }
                  PanelToolTip {
                    visible: volumeSliderHover.hovered
                    text: "Volume · Ctrl+Up / Ctrl+Down · M to mute"
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  Timer {
    id: unifiedSearchDelay
    interval: 300
    repeat: false
    onTriggered: root.runUnifiedSearch()
  }

  Timer {
    id: escapeCloseTimer
    interval: 1500
    repeat: false
    onTriggered: root.escapeCloseArmed = false
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.opened && root.service && root.service.playing
    onTriggered: root.service.refreshPosition()
  }

  Component {
    id: homePage

    Item {
      Column {
        anchors.fill: parent
        spacing: Style.space(7)

        Row {
          id: homeTypes
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: [
              { type: "recent", label: "Recently played", icon: "󰋚" },
              { type: "tracks", label: "Top songs", icon: "󰎈" },
              { type: "artists", label: "Top artists", icon: "󰠃" }
            ]
            Button {
              required property var modelData
              text: modelData.label
              iconText: modelData.icon
              foreground: root.foreground
              selected: root.homeType === modelData.type
              onClicked: root.homeType = modelData.type
            }
          }
        }

        MediaCollection {
          width: parent.width
          height: Math.max(40, parent.height - homeTypes.height - parent.spacing)
          service: root.service
          sourceItems: root.service ? root.service.homeItems(root.homeType) : []
          filterText: root.homeFilter
          showFilter: false
          showQueue: true
          showSave: true
          browseContexts: true
          loading: root.service && root.service.homeLoading
          hasMore: false
          restoredContentY: root.scrollFor("home:" + root.homeType)
          stateKey: "home:" + root.homeType
          emptyMessage: root.service && root.service.homeLoading
            ? "Loading your listening history…"
            : (root.homeFilter.trim() ? "No matches in " + root.activeSearchScope.label + "."
              : "No listening history is available yet.")
          onActivated: function(item, items, uri) {
            root.activateMedia(item, items, uri)
          }
          onOpened: function(item) { root.openItem(item) }
          onQueued: function(item) { if (root.service) root.service.addToQueue(item) }
          onPlaylistRequested: function(item) { root.openPlaylistPicker(item) }
          onSaveToggled: function(item) { if (root.service) root.service.toggleSaved(item) }
          onContextRequested: function(item, x, y, index, items, uri) {
            root.openMediaContext(item, x, y, items, uri, index)
          }
          onViewStateChanged: function(filter, sort, y) {
            root.rememberScroll("home:" + root.homeType, y)
          }
        }
      }
    }
  }

  Component {
    id: discoverPage

    Item {
      MediaCollection {
        anchors.fill: parent
        service: root.service
        sourceItems: root.service ? root.service.discoverPlaylists : []
        filterText: root.discoverFilter
        showFilter: false
        showQueue: false
        showPlaylist: false
        showSave: true
        browseContexts: true
        loading: root.service && root.service.discoverLoading
        hasMore: false
        restoredContentY: root.scrollFor("discover")
        stateKey: "discover"
        emptyMessage: root.service && root.service.discoverLoading
          ? "Finding playlists picked for you…"
          : (root.discoverFilter.trim() ? "No matches in Discover."
            : (root.service && root.service.discoverMessage
            ? root.service.discoverMessage : "No discovery playlists are available yet."))
        onActivated: function(item, items, uri) {
          root.activateMedia(item, items, uri)
        }
        onOpened: function(item) { root.openItem(item) }
        onSaveToggled: function(item) { if (root.service) root.service.toggleSaved(item) }
        onContextRequested: function(item, x, y, index, items, uri) {
          root.openMediaContext(item, x, y, items, uri, index)
        }
        onViewStateChanged: function(filter, sort, y) {
          root.rememberScroll("discover", y)
        }
      }
    }
  }

  Component {
    id: detailPage

    Item {
      id: detailRoot
      readonly property bool isArtist: root.service && root.service.detailItem
        && root.service.detailItem.type === "artist"
      readonly property bool searchActive: isArtist && root.artistScopedSearchActive
      readonly property bool searchLoading: root.service
        && root.service.artistCatalogLoading
      readonly property int searchResultCount: root.service
        ? root.service.artistSongs.length + root.service.artistAlbums.length
          + root.service.artistPlaylists.length : 0
      readonly property int searchColumnCount: Api.responsiveResultColumns(
        Math.max(0, width - Style.space(10)), Style.space(760))
      readonly property var searchRows: Api.sectionedMediaRows([
        {
          id: "songs",
          heading: "SONGS",
          items: root.service ? root.service.artistSongs : [],
          loading: root.service && root.service.artistSongsLoading,
          hasMore: root.service && root.service.artistSongsNext !== ""
        },
        {
          id: "albums",
          heading: "ALBUMS & EPS",
          items: root.service ? root.service.artistAlbums : [],
          loading: root.service && root.service.artistAlbumsLoading,
          hasMore: root.service && root.service.artistAlbumsNext !== ""
        },
        {
          id: "playlists",
          heading: "PLAYLISTS",
          items: root.service ? root.service.artistPlaylists : [],
          loading: root.service && root.service.artistPlaylistsLoading,
          hasMore: root.service && root.service.artistPlaylistsNext !== ""
        }
      ], searchColumnCount)

      function artistSearchSource(sectionId) {
        if (!root.service) return []
        if (sectionId === "albums") return root.service.artistAlbums
        if (sectionId === "playlists") return root.service.artistPlaylists
        return root.service.artistSongs
      }

      function loadMoreArtistSearch(sectionId) {
        if (!root.service) return
        if (sectionId === "albums") root.service.loadMoreArtistAlbums()
        else if (sectionId === "playlists") root.service.loadMoreArtistPlaylists()
        else root.service.loadMoreArtistSongs()
      }

      Column {
        anchors.fill: parent
        spacing: Style.space(8)

        BorderSurface {
          id: detailHero
          width: parent.width
          height: visible ? Style.space(132) : 0
          visible: !detailRoot.searchActive
          radius: Style.cornerRadius
          color: Style.normalFillFor(root.foreground, root.accent)
          borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

          Row {
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(12)

            BorderSurface {
              width: parent.height
              height: width
              radius: Style.cornerRadius
              color: Style.selectedFillFor(root.foreground, root.accent)
              borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

              Image {
                id: detailArtwork
                anchors.fill: parent
                anchors.margins: Style.space(2)
                source: root.service && root.service.detailItem
                  ? String(root.service.detailItem.imageUrl || "") : ""
                sourceSize.width: 256
                sourceSize.height: 256
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: false
                visible: status === Image.Ready
              }
              Text {
                anchors.centerIn: parent
                visible: detailArtwork.status !== Image.Ready
                text: ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge
              }
            }

            Column {
              width: Math.max(80, parent.width - parent.height - detailActions.width
                - parent.spacing * 2)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              Text {
                width: parent.width
                text: root.service && root.service.detailItem
                  ? root.service.detailItem.name : "Loading…"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }
              ArtistLinks {
                width: parent.width
                artists: root.service && root.service.detailItem
                  ? root.service.detailItem.artists : []
                fallbackText: root.service && root.service.detailItem
                  ? root.service.detailItem.subtitle : ""
                suffixText: root.service && root.service.detailItem
                  ? Api.artistSubtitleSuffix(root.service.detailItem) : ""
                color: root.accent
                accent: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                onArtistRequested: function(item) { root.openItem(item) }
              }
              Text {
                width: parent.width
                text: root.service && root.service.detailItem
                  ? String(root.service.detailItem.description
                    || root.service.detailItem.releaseDate || "") : ""
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                maximumLineCount: 2
                elide: Text.ElideRight
                wrapMode: Text.WordWrap
              }
            }

            Column {
              id: detailActions
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              Button {
                text: "Play"
                iconText: "󰐊"
                foreground: root.foreground
                selected: true
                enabled: root.service && root.service.detailItem
                  && (["show", "audiobook"].indexOf(root.service.detailItem.type) < 0
                    || root.service.detailItems.length > 0)
                onClicked: {
                  if (["show", "audiobook"].indexOf(root.service.detailItem.type) >= 0)
                    root.activateMedia(root.service.detailItems[0],
                      root.service.detailItems, "")
                  else root.activateMedia(root.service.detailItem)
                }
              }
              Button {
                text: root.service && root.service.isSaved(root.service.detailItem)
                  ? "Saved" : "Save"
                iconText: root.service && root.service.isSaved(root.service.detailItem)
                  ? "󰓎" : "󰋑"
                foreground: root.foreground
                selected: root.service && root.service.isSaved(root.service.detailItem)
                enabled: root.service && root.service.detailItem
                  && !root.service.isSaved(root.service.detailItem)
                onClicked: if (root.service && !root.service.isSaved(root.service.detailItem))
                  root.service.toggleSaved(root.service.detailItem)
              }
              Button {
                id: detailMoreActions
                visible: root.service && root.service.detailItem
                iconText: "󰇙"
                foreground: root.foreground
                tooltipText: "More actions"
                onClicked: {
                  var point = detailMoreActions.mapToItem(window.contentItem,
                    detailMoreActions.width, 0)
                  root.openMediaContext(root.service.detailItem, point.x, point.y,
                    root.service.detailItems, root.service.detailItem.uri, -1)
                }
              }
            }
          }
        }

        Text {
          id: detailNotice
          width: parent.width
          height: visible ? implicitHeight : 0
          visible: root.service && root.service.detailMessage !== ""
          text: root.service ? root.service.detailMessage : ""
          color: Qt.darker(root.foreground, 1.35)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Column {
          id: artistCatalog
          width: parent.width
          height: visible ? Math.max(40, parent.height - detailHero.height
            - detailNotice.height - parent.spacing * 2) : 0
          visible: detailRoot.isArtist && !detailRoot.searchActive
          spacing: Style.space(7)

          Row {
            id: artistLists
            width: parent.width
            height: parent.height
            spacing: Style.space(10)

            Column {
              width: Math.max(80, (parent.width - parent.spacing) / 2)
              height: parent.height
              spacing: Style.space(5)

              Text {
                id: artistAlbumsHeading
                width: parent.width
                text: root.artistSearchText.trim() ? "ALBUMS & EPS" : "TOP ALBUMS & EPS"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              MediaCollection {
                width: parent.width
                height: Math.max(30, parent.height - artistAlbumsHeading.height
                  - parent.spacing)
                service: root.service
                sourceItems: root.service ? root.service.artistAlbums : []
                showFilter: false
                showQueue: false
                showSave: true
                browseContexts: true
                loading: root.service && root.service.artistAlbumsLoading
                hasMore: root.service && root.service.artistAlbumsNext !== ""
                emptyMessage: root.service && root.service.artistAlbumsLoading
                  ? "Finding releases…" : "No matching albums or EPs."
                onActivated: function(item, items, uri) {
                  root.activateMedia(item, items, uri)
                }
                onOpened: function(item) { root.openItem(item) }
                onSaveToggled: function(item) { if (root.service) root.service.toggleSaved(item) }
                onContextRequested: function(item, x, y, index, items, uri) {
                  root.openMediaContext(item, x, y, items, uri, index)
                }
                onLoadMoreRequested: if (root.service) root.service.loadMoreArtistAlbums()
              }
            }

            Column {
              width: Math.max(80, parent.width - parent.spacing
                - Math.max(80, (parent.width - parent.spacing) / 2))
              height: parent.height
              spacing: Style.space(5)

              Text {
                id: artistSongsHeading
                width: parent.width
                text: root.artistSearchText.trim() ? "SONGS" : "TOP 10 SONGS"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              MediaCollection {
                width: parent.width
                height: Math.max(30, parent.height - artistSongsHeading.height
                  - artistThisIsRow.height - parent.spacing
                  * (artistThisIsRow.visible ? 2 : 1))
                service: root.service
                sourceItems: root.service ? root.service.artistSongs : []
                showFilter: false
                showQueue: true
                showSave: true
                browseContexts: false
                loading: root.service && root.service.artistSongsLoading
                hasMore: root.service && root.service.artistSongsNext !== ""
                emptyMessage: root.service && root.service.artistSongsLoading
                  ? "Finding songs…" : "No matching songs."
                onActivated: function(item, items, uri) {
                  root.activateMedia(item, items, uri)
                }
                onOpened: function(item) { root.openItem(item) }
                onQueued: function(item) { if (root.service) root.service.addToQueue(item) }
                onPlaylistRequested: function(item) { root.openPlaylistPicker(item) }
                onSaveToggled: function(item) { if (root.service) root.service.toggleSaved(item) }
                onContextRequested: function(item, x, y, index, items, uri) {
                  root.openMediaContext(item, x, y, items, uri, index)
                }
                onLoadMoreRequested: if (root.service) root.service.loadMoreArtistSongs()
              }

              MediaRow {
                id: artistThisIsRow
                width: parent.width
                height: visible ? implicitHeight : 0
                visible: root.service && root.service.artistThisIsPlaylist
                itemData: root.service ? root.service.artistThisIsPlaylist : null
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                browseOnActivate: true
                showQueue: false
                showPlaylist: false
                showSave: true
                saved: root.service && root.service.isSaved(itemData)
                onActivated: function(item) { root.activateMedia(item, [item], item.uri) }
                onOpenRequested: function(item) { root.openItem(item) }
                onSaveRequested: function(item) {
                  if (root.service) root.service.toggleSaved(item)
                }
                onContextRequested: function(item, sceneX, sceneY) {
                  root.openMediaContext(item, sceneX, sceneY, [item], item.uri, 0)
                }
              }
            }
          }

        }

        Item {
          id: artistSearchPage
          width: parent.width
          height: visible ? Math.max(40, parent.height - detailNotice.height
            - parent.spacing) : 0
          visible: detailRoot.searchActive

          Column {
            anchors.fill: parent
            spacing: Style.space(7)

            Text {
              id: artistSearchStatus
              width: parent.width
              text: detailRoot.searchLoading
                ? "Searching " + (root.service && root.service.detailItem
                  ? root.service.detailItem.name : "this artist") + "…"
                : detailRoot.searchResultCount
                  + (detailRoot.searchResultCount === 1 ? " result" : " results")
              color: Qt.darker(root.foreground, 1.35)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            ListView {
              id: artistSearchList
              width: Math.max(1, parent.width - Style.space(10))
              height: Math.max(30, parent.height - artistSearchStatus.height
                - artistSearchEmpty.height - parent.spacing * 2)
              property string queryKey: root.artistSearchText
              model: detailRoot.searchRows.length
              clip: true
              spacing: Style.space(4)
              reuseItems: true
              cacheBuffer: Style.space(160)
              boundsBehavior: Flickable.StopAtBounds
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
              onQueryKeyChanged: positionViewAtBeginning()

              FastScrollHandler {
                parent: artistSearchList
                flickable: artistSearchList
              }

              delegate: Loader {
                id: artistSearchRowLoader
                required property int index
                property var rowData: detailRoot.searchRows[index]
                width: ListView.view.width
                height: {
                  if (!rowData) return 0
                  if (rowData.kind === "items") return Style.space(72)
                  return rowData.kind === "heading" ? Style.space(28) : Style.space(40)
                }
                sourceComponent: {
                  if (!rowData) return null
                  if (rowData.kind === "items") return artistSearchMediaRow
                  return rowData.kind === "heading" ? artistSearchHeadingRow
                    : artistSearchMoreRow
                }
                onLoaded: if (item) item.rowData = rowData
                onRowDataChanged: if (item) item.rowData = rowData
              }
            }

            Text {
              id: artistSearchEmpty
              width: parent.width
              height: visible ? implicitHeight : 0
              visible: !detailRoot.searchLoading
                && detailRoot.searchResultCount === 0
              text: "No songs, albums, or playlists matched this search."
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }
          }

          Component {
            id: artistSearchHeadingRow

            Row {
              id: searchHeadingRow
              property var rowData: null
              spacing: Style.space(8)

              Text {
                width: Math.max(40, parent.width - artistSearchSectionCount.width
                  - parent.spacing)
                anchors.verticalCenter: parent.verticalCenter
                text: searchHeadingRow.rowData
                  ? searchHeadingRow.rowData.heading : "RESULTS"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                id: artistSearchSectionCount
                anchors.verticalCenter: parent.verticalCenter
                text: searchHeadingRow.rowData && searchHeadingRow.rowData.loading
                  && searchHeadingRow.rowData.count === 0 ? "Finding…"
                  : String(searchHeadingRow.rowData
                    ? searchHeadingRow.rowData.count : 0)
                color: Qt.darker(root.foreground, 1.42)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          Component {
            id: artistSearchMediaRow

            Item {
              id: searchMediaGroup
              property var rowData: null

              Row {
                anchors.fill: parent
                spacing: Style.space(4)

                Repeater {
                  model: searchMediaGroup.rowData
                    ? Api.arrayValues(searchMediaGroup.rowData.items) : []

                  MediaRow {
                    required property var modelData
                    required property int index
                    width: Math.max(40, (parent.width - parent.spacing
                      * (detailRoot.searchColumnCount - 1))
                      / detailRoot.searchColumnCount)
                    height: parent.height
                    itemData: modelData
                    foreground: root.foreground
                    accent: root.accent
                    fontFamily: root.fontFamily
                    browseOnActivate: searchMediaGroup.rowData
                      && searchMediaGroup.rowData.sectionId !== "songs"
                      && modelData && modelData.kind === "context"
                    showQueue: searchMediaGroup.rowData
                      && searchMediaGroup.rowData.sectionId === "songs"
                    showPlaylist: showQueue
                    showSave: true
                    saved: root.service && root.service.isSaved(modelData)
                    onActivated: function(item) {
                      var sectionId = searchMediaGroup.rowData.sectionId
                      root.activateMedia(item,
                        detailRoot.artistSearchSource(sectionId), "")
                    }
                    onOpenRequested: function(item) { root.openItem(item) }
                    onArtistRequested: function(item) { root.openItem(item) }
                    onAlbumRequested: function(item) { root.openItem(item) }
                    onQueueRequested: function(item) {
                      if (root.service) root.service.addToQueue(item)
                    }
                    onPlaylistRequested: function(item) {
                      root.openPlaylistPicker(item)
                    }
                    onSaveRequested: function(item) {
                      if (root.service) root.service.toggleSaved(item)
                    }
                    onContextRequested: function(item, sceneX, sceneY) {
                      var row = searchMediaGroup.rowData
                      var items = detailRoot.artistSearchSource(row.sectionId)
                      root.openMediaContext(item, sceneX, sceneY, items, "",
                        row.startIndex + index)
                    }
                  }
                }
              }
            }
          }

          Component {
            id: artistSearchMoreRow

            Item {
              id: searchMoreRow
              property var rowData: null

              Button {
                anchors.centerIn: parent
                text: searchMoreRow.rowData && searchMoreRow.rowData.loading
                  ? "Loading…" : "Load more"
                foreground: root.foreground
                enabled: searchMoreRow.rowData && searchMoreRow.rowData.hasMore
                  && !searchMoreRow.rowData.loading
                onClicked: if (searchMoreRow.rowData)
                  detailRoot.loadMoreArtistSearch(searchMoreRow.rowData.sectionId)
              }
            }
          }
        }

        MediaCollection {
          id: detailCollection
          width: parent.width
          height: Math.max(40, parent.height - detailHero.height - detailNotice.height
            - parent.spacing * 2)
          visible: !detailRoot.isArtist
          service: root.service
          sourceItems: root.service ? root.service.detailItems : []
          filterText: root.detailFilter
          sortKey: root.detailSort
          contextUri: root.service && root.service.detailItem
            ? root.service.detailItem.uri : ""
          showQueue: true
          showFilter: false
          showSort: true
          showSave: true
          browseContexts: true
          allowReorder: root.service && root.service.detailItem
            && root.service.playlistOwned(root.service.detailItem)
          reorderBusy: root.service && root.service.playlistActionBusy
          loading: root.service && root.service.detailLoading
          hasMore: root.service && root.service.detailNext !== ""
          restoredContentY: root.scrollFor("detail:" + (root.service && root.service.detailItem
            ? root.service.detailItem.uri : ""))
          stateKey: "detail:" + (root.service && root.service.detailItem
            ? root.service.detailItem.uri : "")
          emptyMessage: root.service && root.service.detailMessage
            ? root.service.detailMessage : "No items are available for this selection."
          onActivated: function(item, items, uri) {
            root.activateMedia(item, items, uri)
          }
          onOpened: function(item) { root.openItem(item) }
          onQueued: function(item) { if (root.service) root.service.addToQueue(item) }
          onPlaylistRequested: function(item) { root.openPlaylistPicker(item) }
          onSaveToggled: function(item) { if (root.service) root.service.toggleSaved(item) }
          onContextRequested: function(item, x, y, index, items, uri) {
            root.openMediaContext(item, x, y, items, uri, index)
          }
          onReorderRequested: function(sourceIndex, destinationIndex) {
            if (root.service && root.service.detailItem)
              root.service.reorderPlaylistItem(sourceIndex, destinationIndex,
                root.service.detailItem, root.service.detailItems.length,
                root.service.detailItems)
          }
          onLoadMoreRequested: if (root.service) root.service.loadMoreDetail()
          onViewStateChanged: function(filter, sort, y) {
            root.detailFilter = filter
            root.detailSort = sort
            root.rememberScroll("detail:" + (root.service && root.service.detailItem
              ? root.service.detailItem.uri : ""), y)
          }
        }
      }
    }
  }

  Component {
    id: searchPage

    Item {
      id: searchRoot

      Component.onDestruction: {
        if (root.service) root.service.cancelSearch(false)
      }

      Column {
        anchors.fill: parent
        spacing: Style.space(7)

        Row {
          id: searchTypes
          width: parent.width
          spacing: Style.space(3)

          Repeater {
            model: [
              { type: "track", label: "Songs" },
              { type: "artist", label: "Artists" },
              { type: "album", label: "Albums" },
              { type: "playlist", label: "Playlists" },
              { type: "show", label: "Podcasts" },
              { type: "episode", label: "Episodes" },
              { type: "audiobook", label: "Books" }
            ]

            Button {
              required property var modelData
              text: modelData.label
              foreground: root.foreground
              selected: root.searchType === modelData.type
              horizontalPadding: Style.space(7)
              onClicked: root.searchType = modelData.type
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(7)
          visible: root.searchText.trim() === ""

          Row {
            width: parent.width

            Text {
              text: "RECENT SEARCHES"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            Item { width: Math.max(0, parent.width - clearHistory.width - Style.space(120)); height: 1 }
            Button {
              id: clearHistory
              text: "Clear"
              foreground: root.foreground
              visible: root.service && root.service.searchHistory.length > 0
              onClicked: root.service.clearSearchHistory()
            }
          }

          Flow {
            width: parent.width
            spacing: Style.space(5)

            Repeater {
              model: root.service ? root.service.searchHistory : []
              Button {
                required property string modelData
                text: modelData
                iconText: "󰍉"
                foreground: root.foreground
                onClicked: {
                  root.searchText = modelData
                  root.service.search(modelData)
                  Qt.callLater(function() { unifiedSearchField.forceActiveFocus() })
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: !root.service || root.service.searchHistory.length === 0
            text: "Type a title, artist, album, playlist, podcast, episode, or audiobook."
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }

        MediaCollection {
          id: resultsView
          width: parent.width
          height: Math.max(40, parent.height - searchTypes.height - parent.spacing)
          visible: root.searchText.trim() !== ""
          service: root.service
          sourceItems: root.service ? root.service.searchItems(root.searchType) : []
          showFilter: false
          showQueue: true
          showSave: true
          browseContexts: true
          loading: root.service && root.service.searchLoading
          hasMore: root.service && root.service.searchNext(root.searchType) !== ""
          restoredContentY: root.scrollFor("search:" + root.searchType)
          stateKey: "search:" + root.searchType
          emptyMessage: root.service && root.service.searchLoading
            ? "Searching…" : "No " + root.searchType + " results."
          onActivated: function(item, items, uri) {
            root.activateMedia(item, items, uri)
          }
          onOpened: function(item) { root.openItem(item) }
          onQueued: function(item) { if (root.service) root.service.addToQueue(item) }
          onPlaylistRequested: function(item) { root.openPlaylistPicker(item) }
          onSaveToggled: function(item) { if (root.service) root.service.toggleSaved(item) }
          onContextRequested: function(item, x, y, index, items, uri) {
            root.openMediaContext(item, x, y, items, uri, index)
          }
          onLoadMoreRequested: if (root.service) root.service.loadMoreSearch(root.searchType)
          onViewStateChanged: function(filter, sort, y) {
            root.rememberScroll("search:" + root.searchType, y)
          }
        }
      }

    }
  }

  Component {
    id: libraryPage

    Item {
      Component.onCompleted: if (root.service) root.service.loadLibrary(root.libraryType, false)

      Column {
        anchors.fill: parent
        spacing: Style.space(7)

        Row {
          id: libraryTypes
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: [
              { type: "tracks", label: "Songs", icon: "󰎈" },
              { type: "albums", label: "Albums", icon: "󰀥" },
              { type: "artists", label: "Artists", icon: "󰠃" },
              { type: "shows", label: "Podcasts", icon: "󰦔" },
              { type: "episodes", label: "Episodes", icon: "󰐾" },
              { type: "audiobooks", label: "Books", icon: "󰂺" }
            ]
            Button {
              required property var modelData
              text: modelData.label
              iconText: modelData.icon
              foreground: root.foreground
              selected: root.libraryType === modelData.type
              onClicked: {
                root.libraryType = modelData.type
                if (root.service) root.service.loadLibrary(modelData.type, false)
              }
            }
          }
        }

        MediaCollection {
          id: libraryCollection
          width: parent.width
          height: Math.max(40, parent.height - libraryTypes.height - parent.spacing)
          service: root.service
          sourceItems: root.service ? root.service.libraryItems(root.libraryType) : []
          filterText: root.libraryFilter
          sortKey: root.librarySort
          showFilter: false
          showSort: true
          showQueue: true
          showSave: true
          browseContexts: true
          loading: root.service && root.service.libraryLoading(root.libraryType)
          hasMore: root.service && root.service.libraryNext(root.libraryType) !== ""
          restoredContentY: root.scrollFor("library:" + root.libraryType)
          stateKey: "library:" + root.libraryType
          emptyMessage: "No saved items in this section."
          onActivated: function(item, items, uri) {
            root.activateMedia(item, items, uri)
          }
          onOpened: function(item) { root.openItem(item) }
          onQueued: function(item) { if (root.service) root.service.addToQueue(item) }
          onPlaylistRequested: function(item) { root.openPlaylistPicker(item) }
          onSaveToggled: function(item) { if (root.service) root.service.toggleSaved(item) }
          onContextRequested: function(item, x, y, index, items, uri) {
            root.openMediaContext(item, x, y, items, uri, index)
          }
          onLoadMoreRequested: if (root.service) root.service.loadLibrary(root.libraryType, true)
          onViewStateChanged: function(filter, sort, y) {
            root.libraryFilter = filter
            root.librarySort = sort
            root.rememberScroll("library:" + root.libraryType, y)
          }
        }
      }
    }
  }

  Component {
    id: playlistsPage

    Item {
      Column {
        anchors.fill: parent
        spacing: Style.space(6)

        Column {
          id: selectedPlaylistHeader
          width: parent.width
          spacing: Style.space(6)

          SearchableDropdown {
            visible: root.compactWidth
            width: parent.width
            height: visible ? implicitHeight : 0
            showLabel: false
            foreground: root.foreground
            background: root.background
            accent: root.accent
            fontFamily: root.fontFamily
            placeholderText: "Choose a playlist…"
            emptyText: root.service && root.service.playlistsLoading
              ? "Loading playlists…" : "No playlists found"
            options: root.playlistOptions()
            value: root.service && root.service.selectedPlaylist
              ? String(root.service.selectedPlaylist.id) : ""
            onChanged: function(value) {
              var playlist = root.service ? root.service.playlistById(value) : null
              if (playlist) root.service.openPlaylist(playlist)
            }
          }

          Button {
            visible: root.compactWidth && root.service
              && root.service.playlistsNext !== ""
            width: parent.width
            text: root.service && root.service.playlistsLoading
              ? "Loading more playlists…" : "Load more playlists"
            iconText: "󰑐"
            foreground: root.foreground
            enabled: root.service && !root.service.playlistsLoading
            onClicked: root.service.loadMorePlaylists()
          }

          Row {
            width: parent.width
            spacing: Style.space(4)

            Text {
              width: Math.max(40, parent.width
                - (playPlaylist.visible ? playPlaylist.width + parent.spacing : 0)
                - (playlistMoreActions.visible
                  ? playlistMoreActions.width + parent.spacing : 0))
              text: root.service && root.service.selectedPlaylist
                ? root.service.selectedPlaylist.name : "Select a playlist"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              elide: Text.ElideRight
            }

            Button {
              id: playPlaylist
              visible: root.service && root.service.selectedPlaylist
              iconText: "󰐊"
              text: "Play"
              foreground: root.foreground
              onClicked: root.activateMedia(root.service.selectedPlaylist)
            }

            Button {
              id: playlistMoreActions
              visible: root.service && root.service.selectedPlaylist
              iconText: "󰇙"
              foreground: root.foreground
              tooltipText: "More actions"
              onClicked: {
                var point = playlistMoreActions.mapToItem(window.contentItem,
                  playlistMoreActions.width, 0)
                root.openMediaContext(root.service.selectedPlaylist, point.x, point.y,
                  [], root.service.selectedPlaylist.uri, -1)
              }
            }
          }

          Button {
            width: parent.width
            visible: root.service && root.service.selectedPlaylist
              && root.service.currentUserId !== ""
              && !root.service.playlistOwned(root.service.selectedPlaylist)
            text: root.service && root.service.playlistConversionBusy
              ? "Making your copy…" : "Turn into your own playlist"
            iconText: "󰒍"
            foreground: root.foreground
            selected: true
            enabled: root.service && !root.service.playlistActionBusy
            tooltipText: "Copy every available item, then remove the followed original"
            onClicked: root.turnPlaylistIntoOwn(root.service.selectedPlaylist)
          }
        }

        MediaCollection {
          id: playlistItemsCollection
          width: parent.width
          height: Math.max(40, parent.height - selectedPlaylistHeader.height - parent.spacing)
          service: root.service
          sourceItems: root.service ? root.service.playlistItems : []
          filterText: root.playlistFilter
          sortKey: root.playlistSort
          contextUri: root.service && root.service.selectedPlaylist
            ? root.service.selectedPlaylist.uri : ""
          showQueue: true
          showFilter: false
          showSort: true
          showSave: true
          browseContexts: false
          allowReorder: root.service && root.service.selectedPlaylist
            && root.service.playlistOwned(root.service.selectedPlaylist)
          reorderBusy: root.service && root.service.playlistActionBusy
          loading: root.service && root.service.playlistItemsLoading
          hasMore: root.service && root.service.playlistItemsNext !== ""
          emptyMessage: root.service && root.service.selectedPlaylist
            ? "This playlist has no visible items."
            : (root.compactWidth ? "Choose a playlist above."
              : "Choose a playlist from the sidebar.")
          restoredContentY: root.scrollFor("playlist:" + (root.service
            && root.service.selectedPlaylist ? root.service.selectedPlaylist.id : ""))
          stateKey: "playlist:" + (root.service && root.service.selectedPlaylist
            ? root.service.selectedPlaylist.id : "")
          onActivated: function(item, items, uri) {
            root.activateMedia(item, items, uri)
          }
          onOpened: function(item) { root.openItem(item) }
          onQueued: function(item) { if (root.service) root.service.addToQueue(item) }
          onPlaylistRequested: function(item) { root.openPlaylistPicker(item) }
          onSaveToggled: function(item) { if (root.service) root.service.toggleSaved(item) }
          onContextRequested: function(item, x, y, index, items, uri) {
            root.openMediaContext(item, x, y, items, uri, index)
          }
          onReorderRequested: function(sourceIndex, destinationIndex) {
            if (root.service && root.service.selectedPlaylist)
              root.service.reorderPlaylistItem(sourceIndex, destinationIndex,
                root.service.selectedPlaylist, root.service.playlistItems.length,
                root.service.playlistItems)
          }
          onLoadMoreRequested: if (root.service) root.service.loadMorePlaylistItems()
          onViewStateChanged: function(filter, sort, y) {
            root.playlistFilter = filter
            root.playlistSort = sort
            root.rememberScroll("playlist:" + (root.service
              && root.service.selectedPlaylist ? root.service.selectedPlaylist.id : ""), y)
          }
        }
      }
    }
  }

  Component {
    id: queuePage

    Item {
      id: queueRoot
      readonly property var visibleItems: Api.filteredSorted(
        root.service ? root.service.queue : [], root.queueFilter, "default")

      Column {
        anchors.fill: parent
        spacing: Style.space(8)

        Row {
          width: parent.width

          Text {
            text: "UP NEXT"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Item { width: Math.max(0, parent.width - queueRefresh.width - Style.space(80)); height: 1 }

          Button {
            id: queueRefresh
            text: root.service && root.service.queueLoading ? "Loading…" : "Refresh"
            iconText: "󰑐"
            foreground: root.foreground
            enabled: root.service && !root.service.queueLoading
            onClicked: root.service.loadQueue()
          }
        }

        ListView {
          id: queueList
          width: parent.width
          height: Math.max(60, parent.height - Style.space(44))
          model: queueRoot.visibleItems
          clip: true
          spacing: Style.space(3)
          reuseItems: true
          cacheBuffer: Style.space(140)
          ScrollBar.vertical: ScrollBar { }

          FastScrollHandler { parent: queueList; flickable: queueList }

          delegate: MediaRow {
            required property var modelData
            required property int index
            itemData: modelData
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            showQueue: false
            showSave: true
            saved: root.service && root.service.isSaved(modelData)
            onActivated: function(item) {
              root.activateMedia(item, queueRoot.visibleItems, "")
            }
            onArtistRequested: function(item) { root.openItem(item) }
            onAlbumRequested: function(item) { root.openItem(item) }
            onOpenRequested: function(item) { root.openItem(item) }
            onPlaylistRequested: function(item) { root.openPlaylistPicker(item) }
            onSaveRequested: function(item) { if (root.service) root.service.toggleSaved(item) }
            onContextRequested: function(item, sceneX, sceneY) {
              root.openMediaContext(item, sceneX, sceneY,
                queueRoot.visibleItems, "", index)
            }
          }
        }
      }
    }
  }

  Component {
    id: devicesPage

    Item {
      ScrollView {
        id: devicesScroll
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        Column {
          width: devicesScroll.availableWidth
          spacing: Style.space(9)

          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: Math.max(80, parent.width - deviceRefresh.width - parent.spacing)
              text: "Choose where your music plays. This computer and nearby Spotify Connect devices appear here."
              color: Qt.darker(root.foreground, 1.3)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Button {
              id: deviceRefresh
              text: root.service && root.service.devicesLoading ? "Loading…" : "Refresh"
              iconText: "󰑐"
              foreground: root.foreground
              enabled: root.service && !root.service.devicesLoading
                && !root.service.deviceActivationBusy
              onClicked: root.service.loadDevices(null, undefined, true)
            }
          }

          Text {
            text: "AVAILABLE DEVICES"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Text {
            width: parent.width
            text: "A nearby speaker may take a moment to connect the first time you choose it."
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Repeater {
            model: root.service ? root.service.devices : []

            delegate: BorderSurface {
            id: deviceRow
            required property var modelData
            width: devicesScroll.availableWidth
            implicitHeight: Style.space(58)
            height: implicitHeight
            radius: Style.cornerRadius
            color: modelData.id === (root.service ? root.service.selectedDeviceId : "")
              ? Style.selectedFillFor(root.foreground, root.accent)
              : (deviceHover.hovered ? Style.hoverFillFor(root.foreground, root.accent) : "transparent")
            borderSpec: modelData.active
              ? Border.controlSpec("selected", root.foreground, root.accent) : Border.none()

            HoverHandler { id: deviceHover }
            MouseArea {
              anchors.fill: parent
              enabled: (!deviceRow.modelData.restricted
                || deviceRow.modelData.activationRequired) && root.service
                && !root.service.deviceActivationBusy
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ForbiddenCursor
              onClicked: if (root.service) root.service.selectDevice(deviceRow.modelData.id, true)
            }

            Row {
              anchors.fill: parent
              anchors.margins: Style.space(9)
              spacing: Style.space(10)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: deviceRow.modelData.type.toLowerCase() === "computer" ? "󰟀" : "󰋋"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.iconLarge
              }

              Column {
                width: Math.max(40, parent.width - Style.space(150))
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: deviceRow.modelData.name
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: deviceRow.modelData.active
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  text: deviceRow.modelData.type
                    + (deviceRow.modelData.description ? " · " + deviceRow.modelData.description : "")
                    + (deviceRow.modelData.local ? " · this computer" : "")
                    + (deviceRow.modelData.localDiscovery ? " · nearby" : "")
                    + (deviceRow.modelData.restricted
                      ? (deviceRow.modelData.active
                        ? (root.service && root.service.sonosControlAvailable
                          ? " · local controls" : " · limited controls")
                        : " · unavailable") : "")
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.service && root.service.deviceActivationBusy
                    && deviceRow.modelData.id === root.service.selectedDeviceId ? "Connecting"
                  : (deviceRow.modelData.active ? "Active"
                    : (deviceRow.modelData.activationRequired ? "Available"
                      : Math.round(deviceRow.modelData.volumePercent) + "%"))
                color: deviceRow.modelData.active ? root.accent : Qt.darker(root.foreground, 1.35)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }
          }
          }

          Text {
            width: parent.width
            visible: root.service && root.service.devicesLoaded
              && root.service.devices.length === 0
            text: "No Spotify Connect devices are available right now. Make sure the device is online, then refresh."
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Item { width: 1; height: Style.space(4) }
        }
      }

      FastScrollHandler {
        parent: devicesScroll.contentItem
        flickable: devicesScroll.contentItem
      }
    }
  }

  Component {
    id: loginPage

    Item {
      ScrollView {
        id: loginScroll
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        Column {
          width: Math.min(Style.space(620), loginScroll.availableWidth)
          x: Math.max(0, (loginScroll.availableWidth - width) / 2)
          spacing: Style.space(14)

          Item { width: 1; height: Style.space(4) }

          Column {
            width: parent.width
            spacing: Style.space(5)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: ""
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
            }
            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: "Omarchy Spotify"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: "Your music, library, playlists, and Spotify Connect devices — at home in Omarchy."
              color: Qt.darker(root.foreground, 1.35)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }
          }

          BorderSurface {
            width: parent.width
            implicitHeight: loginContent.implicitHeight + Style.space(28)
            color: Style.normalFillFor(root.foreground, root.accent)
            borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
            radius: Style.cornerRadius

            Column {
              id: loginContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(14)
              spacing: Style.space(12)

              Row {
                width: parent.width
                spacing: Style.space(10)

                BorderSurface {
                  width: Style.space(34)
                  height: width
                  radius: width / 2
                  color: root.fullyConnected
                    ? Style.selectedFillFor(root.foreground, root.accent)
                    : Style.normalFillFor(root.foreground, root.accent)
                  borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

                  Text {
                    anchors.centerIn: parent
                    text: root.fullyConnected ? "󰄬" : ""
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.icon
                    font.bold: true
                  }
                }

                Column {
                  width: Math.max(40, parent.width - Style.space(44))
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Text {
                    text: root.connectionHeadline()
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                  }
                  Text {
                    text: root.service ? root.service.loginProgress : "Spotify is unavailable"
                    color: root.fullyConnected
                      ? root.accent : Qt.darker(root.foreground, 1.4)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              Text {
                width: parent.width
                text: "Spotify may open two approval pages the first time. Finish both and Omarchy Spotify will bring you back here automatically."
                color: Qt.darker(root.foreground, 1.3)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }

              Column {
                width: parent.width
                spacing: Style.space(7)

                Row {
                  spacing: Style.space(7)
                  Text {
                    text: root.service && root.service.auth.loggedIn ? "󰄬" : "󰋼"
                    color: root.service && root.service.auth.loggedIn
                      ? root.accent : Qt.darker(root.foreground, 1.35)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    text: root.service && root.service.auth.loggedIn
                      ? "Your Spotify account is connected"
                      : (root.service && root.service.auth.loginBusy
                        ? "Connecting your Spotify account…"
                        : "Your Spotify account and library")
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                Row {
                  spacing: Style.space(7)
                  Text {
                    text: root.service && root.service.daemon.credentialsAvailable ? "󰄬" : "󰓃"
                    color: root.service && root.service.daemon.credentialsAvailable
                      ? root.accent : Qt.darker(root.foreground, 1.35)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    text: root.service && root.service.daemon.credentialsAvailable
                      ? "Playback on this computer is connected"
                      : (root.service && root.service.daemon.authenticationBusy
                        ? "Connecting playback on this computer…"
                        : "Playback on this computer")
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }
              }

              Button {
                width: parent.width
                text: root.connectionButtonText()
                iconText: "󰍂"
                foreground: root.foreground
                selected: root.fullyConnected
                enabled: root.service && !root.fullyConnected && !root.service.loginBusy
                onClicked: if (root.service) root.service.login()
              }

              Text {
                width: parent.width
                text: !root.service || root.service.daemon.playbackReady
                  || root.service.daemon.setupBusy ? ""
                  : (root.service.daemon.binaryAvailable
                    ? "This prepares private, on-demand playback for your account."
                    : "Omarchy may ask for your computer password to install its small playback component.")
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
                visible: text !== ""
              }

              Text {
                width: parent.width
                text: root.connectionErrorText()
                color: Color.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
                visible: text !== ""
              }
            }
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "Your password is entered only on Spotify's own page. Omarchy Spotify never sees it."
            color: Qt.darker(root.foreground, 1.45)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Item { width: 1; height: Style.space(4) }
        }
      }

      FastScrollHandler {
        parent: loginScroll.contentItem
        flickable: loginScroll.contentItem
      }
    }
  }

  Component {
    id: setupPage

    Item {
      ScrollView {
        id: setupScroll
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        Column {
          width: setupScroll.availableWidth
          spacing: Style.space(16)

          Column {
            width: parent.width
            spacing: Style.space(7)

            Text {
              text: "SPOTIFY ACCOUNT"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            Text {
              width: parent.width
              text: "Connect Spotify to search, browse your library, manage playlists, and listen on this computer or another Spotify Connect device."
              color: Qt.darker(root.foreground, 1.3)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            BorderSurface {
              width: parent.width
              implicitHeight: accountStatus.implicitHeight + Style.space(16)
              color: Style.normalFillFor(root.foreground, root.accent)
              borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
              radius: Style.cornerRadius

              Text {
                id: accountStatus
                anchors.fill: parent
                anchors.margins: Style.space(8)
                text: !root.service ? "Spotify is unavailable"
                  : (root.service.loginBusy ? root.service.loginProgress + "…"
                  : (root.fullyConnected ? "Connected and ready to play"
                  : (root.service.auth.loggedIn
                    ? "Spotify is connected · playback needs approval"
                    : (root.service.daemon.credentialsAvailable
                      ? "Playback is ready · Spotify needs approval"
                      : "Not connected"))))
                color: root.fullyConnected ? root.accent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }
            }

            Row {
              spacing: Style.space(7)

              Button {
                text: root.connectionButtonText()
                iconText: "󰍂"
                foreground: root.foreground
                selected: root.fullyConnected
                visible: !root.fullyConnected
                enabled: root.service && !root.service.loginBusy
                onClicked: if (root.service) root.service.login()
              }
              Button {
                text: "Reconnect Spotify"
                iconText: "󰑐"
                foreground: root.foreground
                visible: root.service && root.service.auth.loggedIn
                enabled: root.service && !root.service.loginBusy
                tooltipText: "Reconnect if library or playlist features are not working"
                onClicked: root.service.reconnectAccount()
              }
              Button {
                text: "Log out"
                iconText: "󰍃"
                foreground: root.foreground
                visible: root.service && (root.service.auth.loggedIn
                  || root.service.daemon.credentialsAvailable)
                enabled: root.service && !root.service.loginBusy
                  && !root.service.daemon.busy
                onClicked: root.service.logout()
              }
            }

            Text {
              width: parent.width
              text: root.connectionErrorText()
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              visible: text !== ""
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            id: localPlaybackSetup
            width: parent.width
            spacing: Style.space(7)
            visible: root.service && !root.service.daemon.playbackReady

            Text {
              text: "PLAYBACK ON THIS COMPUTER"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            Text {
              width: parent.width
              text: "A lightweight background player starts only when you need it, works with Omarchy's media controls, and appears in Spotify Connect as this computer."
              color: Qt.darker(root.foreground, 1.3)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            BorderSurface {
              width: parent.width
              implicitHeight: engineStatus.implicitHeight + Style.space(16)
              color: Style.normalFillFor(root.foreground, root.accent)
              borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
              radius: Style.cornerRadius

              Text {
                id: engineStatus
                anchors.fill: parent
                anchors.margins: Style.space(8)
                text: root.playbackStatusText()
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }
            }

            Row {
              spacing: Style.space(7)

              Button {
                text: root.service && root.service.daemon.setupBusy
                  ? "Setting up playback…" : "Set up playback"
                iconText: "󰓃"
                foreground: root.foreground
                visible: root.service && !root.service.daemon.playbackReady
                enabled: root.service && !root.service.loginBusy
                onClicked: root.service.login()
              }
            }
          }

          PanelSeparator {
            foreground: root.foreground
            visible: localPlaybackSetup.visible
          }

          Column {
            width: parent.width
            spacing: Style.space(7)

            Text {
              text: "PREFERENCES"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Text {
              text: "SPOTIFY CONNECT"
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Column {
                width: Math.round(parent.width * 0.58)
                spacing: Style.space(4)

                Text {
                  text: "THIS COMPUTER APPEARS AS"
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                TextField {
                  width: parent.width
                  foreground: root.foreground
                  placeholderText: "Omarchy Spotify"
                  text: root.draftDeviceName
                  onTextEdited: root.draftDeviceName = text
                }
              }
              Column {
                width: Math.max(Style.space(150), parent.width - Math.round(parent.width * 0.58)
                  - parent.spacing)
                spacing: Style.space(4)

                Text {
                  text: "STOP WHEN IDLE · MINUTES"
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                TextField {
                  width: parent.width
                  foreground: root.foreground
                  placeholderText: "15"
                  text: root.draftIdleMinutes
                  validator: IntValidator { bottom: 0; top: 1440 }
                  onTextEdited: root.draftIdleMinutes = text
                }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                text: "BAR PLAYER"
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Button {
                text: "Mini-player first · "
                  + (root.draftShowMiniPlayer ? "On" : "Off")
                iconText: "󰍹"
                foreground: root.foreground
                selected: root.draftShowMiniPlayer
                tooltipText: root.draftShowMiniPlayer
                  ? "Clicking the bar icon opens the mini-player first"
                  : "Clicking the bar icon opens the full player directly"
                onClicked: root.draftShowMiniPlayer = !root.draftShowMiniPlayer
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                text: "KEYBOARD"
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Button {
                text: "Super + Shift + M · " + root.draftShortcutPlayer
                iconText: "󰌌"
                foreground: root.foreground
                selected: root.draftShortcutPlayer !== "Omarchy default"
                focusable: true
                tooltipText: "Cycle between Omarchy's music app, full player, and mini-player"
                onClicked: root.cycleShortcutPlayer()
              }

              Text {
                width: parent.width
                text: "Cycles Omarchy default → Full player → Mini player. The shortcut uses this preference after it is bound once."
                color: Qt.darker(root.foreground, 1.45)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                text: "BAR TEXT"
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Flow {
                width: parent.width
                spacing: Style.space(8)

                Button {
                  text: "Title · " + (root.draftShowTitle ? "On" : "Off")
                  foreground: root.foreground
                  selected: root.draftShowTitle
                  tooltipText: "Show the song title in the top bar"
                  onClicked: {
                    root.draftShowTitle = !root.draftShowTitle
                    root.enforceScrollAvailability()
                  }
                }
                Button {
                  text: "Artist · " + (root.draftShowArtist ? "On" : "Off")
                  foreground: root.foreground
                  selected: root.draftShowArtist
                  tooltipText: "Show the artist name in the top bar"
                  onClicked: {
                    root.draftShowArtist = !root.draftShowArtist
                    root.enforceScrollAvailability()
                  }
                }
                Button {
                  text: "Scroll overflow · " + (root.draftScrollBarText ? "On" : "Off")
                  foreground: root.foreground
                  selected: root.draftScrollBarText
                  enabled: Api.canScrollBarText(root.draftShowTitle, root.draftShowArtist)
                  tooltipText: "Scroll bar text only when it is too wide to fit"
                  onClicked: root.draftScrollBarText = !root.draftScrollBarText
                }
              }

              Column {
                width: parent.width
                spacing: Style.space(4)
                visible: Api.canScrollBarText(root.draftShowTitle, root.draftShowArtist)
                  && root.draftScrollBarText

                Row {
                  width: parent.width

                  Text {
                    id: scrollSpeedTitle
                    text: "SCROLL SPEED"
                    color: Qt.darker(root.foreground, 1.4)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                  Item {
                    width: Math.max(0, parent.width - scrollSpeedTitle.implicitWidth
                      - scrollSpeedValue.implicitWidth)
                    height: 1
                  }
                  Text {
                    id: scrollSpeedValue
                    text: root.scrollSpeedLabel()
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }
                }

                PanelSlider {
                  width: parent.width
                  bar: root.panelBar
                  minimum: 0.25
                  maximum: 3
                  step: 0.25
                  tickCount: 12
                  value: root.draftScrollSpeed
                  onMoved: function(value) {
                    root.draftScrollSpeed = Api.normalizedScrollSpeed(value)
                  }
                  onReleased: function(value) {
                    root.draftScrollSpeed = Api.normalizedScrollSpeed(value)
                  }
                }
              }

              Text {
                width: parent.width
                visible: root.draftScrollBarText
                text: "Long labels fade at the edges and scroll only when they exceed the available bar space."
                color: Qt.darker(root.foreground, 1.45)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                text: "PLAYBACK"
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Button {
                text: "Audio quality · " + root.audioQualityLabel()
                iconText: "󰎈"
                foreground: root.foreground
                tooltipText: "Change streaming quality"
                onClicked: root.cycleAudioQuality()
              }
            }

            Text {
              width: parent.width
              text: "Use 0 idle minutes to keep this computer visible in Spotify Connect. Otherwise playback support sleeps when it is not in use. Device name and audio quality changes apply to Spotify Connect the next time music starts."
              color: Qt.darker(root.foreground, 1.45)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Row {
              width: parent.width

              Item {
                width: Math.max(0, parent.width - saveChangesButton.implicitWidth)
                height: 1
              }
              Button {
                id: saveChangesButton
                text: "Save changes"
                iconText: "󰆓"
                foreground: root.foreground
                selected: true
                onClicked: root.saveSettings()
              }
            }
          }
        }
      }

      FastScrollHandler {
        parent: setupScroll.contentItem
        flickable: setupScroll.contentItem
      }
    }
  }
}
