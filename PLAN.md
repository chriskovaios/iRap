# Plan: standalone iOS-style lyric writing app (single HTML file)

## Context

Build one self-contained `index.html` that anyone can open (double-click, or hosted on any static https site) to write lyrics as plain `.txt` files in a folder they choose. Apple iOS design language for structure and components, with a twist: a theme picker of urban-inspired palettes (streetlight amber, neon, brick, graffiti, subway, concrete). Minimal, light on CPU/GPU. Includes a beat player with A–B loop or system-audio capture, soft audio-reactive background visuals without Three.js, and adjustable writing helpers (syllables + bars, rhyme highlighting, metronome with tap tempo).

Facts that shape the design:

- **Folder access** uses the File System Access API (Chrome, Edge, Brave, Opera). The visitor picks a folder once; the app keeps the `FileSystemDirectoryHandle` in IndexedDB (localStorage can only hold text) and reconnects on later visits. Chromium 122+ offers "Allow on every visit"; otherwise the app shows a single "Reopen folder" button. The API works from a double-clicked file and from any https page. Browsers without it get a plain message asking for a Chromium browser.
- **Text round-trip:** a textarea converts CRLF to LF and `Blob.text()` drops a BOM, so the app detects both on read and restores them on write.
- **Performance:** the earlier Three.js visualizer was GPU-bound (bloom passes, noise-displaced sphere, blur panels at 60 fps). One `AnalyserNode` plus a small 2D canvas at 30 fps costs about 1–3 % of one core and nothing when no audio plays.

## Deliverable

`index.html` in the current workspace, no dependencies, no build step. Runtime creates a `Trash/` subfolder inside the chosen folder for "Recently Deleted".

## Design language: iOS structure, urban palettes

- **Token system:** every color is a CSS custom property on `:root` (`--bg`, `--bg-2`, `--bg-3`, `--label`, `--label-2`, `--label-3`, `--separator`, `--accent`, `--accent-2`, `--danger`, `--ok`) plus `color-scheme` for native controls. A `THEMES` object in JS holds one value set per theme and applies it with `style.setProperty`, so the canvas visuals read the same values. The "System" theme follows `prefers-color-scheme`; all others are fixed. Switching crossfades colors over 300 ms (instant under reduced motion). The choice persists in localStorage.
- **Themes (7):**
  - *System*: iOS defaults. Dark `#000 / #1C1C1E / #2C2C2E`, accent `#0A84FF`; light `#F2F2F7 / #FFF / #FFF`, accent `#007AFF`.
  - *Asphalt*: near-black `#0B0C10 / #15171C / #1E2128`, warm-white labels `#F2EFE9`, streetlight amber accent `#FFB020`, secondary `#FF6A3D`.
  - *Neon*: `#050308 / #120A1A / #1B1026`, labels `#F5F0FF`, magenta accent `#FF2BD6`, cyan secondary `#00E5FF`.
  - *Brick*: `#1A0F0C / #2A1712 / #3A211A`, labels `#F6E9E0`, terracotta accent `#E2543A`, secondary `#F0B27A`.
  - *Graffiti*: `#0F0F12 / #19191F / #23232B`, lime accent `#B6FF3B`, hot-pink secondary `#FF3B8D`.
  - *Subway*: `#101317 / #1A1F26 / #242B34`, labels `#ECEFF3`, safety-yellow accent `#FFD100`, red secondary `#EE352E`.
  - *Concrete* (light): `#D9DADF / #EDEEF1 / #FFF`, labels `#1C1C1E`, safety-orange accent `#FF6A00`, secondary `#3A3D45`.
- **Theme picker:** first row of the Settings sheet, iOS accent-picker style: a horizontal strip of 40 px circular swatches (each a two-tone disc of background + accent), the selected one ringed in `--accent`, name in a Caption below. Optional "Grain" switch adds a static 3 % noise overlay (tiny repeating SVG data URI, no animation) for a street-poster texture.
- **Derived palettes:** rhyme tints are 8 hues evenly spaced starting from `--accent`, at saturation and lightness adapted to the theme's scheme; the background visuals blend `--accent`, `--accent-2` and a third hue midway between them.
- **Semantic colors** stay iOS: danger `#FF453A`, success `#30D158`, with light-scheme variants where a theme is light.
- **Type:** `-apple-system, "SF Pro Text", "Segoe UI Variable", system-ui`; Large Title 34/700, Headline 17/600, Body 17/400 at 1.45 line height for lyrics, Footnote 13, Caption 12; tabular numerals for counters and time.
- **Structure (iPadOS split view):** sidebar 320 px with large title "Lyrics", rounded search field, inset grouped list (10 px cards, 44 px cells, hairline separators) showing title (filename), date and a one-line snippet, plus a collapsed "Recently Deleted" group. Detail pane: nav bar with file title, "Edit/Done", and a "…" menu (Rename, Duplicate, History, Delete). History opens a sheet listing snapshots by time with their first line; tapping one loads it into the editor (the current text is snapshotted first, so this is always reversible). Bottom toolbar (49 px) with mini transport, metronome and helper toggles. Under 760 px the panes stack with push navigation and a back chevron.
- **Components:** iOS switches, segmented controls with sliding thumb, bottom sheets with a grabber (Player, Settings), action sheets for destructive confirms (red "Delete" first), banner toasts, inline SVG icons in the SF Symbols spirit. Motion `cubic-bezier(.32,.72,0,1)` 300–350 ms, disabled under `prefers-reduced-motion`.
- **Materials:** `backdrop-filter` blur only on the thin nav bar and toolbar; sidebar and sheets use opaque fills so they never re-blur over the animating canvas.
- **Reading view:** "Done" hides helpers and chrome (fades after 3 s idle) and shows the text as a centered typographic column over the dimmed visuals.

