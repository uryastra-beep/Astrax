import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

// Everything that can make the island react. Each source emits `event(ev)`:
//   kind      string   unique name of the source ("volume", "usb", ...)
//   layout    string   "hud" (icon + bar), "status" (icon + title + detail), "notif"
//   coalesce  string   events with the same value replace each other in place
//   glyph     string   Nerd Font glyph (hud/status)
//   title, detail      text
//   value     real     0..1 for hud bars, -1 = no bar
//   accent    color    tint for the glyph
//   duration  int      ms on screen
Item {
    id: src

    property var cfg: ({})
    signal event(var ev)

    readonly property string serpDir: Quickshell.env("HOME") + "/.local/share/serpantinum/src/quickshell"
    readonly property string eventFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/astrax-island.events"

    // nothing fires during the first moments (initial values settling)
    property bool ready: false
    Timer { interval: 2500; running: true; onTriggered: src.ready = true }

    function on(key) { return src.ready && src.cfg[key] !== false; }

    // ---------------------------------------------------------------- audio
    PwObjectTracker { objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource] }
    readonly property var sinkAudio: Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.audio : null
    readonly property var micAudio: Pipewire.defaultAudioSource ? Pipewire.defaultAudioSource.audio : null

    function volGlyph(v, muted) {
        if (muted || v <= 0) return "󰖁";
        return v < 0.34 ? "󰕿" : v < 0.67 ? "󰖀" : "󰕾";
    }
    function emitVolume() {
        if (!src.on("showVolume") || !src.sinkAudio) return;
        const v = src.sinkAudio.volume, m = src.sinkAudio.muted;
        src.event({ kind: "volume", layout: "hud", coalesce: "audio", glyph: volGlyph(v, m),
                    title: m ? "Muted" : "Volume", value: m ? 0 : Math.min(1, v), detail: m ? "" : Math.round(v * 100) + "",
                    accent: "#ffffff", duration: 1600 });
    }
    function emitMic() {
        if (!src.on("showMic") || !src.micAudio) return;
        const v = src.micAudio.volume, m = src.micAudio.muted;
        src.event({ kind: "mic", layout: "hud", coalesce: "audio", glyph: m ? "󰍭" : "󰍬",
                    title: m ? "Mic off" : "Microphone", value: m ? 0 : Math.min(1, v), detail: m ? "" : Math.round(v * 100) + "",
                    accent: m ? "#ff453a" : "#ffffff", duration: 1600 });
    }
    Connections { target: src.sinkAudio; function onVolumeChanged() { src.emitVolume(); } function onMutedChanged() { src.emitVolume(); } }
    Connections { target: src.micAudio; function onVolumeChanged() { src.emitMic(); } function onMutedChanged() { src.emitMic(); } }

    // ----------------------------------------------------------- brightness
    property int lastBri: -1
    Process {
        running: true
        command: ["setpriv", "--pdeathsig", "TERM", "bash", src.serpDir + "/../scripts/brightness.sh", "watch"]
        stdout: SplitParser { onRead: briDebounce.restart() }
    }
    Timer { id: briDebounce; interval: 40; onTriggered: { briGet.running = false; briGet.running = true; } }
    Process {
        id: briGet
        command: ["bash", src.serpDir + "/../scripts/brightness.sh", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseInt(this.text.trim());
                if (isNaN(v)) return;
                const first = src.lastBri < 0;
                const changed = v !== src.lastBri;
                src.lastBri = v;
                if (first || !changed || !src.on("showBrightness")) return;
                src.event({ kind: "brightness", layout: "hud", coalesce: "brightness", glyph: v < 34 ? "󰃞" : v < 67 ? "󰃟" : "󰃠",
                            title: "Brightness", value: v / 100, detail: v + "", accent: "#ffd60a", duration: 1600 });
            }
        }
    }

    // ------------------------------------------------------ caps / num lock
    Process {
        running: true
        command: ["setpriv", "--pdeathsig", "TERM", "bash", src.serpDir + "/watchers/kb_locks.sh", "watch"]
        stdout: SplitParser {
            onRead: data => {
                const p = data.trim().split(/\s+/);
                if (p.length < 2 || !src.on("showLocks")) return;
                const isOn = p[1] === "1" || p[1] === "on";
                const name = p[0] === "capslock" ? "Caps Lock" : p[0] === "numlock" ? "Num Lock" : "";
                if (!name) return;
                src.event({ kind: p[0], layout: "status", glyph: p[0] === "capslock" ? "󰪛" : "󰎠", title: name,
                            detail: isOn ? "On" : "Off", accent: isOn ? "#ff9f0a" : "#8e8e93", duration: 1500 });
            }
        }
    }

    // -------------------------------------------------------- airplane mode
    readonly property bool airplane: !Networking.wifiEnabled && !Boolean(Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled)
    onAirplaneChanged: {
        if (!src.on("showAirplane")) return;
        src.event({ kind: "airplane", layout: "status", glyph: "󰀝", title: "Airplane Mode",
                    detail: src.airplane ? "On" : "Off", accent: src.airplane ? "#ff9f0a" : "#8e8e93", duration: 1800 });
    }

    // ------------------------------------------------------------- charging
    readonly property var bat: UPower.displayDevice
    readonly property int batState: bat.ready ? bat.state : -1
    readonly property int batPct: bat.ready ? Math.round(bat.percentage * 100) : -1
    property int prevBatState: -2
    property int lowStage: 0
    onBatStateChanged: {
        const prev = src.prevBatState;
        src.prevBatState = src.batState;
        if (prev === -2 || !bat.isLaptopBattery || !src.on("showCharging")) return;
        if (src.batState === UPowerDeviceState.Charging && prev !== UPowerDeviceState.Charging)
            src.event({ kind: "charge", layout: "status", glyph: "󱐋", title: "Charging", detail: src.batPct + "%",
                        accent: "#30d158", duration: 2400, battery: src.batPct });
        else if (src.batState === UPowerDeviceState.Discharging && prev !== UPowerDeviceState.Discharging)
            src.event({ kind: "charge", layout: "status", glyph: "󰂃", title: "On battery", detail: src.batPct + "%",
                        accent: "#ffffff", duration: 2000, battery: src.batPct });
        else if (src.batState === UPowerDeviceState.FullyCharged)
            src.event({ kind: "charge", layout: "status", glyph: "󰂅", title: "Fully charged", detail: "100%",
                        accent: "#30d158", duration: 2400, battery: 100 });
    }
    onBatPctChanged: {
        if (!bat.isLaptopBattery || !src.on("showCharging") || src.batState !== UPowerDeviceState.Discharging) {
            if (src.batPct > 25) src.lowStage = 0;
            return;
        }
        if (src.batPct <= 10 && src.lowStage < 2) {
            src.lowStage = 2;
            src.event({ kind: "lowbat", layout: "status", glyph: "󰂎", title: "Battery critical", detail: src.batPct + "%",
                        accent: "#ff453a", duration: 5000, battery: src.batPct });
        } else if (src.batPct <= 20 && src.lowStage < 1) {
            src.lowStage = 1;
            src.event({ kind: "lowbat", layout: "status", glyph: "󰁻", title: "Low battery", detail: src.batPct + "%",
                        accent: "#ff9f0a", duration: 4000, battery: src.batPct });
        }
    }

    // ------------------------------------------------------------ bluetooth
    function btGlyph(icon) {
        if (!icon) return "󰂯";
        if (icon.indexOf("headset") >= 0 || icon.indexOf("headphone") >= 0) return "󰋋";
        if (icon.indexOf("speaker") >= 0 || icon.indexOf("audio-card") >= 0) return "󰓃";
        if (icon.indexOf("mouse") >= 0) return "󰍽";
        if (icon.indexOf("keyboard") >= 0) return "󰌌";
        if (icon.indexOf("gamepad") >= 0 || icon.indexOf("joystick") >= 0) return "󰖺";
        if (icon.indexOf("phone") >= 0) return "󰏲";
        return "󰂯";
    }
    Instantiator {
        model: Bluetooth.devices
        delegate: QtObject {
            id: dev
            required property var modelData
            readonly property bool isConnected: modelData.connected
            property bool seen: false
            onIsConnectedChanged: {
                if (!seen) { seen = true; return; }
                if (!src.on("showBluetooth")) return;
                const name = modelData.name || modelData.deviceName || "Bluetooth device";
                const bat = modelData.batteryAvailable ? Math.round(modelData.battery * 100) : -1;
                src.event({ kind: "bt:" + name, layout: "status", glyph: src.btGlyph(modelData.icon), title: name,
                            detail: isConnected ? (bat >= 0 ? "Connected · " + bat + "%" : "Connected") : "Disconnected",
                            accent: isConnected ? "#0a84ff" : "#8e8e93", duration: 2400 });
            }
            Component.onCompleted: seen = true
        }
    }

    // ------------------------------------------------------------------ usb
    property var usbProps: ({})
    Process {
        running: true
        command: ["setpriv", "--pdeathsig", "TERM", "udevadm", "monitor", "--udev", "--subsystem-match=usb", "--property"]
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim();
                if (line === "") {
                    const p = src.usbProps;
                    src.usbProps = {};
                    if (p.DEVTYPE !== "usb_device" || !p.ACTION) return;
                    if (p.ACTION !== "add" && p.ACTION !== "remove") return;
                    if (!src.on("showUsb")) return;
                    const clean = s => (s || "").replace(/_/g, " ").trim();
                    const name = clean(p.ID_MODEL_FROM_DATABASE) || clean(p.ID_MODEL) || clean(p.ID_VENDOR_FROM_DATABASE) || "USB device";
                    if (/\bhub\b/i.test(name) && p.ACTION === "add" && !p.ID_MODEL_FROM_DATABASE) return;
                    const added = p.ACTION === "add";
                    src.event({ kind: "usb:" + (p.DEVPATH || name), layout: "status", glyph: "󱇰", title: name,
                                detail: added ? "Connected" : "Removed", accent: added ? "#30d158" : "#8e8e93", duration: 2400 });
                    return;
                }
                const eq = line.indexOf("=");
                if (eq > 0) { const o = src.usbProps; o[line.substring(0, eq)] = line.substring(eq + 1); src.usbProps = o; }
            }
        }
    }

    function isAlarm(n) {
        // Match the sending app or explicit system hints, never words in a chat.
        const source = [n.sourceApp, n.app, n.entry].map(x => String(x || "").toLowerCase().trim());
        const clockApp = source.some(x => /^(?:org\.gnome\.clocks|org\.kde\.kclock|com\.apple\.mobiletimer(?:d)?|mobiletimer(?:d)?|gnome clocks|clocks?|reloj(?:es)?|kclock|alarmas?|alarms?)$/.test(x));
        const icon = String(n.icon || "").toLowerCase();
        const sound = String(n.soundName || "").toLowerCase();
        const category = String(n.category || "").toLowerCase();
        return clockApp || category === "alarm" || category === "alarm-clock"
            || /^(?:alarm-clock-elapsed|alarm-clock|alarm-timer-elapsed)$/.test(sound)
            || /^(?:alarm-clock|alarm-symbolic)$/.test(icon);
    }
    function emitAlarm(n) {
        src.event({ kind: "alarm", layout: "file", state: "alarm", coalesce: "alarm",
                    name: n.summary || "Alarm", sub: n.body || ((n.app || "Clock") + " · Ringing"),
                    glyph: "󰀠", uid: n.uid, actions: n.actions || [],
                    duration: (src.cfg.notifSeconds || 5) * 1000 });
    }

    // -------------------------------------------- notifications (from srp)
    // Serpantinum owns the org.freedesktop.Notifications server (so its history
    // panel keeps working) and appends one JSON object per line to eventFile.
    Process { running: true; command: ["sh", "-c", ": >> \"$1\"", "_", src.eventFile] }
    Process {
        running: true
        command: ["setpriv", "--pdeathsig", "TERM", "tail", "-n0", "-F", src.eventFile]
        stdout: SplitParser {
            onRead: data => {
                if (!src.on("showNotifications")) return;
                let n;
                try { n = JSON.parse(data); } catch (e) { return; }
                // scripts can push any event shape directly: {"layout":"status","glyph":"...","title":"..."}
                if (n.layout) { n.duration = n.duration || 2500; src.event(n); return; }
                if (src.isAlarm(n)) { src.emitAlarm(n); return; }
                src.event({ kind: "notif", layout: "notif", app: n.app || "", title: n.summary || "", detail: n.body || "",
                            icon: n.icon || "", image: n.image || "", uid: n.uid, actions: n.actions || [], urgent: n.urgency === 2,
                            duration: (src.cfg.notifSeconds || 5) * 1000 });
            }
        }
    }
}
