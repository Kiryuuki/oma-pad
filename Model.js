.pragma library

function parseState(rawText) {
  if (!rawText || typeof rawText !== "string" || !rawText.trim() || rawText.length > 524288) {
    return {
      version: 1,
      entries: [],
      workspaces: [],
      installedApps: [],
      totalPinned: 0,
      totalRunningWindows: 0
    };
  }
  try {
    var doc = JSON.parse(rawText);
    if (!doc || typeof doc !== "object") doc = {};
    if (!Array.isArray(doc.entries)) doc.entries = [];
    if (!Array.isArray(doc.workspaces)) doc.workspaces = [];
    if (!Array.isArray(doc.installedApps)) doc.installedApps = [];
    return doc;
  } catch (e) {
    console.log("[OmaPad Model] Error parsing state JSON: " + e);
    return {
      version: 1,
      entries: [],
      workspaces: [],
      installedApps: [],
      totalPinned: 0,
      totalRunningWindows: 0
    };
  }
}

function filterApps(appsList, query) {
  if (!Array.isArray(appsList)) return [];
  var q = (query || "").toLowerCase().trim();
  if (!q) return appsList.slice(0, 30);
  return appsList.filter(function(a) {
    if (!a) return false;
    var name = (a.name || "").toLowerCase();
    var match = (a.match || "").toLowerCase();
    var cmd = (a.command || "").toLowerCase();
    return name.indexOf(q) !== -1 || match.indexOf(q) !== -1 || cmd.indexOf(q) !== -1;
  }).slice(0, 40);
}