## Architecture (sections inside `index.html`)

1. **Tokens + CSS + themes**: custom properties as above, `THEMES` object and `applyTheme(name)` in JS, optional grain overlay; fixed `<canvas id="bg">` behind a grid of sidebar, detail, toolbar, sheets.
2. **Store**: tiny IndexedDB wrapper with two stores: `kv` (folder handle, optional beats-folder handle) and `snapshots` (bounded version history per file). `localStorage` holds settings JSON and the synchronous per-file drafts that survive a tab or browser kill.
3. **Folder**: `pick()` → `showDirectoryPicker({mode:'readwrite'})`; `reconnect()` on load → `queryPermission` → granted lists files, prompt shows the reopen button. `list()` keeps `.txt` in the folder root, skips dotfiles and `.crswap`, sorts by modified date or name (setting). `read()` via ArrayBuffer → detect BOM/EOL → `TextDecoder('utf-8')`. `write()` restores BOM/EOL, per-file promise queue, `createWritable → write → close`. `create()` makes "Untitled.txt" auto-numbered; `rename()` = create + write + read back and compare length + only then remove the original (native `move()` is still flagged); `duplicate()`; `delete()` moves into `Trash/`; Recently Deleted offers Restore and Delete Forever (action sheet). Every write goes through `createWritable()`, which writes a swap file and replaces the original atomically on `close()`, so a crash mid-write never corrupts a file.
4. **Editor + autosave**: plain `<textarea spellcheck>` with a mirror layer behind it (same metrics, one block per line) for rhyme tints and a wrap-safe syllable gutter. Three layers of persistence run without any user decision (see Durability model): a synchronous localStorage draft on every change (throttled to 250 ms, always written on `visibilitychange: hidden` and `pagehide`), a disk write debounced 500 ms with a 1.5 s max wait through the per-file queue, and a snapshot of the previous on-disk text into IndexedDB on every successful write. Status under the title reads "Saved · 12:04", "Saving…", "Restored unsaved edits" or "Saving paused · reopen folder"; no dialogs.
5. **Helpers** (Settings sheet, all adjustable):
   - *Syllables* per line: Greek vowel groups with tonos/dialytika forms, digraphs `αι ει οι ου υι αυ ευ ηυ` count once, synizesis toggle; Latin scripts use vowel groups with silent-e and `y` as vowel; script detected per line.
   - *Bars and words* in the footer: non-empty lines ÷ lines-per-bar (default 1) and word count.
   - *Rhymes*: key of each line's last word (Greek: from the stressed vowel; Latin: last 1–2 vowel groups by strictness); lines in the same stanza or last N lines sharing a key get one of 8 soft tints; optional internal-rhyme marking.
   - *Metronome*: lookahead scheduler (25 ms timer, 0.1 s ahead), filtered click, accent on 1, BPM, subdivision, volume, count-in; tap tempo averages the last 4–8 taps; clicks bypass the analyser.
