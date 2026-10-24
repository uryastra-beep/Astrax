-- Separate layer rule; leaves DI and SRP materials untouched.
if _G.astraxMacDockGlassRule then pcall(function() _G.astraxMacDockGlassRule:set_enabled(false) end) end
_G.astraxMacDockGlassRule = hl.layer_rule({
    name = "astrax-macos-dock-blur",
    match = { namespace = "^astrax-macos-dock$" },
    blur = true,
    ignore_alpha = 0.05,
    xray = false,
})
