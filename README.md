# Metadata Repair Tool

**Version 2.5.2**

A Windows desktop utility for managing [Pegasus Frontend](https://pegasus-frontend.org/) collection metadata. Edit game entries in form or raw view, fix paths and art, pull titles/covers from GameTDB, import EmulationStation gamelists, and run batch repair jobs on large libraries.

Developed by **jacktrabblt72380**.

---

## Requirements

- **Windows** (Windows Forms / PowerShell)
- **PowerShell 5.1+** (Windows PowerShell or PowerShell 7+)
- No installers beyond the scripts in this folder

Optional network access is used for GameTDB downloads and related tools.

---

## Quick start

1. Keep these files in the **same folder**:
   - `Metadata-Repair-Tool.ps1` — main application
   - `Metadata-Repair-Launcher.bat` — double-click launcher
2. Double-click **`Metadata-Repair-Launcher.bat`**  
   (runs the script with `-ExecutionPolicy Bypass` and a hidden console).
3. Or run from PowerShell:

   ```powershell
   powershell -ExecutionPolicy Bypass -File ".\Metadata-Repair-Tool.ps1"
   ```

4. **Create** or **Add** a collection (metadata `.txt` + media folder).
5. Select the collection — games load into Form view. Edit fields, use the tool panels on the left, then **Save**.

Config is stored under:

`%APPDATA%\Pegasus-Metadata-Editor\config.json`

---

## Layout overview

| Area | Purpose |
|------|---------|
| **Left panel** | Collapsible tool sections (Collections, Metadata, Image, SNS, Game ID, GameTDB, Build & Repair) |
| **Item Metadata** | Collection header + per-game fields (Form view). Drag the bottom edge to resize; Games list height stays in sync |
| **Games** | Searchable game list. Selection loads fields into the form |
| **Action bar** | Apply, Refresh, Form / Raw, Save, Theme, Guide |
| **Terminal Output** | Log of operations; collapsible |

**Theme:** Steam-style dark or Windows (light/dark + system accent) via the **Theme** button.

---

## Collections

- **Create** — new folder layout: metadata file, `media\box2dfront`, `media\box2dThumb`
- **Add** — point at an existing metadata file and media path
- **Remove / Refresh / Load** — manage the list of known collections

Typical Pegasus metadata is a text file with a collection header followed by `game:` blocks.

---

## Metadata Tools

| Tool | Description |
|------|-------------|
| **Check Health** | Basic health pass on the current collection |
| **Statistics** | Counts (games, box art, missing, images) |
| **Find Missing Covers** | Games without box art paths / files |
| **Fix Duplicates** | Resolve duplicate game entries |
| **Backup / Restore** | Copy metadata to `.bkup.txt` and restore |

---

## Image Tools

- Add box art or **all media types** into metadata from folders under `media\`
- Rename images to match game titles (optional region stripping: USA / EUR / JPN)
- Rename SNS-coded images to titles
- Update metadata names from image filenames
- Convert PNG ↔ JPG (all or selected); update metadata extensions

### Asset folder reference

| Folder | Metadata key |
|--------|----------------|
| `box2dfront/` | `assets.box_front` |
| `box2dfull/` / `boxFull/` | `assets.box_full` / `assets.boxFull` |
| `box2dback/` | `assets.box_back` |
| `box2dThumb/` | thumb paths |
| `screenshot/` | `assets.screenshot` |
| `videos/` | `assets.video` |
| `wheel/` | `assets.logo` |
| `titlescreen/` | `assets.titlescreen` |
| `fanart/` | `assets.fanart` |
| `cartridge/` | `assets.cartridge` |
| `steamgrid/` | `assets.steamgrid` |
| `marquee/` | `assets.marquee` |
| `banner/` | `assets.banner` |

---

## SNS Code Tools

Aimed at SNES (and similar product-code workflows):

- Extract SNS / product codes from ROMs or lists
- Map codes to titles and box art
- Helpers for internal SNES ROM headers

---

## Game ID Tools

- Extract game IDs from files / metadata
- Create ID ↔ title mapping files
- Apply IDs back into metadata
- Console ID reference (SNS, NUS, DOL, RVL, WUP, HAC, etc.)

---

## GameTDB Tools

Uses [GameTDB](https://www.gametdb.com/) titles and cover CDNs for supported platforms (Wii, Wii U, Switch, 3DS, DS, PS3, …):

| Tool | Description |
|------|-------------|
| **Download Titles DB** | Fetch platform title lists |
| **Download Covers by ID** | Cover art by game ID |
| **Lookup Title by ID** | Resolve a single ID |
| **Open GameTDB Page** | Open the game page in a browser |
| **Apply Titles from GameTDB** | Rename `game:` lines to GameTDB titles |
| **Fill Missing Box Art Paths** | Write `assets.box_front` when matching images exist |
| **DL Covers from Game List** | Download covers from the current game list |

SNES SNS product codes are **not** on the GameTDB art CDN — use **SNS Code Tools** for those.

---

## Build & Repair Tools

| Tool | Description |
|------|-------------|
| **Scan Folder for Games** | List ROM filenames from a folder |
| **Titles from Covers** | Title list from box art filenames |
| **Build Meta from Folder** | Create `game:` entries from ROMs on disk |
| **Import Games from List** | Import titles from a text list |
| **Sync File Paths** | Match `file:` paths to ROMs in the folder |
| **Export Game List / Export Missing List** | Export helpers |
| **DL Covers from Mapping** | Download covers using a mapping file |
| **Read SNES ROM Headers** | Scan internal SNES titles |
| **Strip All Box Art Paths** | Remove box art asset lines only |
| **Strip All Assets** | Remove every `assets.*` line |
| **Clean Bogus Games** | Remove garbled / junk titles |
| **Hide Multi-Disc + M3U** | Multi-disc handling + `.m3u` / ignore-files |
| **Backup All Meta (Zip)** | Recursive zip of metadata under a root |
| **Edit Genres** | Multi-select rename / merge genres |
| **Full File Check Report** | ROMs vs metadata vs media gaps → report file |
| **Export / Import EmulationStation XML** | `gamelist.xml` (optional “ROM must exist on disk”) |
| **Backup Orphan Media** | Move unmatched media to `media.backup\<type>\` |
| **Batch Import Library** | Import all `gamelist.xml` under a library root |
| **Sort Games A-Z** | Reorder all game blocks alphabetically (uses `sort_title` when set, otherwise `game:` title; case-insensitive). Creates a backup first |

Helper outputs (reports, lists, tools files) prefer `<media>\Tools\` so they stay out of ROM and curated import paths.

---

## Form vs Raw view

- **Form** — structured fields for collection header and the selected game; **Apply** writes the current game’s fields back into memory before **Save**.
- **Raw** — full metadata text editor. Switching modes parses or rebuilds the Pegasus text.

**Save** writes the collection metadata file (UTF-8 without BOM in form mode).

---

## Typical workflows

### New Pegasus collection from ROMs

1. **Create** collection (or **Add** existing folder).
2. **Build & Repair → Build Meta from Folder** (or **Scan** + **Import**).
3. **Image Tools → Add All Media Types**.
4. Optional: **GameTDB** / **SNS** tools for titles and covers.
5. **Save**.

### After Skraper / EmulationStation

1. **Import EmulationStation XML** or **Batch Import Library**.
2. Prefer “only games whose ROM exists on disk” when prompted.
3. **Image Tools → Add All Media Types**.
4. **Full File Check Report** / **Backup Orphan Media** as needed.

### Alphabetical library

1. Load the collection.
2. **Build & Repair → Sort Games A-Z**.
3. Confirm; backup is created automatically.

Use the in-app **Guide** button for more step-by-step scenarios.

---

## Files in this project

| File | Role |
|------|------|
| `Metadata-Repair-Tool.ps1` | Full application (UI + all tools) |
| `Metadata-Repair-Launcher.bat` | Convenience launcher |
| `README.md` | This document |

---

## Notes & safety

- Destructive or bulk operations (**Clean Bogus**, **Sort Games A-Z**, strip tools, orphan backup, etc.) prompt first and/or write backups (`.bkup.txt` or zip / `media.backup`).
- Always keep your own copy of large libraries before mass path or title changes.
- Theme and collection list persist in AppData; metadata and media stay in your collection folders.

---

## License / credit

Application developed by **jacktrabblt72380**.  
GameTDB data and art remain subject to [GameTDB](https://www.gametdb.com/) terms.  
Pegasus Frontend is a separate project.

---

*Metadata Repair Tool — maintain Pegasus collections with less manual metadata editing.*