6. **Audio**: one lazy `AudioContext` and one `AnalyserNode` (`fftSize` 1024, smoothing 0.85). *Player sheet:* `<audio>` + playlist from file input, drag-drop or beats folder; play/pause, prev/next, seek, volume, loop track, A–B loop enforced each frame; `createMediaElementSource → analyser → destination`. *System audio:* `getDisplayMedia({video:true, audio:true})`, stop video track, `createMediaStreamSource → analyser` only; pause the player first to avoid echo.
7. **Visuals**: quarter-resolution 2D canvas, CSS-upscaled; three or four radial-gradient blobs drifting slowly, sized and brightened by bass/mid/high with slow auto-gain; faint 48-band log spectrum ribbon above the toolbar; colors read from the active theme's accent pair and recolor on theme change. 30 fps cap, no frames when hidden or silent, static under reduced motion, intensity slider and off switch.
8. **Shortcuts** (Ctrl-based, never plain keys): `Ctrl+Space` play/pause, `Ctrl+[` / `Ctrl+]` loop A/B, `Ctrl+Shift+L` clear loop, `Ctrl+Shift+M` metronome, `Ctrl+T` tap, `Ctrl+N` new, `Ctrl+K` search, `Ctrl+,` settings, `Ctrl+\` sidebar, `Ctrl+E` edit/reading, `Ctrl+S` save now.

## Durability model (automatic, no prompts, never discards text)

- **Three layers.** Disk file (primary, written within ~0.5–1.5 s of typing, atomic swap). localStorage draft (synchronous, so it survives a tab or browser kill; keyed by folder + filename, capped at 20 files / ~2 MB, oldest pruned). IndexedDB snapshots (previous on-disk text saved before each write, coalesced to one per 30 s, capped at 50 per file / ~20 MB total, oldest pruned).
- **Reconciliation on open and on reconnect**, for every file that has a draft, not only the visible one:
  - draft newer than the file's `lastModified` and different → load the draft, write it to disk immediately, snapshot the disk text first; status "Restored unsaved edits".
  - file newer than the draft (edited elsewhere) → load the disk text; if the draft differs, keep it as a snapshot in History so nothing is lost.
  - identical → drop the draft.
- **Before every disk write** re-read `lastModified`; if it changed since the app last read the file (another editor or another tab), snapshot the disk version, then write. No conflict dialog, both versions survive.
- **Write failure** (permission revoked, disk error): text stays in the draft, status shows "Saving paused · reopen folder", and the app retries every 5 s and immediately after the folder is reopened. Typing is never blocked.
- **Multiple tabs**: a `BroadcastChannel` announces saves; a tab that has the same file open and unmodified reloads it silently. A modified tab falls under the write rule above.
- **Nothing else is destructive**: delete goes to `Trash/`; rename removes the original only after the copy is read back; restoring from History snapshots the current text first.
- **Kept light**: drafts are one string write per 250 ms; snapshots are one small IndexedDB put per save; the `lastModified` check is one `getFile()` per write. No polling while idle, no service worker.

## Build sequence

1. Shell in iOS tokens (split view, list, nav bar, toolbar, sheets), the `THEMES` table with the picker and grain toggle, folder pick and reconnect, unsupported-browser message.
2. Editor, reading view, the three persistence layers (draft, disk write queue, snapshots), reconciliation on open and reconnect, retry on failure, BOM/EOL round-trip, History sheet.
3. File ops: new, rename, duplicate, delete to Trash, restore, delete forever, search.
4. Mirror layer, syllable gutter, rhyme tints, counters, Settings sheet.
5. Player sheet with A–B loop, system capture, metronome + tap tempo.
6. Background visuals with caps; shortcuts, idle fade, light-mode and reduced-motion pass; verification.

## Pitfalls and mitigations

- CRLF/BOM rewritten → detect on read, restore on write.
- Edits lost at tab or browser kill → synchronous localStorage draft every 250 ms and on hide, auto-applied on next open.
- Edits lost when permission lapses → draft kept, silent retry every 5 s, flush on reopen.
- Two versions of one file (other editor, other tab) → snapshot the disk version, then write; both survive in History.
- Crash mid-write → atomic swap via `createWritable().close()`.
- Overlapping saves → per-file promise queue.
- Storage growth → bounded drafts and snapshots with oldest-first pruning.
- Irreversible delete → `Trash/` with Recently Deleted.
- `move()` unavailable → create + write + remove.
- Blur over animated canvas → only on the two thin bars.
- Wrapped lines vs gutter → heights measured from mirror blocks.
- Imperfect syllable/rhyme heuristics → simple rules, exposed toggles, per-line counts.

## Verification

1. Open `index.html` by double-click in Edge or Chrome, pick any folder: `.txt` files listed. Firefox shows the unsupported message.
2. Restart the browser: reconnects with no prompt after "Allow on every visit", otherwise one click on "Reopen folder".
3. Type, wait 1 s, open the file in Notepad: change present; a CRLF file and a BOM file stay byte-identical after a no-op edit (`fc /b`).
4. Durability, all without any prompt: (a) type and close the tab within 200 ms, reopen: the text is there and the file on disk matches within 2 s; (b) end the browser process from Task Manager mid-typing, reopen: same result; (c) revoke the folder permission from the address bar while typing: status shows "Saving paused", typing continues, re-grant: file catches up; (d) edit the same file in Notepad while it is open and modified in the app: the app's text wins on disk and Notepad's version appears in History; (e) open the app in two tabs on the same file: a save in one appears in the other; (f) restore an old version from History, then restore the newest snapshot: the text returns.
5. New, rename, duplicate, delete, restore, delete forever: the folder and `Trash/` reflect each step.
6. Helpers on Greek and English test lines: plausible counts, rhyme tints, live toggles.
7. Two beat files with an A–B loop; system audio from a YouTube tab drives the visuals without echo; metronome steady while typing; tap tempo within ±2 BPM.
8. Task Manager with visuals on: CPU under ~5 % of one core, GPU near zero; hidden tab renders no frames. Light and dark readable at 760 px and 1440 px.
9. Themes: switch through all seven in the Settings sheet; colors crossfade, visuals and rhyme tints recolor, the choice survives a reload, and body text on every theme passes 4.5:1 contrast (check with the DevTools color picker). Grain toggle adds texture without any per-frame cost.
