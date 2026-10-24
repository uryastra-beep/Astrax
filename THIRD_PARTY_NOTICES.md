# Third-party notices

## @braccato/parsers 0.2.1 (MIT)

Bundled (minified) inside `scripts/liner/page.bundle.js`, which `liner-bridge` injects into Liner's
page to read the lyric formats Liner downloads. Source: https://github.com/better-lyrics/braccato

    MIT License
    
    Copyright (c) 2025 Better Lyrics
    
    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:
    
    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.
    
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.

## Apple-style app icons (optional download, NOT in the Astrax source)

`astrax-icons install` downloads app-icon artwork to `~/.local/share/astrax/icons/`. It is official
App Store artwork (Apple iTunes Lookup API) plus a few macOS-style equivalents. The artwork belongs
to its respective owners (Apple Inc. and each app's developer) and is not covered by Astrax's
license. It is not in this repository: it is published only as a separate, optional release asset
("packs") that you choose to download, and each download records its source in `SOURCES.json`.
Astrax itself only contains the code that looks the icons up (`AppleAppIcons.js`, `AppIcon.qml`),
and falls back to the normal system icons when the pack isn't installed. If you are a rights holder
and want an icon removed, open an issue and it will be taken out of the pack.

## iPhone notifications / Bluetooth audio bridge (optional download, NOT in the Astrax source)

`astrax-iphone install` downloads a separate pack (release asset "packs") with `ancs-linux`, a
modified build of https://github.com/kmod-midori/ancs-linux (MIT, Copyright (c) 2024 Midori Kochiya;
the pack carries its LICENSE and the modified source), plus a few helper scripts. The island works
without it.
