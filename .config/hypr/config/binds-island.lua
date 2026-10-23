-- Dynamic Island: announce pastes. Wayland has no "paste happened" event, so Ctrl+V and
-- Ctrl+Shift+V also tell the island. The binds are non_consuming: the keys still reach
-- the focused app exactly as before. (Copies are seen by the island itself, via wl-paste --watch.)
local announce = hl.dsp.exec_cmd("qs -c astrax-island ipc call island paste")
hl.bind("CONTROL + V", announce, { non_consuming = true })
hl.bind("CONTROL + SHIFT + V", announce, { non_consuming = true })
