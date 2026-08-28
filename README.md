# Metadata Repair Tool

**Version 2.5.2**

A Windows desktop utility for managing [Pegasus Frontend](https://pegasus-frontend.org/) collection metadata. Edit game entries in form or raw view, fix paths and art, pull titles/covers from GameTDB, import EmulationStation gamelists, and run batch repair jobs on large libraries.

Developed by **jacktrabblt72380**.

---

## Requirements (native)

| Item | Detail |
|------|--------|
| **Platform** | **Windows 10 / 11** (primary and fully supported) |
| **Runtime** | PowerShell 5.1+ (built-in) or PowerShell 7+ |
| **UI** | .NET Windows Forms (`System.Windows.Forms`) |
| **Install** | No installer — only the `.ps1` and `.bat` in this folder |

Optional network access is used for GameTDB downloads and related tools.

> **Important:** This application is a **Windows desktop GUI** built with WinForms. It does **not** run natively on Android, iOS, Linux, or macOS. See [Platform instructions](#platform-instructions) below for what works on each system.

---

## Platform instructions

### Windows (full support)

This is the intended environment.

1. Keep these files in the **same folder**:
   - `Metadata-Repair-Tool.ps1` — main application  
   - `Metadata-Repair-Launcher.bat` — double-click launcher  
2. Double-click **`Metadata-Repair-Launcher.bat`**  
   (runs the script with `-ExecutionPolicy Bypass` and a hidden console window).  
3. Or run from PowerShell / Terminal:

   ```powershell
   Set-Location "C:\path\to\this\folder"
   powershell -ExecutionPolicy Bypass -File ".\Metadata-Repair-Tool.ps1"
   ```

   PowerShell 7:

   ```powershell
   pwsh -ExecutionPolicy Bypass -File ".\Metadata-Repair-Tool.ps1"
   ```

4. If Windows blocks the script: right-click the `.ps1` → **Properties** → check **Unblock** → OK.  
5. **Create** or **Add** a collection (metadata `.txt` + media folder).  
6. Select the collection — games load into Form view. Edit fields, use the left tool panels, then **Save**.

**Config path (Windows):**

`%APPDATA%\Pegasus-Metadata-Editor\config.json`  
(typically `C:\Users\<You>\AppData\Roaming\Pegasus-Metadata-Editor\config.json`)

Point collections at folders on local drives, external HDDs, or mapped network shares that Windows can access.

---

### Linux

#### Install PowerShell on Linux

PowerShell (formerly “PowerShell Core”) is cross-platform and works on Linux, macOS, and Windows. You can install it and run **many** `.ps1` scripts. For *this* tool, read the **important limitation** below.

**Ubuntu / Debian:**

```bash
# Update package lists
sudo apt update

# Install prerequisites
sudo apt install -y wget apt-transport-https software-properties-common

# Import Microsoft package repository
wget -q https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb

# Update again and install PowerShell
sudo apt update
sudo apt install -y powershell
```

**Fedora / CentOS / RHEL** (example repo for Fedora 38 — use the matching packages.microsoft.com package for your release):

```bash
sudo dnf install -y https://packages.microsoft.com/config/fedora/38/packages-microsoft-prod.rpm
sudo dnf install -y powershell
```

**Start PowerShell:**

```bash
pwsh
```

You should see a `PS>` prompt.

**Run a PowerShell script:**

```bash
pwsh ./Metadata-Repair-Tool.ps1
```

Or from inside PowerShell:

```powershell
./Metadata-Repair-Tool.ps1
```

**Execution policy** (if unsigned/local scripts are blocked):

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Optional — run `.ps1` files directly:**

Add a shebang at the top of a script:

```powershell
#!/usr/bin/env pwsh
```

Then:

```bash
chmod +x Metadata-Repair-Tool.ps1
./Metadata-Repair-Tool.ps1
```

Other distributions: [Install PowerShell on Linux](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux).

**Key points about PowerShell on Linux:**

- Same language engine as on Windows — many scripts work without changes  
- You can mix PowerShell with native Linux commands  
- Useful for cross-platform automation  

#### Important limitation for *this* application

Installing PowerShell on Linux does **not** make Metadata Repair Tool’s GUI work.

This app is built with **.NET Windows Forms** (`System.Windows.Forms`), which is **Windows-only**. On Linux, `pwsh ./Metadata-Repair-Tool.ps1` will typically fail when loading WinForms — the main window will not open.

**What Linux users should do for this tool:**

| Approach | Notes |
|----------|--------|
| **Windows PC or VM (recommended)** | Run the tool in a Windows VM (VirtualBox, VMware, QEMU/KVM). Share ROM/metadata folders with the guest (Samba, virtio-9p, shared folder). Full UI and all features work. |
| **Wine + Windows PowerShell** | Experimental only. WinForms under Wine is unreliable; dialogs and controls often break. **Not recommended** for production libraries. |
| **Edit metadata as text** | Pegasus metadata is plain text. Use any editor or your own scripts for small fixes. |

**Light editing without this app:**

```bash
less "/path/to/collection/snes.txt"
nano "/path/to/collection/snes.txt"
```

Keep backups before hand-editing large files. Use **Metadata Repair Tool on Windows** (or a Windows VM) when you need health checks, GameTDB, batch import, Sort A–Z, image tools, etc.

---

### macOS (not native — limited options)

Same limitation as Linux: **WinForms is Windows-only**. PowerShell for macOS (`pwsh`) cannot display this UI.

**Practical options:**

| Approach | Notes |
|----------|--------|
| **Windows VM or Boot Camp / Parallels / VMware Fusion** | Run the tool inside Windows; share the folder that holds your Pegasus collections (or copy metadata in/out). |
| **Remote Windows machine** | RDP / remote desktop into a Windows PC that has the tool and access to the library (local or network path). |
| **Plain-text editing** | Metadata remains UTF-8 text. Use TextEdit, VS Code, or similar for small fixes only. |

Do not expect `pwsh Metadata-Repair-Tool.ps1` to open the window on macOS — it will fail when loading `System.Windows.Forms`.

---

### Android (not supported)

This is a **desktop Windows executable script**, not an Android app.

- It cannot be installed from Play Store or sideloaded as an APK.  
- Termux / PowerShell-on-Android **cannot** host WinForms UI.  
- Pegasus or other Android frontends may **read** the same metadata files if you sync them, but **repair/editing with this tool must be done on Windows**.

**Suggested workflow for Android libraries:**

1. Keep the master metadata + media on a PC (or synced cloud/USB).  
2. Run **Metadata Repair Tool on Windows** to fix titles, paths, art, and order.  
3. Copy or sync the updated collection folder to the Android device for the frontend to use.

Use a file manager or text editor on Android only for emergency one-line fixes; prefer the Windows tool for bulk work.

---

### iOS / iPadOS (not supported)

There is **no way** to run this application on iPhone or iPad:

- No WinForms / Windows PowerShell GUI on iOS.  
- Shortcuts, Pythonista, or SSH apps cannot host this UI.  
- App Store policies and sandboxing prevent running arbitrary Windows desktop tools.

**Suggested workflow:**

1. Maintain collections on a **Windows PC** (or Mac with a Windows VM) using this tool.  
2. Transfer the collection folder to the device via Files, a computer, or cloud sync if your frontend supports it.  
3. Use the mobile frontend only to **play**; use Windows for **metadata repair**.

---

### Summary

| Platform | Runs this app? | What to do |
|----------|----------------|------------|
| **Windows** | **Yes — full support** | Use the launcher or PowerShell; see steps above |
| **Linux** | No (native) | Windows VM + shared folders, or edit text files carefully |
| **macOS** | No (native) | Windows VM / Parallels / remote Windows |
| **Android** | No | Repair on Windows, then sync library to device |
| **iOS** | No | Repair on Windows, then transfer collection data |

---

## Quick start (Windows)

1. Place `Metadata-Repair-Tool.ps1` and `Metadata-Repair-Launcher.bat` in the same folder.  
2. Double-click **`Metadata-Repair-Launcher.bat`**.  
3. **Create** or **Add** a collection.  
4. Select it, edit in Form (or Raw) view, run tools from the left panel, then **Save**.

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
