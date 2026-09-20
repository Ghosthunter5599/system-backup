import QtQuick

import "Api.js" as Api

// Thin authenticated transport. It performs no polling and owns only one
// special request: search, which is cancelled whenever a newer query arrives.
Item {
  id: root

  visible: false
  width: 0
  height: 0

  required property var auth

  property var searchRequest: null
  property int searchSerial: 0

  function request(method, path, query, body, callback, retried) {
    var url = Api.safeApiUrl(path)
    if (!url) {
      if (typeof callback === "function")
        callback(0, null, "Something went wrong while contacting Spotify", null)
      return null
    }
    url = Api.appendQuery(url, query)

    auth.withAccessToken(function(token, tokenError) {
      if (!token) {
        if (typeof callback === "function") callback(0, null, tokenError || "Not logged in", null)
        return
      }
      var xhr = new XMLHttpRequest()
      xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE) return
        var payload = Api.parseJson(xhr.responseText, null)
        if (xhr.status === 401 && retried !== true) {
          auth.invalidateAccessToken()
          root.request(method, path, query, body, callback, true)
          return
        }
        var ok = xhr.status >= 200 && xhr.status < 300
        var error = ok ? "" : Api.responseError(xhr.status, payload,
          "Spotify could not complete this request")
        if (!ok && xhr.status === 429) {
          var retryAfter = String(xhr.getResponseHeader("Retry-After") || "")
          if (retryAfter) error += ". Try again in " + retryAfter + " seconds"
        }
        if (typeof callback === "function") callback(xhr.status, payload, error, xhr)
      }
      xhr.open(String(method || "GET"), url)
      xhr.setRequestHeader("Authorization", "Bearer " + token)
      if (body !== undefined && body !== null) {
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.send(JSON.stringify(body))
      } else {
        xhr.send()
      }
      return xhr
    })
    return null
  }

  function cancelSearch() {
    searchSerial++
    if (searchRequest && searchRequest.abort) searchRequest.abort()
    searchRequest = null
  }

  // Search uses its own request creation so its concrete XHR can be aborted;
  // authenticated request setup may be asynchronous while a token refreshes,
  // so the serial also rejects stale callbacks created before that point.
  function search(query, callback) {
    cancelSearch()
    var serial = searchSerial
    var term = String(query || "").trim()
    if (!term) {
      if (typeof callback === "function") callback(Api.searchGroups({}, 128), "")
      return
    }
    issueSearch(term, callback, serial, false)
  }

  function issueSearch(term, callback, serial, retried) {
    auth.withAccessToken(function(token, tokenError) {
      if (serial !== root.searchSerial) return
      if (!token) {
        if (typeof callback === "function") callback(Api.searchGroups({}, 128),
          tokenError || "Not logged in")
        return
      }
      var url = Api.appendQuery(Api.API_BASE + "/search", {
        q: term,
        type: Api.SEARCH_TYPES.join(","),
        limit: 10
      })
      var xhr = new XMLHttpRequest()
      root.searchRequest = xhr
      xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE || serial !== root.searchSerial) return
        if (root.searchRequest === xhr) root.searchRequest = null
        var payload = Api.parseJson(xhr.responseText, null)
        if (xhr.status < 200 || xhr.status >= 300) {
          if (xhr.status === 401 && retried !== true) {
            auth.invalidateAccessToken()
            root.issueSearch(term, callback, serial, true)
            return
          }
          var error = Api.responseError(xhr.status, payload, "Search failed")
          if (xhr.status === 429) {
            var retryAfter = String(xhr.getResponseHeader("Retry-After") || "")
            if (retryAfter) error += ". Try again in " + retryAfter + " seconds"
          }
          if (typeof callback === "function") callback(Api.searchGroups({}, 128), error)
          return
        }
        if (typeof callback === "function") callback(Api.searchGroups(payload, 128), "")
      }
      xhr.open("GET", url)
      xhr.setRequestHeader("Authorization", "Bearer " + token)
      xhr.send()
    })
  }
}
