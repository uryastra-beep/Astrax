-- Dynamic Island: announce pastes. Wayland has no "paste happened" event, so Ctrl+V and
-- Ctrl+Shift+V also tell the island. The binds are non_consuming: the keys still reach
-- the focused app exactly as before. (Copies are seen by the island itself, via wl-paste --watch.)
local announce = hl.dsp.exec_cmd("qs -c astrax-island ipc call island paste")
hl.bind("CONTROL + V", announce, { non_consuming = true })
hl.bind("CONTROL + SHIFT + V", announce, { non_consuming = true })

-- Outside clicks close an expanded island without taking the click from the app.
-- No mouse-grab flag: these are ordinary, non-consuming button notifications.
local outsideClick = hl.dsp.exec_cmd("qs -c astrax-island ipc call island outsideClick")
for _, button in ipairs({ "mouse:272", "mouse:273", "mouse:274" }) do
    hl.bind(button, outsideClick, {
        non_consuming = true,
        description = "Dynamic Island: outside click"
    })
end
