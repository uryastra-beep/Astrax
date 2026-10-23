.pragma library

function base(p) { return p.substring(p.lastIndexOf("/") + 1); }
function ext(p) { const b = base(p); const i = b.lastIndexOf("."); return i > 0 ? b.substring(i + 1).toLowerCase() : ""; }

// Nerd Font glyph for a file type
function glyphFor(p, isDir) {
    if (isDir) return "󰉋";
    const e = ext(p);
    if (["png","jpg","jpeg","gif","webp","svg","bmp","heic","avif"].indexOf(e) >= 0) return "󰋩";
    if (["mp4","mkv","mov","webm","avi","m4v"].indexOf(e) >= 0) return "󰈫";
    if (["mp3","flac","wav","ogg","m4a","opus","aac"].indexOf(e) >= 0) return "󰎆";
    if (e === "pdf") return "󰈦";
    if (["zip","rar","7z","tar","gz","xz","bz2","zst","iso"].indexOf(e) >= 0) return "󰗄";
    if (["doc","docx","odt","txt","md","rtf","pptx","xlsx","csv","ods"].indexOf(e) >= 0) return "󰈙";
    if (["py","js","ts","qml","rs","c","cpp","h","sh","lua","json","html","css","java","go"].indexOf(e) >= 0) return "󰅩";
    if (["exe","msi","appimage","deb","rpm","pkg"].indexOf(e) >= 0) return "󰏖";
    return "󰈔";
}
function fmtSize(b) {
    if (b < 1024) return b + " B";
    if (b < 1048576) return (b / 1024).toFixed(0) + " KB";
    if (b < 1073741824) return (b / 1048576).toFixed(b < 10485760 ? 1 : 0) + " MB";
    return (b / 1073741824).toFixed(2) + " GB";
}
