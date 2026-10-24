import QtQuick
import Quickshell
import Quickshell.Io

// A read-only view of Astrax's word timings and line-timing fallback.
Item {
    id: lyrics
    required property var player
    required property real position
    property string textFont: "Rubik"
    clip: true
    readonly property string requestKey: player ? JSON.stringify([
        player.dbusName, player.trackArtist || "", player.trackTitle || "",
        player.length || 0, String((player.metadata || {})["mpris:trackid"] || ""),
        String(player.identity || player.desktopEntry || "")]) : ""
    property var lines: []
    property bool helperMissing: false
    property var clockSample: ({})
    readonly property real syncedPosition: {
        const sample = clockSample;
        const age = Date.now() / 1000 - Number(sample.stamp || 0);
        // position is refreshed every visible frame; stale clock samples expire.
        const current = position;
        if (age < 0 || age > 3 || !isFinite(Number(sample.progress))) return current;
        if (sample.playing !== undefined && sample.playing !== player.isPlaying) return current;
        const rate = sample.rate !== undefined ? Number(sample.rate) : 1;
        return Number(sample.progress) + (player.isPlaying ? age * rate : 0);
    }
    readonly property int lineIndex: {
        let low = 0, high = lines.length - 1, found = -1;
        while (low <= high) {
            const mid = (low + high) >> 1;
            if (Number(lines[mid].time) <= syncedPosition) { found = mid; low = mid + 1; }
            else high = mid - 1;
        }
        return found;
    }
    readonly property var words: lineIndex >= 0 ? (lines[lineIndex].words || []) : []
    readonly property bool isLinerPlayer: !!player && /liner/i.test(String(player.identity || player.desktopEntry || ""))
    // Match Astrax: real word timings first, syllable-weighted estimation for LRC.
    readonly property string currentWord: lineIndex >= 0
        ? activeWordText(lines[lineIndex], syncedPosition) : ""
    opacity: currentWord !== "" ? 1 : 0

    readonly property bool englishLyrics: {
        let L = lyrics.lines;
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
        // "e" muda final en ingles (love, time): no suma silaba
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

    // Ritmo de la cancion (segundos por silaba): mediana de las lineas "apretadas"
    // (poco hueco hasta la siguiente), asi se calibra con el tempo/idioma real
    // de la cancion en vez de un valor fijo.
    readonly property real secPerSyllable: {
        let L = lyrics.lines;
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
        // percentil 35: las lineas con hueco inflan la tasa, las apretadas se acercan al canto real
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
        let nxt = (idx + 1 < lyrics.lines.length) ? lyrics.lines[idx + 1].time : start + total * secPerSyllable + 1;
        let gap = Math.max(0.8, nxt - start);
        // lo que dura el canto de la linea: no mas que el hueco, ni mas que
        // silabas * ritmo (los huecos largos son instrumental, no estiran la linea)
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

    // Palabra que esta sonando de una linea: la ultima que ya empezo (se queda
    // en ella durante los silencios); antes de la primera, la primera.
    function activeWordText(modelData, pos) {
        let ws = modelData.words;
        if (!ws || ws.length === 0) {
            // solo letra por linea: estimar la palabra segun silabas/ritmo
            let est = estimatedWord(modelData, lyrics.lineIndex, pos);
            return est !== "" ? est : "♪";
        }
        let idx = 0;
        for (let i = 0; i < ws.length; i++) {
            if (pos >= ws[i].time) idx = i; else break;
        }
        // igual que u-lyrc: el hueco ENTRE lineas (despues de la ultima palabra de la
        // linea y antes de la siguiente) muestra la nota, solo si la cancion tiene
        // letra (ya hay linea activa) y esta sonando. Los silencios dentro de la
        // linea mantienen la ultima palabra.
        let playing = !lyrics.player || lyrics.player.isPlaying;
        if (playing && pos > ws[ws.length - 1].endTime + 0.5) return "♫";
        // Liner (via liner-bridge) sends each word's syllables: the word builds up
        // as they are sung, "Cu" -> "Cuan" -> "Cuando"
        let syl = ws[idx].syl;
        if (lyrics.isLinerPlayer && syl && syl.length > 1) {
            let shown = syl[0].text;
            for (let k = 1; k < syl.length; k++) {
                if (pos >= syl[k].time) shown += syl[k].text; else break;
            }
            if (shown.trim() !== "") return shown.trim();
        }
        let t = ws[idx].text.trim();
        return t !== "" ? t : "♫";
    }


    onRequestKeyChanged: {
        lines = [];
        clockSample = ({});
        retryFeed.stop();
        feed.running = false;
        restartFeed.restart();
    }
    Component.onCompleted: restartFeed.restart()
    Timer {
        id: restartFeed
        interval: 80
        onTriggered: {
            if (!lyrics.requestKey) return;
            if (feed.running) return;
            feed.loadedKey = lyrics.requestKey;
            // The lyrics helper belongs to the optional iPhone/Bluetooth pack (`astrax-iphone install`).
            // Without it exit code 99 is returned and the island simply shows no lyrics.
            if (lyrics.helperMissing) return;
            feed.command = ["sh", "-c", "[ -f \"$1\" ] || exit 99; exec /usr/bin/python3 \"$1\" \"$2\"",
                            "sh", Quickshell.env("HOME") + "/.local/lib/iphone-notifications/island-lyrics.py", lyrics.requestKey];
            feed.running = true;
        }
    }
    Process {
        id: feed
        property string loadedKey: ""
        stdout: SplitParser {
            onRead: data => {
                try {
                    const message = JSON.parse(data);
                    if (message.key !== lyrics.requestKey) return;
                    if (message.kind === "lyrics") lyrics.lines = Array.isArray(message.data) ? message.data : [];
                    else if (message.kind === "progress") lyrics.clockSample = message.data || ({});
                } catch (e) {}
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 99) { lyrics.helperMissing = true; return; }
            if (!lyrics.requestKey) return;
            if (loadedKey === lyrics.requestKey) retryFeed.restart();
            else restartFeed.restart();
        }
    }
    Timer { id: retryFeed; interval: 2000; onTriggered: if (!feed.running) restartFeed.restart() }
    Text {
        anchors.fill: parent
        text: lyrics.currentWord
        textFormat: Text.PlainText
        color: "#f5f5f7"
        font.family: lyrics.textFont
        font.pixelSize: 24
        font.weight: Font.DemiBold
        fontSizeMode: Text.Fit
        minimumPixelSize: 11
        maximumLineCount: 1
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
    }
}
