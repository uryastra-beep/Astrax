pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "../../"
import "LyricsMatch.js" as LyricsMatch

Item {
    id: root

    property int subscribers: 0
    property var customPlayer: null
    readonly property var player: customPlayer || MprisController.activePlayer

    // Sources that have no real song lyrics: Spotify's DJ narration (not a
    // track) and short-video sites playing through a browser (TikTok etc.),
    // where the title/artist are a username or caption and lrclib/YouTube
    // would "match" some unrelated song in another language.
    // Extra "no lyrics for this" patterns, one regular expression per line in
    // ~/.config/astrax/lyrics-blocklist.txt (# starts a comment). Each is tested,
    // case-insensitive, against the player name, the page URL, the title and the artist.
    property var userBlock: []
    FileView {
        id: blocklistFile
        path: Quickshell.env("HOME") + "/.config/astrax/lyrics-blocklist.txt"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const out = [];
            for (const raw of text().split("\n")) {
                const line = raw.replace(/#.*$/, "").trim();
                if (line === "") continue;
                try { out.push(new RegExp(line, "i")); } catch (e) {}
            }
            root.userBlock = out;
        }
        onLoadFailed: root.userBlock = []
    }

    readonly property bool lyricsEligible: {
        try {
            if (!player) return false;
            const md = player.metadata || {};
            const id = String(md["mpris:trackid"] || "");
            const title = String(player.trackTitle || "");
            const artist = String(player.trackArtist || "");
            const url = String(md["xesam:url"] || "").toLowerCase();
            const who = String(player.identity || player.desktopEntry || "").toLowerCase();
            if (/spotify/.test(who) && id !== "" && !/\/track\/|:track:/.test(id)) return false;
            if (/^dj\b/i.test(artist.trim()) || /^dj\b/i.test(title.trim())) return false;
            if (/(tiktok|instagram|facebook|twitter|snapchat|reddit)\.|fb\.watch|\/\/(www\.)?x\.com/.test(url)) return false;
            if (/tiktok/i.test(title) || /tiktok/i.test(artist)) return false;
            for (const re of userBlock) {
                if (re.test(who) || re.test(url) || re.test(title) || re.test(artist)) return false;
            }
            return true;
        } catch (e) {
            return true;
        }
    }

    readonly property bool isMediaActive: {
        try {
            return lyricsEligible && !!player && player.playbackState !== MprisPlaybackState.Stopped && (player.trackTitle || "") !== "";
        } catch (e) {
            return false;
        }
    }
    readonly property string trackTitle: {
        try {
            return player ? String(player.trackTitle || "") : "";
        } catch (e) {
            return "";
        }
    }
    readonly property string trackArtist: {
        try {
            return player ? String(player.trackArtist || "") : "";
        } catch (e) {
            return "";
        }
    }
    readonly property bool isLinerPlayer: !!player && /liner/i.test(String(player.identity || player.desktopEntry || ""))
    readonly property string currentTrackKey: isMediaActive ? (trackArtist.trim() + " - " + trackTitle.trim()) : ""

    property var localCache: ({})

    function getMemCache() {
        try {
            if (typeof globalThis !== "undefined" && globalThis) {
                if (!globalThis._serpantinumLyrics) globalThis._serpantinumLyrics = {};
                return globalThis._serpantinumLyrics;
            }
        } catch(e) {}
        if (!root.localCache) root.localCache = {};
        return root.localCache;
    }

    property var lyrics: []
    property bool hasLyrics: false
    property bool loading: false
    property string activeFetchKey: ""
    property string lastFetchedKey: ""
    property real currentPosition: 0
    property var activeSession: null
    // Word-by-word lyrics from Spicy Lyrics (optional spicy-bridge service). If they
    // arrive, they win over NetEase/lrclib for that song.
    property string bridgeKey: ""

    // ---- star ratings + shared best lyrics (astrax-lyrics-rating) ----
    // lyricsOrigin: where the lyrics on screen came from (spotify, liner, web, youtube,
    // or best:<origin> when they are the saved best ones). bestKey is set when the
    // song has saved best lyrics: they win over whatever this player brings.
    property string lyricsOrigin: "web"
    property string bridgeOriginHint: "spotify"
    property string bestKey: ""
    property string bestOrigin: ""
    // last song that ended (you can still rate it for a minute) and the song on screen
    property var pendingRate: null
    property var lastSong: null
    signal rated(bool saved, int stars)

    function playerId() {
        let who = root.player ? String(root.player.identity || root.player.desktopEntry || "") : "";
        if (/spotify/i.test(who)) return "spotify";
        if (/liner/i.test(who)) return "liner";
        return who !== "" ? who.toLowerCase().replace(/[^a-z0-9]+/g, "-") : "player";
    }

    function currentSnapshot() {
        if (!root.hasLyrics || root.currentTrackKey === "") return null;
        return { key: root.currentTrackKey, artist: root.trackArtist, title: root.trackTitle,
                 dur: root.getPlayerDurationSec(), origin: root.lyricsOrigin, player: root.playerId() };
    }

    function rate(stars, snap) {
        if (!snap || rateProc.running) return;
        rateProc.pendingStars = stars;
        rateProc.target = snap;
        rateProc.command = ["bash", "-c", 'exec "$HOME/.local/bin/astrax-lyrics-rating" "$@"', "--",
                            "rate", snap.player, String(stars), snap.artist, snap.title,
                            String(Math.round(snap.dur || 0)), snap.origin, snap.key];
        rateProc.running = true;
    }

    Process {
        id: rateProc
        property int pendingStars: 0
        property var target: null
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let saved = false;
                try { saved = JSON.parse(this.text.trim()).saved === true; } catch (e) {}
                if (root.pendingRate && rateProc.target && root.pendingRate.key === rateProc.target.key) root.pendingRate = null;
                root.rated(saved, rateProc.pendingStars);
            }
        }
    }

    Timer {
        id: pendingTimer
        interval: 60000
        onTriggered: root.pendingRate = null
    }

    // remember the song on screen, so it can be rated after it ends
    Timer {
        interval: 1000
        repeat: true
        running: root.subscribers > 0 && root.hasLyrics
        onTriggered: {
            let prev = root.lastSong;
            let maxPos = (prev && prev.key === root.currentTrackKey) ? Math.max(prev.maxPos, root.currentPosition) : root.currentPosition;
            let s = root.currentSnapshot();
            if (!s) return;
            s.maxPos = maxPos;
            root.lastSong = s;
        }
    }

    function lookupBest(key) {
        bestLookupProc.running = false;
        bestLookupProc.key = key;
        bestLookupProc.command = ["bash", "-c", 'exec "$HOME/.local/bin/astrax-lyrics-rating" "$@"', "--",
                                  "lookup", root.trackArtist, root.trackTitle,
                                  String(Math.round(root.getPlayerDurationSec()))];
        bestLookupProc.running = true;
    }

    Process {
        id: bestLookupProc
        property string key: ""
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let t = this.text.trim();
                if (t === "" || bestLookupProc.key !== root.currentTrackKey) return;
                try {
                    let o = JSON.parse(t);
                    if (!Array.isArray(o.lyrics) || o.lyrics.length === 0) return;
                    root.bestKey = bestLookupProc.key;
                    root.bestOrigin = String(o.origin || "");
                    root.applyLyrics(o.lyrics, bestLookupProc.key, false, false, true);
                } catch (e) {}
            }
        }
    }

    readonly property int currentIndex: {
        if (!hasLyrics || lyrics.length === 0) return -1;
        let pos = currentPosition;
        let idx = -1;
        for (let i = 0; i < lyrics.length; i++) {
            if (pos >= lyrics[i].time) {
                // background-only lines "(ooh, ah)" don't become the current line:
                // the previous normal one stays and the background shows below it
                if (!lyrics[i].isBg || idx < 0) idx = i;
            } else {
                break;
            }
        }
        return idx;
    }

    function subscribe() {
        subscribers++;
        triggerSearch();
    }

    function unsubscribe() {
        subscribers = Math.max(0, subscribers - 1);
        if (subscribers === 0) {
            searchTimeoutTimer.stop();
            cacheReadProcess.running = false;
            fileReadProcess.running = false;
            if (loading) {
                loading = false;
                lastFetchedKey = "";
                activeFetchKey = "";
                activeSession = null;
            }
        }
    }

    function getPlayerDurationSec() {
        if (!root.player || !root.player.length) return 0;
        return LyricsMatch.durationSecondsFromMpris(root.player.length);
    }

    function pickBestNetEaseSong(songs, session) {
        let wantT = session ? session.title : root.trackTitle;
        let wantA = session ? session.artist : root.trackArtist;
        let targetDur = session && session.durationSec > 0 ? session.durationSec : getPlayerDurationSec();
        return LyricsMatch.pickBestNetEaseSong(songs, wantT, wantA, targetDur);
    }

    function getLineOpacity(idx, curIdx) {
        if (curIdx < 0) return 0.50;
        if (idx === curIdx) return 1.0;
        let d = Math.abs(idx - curIdx);
        if (d === 1) return 0.60;
        if (d === 2) return 0.38;
        return Math.max(0.20, 0.38 - ((d - 2) * 0.08));
    }

    // Background vocals written in parentheses inside the lyrics (line-only songs:
    // "(Ooh, ah, ooh, ah)" as its own line or "Yo (Co-co-co)" inline).
    // Doesn't change `text`: marks background-only lines with isBg and gives them their bg
    // {time,endTime,text}; on mixed lines it adds bg and a `mainText` without the parentheses.
    // The end is estimated from syllables and cut shortly after the next
    // line starts.
    function normalizeBackground(list) {
        if (!Array.isArray(list)) return list;
        let rate = 0.26;
        function syl(t) {
            let m = t.toLowerCase().match(/[aeiouyáéíóúüàèìòùâêîôû]+/g);
            return m ? m.length : (t.trim() === "" ? 0 : 1);
        }
        function wt(t) {
            let ws = t.split(/\s+/).filter(x => x !== "");
            let n = 0;
            for (let i = 0; i < ws.length; i++) n += Math.max(1, syl(ws[i]));
            return n;
        }
        let out = [];
        for (let i = 0; i < list.length; i++) {
            let ln = list[i];
            let raw = String(ln.text || "").replace(/​/g, "");
            if (ln.bg || raw.indexOf("(") < 0) { out.push(ln); continue; }
            let groups = [];
            let main = raw.replace(/\([^)]*\)/g, function(g, off) {
                groups.push({ text: g.trim(), off: off });
                return " ";
            }).replace(/\s+/g, " ").trim();
            if (groups.length === 0) { out.push(ln); continue; }
            let nextT = (i + 1 < list.length) ? list[i + 1].time : ln.time + 6;
            let copy = Object.assign({}, ln);
            let entries = [];
            if (main === "") {
                if (out.length === 0) { out.push(ln); continue; }
                let dur = Math.max(1, wt(raw) * rate * 1.12 + 0.4);
                entries.push({ time: ln.time, endTime: Math.max(ln.time + 0.8, Math.min(ln.time + dur, nextT + 0.5)),
                               text: groups.map(g => g.text).join(" "), words: [] });
                copy.isBg = true;
            } else {
                let total = Math.max(1, wt(raw));
                let sung = Math.max(0.8, Math.min(nextT - ln.time - 0.15, total * rate * 1.12));
                for (let k = 0; k < groups.length; k++) {
                    let start = ln.time + (wt(raw.slice(0, groups[k].off)) / total) * sung;
                    let dur = Math.max(1, wt(groups[k].text) * rate * 1.12 + 0.4);
                    entries.push({ time: start, endTime: Math.max(start + 0.8, Math.min(start + dur, nextT + 0.5)),
                                   text: groups[k].text, words: [] });
                }
                copy.mainText = main;
            }
            copy.bg = entries;
            out.push(copy);
        }
        return out;
    }

    // ---- per-word timing estimate (when the song only has line timing) ----
    // Shared by the bar module and the Simple Lyrics widget.
    // Approximate syllables: vowel groups (es/en). A word weighs its
    // syllables, plus a pause if it ends in punctuation (comma/period).
    // lyrics language (es vs en): a final "e" is only silent in English
    readonly property bool englishLyrics: {
        let L = root.lyrics;
        if (!L || L.length === 0) return true;
        let txt = "";
        for (let i = 0; i < L.length && i < 40; i++) txt += " " + (L[i].text || "");
        txt = txt.toLowerCase();
        let es = (txt.match(/[ñáéíóú¿¡]|\b(que|el|la|los|las|de|no|te|me|yo|tu|mi|con|por|un|una|y|en|es|se|lo)\b/g) || []).length;
        let en = (txt.match(/\b(the|you|and|i|to|my|is|it|me|in|of|that|on|your|we|be|a)\b/g) || []).length;
        return en >= es;
    }

    function syllables(w) {
        let m = w.toLowerCase().match(/[aeiouyáéíóúüàèìòùâêîôû]+/g);
        let n = m ? m.length : 1;
        // silent final "e" in English (love, time): doesn't add a syllable
        if (englishLyrics && n > 1 && /[^aeiouy]e[sd]?$/.test(w.toLowerCase()) && !/(le|ee)$/.test(w.toLowerCase())) n--;
        return Math.max(1, n);
    }
    function splitLine(txt) {
        let ws = txt.replace(/​/g, "").trim().split(/\s+/).filter(x => x !== "");
        return ws.map(w => {
            let pause = /[.!?…]$/.test(w) ? 0.8 : (/[,;:—-]$/.test(w) ? 0.5 : 0);
            return { text: w, weight: syllables(w) + pause };
        });
    }

    // Song pace (seconds per syllable): median of the "tight" lines
    // (little gap before the next one), so it calibrates to the song's real
    // tempo/language instead of a fixed value.
    readonly property real secPerSyllable: {
        let L = root.lyrics;
        if (!L || L.length < 3) return 0.26;
        let rates = [];
        for (let i = 0; i + 1 < L.length; i++) {
            let ws = splitLine(L[i].text || "");
            let syl = 0;
            for (let k = 0; k < ws.length; k++) syl += ws[k].weight;
            let gap = L[i + 1].time - L[i].time;
            if (syl >= 3 && gap > 0.5 && gap < 6) rates.push(gap / syl);
        }
        if (rates.length < 3) return 0.26;
        rates.sort((x, y) => x - y);
        // 35th percentile: lines with gaps inflate the rate, tight ones are close to the real singing
        let r = rates[Math.floor(rates.length * 0.35)];
        return Math.max(0.12, Math.min(0.45, r * 0.95));
    }

    function estimatedWord(ln, idx, pos) {
        let ws = splitLine(ln.mainText !== undefined ? ln.mainText : (ln.text || ""));
        if (ws.length === 0) return "";
        if (ws.length === 1) return ws[0].text;
        let total = 0;
        for (let i = 0; i < ws.length; i++) total += ws[i].weight;
        let start = ln.time || 0;
        let nxt = (idx + 1 < root.lyrics.length) ? root.lyrics[idx + 1].time : start + total * secPerSyllable + 1;
        let gap = Math.max(0.8, nxt - start);
        // how long the line is sung: no more than the gap, nor more than
        // syllables * pace (long gaps are instrumental, they don't stretch the line)
        let sung = Math.max(0.8, Math.min(gap - 0.15, total * secPerSyllable * 1.12));
        let t = pos - start - 0.05;
        if (t > sung + 1.2 && gap - sung > 1.5) return "♫";
        let frac = Math.max(0, Math.min(0.999, t / sung));
        let acc = 0;
        for (let i = 0; i < ws.length; i++) {
            acc += ws[i].weight / total;
            if (frac < acc) return ws[i].text;
        }
        return ws[ws.length - 1].text;
    }

    // Word currently playing in a line: the last one that already started (it stays
    // on it during silences); before the first one, the first one.
    function activeWordText(modelData, pos) {
        let ws = modelData.words;
        if (!ws || ws.length === 0) {
            // line-only lyrics: estimate the word from syllables/pace
            let est = estimatedWord(modelData, root.currentIndex, pos);
            return est !== "" ? est : "♪";
        }
        let idx = 0;
        for (let i = 0; i < ws.length; i++) {
            if (pos >= ws[i].time) idx = i; else break;
        }
        // like u-lyrc: the gap BETWEEN lines (after the last word of the
        // line and before the next one) shows the note, only if the song has
        // lyrics (there's an active line) and is playing. Silences inside the
        // line keep the last word.
        let playing = !root.player || root.player.isPlaying;
        if (playing && pos > ws[ws.length - 1].endTime + 0.5) return "♫";
        // Liner (via liner-bridge) sends each word's syllables: the word builds up
        // as they are sung, "Cu" -> "Cuan" -> "Cuando"
        let syl = ws[idx].syl;
        if (root.isLinerPlayer && syl && syl.length > 1) {
            let shown = syl[0].text;
            for (let k = 1; k < syl.length; k++) {
                if (pos >= syl[k].time) shown += syl[k].text; else break;
            }
            if (shown.trim() !== "") return shown.trim();
        }
        let t = ws[idx].text.trim();
        return t !== "" ? t : "♫";
    }

    function renderActiveLineText(modelData, pos, highlightColor, textColor) {
        if (!modelData.words || modelData.words.length === 0) {
            return modelData.text !== "" ? modelData.text : "♪";
        }
        let activeIdx = -1;
        for (let i = 0; i < modelData.words.length; i++) {
            let w = modelData.words[i];
            let end = (w.endTime !== undefined && w.endTime > w.time) ? w.endTime : (i < modelData.words.length - 1 ? modelData.words[i + 1].time : (w.time + 0.8));
            if (pos >= w.time && pos < end) {
                activeIdx = i;
                break;
            }
        }
        let highlight = highlightColor ? highlightColor.toString() : "#cba6f7";
        let baseText = textColor ? textColor.toString() : "#cdd6f4";
        let parsedTextCol = Qt.color(baseText);
        let upcoming = Qt.rgba(parsedTextCol.r, parsedTextCol.g, parsedTextCol.b, 0.40).toString();
        let html = "";
        for (let i = 0; i < modelData.words.length; i++) {
            let w = modelData.words[i];
            let end = (w.endTime !== undefined && w.endTime > w.time) ? w.endTime : (i < modelData.words.length - 1 ? modelData.words[i + 1].time : (w.time + 0.8));

            let space = "";
            if (i < modelData.words.length - 1) {
                let nextW = modelData.words[i + 1];
                if (!w.text.endsWith(" ") && !nextW.text.startsWith(" ")) {
                    if (/\S/.test(w.text) && !/^[,.\!?:;)\]]/.test(nextW.text)) {
                        space = " ";
                    }
                }
            }

            let escaped = w.text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

            if (i === activeIdx) {
                html += "<font color='" + highlight + "'>" + escaped + "</font>" + space;
            } else if (pos >= end || (activeIdx !== -1 && i < activeIdx)) {
                html += "<font color='" + baseText + "'>" + escaped + "</font>" + space;
            } else {
                html += "<font color='" + upcoming + "'>" + escaped + "</font>" + space;
            }
        }
        return html.trim();
    }

    // Background vocals (the "(lyrics)" behind): they come in line.bg with their own
    // start/end and often overlap the next line, so they're searched
    // around the current line and kept until they finish playing.
    // A background vocal that comes with per-word timing builds up as it is sung:
    // "and", "and i", "and i wanna"... (the word being sung grows syllable by syllable for
    // Liner). Without word timing it is shown whole: no estimation for these.
    function bgWordText(b, pos) {
        let ws = b.words;
        if (!ws || ws.length === 0) return b.text;
        let idx = 0;
        for (let i = 0; i < ws.length; i++) {
            if (pos >= ws[i].time) idx = i; else break;
        }
        let parts = [];
        for (let i = 0; i < idx; i++) {
            let t = String(ws[i].text || "").trim();
            if (t !== "") parts.push(t);
        }
        let w = ws[idx];
        let cur = String(w.text || "").trim();
        let syl = w.syl;
        if (root.isLinerPlayer && syl && syl.length > 1) {
            let shown = syl[0].text;
            for (let k = 1; k < syl.length; k++) {
                if (pos >= syl[k].time) shown += syl[k].text; else break;
            }
            if (shown.trim() !== "") cur = shown.trim();
        }
        if (cur !== "") parts.push(cur);
        return parts.length > 0 ? parts.join(" ") : b.text;
    }

    readonly property string activeBgText: {
        let L = root.lyrics;
        if (!L || L.length === 0) return "";
        let pos = root.currentPosition;
        let ci = Math.max(0, root.currentIndex);
        let parts = [];
        for (let i = Math.max(0, ci - 3); i <= Math.min(L.length - 1, ci + 4); i++) {
            let bgs = L[i].bg;
            if (!bgs) continue;
            for (let k = 0; k < bgs.length; k++) {
                let b = bgs[k];
                if (pos >= b.time - 0.05 && pos <= b.endTime + 0.35 && (b.text || "") !== "") parts.push(root.bgWordText(b, pos));
            }
        }
        return parts.join(" ");
    }

    // ---- auto-sync with Spotify's real position ----
    // MPRIS drifts with crossfade/automix. An optional bridge can write
    // the real position to ~/.cache/spicy-bridge/progress.json and
    // here the real - MPRIS offset is computed, smoothed, and added to the
    // position. Without fresh data (no bridge, etc.) it goes back to 0.
    property real syncOffset: 0

    // The bridges write one JSON object per file: spicy-bridge (Spotify, no key,
    // matched by uri) and liner-bridge (Liner, keyed "Artist - Title"). Returns the
    // sample for the current song: a keyed one that matches wins, else the unkeyed one.
    function pickBridgeSample(text) {
        let unkeyed = null;
        for (const raw of String(text || "").split("\n")) {
            const line = raw.trim();
            if (line === "") continue;
            let obj = null;
            try { obj = JSON.parse(line); } catch (e) { continue; }
            if (!obj) continue;
            if (obj.player === "liner") { if (root.isLinerPlayer && obj.key === root.currentTrackKey) return obj; }
            else if (!root.isLinerPlayer && !unkeyed) unkeyed = obj;
        }
        return unkeyed;
    }

    function applyProgressSample(obj) {
        if (!root.player || !obj) { syncOffset = 0; return; }
        let nowS = Date.now() / 1000;
        let age = nowS - obj.stamp;
        let tid = "";
        try { tid = String((root.player.metadata || {})["mpris:trackid"] || ""); } catch (e) {}
        let m = /track[:\/](\w+)/.exec(String(obj.uri || ""));
        if (m && tid !== "" && tid.indexOf(m[1]) < 0) { syncOffset = 0; return; }
        if (age > 3) { if (root.player.isPlaying) syncOffset = 0; return; }
        let real = obj.progress + (root.player.isPlaying ? age : 0);
        let raw = real - root.player.position;
        if (Math.abs(raw) > 60) { syncOffset = 0; return; }
        if (Math.abs(raw - syncOffset) > 0.8) syncOffset = raw;
        else syncOffset += (raw - syncOffset) * 0.3;
    }

    Timer {
        interval: 400
        repeat: true
        running: root.subscribers > 0 && root.isMediaActive
        onTriggered: if (!progressReadProcess.running) progressReadProcess.running = true
    }

    Process {
        id: progressReadProcess
        command: ["bash", "-c", 'cat "$HOME/.cache/spicy-bridge/progress.json" 2>/dev/null; echo; cat "$HOME/.cache/liner-bridge/progress.json" 2>/dev/null']
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let obj = root.pickBridgeSample(this.text);
                if (!obj) { root.syncOffset = 0; return; }
                root.applyProgressSample(obj);
            }
        }
    }

    property real polledPosition: 0
    property real nextBoundaryTime: Infinity

    function computeNextBoundary() {
        let ly = root.lyrics;
        if (!root.hasLyrics || !ly || ly.length === 0) return Infinity;
        let p = root.currentPosition;
        let idx = root.currentIndex;
        let best = Infinity;
        if (idx + 1 < ly.length) best = ly[idx + 1].time;
        if (idx >= 0) {
            let words = ly[idx].words;
            if (words) {
                for (let i = 0; i < words.length; i++) {
                    let w = words[i];
                    let end = (w.endTime !== undefined && w.endTime > w.time) ? w.endTime : (i < words.length - 1 ? words[i + 1].time : (w.time + 0.8));
                    if (w.time > p && w.time < best) best = w.time;
                    // Liner words come split in syllables: each start is a boundary too
                    if (w.syl) for (let k = 0; k < w.syl.length; k++) {
                        if (w.syl[k].time > p && w.syl[k].time < best) best = w.syl[k].time;
                    }
                    if (end > p && end < best) best = end;
                }
            }
        }
        return best;
    }

    property real pendingJumpPosition: -1
    property real seekGuardTarget: 0
    property double seekGuardUntil: 0

    function noteSeek(t) {
        root.seekGuardTarget = t;
        root.seekGuardUntil = Date.now() + 1500;
        root.pendingJumpPosition = -1;
        root.polledPosition = t;
        root.currentPosition = t;
    }

    function applyPosition(pos) {
        if (typeof pos !== "number" || !isFinite(pos) || pos < 0) return;

        if (root.seekGuardUntil > 0) {
            if (Date.now() < root.seekGuardUntil && Math.abs(pos - root.seekGuardTarget) > 1.5) return;
            root.seekGuardUntil = 0;
        }

        root.polledPosition = pos;

        if (pos < root.currentPosition - 0.3) {
            let pending = root.pendingJumpPosition;
            if (pending >= 0 && Math.abs(pos - pending) < 1.5) {
                root.pendingJumpPosition = -1;
                root.currentPosition = pos;
            } else {
                root.pendingJumpPosition = pos;
            }
            return;
        }

        root.pendingJumpPosition = -1;
        if (pos >= root.nextBoundaryTime) {
            root.currentPosition = pos;
        }
    }

    onCurrentPositionChanged: root.nextBoundaryTime = root.computeNextBoundary()

    function refreshForLyrics() {
        if (root.hasLyrics && positionTimer.running) root.currentPosition = root.polledPosition;
        root.nextBoundaryTime = root.computeNextBoundary();
    }

    onLyricsChanged: root.refreshForLyrics()
    onHasLyricsChanged: root.refreshForLyrics()

    Timer {
        id: positionTimer
        interval: 100
        repeat: true
        running: root.subscribers > 0 && root.isMediaActive && (root.player ? root.player.isPlaying : false)
        onRunningChanged: {
            if (running) positionTimer.interval = 25;
        }
        onTriggered: {
            if (root.player) {
                if (typeof root.player.positionChanged === "function") {
                    root.player.positionChanged();
                }
                root.applyPosition(root.player.position + root.syncOffset);
            } else {
                root.applyPosition(MprisController.livePosition);
            }
            if (!root.hasLyrics) {
                positionTimer.interval = 250;
            } else {
                positionTimer.interval = (root.nextBoundaryTime - root.polledPosition < 0.3) ? 25 : 100;
            }
        }
    }

    Timer {
        id: searchTimeoutTimer
        interval: 10000
        repeat: false
        onTriggered: {
            if (root.loading && root.activeSession && !root.activeSession.done) {
                root.loading = false;
            }
        }
    }

    Connections {
        target: MprisController
        function onLivePositionChanged() {
            if (!root.player || !root.player.isPlaying) {
                root.currentPosition = MprisController.livePosition;
            }
        }
        function onActivePlayerChanged() {
            if (!root.customPlayer) {
                root.triggerSearch();
            }
        }
    }

    Connections {
        target: root.player
        function onPositionChanged() {
            if (!root.player) return;
            if (root.player.isPlaying) {
                if (!positionTimer.running) root.applyPosition(root.player.position + root.syncOffset);
            } else {
                root.pendingJumpPosition = -1;
                root.currentPosition = root.player.position + root.syncOffset;
            }
        }
        function onTrackTitleChanged() {
            root.triggerSearch();
        }
        function onTrackArtistChanged() {
            root.triggerSearch();
        }
        function onPlaybackStateChanged() {
            root.triggerSearch();
        }
    }

    onCurrentTrackKeyChanged: {
        let ls = root.lastSong;
        if (ls && ls.key !== root.currentTrackKey && ls.dur > 0 && ls.maxPos >= ls.dur * 0.5) {
            root.pendingRate = ls;
            pendingTimer.restart();
        }
        triggerSearch();
    }
    onPlayerChanged: triggerSearch()

    property double lastAttemptAt: 0

    function resetPositionGuards() {
        root.pendingJumpPosition = -1;
        root.seekGuardUntil = 0;
    }

    function triggerSearch() {
        if (root.subscribers <= 0) return;
        if (ytProc.running && ytProc.key !== root.currentTrackKey) ytProc.running = false;

        if (!isMediaActive || currentTrackKey === "") {
            lastFetchedKey = "";
            activeFetchKey = "";
            activeSession = null;
            lyrics = [];
            hasLyrics = false;
            loading = false;
            searchTimeoutTimer.stop();
            return;
        }

        let isNewKey = currentTrackKey !== activeFetchKey;
        if (!isNewKey) {
            if (lyrics && lyrics.length > 0) return;
            if (loading) return;
            if (Date.now() - lastAttemptAt < 30000) return;
        }

        lastFetchedKey = currentTrackKey;
        activeFetchKey = currentTrackKey;
        if (activeSession) activeSession.done = true;
        bridgeKey = "";
        bestKey = "";
        bestOrigin = "";
        lyricsOrigin = "web";
        lookupBest(currentTrackKey);
        activeSession = null;
        searchTimeoutTimer.stop();
        cacheReadProcess.running = false;
        if (isNewKey) resetPositionGuards();
        lyrics = [];
        hasLyrics = false;
        loading = true;
        lastAttemptAt = Date.now();
        checkCacheAndFetch(currentTrackKey);
    }

    function checkCacheAndFetch(key) {
        let mem = getMemCache();
        if (mem && mem[key] && Array.isArray(mem[key]) && mem[key].length > 0) {
            applyLyrics(mem[key], key, false);
            return;
        }

        root.loading = true;
        cacheReadProcess.running = false;
        cacheReadProcess.targetKey = key;
        cacheReadProcess.running = true;
    }

    function saveLyricsToDisk(key, parsedList) {
        if (!key || !parsedList || parsedList.length === 0) return;
        try {
            let jsonStr = JSON.stringify(parsedList);
            if (saveLyricsProcess.running) {
                saveLyricsProcess.running = false;
            }
            saveLyricsProcess.pendingKey = key;
            saveLyricsProcess.pendingData = jsonStr;
            saveLyricsProcess.running = true;
        } catch (e) {}
    }

    function cleanString(str) {
        return LyricsMatch.cleanString(str);
    }

    function parseYrc(yrcText) {
        if (!yrcText || typeof yrcText !== "string") return null;
        let lines = yrcText.split("\n");
        let result = [];
        let hasAnyWord = false;

        for (let i = 0; i < lines.length; i++) {
            let line = lines[i].trim();
            if (!line) continue;

            let lineTime = -1;
            let content = "";

            let msMatch = line.match(/^\[(\d+),(\d+)\](.*)$/);
            if (msMatch) {
                lineTime = parseFloat(msMatch[1]) / 1000.0;
                content = msMatch[3];
            } else {
                let lrcMatch = line.match(/^\[(\d{1,2}):(\d{1,2}(?:\.\d{1,3})?)\](.*)$/);
                if (lrcMatch) {
                    lineTime = parseFloat(lrcMatch[1]) * 60 + parseFloat(lrcMatch[2]);
                    content = lrcMatch[3];
                }
            }

            if (lineTime < 0) continue;

            let words = [];
            let wordRegex = /\((\d+),(\d+)(?:,\d+)?\)([^\(\[\n\r]*)/g;
            let match;

            while ((match = wordRegex.exec(content)) !== null) {
                let rawStart = parseFloat(match[1]) / 1000.0;
                let dur = parseFloat(match[2]) / 1000.0;
                let wStart = (rawStart < lineTime) ? (lineTime + rawStart) : rawStart;
                let wEnd = wStart + (dur > 0 ? dur : 0.25);
                let wText = match[3];
                if (wText !== "") {
                    words.push({ time: wStart, endTime: wEnd, text: wText });
                }
            }

            if (words.length === 0) {
                let altRegex = /<(\d+),(\d+)>([^<]*)/g;
                while ((match = altRegex.exec(content)) !== null) {
                    let rawStart = parseFloat(match[1]) / 1000.0;
                    let dur = parseFloat(match[2]) / 1000.0;
                    let wStart = (rawStart < lineTime) ? (lineTime + rawStart) : rawStart;
                    let wEnd = wStart + (dur > 0 ? dur : 0.25);
                    let wText = match[3];
                    if (wText !== "") {
                        words.push({ time: wStart, endTime: wEnd, text: wText });
                    }
                }
            }

            let cleanLine = content.replace(/\(\d+,\d+(?:,\d+)?\)/g, "").replace(/<\d+,\d+>/g, "").trim();
            if (cleanLine === "" && words.length > 0) {
                cleanLine = words.map(function(w) { return w.text; }).join("").trim();
            }

            if (words.length > 0) {
                hasAnyWord = true;
                result.push({
                    time: lineTime,
                    text: cleanLine,
                    words: words
                });
            } else if (cleanLine !== "") {
                result.push({
                    time: lineTime,
                    text: cleanLine,
                    words: []
                });
            }
        }

        if (hasAnyWord && result.length > 0) {
            result.sort(function(a, b) { return a.time - b.time; });
            return result;
        }
        return null;
    }

    function parseEnhancedLrc(lrcText) {
        if (!lrcText || typeof lrcText !== "string") return null;
        let lines = lrcText.split("\n");
        let result = [];
        let hasAnyWord = false;

        for (let i = 0; i < lines.length; i++) {
            let line = lines[i].trim();
            if (!line) continue;

            let lineTimeMatch = line.match(/^\[(\d{1,2}):(\d{1,2}(?:\.\d{1,3})?)\]/);
            if (!lineTimeMatch) continue;

            let lineTime = parseFloat(lineTimeMatch[1]) * 60 + parseFloat(lineTimeMatch[2]);
            let content = line.replace(/^\[\d{1,2}:\d{1,2}(?:\.\d{1,3})?\]/, "").trim();

            let wordRegex = /<(\d{1,2}):(\d{1,2}(?:\.\d{1,3})?)>\s*([^<]*)/g;
            let wordMatch;
            let words = [];

            while ((wordMatch = wordRegex.exec(content)) !== null) {
                let wTime = parseFloat(wordMatch[1]) * 60 + parseFloat(wordMatch[2]);
                let wText = wordMatch[3].trim();
                if (wText !== "") {
                    words.push({ time: wTime, endTime: wTime + 0.3, text: wText });
                }
            }

            for (let j = 0; j < words.length - 1; j++) {
                words[j].endTime = words[j + 1].time;
            }

            if (words.length > 0) {
                hasAnyWord = true;
                let cleanLine = content.replace(/<\d{1,2}:\d{1,2}(?:\.\d{1,3})?>/g, " ").replace(/\s+/g, " ").trim();
                result.push({
                    time: lineTime,
                    text: cleanLine,
                    words: words
                });
            } else {
                result.push({
                    time: lineTime,
                    text: content.trim(),
                    words: []
                });
            }
        }

        if (hasAnyWord && result.length > 0) {
            result.sort(function(a, b) { return a.time - b.time; });
            return result;
        }
        return null;
    }

    function parseWordSynced(raw) {
        if (!raw) return null;
        let data = raw;
        if (typeof raw === "string") {
            let trimmed = raw.trim();
            if (trimmed.startsWith("{") || trimmed.startsWith("[")) {
                try {
                    data = JSON.parse(trimmed);
                } catch(e) {
                    data = null;
                }
            }
        }

        if (data && typeof data === "object") {
            let linesArr = Array.isArray(data) ? data : (data.lines || data.lyrics || data.sync || null);
            if (Array.isArray(linesArr) && linesArr.length > 0) {
                let parsed = [];
                for (let i = 0; i < linesArr.length; i++) {
                    let l = linesArr[i];
                    let lineTime = 0;
                    if (l.time !== undefined) lineTime = parseFloat(l.time);
                    else if (l.start_ms !== undefined) lineTime = parseFloat(l.start_ms) / 1000;
                    else if (l.startTime !== undefined) lineTime = parseFloat(l.startTime) / 1000;
                    else if (l.start !== undefined) lineTime = parseFloat(l.start) > 1000 ? parseFloat(l.start) / 1000 : parseFloat(l.start);

                    let wordsArr = l.words || l.syllables || [];
                    let words = [];
                    let lineText = l.text || l.line || "";

                    if (Array.isArray(wordsArr) && wordsArr.length > 0) {
                        for (let j = 0; j < wordsArr.length; j++) {
                            let w = wordsArr[j];
                            let wTime = lineTime;
                            if (w.time !== undefined) wTime = parseFloat(w.time);
                            else if (w.start_ms !== undefined) wTime = parseFloat(w.start_ms) / 1000;
                            else if (w.startTime !== undefined) wTime = parseFloat(w.startTime) / 1000;
                            else if (w.start !== undefined) wTime = parseFloat(w.start) > 1000 ? parseFloat(w.start) / 1000 : parseFloat(w.start);

                            let wEnd = wTime + 0.3;
                            if (w.endTime !== undefined) wEnd = parseFloat(w.endTime) > 1000 ? parseFloat(w.endTime) / 1000 : parseFloat(w.endTime);
                            else if (w.end_ms !== undefined) wEnd = parseFloat(w.end_ms) / 1000;
                            else if (w.duration !== undefined) wEnd = wTime + (parseFloat(w.duration) > 1000 ? parseFloat(w.duration) / 1000 : parseFloat(w.duration));

                            let wText = w.text !== undefined ? w.text : (w.word !== undefined ? w.word : "");
                            if (wText !== "") {
                                words.push({ time: wTime, endTime: wEnd, text: wText });
                            }
                        }

                        for (let j = 0; j < words.length - 1; j++) {
                            if (words[j].endTime <= words[j].time) {
                                words[j].endTime = words[j + 1].time;
                            }
                        }
                    }

                    if (words.length > 0 && lineText === "") {
                        lineText = words.map(function(item) { return item.text; }).join(" ").trim();
                    }

                    if (words.length > 0 || lineText !== "") {
                        if (words.length > 0 && lineTime === 0) {
                            lineTime = words[0].time;
                        }
                        parsed.push({
                            time: lineTime,
                            text: lineText,
                            words: words
                        });
                    }
                }

                if (parsed.length > 0 && parsed.some(function(p) { return p.words && p.words.length > 0; })) {
                    parsed.sort(function(a, b) { return a.time - b.time; });
                    return parsed;
                }
            }
        }

        if (typeof raw === "string") {
            return parseEnhancedLrc(raw);
        }

        return null;
    }

    function parseWordLevelLyrics(raw) {
        if (!raw) return null;
        let res = parseYrc(raw);
        if (res && res.length > 0) return res;
        res = parseWordSynced(raw);
        if (res && res.length > 0) return res;
        return null;
    }

    function parseLrc(lrcText) {
        if (!lrcText || typeof lrcText !== "string") return [];
        let lines = lrcText.split("\n");
        let result = [];
        let timeRegex = /\[(\d{1,2}):(\d{1,2}(?:\.\d{1,3})?)\]/g;

        for (let i = 0; i < lines.length; i++) {
            let line = lines[i].trim();
            if (!line) continue;

            let times = [];
            let match;
            timeRegex.lastIndex = 0;

            while ((match = timeRegex.exec(line)) !== null) {
                times.push(parseFloat(match[1]) * 60 + parseFloat(match[2]));
            }

            if (times.length > 0) {
                let text = line.replace(/\[\d{1,2}:\d{1,2}(?:\.\d{1,3})?\]/g, "").trim();
                for (let j = 0; j < times.length; j++) {
                    result.push({ time: times[j], text: text, words: [] });
                }
            }
        }

        result.sort(function(a, b) { return a.time - b.time; });
        return result;
    }

    function applyLyrics(parsedList, key, shouldSaveToDisk, fromBridge, fromBest) {
        if (key !== root.activeFetchKey) return;
        if (root.bestKey === key && fromBest !== true) return;
        if (root.bridgeKey === key && fromBridge !== true) return;
        root.lyricsOrigin = fromBest === true ? ("best:" + root.bestOrigin) : (fromBridge === true ? root.bridgeOriginHint : "web");
        searchTimeoutTimer.stop();
        root.lyrics = normalizeBackground(parsedList);
        root.hasLyrics = !!parsedList && parsedList.length > 0;
        root.loading = false;
        if (root.hasLyrics) {
            let mem = getMemCache();
            if (mem) mem[key] = parsedList;
            if (shouldSaveToDisk !== false) {
                saveLyricsToDisk(key, parsedList);
            }
        }
    }

    function checkCompletion(session) {
        if (session.key !== root.activeFetchKey || session.done) return;
        if (session.netEaseDone && session.lrclibDone) {
            session.done = true;
            searchTimeoutTimer.stop();
            let hadLine = !!(session.lineCandidate && session.lineCandidate.length > 0);
            if (hadLine) {
                applyLyrics(session.lineCandidate, session.key, true);
            } else {
                root.loading = false;
                root.hasLyrics = false;
                root.lyrics = [];
            }
            // no word-by-word lyrics: try YouTube CC (real word timing)
            if (!session.hasWordLyrics) startYtLyrics(session, hadLine);
        }
    }

    // ---- extra source: YouTube subtitles (CC) via ~/.local/bin/yt-lyrics ----
    // Optional, not shipped with Astrax: if the tool is missing this returns
    // nothing and the NetEase/lrclib lyrics stay. Only runs when those didn't give word-by-word;
    // line lyrics stay until a result arrives and are only replaced if it has per-word timing.
    // Spicy (bridge) has priority over everything.
    property string ytWordsKey: ""

    function hasWordTiming(list) {
        if (!Array.isArray(list)) return false;
        for (let i = 0; i < list.length; i++) {
            if (list[i].words && list[i].words.length > 0) return true;
        }
        return false;
    }

    function startYtLyrics(session, hadLine) {
        // Spicy with word-by-word is already the best; if Spicy only has lines, YouTube can improve it
        if ((root.bridgeKey === session.key && hasWordTiming(root.lyrics)) || root.bestKey === session.key || root.subscribers <= 0) return;
        ytProc.running = false;
        ytProc.key = session.key;
        ytProc.hadLine = hadLine;
        ytProc.command = ["bash", "-c", 'exec "$HOME/.local/bin/yt-lyrics" "$@"', "--",
                          session.rawArtist || session.artist, session.rawTitle || session.title,
                          String(Math.round(session.durationSec || 0))];
        if (!hadLine) root.loading = true;
        ytProc.running = true;
    }

    function onYtResult(key, text, hadLine) {
        if (key !== root.activeFetchKey) return;
        let list = [];
        try { list = JSON.parse(text.trim() || "[]"); } catch (e) { list = []; }
        let hasWords = hasWordTiming(list);
        if (root.bridgeKey === key && hasWordTiming(root.lyrics)) return;
        if (list.length >= 3 && (hasWords || !hadLine)) {
            if (hasWords) root.ytWordsKey = key;
            root.bridgeOriginHint = "youtube";
            applyLyrics(list, key, true, true);
        } else if (!hadLine) {
            root.loading = false;
        }
    }

    Process {
        id: ytProc
        property string key: ""
        property bool hadLine: false
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.onYtResult(ytProc.key, this.text, ytProc.hadLine)
        }
    }

    function applyLrclibRecord(resp, session) {
        if (!resp) return false;
        let rawLyricsFile = resp.lyricsfile || resp.lyricsFile || resp.lyrics_file;
        let wordLyrics = null;
        try {
            wordLyrics = parseWordLevelLyrics(rawLyricsFile) || parseWordLevelLyrics(resp.syncedLyrics);
        } catch (e) {
            wordLyrics = null;
        }
        if (wordLyrics && wordLyrics.length > 0) {
            session.hasWordLyrics = true;
            session.done = true;
            session.lrclibDone = true;
            applyLyrics(wordLyrics, session.key, true);
            return true;
        }
        if (resp.syncedLyrics && String(resp.syncedLyrics).trim() !== "") {
            let lines = parseLrc(resp.syncedLyrics);
            if (lines && lines.length > 0) {
                // Apply immediately — do not wait for NetEase / do not keep a weak first hit
                session.lineCandidate = lines;
                session.lrclibDone = true;
                session.done = true;
                applyLyrics(lines, session.key, true);
                return true;
            }
        }
        return false;
    }

    function fetchLyrics(artist, title, requestKey) {
        if (requestKey !== root.currentTrackKey || requestKey !== root.activeFetchKey) return;
        loading = true;
        hasLyrics = false;
        lyrics = [];

        let cleanT = cleanString(title);
        let cleanA = cleanString(artist);
        let album = "";
        try {
            if (root.player && root.player.trackAlbum)
                album = String(root.player.trackAlbum || "");
            else if (root.player && root.player.metadata && root.player.metadata["xesam:album"])
                album = String(root.player.metadata["xesam:album"] || "");
        } catch (e) {}
        album = cleanString(album);

        if (activeSession) activeSession.done = true;

        let session = {
            key: requestKey,
            artist: cleanA,
            title: cleanT !== "" ? cleanT : title,
            rawTitle: title || "",
            rawArtist: artist || "",
            album: album,
            durationSec: getPlayerDurationSec(),
            done: false,
            hasWordLyrics: false,
            netEaseDone: false,
            lrclibDone: false,
            lineCandidate: null
        };

        activeSession = session;
        searchTimeoutTimer.restart();

        fetchNetEase(session);
        fetchLrclib(session);
    }

    function fetchNetEase(session) {
        let query = (session.artist + " " + session.title).trim();
        if (query === "") query = session.title;

        // cloudsearch is generally more reliable than the legacy web search endpoint
        let url = "https://music.163.com/api/cloudsearch/pc?s=" + encodeURIComponent(query) + "&type=1&limit=8&offset=0";
        let xhr = new XMLHttpRequest();
        xhr.open("GET", url);
        xhr.setRequestHeader("Referer", "https://music.163.com");
        xhr.setRequestHeader("User-Agent", "Mozilla/5.0");

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (session.key !== root.activeFetchKey || session.done) return;

            if (xhr.status === 200) {
                try {
                    let resp = JSON.parse(xhr.responseText);
                    let songs = resp.result && resp.result.songs ? resp.result.songs : [];
                    let bestSong = pickBestNetEaseSong(songs, session);

                    if (bestSong && bestSong.id) {
                        fetchNetEaseLyric(bestSong.id, session);
                        return;
                    }
                } catch(e) {}
            }

            fetchNetEaseLegacy(session);
        };

        xhr.send();
    }

    function fetchNetEaseLegacy(session) {
        if (session.key !== root.activeFetchKey || session.done) return;
        let query = (session.artist + " " + session.title).trim();
        if (query === "") query = session.title;
        let url = "https://music.163.com/api/search/get/web?csrf_token=&hlpretag=&hlposttag=&s=" + encodeURIComponent(query) + "&type=1&offset=0&total=true&limit=8";
        let xhr = new XMLHttpRequest();
        xhr.open("GET", url);
        xhr.setRequestHeader("Referer", "https://music.163.com");
        xhr.setRequestHeader("User-Agent", "Mozilla/5.0");

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (session.key !== root.activeFetchKey || session.done) return;

            if (xhr.status === 200) {
                try {
                    let resp = JSON.parse(xhr.responseText);
                    let songs = resp.result && resp.result.songs ? resp.result.songs : [];
                    let bestSong = pickBestNetEaseSong(songs, session);
                    if (bestSong && bestSong.id) {
                        fetchNetEaseLyric(bestSong.id, session);
                        return;
                    }
                } catch(e) {}
            }

            session.netEaseDone = true;
            checkCompletion(session);
        };

        xhr.send();
    }

    function fetchNetEaseLyric(songId, session) {
        let url = "https://music.163.com/api/song/lyric?id=" + songId + "&lv=1&kv=1&tv=-1&yv=1";
        let xhr = new XMLHttpRequest();
        xhr.open("GET", url);
        xhr.setRequestHeader("Referer", "https://music.163.com");
        xhr.setRequestHeader("User-Agent", "Mozilla/5.0");

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (session.key !== root.activeFetchKey || session.done) return;

            if (xhr.status === 200) {
                try {
                    let resp = JSON.parse(xhr.responseText);
                    let wordLyrics = null;

                    if (resp.yrc && resp.yrc.lyric) {
                        wordLyrics = parseWordLevelLyrics(resp.yrc.lyric);
                    }
                    if (!wordLyrics && resp.klyric && resp.klyric.lyric) {
                        wordLyrics = parseWordLevelLyrics(resp.klyric.lyric);
                    }

                    if (wordLyrics && wordLyrics.length > 0) {
                        session.hasWordLyrics = true;
                        session.done = true;
                        applyLyrics(wordLyrics, session.key, true);
                        return;
                    }

                    if (resp.lrc && resp.lrc.lyric) {
                        let lines = parseLrc(resp.lrc.lyric);
                        if (lines && lines.length > 0) {
                            if (!session.lineCandidate || lines.length > session.lineCandidate.length) {
                                session.lineCandidate = lines;
                            }
                        }
                    }
                } catch(e) {}
            }

            session.netEaseDone = true;
            checkCompletion(session);
        };

        xhr.send();
    }

    function fetchLrclib(session) {
        if (session.artist === "" || session.title === "") {
            fetchLrclibSearch(session, 0);
            return;
        }

        // Do NOT send album_name on /get: players (VK/Firefox/etc) often expose a
        // playlist/collection name that does not match lrclib and causes 404.
        let params = "track_name=" + encodeURIComponent(session.title) + "&artist_name=" + encodeURIComponent(session.artist);
        if (session.durationSec && session.durationSec > 1) {
            params += "&duration=" + encodeURIComponent(String(Math.round(session.durationSec)));
        }

        let url = "https://lrclib.net/api/get?" + params;
        let xhr = new XMLHttpRequest();
        xhr.open("GET", url);
        xhr.setRequestHeader("Lrclib-Client", "serpantinum-shell");

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (session.key !== root.activeFetchKey || session.done) return;

            if (xhr.status === 200) {
                try {
                    let resp = JSON.parse(xhr.responseText);
                    if (applyLrclibRecord(resp, session))
                        return;
                } catch(e) {}
            }

            fetchLrclibSearch(session, 0);
        };

        xhr.send();
    }

    function fetchLrclibSearch(session, attempt) {
        if (session.key !== root.activeFetchKey || session.done) return;

        let uniq = LyricsMatch.buildLrclibSearchQueries(session);
        if (uniq.length === 0) {
            session.lrclibDone = true;
            checkCompletion(session);
            return;
        }

        let idx = Math.max(0, attempt || 0);
        if (idx >= uniq.length) {
            session.lrclibDone = true;
            checkCompletion(session);
            return;
        }

        let url = "https://lrclib.net/api/search?q=" + encodeURIComponent(uniq[idx]);
        let xhr = new XMLHttpRequest();
        xhr.open("GET", url);
        xhr.setRequestHeader("Lrclib-Client", "serpantinum-shell");

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (session.key !== root.activeFetchKey || session.done) return;

            if (xhr.status === 200) {
                try {
                    let list = JSON.parse(xhr.responseText);
                    let best = LyricsMatch.pickBestLrclibResult(list, session);
                    if (best) {
                        if (applyLrclibRecord(best, session))
                            return;
                        if (best.id) {
                            fetchLrclibById(best, session, uniq, idx);
                            return;
                        }
                    }
                } catch(e) {}
            }

            fetchLrclibSearch(session, idx + 1);
        };

        xhr.send();
    }

    function fetchLrclibById(best, session, queries, idx) {
        // Canonical /get using the matched record's own metadata (album from lrclib is OK)
        let params = "track_name=" + encodeURIComponent(best.trackName || best.name || session.title)
            + "&artist_name=" + encodeURIComponent(best.artistName || session.artist);
        if (best.albumName) params += "&album_name=" + encodeURIComponent(best.albumName);
        if (best.duration) params += "&duration=" + encodeURIComponent(String(Math.round(Number(best.duration))));

        let url = "https://lrclib.net/api/get?" + params;
        let xhr = new XMLHttpRequest();
        xhr.open("GET", url);
        xhr.setRequestHeader("Lrclib-Client", "serpantinum-shell");

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (session.key !== root.activeFetchKey || session.done) return;

            let applied = false;
            if (xhr.status === 200) {
                try {
                    applied = applyLrclibRecord(JSON.parse(xhr.responseText), session);
                } catch(e) {}
            }
            if (!applied)
                applied = applyLrclibRecord(best, session);
            if (session.done) return;
            if (applied) {
                session.lrclibDone = true;
                checkCompletion(session);
                return;
            }
            fetchLrclibSearch(session, idx + 1);
        };

        xhr.send();
    }

    function loadLocalLyricsFile(filePath) {
        if (!filePath || filePath.trim() === "" || !root.isMediaActive) return;
        let cleanPath = filePath.toString();
        if (cleanPath.startsWith("file://")) {
            cleanPath = cleanPath.substring(7);
        }
        try {
            cleanPath = decodeURIComponent(cleanPath);
        } catch (e) {}

        let key = root.currentTrackKey;
        fileReadProcess.targetKey = key;
        fileReadProcess.command = ["cat", cleanPath];
        fileReadProcess.running = false;
        fileReadProcess.running = true;
    }

    function loadLocalLyricsContent(content, key) {
        if (!content || key !== root.currentTrackKey) return;
        let parsed = parseWordLevelLyrics(content);
        if (!parsed || parsed.length === 0) {
            parsed = parseLrc(content);
        }
        if (parsed && parsed.length > 0) {
            if (root.activeSession) {
                root.activeSession.done = true;
            }
            root.activeFetchKey = key;
            root.lastFetchedKey = key;
            applyLyrics(parsed, key, true);
        }
    }

    Process {
        id: cacheReadProcess
        property string targetKey: ""
        command: [
            "bash",
            "-c",
            'CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/serpantinum/lyrics"; HASH=$(echo -n "$1" | md5sum | cut -d" " -f1); FILE="$CACHE_DIR/${HASH}.json"; printf "%s\\n" "$1"; if [ -f "$FILE" ] && [ -s "$FILE" ]; then cat "$FILE"; fi',
            "--",
            targetKey
        ]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let raw = this.text;
                let nl = raw.indexOf("\n");
                let echoedKey = nl < 0 ? raw : raw.substring(0, nl);
                let content = nl < 0 ? "" : raw.substring(nl + 1).trim();
                let key = cacheReadProcess.targetKey;
                if (echoedKey !== key.split("\n")[0]) return;
                if (key !== root.currentTrackKey || key !== root.activeFetchKey) return;

                if (content !== "") {
                    try {
                        let parsed = JSON.parse(content);
                        if (Array.isArray(parsed) && parsed.length > 0) {
                            let mem = root.getMemCache();
                            if (mem) mem[key] = parsed;
                            root.applyLyrics(parsed, key, false);
                            return;
                        }
                    } catch(e) {}
                }

                root.fetchLyrics(root.trackArtist, root.trackTitle, key);
            }
        }
    }

    Timer {
        interval: 1500
        repeat: true
        running: root.subscribers > 0 && root.isMediaActive && root.bridgeKey !== root.currentTrackKey
        onTriggered: if (!bridgeReadProcess.running) bridgeReadProcess.running = true
    }

    Process {
        id: bridgeReadProcess
        command: ["bash", "-c", 'cat "$HOME/.cache/spicy-bridge/current.json" 2>/dev/null; echo; cat "$HOME/.cache/liner-bridge/current.json" 2>/dev/null']
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let key = root.currentTrackKey;
                let obj = null;
                for (const raw of this.text.split("\n")) {
                    // spicy-bridge (Spotify) and liner-bridge keep their own files; an old one from the
                    // other player must not win just because the same song once played there
                    try { let o = JSON.parse(raw); if (o && o.key === key && ((o.player === "liner") === root.isLinerPlayer)) { obj = o; break; } } catch (e) {}
                }
                if (!obj) return;
                try {
                    if (!obj || obj.key !== key || key !== root.activeFetchKey) return;
                    if (!Array.isArray(obj.lyrics) || obj.lyrics.length === 0) return;
                    if (root.ytWordsKey === key && !root.hasWordTiming(obj.lyrics)) { root.bridgeKey = key; return; }
                    root.bridgeKey = key;
                    root.bridgeOriginHint = (obj.player === "liner") ? "liner" : "spotify";
                    root.applyLyrics(obj.lyrics, key, true, true);
                } catch(e) {}
            }
        }
    }

    Process {
        id: saveLyricsProcess
        property string pendingKey: ""
        property string pendingData: ""
        command: [
            "bash",
            "-c",
            'CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/serpantinum/lyrics"; mkdir -p "$CACHE_DIR"; HASH=$(echo -n "$1" | md5sum | cut -d" " -f1); printf "%s" "$2" > "$CACHE_DIR/${HASH}.json"',
            "--",
            pendingKey,
            pendingData
        ]
        running: false
    }

    Process {
        id: fileReadProcess
        property string targetKey: ""
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let content = this.text;
                if (fileReadProcess.targetKey === root.currentTrackKey && content.trim() !== "") {
                    root.loadLocalLyricsContent(content, fileReadProcess.targetKey);
                }
            }
        }
    }
}
