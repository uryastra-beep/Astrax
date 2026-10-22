pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "../"

Item {
    id: root

    // "Do not disturb" toggle via IPC (SUPER+N) -- same mechanism as the
    // dndBtn button of the native panel (NotificationBox.qml): reads/writes
    // Config "notifications".dnd. With dnd=true popups stay
    // invisible except for critical urgency (see NotificationPopups.qml) and
    // nothing makes a sound -- easy to mistake for "notifications don't show up".
    // Visible confirmation of the toggle (via notify-send, critical urgency
    // to bypass the DND that was just turned on -- see
    // NotificationPopups.qml, hasCriticalPopup bypasses the dnd filter).
    // Without this the toggle is invisible/silent, no feedback on its
    // new state.
    Process {
        id: dndFeedbackProc
        property string pendingSummary: ""
        command: ["notify-send", "-u", "critical", "-a", "Serpantinum", "-i", "notification-symbolic", dndFeedbackProc.pendingSummary]
    }
    function notifyDndState(enabled) {
        dndFeedbackProc.pendingSummary = enabled ? "Do not disturb on" : "Do not disturb off";
        dndFeedbackProc.running = true;
    }

    IpcHandler {
        target: "dnd"

        function toggle(): string {
            let n = Config.getSetting("notifications", { "dnd": false });
            if (typeof n !== "object" || n === null) n = {};
            n.dnd = !n.dnd;
            Config.setSetting("notifications", n);
            root.notifyDndState(n.dnd);
            return n.dnd ? "on" : "off";
        }
    }

    // Astrax Dynamic Island bridge: one JSON object per line appended to a file the
    // island tails. Respects do-not-disturb (critical urgency still goes through).
    function sendToIsland(payload) {
        let isl = Config.getSetting("island", {});
        if (isl && isl.enabled === false) return;
        let n = Config.getSetting("notifications", { "dnd": false });
        if (n && n.dnd && payload.urgency !== 2) return;
        Quickshell.execDetached(["sh", "-c",
            "printf '%s\\n' \"$1\" >> \"${XDG_RUNTIME_DIR:-/tmp}/astrax-island.events\"",
            "_", JSON.stringify(payload)]);
    }

    // ---- Astrax Dynamic Island click-back (qs ipc call island ...) ----
    function islandInvoke(uid, actionId) {
        let n = root.liveNotifs[uid];
        if (!n) return "gone";
        root.markAsRead(uid);
        let acts = n.actions || [];
        let target = null;
        for (let i = 0; i < acts.length; i++) {
            if (actionId !== "" ? acts[i].identifier === actionId : acts[i].identifier === "default") target = acts[i];
        }
        if (!target && actionId === "" && acts.length > 0) target = acts[0];
        if (target && typeof target.invoke === "function") {
            target.invoke();
        } else if (actionId === "") {
            // no action offered: do what a real daemon's click does -- bring the app forward
            let name = ((n.desktopEntry || n.appName || "") + "").replace(/[^A-Za-z0-9]/g, ".");
            if (name !== "")
                Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ window = \"class:(?i).*" + name + ".*\" })"]);
        }
        root.removePopup(uid);
        root.dismissNotification(uid);
        return "ok";
    }

    IpcHandler {
        target: "island"
        function activate(uid: int): string { return root.islandInvoke(uid, ""); }
        function action(uid: int, id: string): string { return root.islandInvoke(uid, id); }
        function dismiss(uid: int): string { root.removePopup(uid); root.dismissNotification(uid); return "ok"; }
    }

    property var liveNotifs: ({})
    property int popupCounter: 0
    property bool isStartup: true
    property bool sysPanelOpen: false
    property real lastNotifTime: 0
    property bool _isBatchUpdating: false

    ListModel { id: historyModel }
    ListModel { id: popupsModel }
    ListModel { id: groupedHistoryModel }

    property alias globalNotificationHistory: historyModel
    property alias activePopupsModel: popupsModel
    property alias groupedHistory: groupedHistoryModel

    property var _resolveCache: ({})
    property var manualAliasTable: ({
        "telegram": "org.telegram.desktop",
        "discord": "discord",
        "slack": "slack",
        "spotify": "spotify"
    })

    signal popupAdded(int uid, var notif)

    onSysPanelOpenChanged: {
        if (sysPanelOpen) {
            popupsModel.clear();
            _resolveCache = {};
        }
    }

    Timer {
        id: startupGraceTimer
        interval: 500
        running: true
        onTriggered: root.isStartup = false
    }

    function resolveApp(n) {
        if (!n) return { groupKey: "system", displayName: "System", icon: "", desktopEntry: null };

        let rawAppName = n.appName || "";
        let appName = rawAppName.toLowerCase().trim();
        appName = appName.replace(/\s*(canary|beta|nightly|-git|git|dev|development)\s*$/g, "");

        let desktopEntry = (n.desktopEntry || "").trim();
        let key = (desktopEntry + "|" + appName);
        if (_resolveCache[key] !== undefined) return _resolveCache[key];

        let entry = null;
        if (desktopEntry) {
            entry = DesktopEntries.byId(desktopEntry);
        }
        if (!entry && appName) {
            let alias = manualAliasTable[appName];
            if (alias) {
                entry = DesktopEntries.byId(alias);
            } else {
                entry = DesktopEntries.heuristicLookup(rawAppName);
            }
        }

        let resolved = {
            groupKey: entry ? entry.id : (appName || "system"),
            displayName: entry ? entry.name : (rawAppName || "System"),
            icon: n.appIcon || (entry ? entry.icon : ""),
            desktopEntry: entry
        };
        _resolveCache[key] = resolved;
        return resolved;
    }

    function markGroupRead(groupKey) {
        let changed = false;
        for (let i = 0; i < historyModel.count; i++) {
            let nData = historyModel.get(i);
            if (!nData) continue;
            let resolved = resolveApp(nData);
            let gKey = resolved.groupKey;
            if (nData.urgency === 2) {
                gKey += "_crit_" + nData.uid;
            }
            if (gKey === groupKey && !nData.read) {
                historyModel.setProperty(i, "read", true);
                changed = true;
            }
        }
        if (changed) rebuildGroups();
    }

    function markAsRead(uid) {
        let changed = false;
        for (let i = 0; i < historyModel.count; i++) {
            let nData = historyModel.get(i);
            if (nData && nData.uid === uid && !nData.read) {
                historyModel.setProperty(i, "read", true);
                changed = true;
                break;
            }
        }
        if (changed) rebuildGroups();
    }

    function rebuildGroups() {
        let groupedMap = {};
        let newOrder = [];

        for (let i = 0; i < historyModel.count; i++) {
            let nData = historyModel.get(i);
            if (!nData) continue;
            let n = root.liveNotifs[nData.uid] || nData.notif;
            let resolved = resolveApp(n || nData);
            let gKey = resolved.groupKey;

            if (nData.urgency === 2) {
                gKey += "_crit_" + nData.uid;
            }

            if (!groupedMap[gKey]) {
                groupedMap[gKey] = {
                    groupKey: gKey,
                    displayName: resolved.displayName,
                    icon: resolved.icon,
                    members: [],
                    count: 0,
                    unreadCount: 0,
                    latestSummary: nData.summary,
                    latestBody: nData.body,
                    latestTimestamp: (n && n.timestamp) ? n.timestamp : (nData.timestamp || Date.now())
                };
                newOrder.push(gKey);
            }

            let ts = (n && n.timestamp) ? n.timestamp : (nData.timestamp || Date.now());
            if (ts >= groupedMap[gKey].latestTimestamp) {
                groupedMap[gKey].latestTimestamp = ts;
                groupedMap[gKey].latestSummary = nData.summary;
                groupedMap[gKey].latestBody = nData.body;
            }

            groupedMap[gKey].members.push({
                "appName": nData.appName,
                "summary": nData.summary,
                "body": nData.body,
                "iconPath": nData.iconPath,
                "image": nData.image,
                "imagePath": nData.imagePath,
                "actionsJson": nData.actionsJson,
                "hasActions": nData.hasActions,
                "uid": nData.uid,
                "notif": nData.notif,
                "timestamp": ts,
                "urgency": nData.urgency,
                "read": nData.read
            });
            groupedMap[gKey].count = groupedMap[gKey].members.length;
            if (!nData.read) {
                groupedMap[gKey].unreadCount++;
            }
        }

        for (let i = groupedHistoryModel.count - 1; i >= 0; i--) {
            let item = groupedHistoryModel.get(i);
            if (!item || !groupedMap[item.groupKey]) {
                groupedHistoryModel.remove(i, 1);
            }
        }

        for (let i = 0; i < newOrder.length; i++) {
            let gKey = newOrder[i];
            let gData = groupedMap[gKey];
            let itemsJsonStr = JSON.stringify(gData.members);

            let existingIndex = -1;
            for (let j = 0; j < groupedHistoryModel.count; j++) {
                let item = groupedHistoryModel.get(j);
                if (item && item.groupKey === gKey) {
                    existingIndex = j;
                    break;
                }
            }

            let modelEntry = {
                "groupKey": gKey,
                "displayName": gData.displayName,
                "icon": gData.icon,
                "count": gData.count,
                "unreadCount": gData.unreadCount,
                "latestSummary": gData.latestSummary,
                "latestBody": gData.latestBody,
                "latestTimestamp": gData.latestTimestamp,
                "itemsJson": itemsJsonStr
            };

            if (existingIndex === -1) {
                groupedHistoryModel.insert(i, modelEntry);
            } else {
                if (existingIndex !== i && existingIndex < groupedHistoryModel.count && i < groupedHistoryModel.count) {
                    groupedHistoryModel.move(existingIndex, i, 1);
                }
                let item = groupedHistoryModel.get(i);
                if (item) {
                    if (item.displayName !== modelEntry.displayName) item.displayName = modelEntry.displayName;
                    if (item.icon !== modelEntry.icon) item.icon = modelEntry.icon;
                    if (item.count !== modelEntry.count) item.count = modelEntry.count;
                    if (item.unreadCount !== modelEntry.unreadCount) item.unreadCount = modelEntry.unreadCount;
                    if (item.latestSummary !== modelEntry.latestSummary) item.latestSummary = modelEntry.latestSummary;
                    if (item.latestBody !== modelEntry.latestBody) item.latestBody = modelEntry.latestBody;
                    if (item.latestTimestamp !== modelEntry.latestTimestamp) item.latestTimestamp = modelEntry.latestTimestamp;
                    if (item.itemsJson !== modelEntry.itemsJson) item.itemsJson = modelEntry.itemsJson;
                }
            }
        }
    }

    Connections {
        target: historyModel
        function onCountChanged() {
            if (!root._isBatchUpdating) {
                root.rebuildGroups();
            }
        }
    }

    function clearNotifications(): void {
        root._isBatchUpdating = true;
        for (let key in root.liveNotifs) {
            let n = root.liveNotifs[key];
            if (n) {
                if (typeof n.dismiss === "function") {
                    n.dismiss();
                } else if (typeof n.close === "function") {
                    n.close();
                }
            }
        }
        root.liveNotifs = {};
        historyModel.clear();
        popupsModel.clear();
        groupedHistoryModel.clear();
        root._isBatchUpdating = false;
    }

    function dismissNotification(uid) {
        if (!historyModel || historyModel.count === 0) return;
        let n = root.liveNotifs[uid];
        delete root.liveNotifs[uid];

        if (n) {
            if (typeof n.dismiss === "function") n.dismiss();
            else if (typeof n.close === "function") n.close();
        }

        for (let i = 0; i < historyModel.count; i++) {
            let nData = historyModel.get(i);
            if (nData && nData.uid === uid) {
                historyModel.remove(i, 1);
                break;
            }
        }
    }

    function dismissGroup(groupKey) {
        if (!historyModel || historyModel.count === 0) return;
        root._isBatchUpdating = true;
        for (let i = historyModel.count - 1; i >= 0; i--) {
            let nData = historyModel.get(i);
            if (!nData) continue;
            let n = root.liveNotifs[nData.uid] || nData.notif;
            let resolved = resolveApp(n || nData);
            let gKey = resolved.groupKey;
            
            if (nData.urgency === 2) {
                gKey += "_crit_" + nData.uid;
            }

            if (gKey === groupKey) {
                delete root.liveNotifs[nData.uid];
                if (n) {
                    if (typeof n.dismiss === "function") n.dismiss();
                    else if (typeof n.close === "function") n.close();
                }
                if (i < historyModel.count) {
                    historyModel.remove(i, 1);
                }
            }
        }
        root._isBatchUpdating = false;
        rebuildGroups();
    }

    function removePopup(uid) {
        if (!popupsModel || popupsModel.count === 0) return;
        for (let i = popupsModel.count - 1; i >= 0; i--) {
            let p = popupsModel.get(i);
            if (!p) continue;
            let matches = (p.uid === uid || p.latestUid === uid);
            if (!matches && p.uidsJson) {
                try {
                    let uList = JSON.parse(p.uidsJson);
                    if (Array.isArray(uList) && uList.indexOf(uid) !== -1) {
                        matches = true;
                    }
                } catch (e) {}
            }
            if (matches) {
                if (i < popupsModel.count) {
                    popupsModel.remove(i, 1);
                }
                break;
            }
        }
    }

    NotificationServer {
        id: globalNotificationServer
        bodySupported: true
        actionsSupported: true
        imageSupported: true

        onNotification: (n) => {
            let now = Date.now();
            if (n.urgency !== 2 && now - root.lastNotifTime < 100) {
                return;
            }
            root.lastNotifTime = now;

            n.tracked = true;

            let extractedActions = [];
            if (n.actions) {
                for (let i = 0; i < n.actions.length; i++) {
                    extractedActions.push({
                        "id": n.actions[i].identifier || "",
                        "text": n.actions[i].text || n.actions[i].name || "Action"
                    });
                }
            }

            root.popupCounter++;
            let currentUid = root.popupCounter;
            root.liveNotifs[currentUid] = n;

            if (n.closed) {
                n.closed.connect(() => {
                    if (root.liveNotifs[currentUid]) {
                        delete root.liveNotifs[currentUid];
                        for (let i = 0; i < historyModel.count; i++) {
                            let item = historyModel.get(i);
                            if (item && item.uid === currentUid) {
                                historyModel.remove(i, 1);
                                break;
                            }
                        }
                    }
                });
            }

            let hasAct = extractedActions.length > 0;
            let resolved = resolveApp(n);

            let summaryText = n.summary !== "" ? n.summary : "No Title";
            let bodyText = n.body !== "" ? n.body : "";
            let imageVal = (n.image ? n.image.toString() : "") || (n.imagePath ? n.imagePath.toString() : "") || (n.appIcon ? n.appIcon.toString() : "");

            let notifData = {
                "appName":     n.appName !== "" ? n.appName : "System",
                "summary":     summaryText,
                "body":        bodyText,
                "iconPath":    n.appIcon !== "" ? n.appIcon : "",
                "image":       imageVal,
                "imagePath":   imageVal,
                "actionsJson": JSON.stringify(extractedActions),
                "hasActions":  hasAct,
                "uid":         currentUid,
                "notif":       n,
                "timestamp":   now,
                "urgency":     n.urgency,
                "read":        false
            };

            historyModel.insert(0, notifData);

            // Astrax Dynamic Island: hand the notification to the island process
            if (!root.isStartup) {
                root.sendToIsland({
                    "app":     resolved.displayName,
                    "summary": summaryText,
                    "body":    bodyText,
                    "icon":    resolved.icon || notifData.iconPath,
                    "image":   imageVal,
                    "urgency": n.urgency,
                    "uid":     currentUid,
                    "actions": extractedActions
                });
            }

            if (!root.isStartup && !root.sysPanelOpen) {
                let newPopup = {
                    "uid":           currentUid,
                    "latestUid":     currentUid,
                    "uidsJson":      JSON.stringify([currentUid]),
                    "groupKey":      resolved.groupKey,
                    "appName":       resolved.displayName,
                    "displayName":   resolved.displayName,
                    "icon":          resolved.icon || notifData.iconPath,
                    "image":         imageVal,
                    "imagePath":     imageVal,
                    "summary":       summaryText,
                    "body":          bodyText,
                    "combinedBody":  bodyText,
                    "messagesJson":  JSON.stringify(bodyText !== "" ? [bodyText] : []),
                    "messagesCount": 1,
                    "iconPath":      notifData.iconPath,
                    "actionsJson":   JSON.stringify(extractedActions),
                    "hasActions":    hasAct,
                    "notif":         n,
                    "urgency":       n.urgency,
                    "timestamp":     now
                };
                popupsModel.insert(0, newPopup);
                root.popupAdded(currentUid, n);
            }
        }
    }
}
