# ============================================================================
# METADATA REPAIR TOOL
# Version: 2.5.10 - Cover Pack: only-missing for boxFull/box_full, platform filter, collection required docs
# (Steam/Light/HighContrast/Windows); UTF-8 BOM for Windows PowerShell 5.1;
# Remove Games w/ No File; SNES guide; Sort A-Z; Games list height fix.
# ============================================================================


Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO

# Compiled CRC32 (matches the algorithm GameDB/GameID use to fingerprint ROMs -
# standard zlib/PKZIP polynomial 0xEDB88320). Implemented in C# via Add-Type
# because a pure-PowerShell byte loop over hundreds of multi-MB ROMs is too slow.
Add-Type -TypeDefinition @"
using System;
public static class MrtCrc32 {
    private static readonly uint[] Table;
    static MrtCrc32() {
        Table = new uint[256];
        for (uint i = 0; i < 256; i++) {
            uint c = i;
            for (int j = 0; j < 8; j++) {
                c = ((c & 1) != 0) ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
            }
            Table[i] = c;
        }
    }
    public static string ComputeHex(byte[] bytes, int offset, int length) {
        uint crc = 0xFFFFFFFF;
        int end = offset + length;
        for (int i = offset; i < end; i++) {
            byte idx = (byte)((crc ^ bytes[i]) & 0xFF);
            crc = Table[idx] ^ (crc >> 8);
        }
        crc ^= 0xFFFFFFFF;
        return crc.ToString("x8");
    }
}
"@

# ============================================================================
# GLOBALS
# ============================================================================
$script:version = "2.5.10"
$script:configPath = "$env:APPDATA\Pegasus-Metadata-Editor\config.json"
$script:collections = @{}
$script:pegasusPath = ""
$script:currentCollection = $null
$script:logBox = $null
$script:editorBox = $null
$script:statusBar = $null
$script:collectionList = $null
$script:countLabel = $null
$script:gameListBox = $null
$script:gameSearchBox = $null
$script:searchLabel = $null
$script:fieldControls = @{}
$script:parsedHeader = ""
$script:parsedHeaderFields = @{}
$script:parsedGames = @()
$script:rawMode = $false
$script:editorSplit = $null
$script:detailPanel = $null
$script:metaOuter = $null
$script:gamesOuter = $null
$script:termOuter = $null
$script:actionBar = $null
$script:headerControls = @{}
$script:suppressGameSelect = $false
$script:snsCodeList = $null
$script:snsInfoLabel = $null
$script:lastSnsCodes = @()
$script:lastSnsCodesFile = $null
$script:leftSections = New-Object System.Collections.ArrayList
$script:leftPanelRef = $null
$script:sectionGap = 8
$script:collapsedHeaderH = 28

# Console ID mappings
$script:consoleIDs = @{
    "SNS" = "SNES (Super Nintendo)"
    "NUS" = "Nintendo 64"
    "DOL" = "GameCube"
    "RVL" = "Wii"
    "WUP" = "Wii U"
    "HAC" = "Nintendo Switch"
    "NTR" = "Nintendo DS"
    "CTR" = "Nintendo 3DS"
    "BLUS" = "PlayStation 3 (US)"
    "BLES" = "PlayStation 3 (EU)"
    "NPUB" = "PSN (US)"
    "NPEB" = "PSN (EU)"
    "CUSA" = "PlayStation 4"
    "PCSH" = "PlayStation Vita"
    "PCSE" = "PlayStation Vita (US)"
    "PCSA" = "PlayStation Vita (EU)"
}

# GameTDB platform + art path mappings (official art.gametdb.com CDN)
# CoverTypes verified on art.gametdb.com (disc/cover3D often PNG when covers are JPG)
$script:gameTdbPlatforms = @{
    "wii" = @{
        Label = "Wii"; TitlesUrl = "https://www.gametdb.com/wiitdb.txt?LANG=EN"
        ArtPath = "wii"; Ext = "png"
        CoverTypes = @("cover", "coverfullHQ", "cover3D", "disc", "discCustom")
        XmlZip = "https://www.gametdb.com/wiitdb.zip"
    }
    "gamecube" = @{
        Label = "GameCube"; TitlesUrl = "https://www.gametdb.com/wiitdb.txt?LANG=EN"
        ArtPath = "wii"; Ext = "png"
        CoverTypes = @("cover", "coverfullHQ", "cover3D", "disc", "discCustom")
        IdFilter = "gamecube"
        XmlZip = "https://www.gametdb.com/wiitdb.zip"
    }
    "wiiu" = @{
        Label = "Wii U"; TitlesUrl = "https://www.gametdb.com/wiiutdb.txt?LANG=EN"
        ArtPath = "wiiu"; Ext = "jpg"
        CoverTypes = @("cover", "coverHQ", "coverfullHQ", "coverM", "cover3D", "back", "backHQ", "backM", "disc")
        XmlZip = "https://www.gametdb.com/wiiutdb.zip"
    }
    "switch" = @{
        Label = "Nintendo Switch"; TitlesUrl = "https://www.gametdb.com/switchtdb.txt?LANG=EN"
        ArtPath = "switch"; Ext = "jpg"
        CoverTypes = @("cover", "coverHQ", "coverfullHQ", "coverM", "back", "backHQ", "backM")
        XmlZip = "https://www.gametdb.com/switchtdb.zip"
    }
    "3ds" = @{
        Label = "Nintendo 3DS"; TitlesUrl = "https://www.gametdb.com/3dstdb.txt?LANG=EN"
        ArtPath = "3ds"; Ext = "jpg"
        CoverTypes = @("cover", "coverHQ", "coverfullHQ", "coverM", "back", "backHQ", "backM")
        XmlZip = "https://www.gametdb.com/3dstdb.zip"
    }
    "ds" = @{
        Label = "Nintendo DS"; TitlesUrl = "https://www.gametdb.com/dstdb.txt?LANG=EN"
        ArtPath = "ds"; Ext = "jpg"
        CoverTypes = @("cover", "coverHQ", "coverM")
        XmlZip = "https://www.gametdb.com/dstdb.zip"
    }
    "ps3" = @{
        Label = "PlayStation 3"; TitlesUrl = "https://www.gametdb.com/ps3tdb.txt?LANG=EN"
        ArtPath = "ps3"; Ext = "jpg"
        CoverTypes = @("cover", "coverHQ", "coverfullHQ", "coverM", "back", "backHQ", "backM", "disc")
        XmlZip = "https://www.gametdb.com/ps3tdb.zip"
    }
}
$script:gameTdbRegions = @("US", "EN", "AU", "FR", "DE", "JP", "JA", "CA", "RU", "ZH", "KO", "IT", "NL", "PT", "ES", "SE", "DK", "NO", "FI")
$script:gameTdbTitlesCache = @{}
$script:lastGameTdbPlatform = "wii"

# Create config directory
$configDir = Split-Path $script:configPath -Parent
if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
}

# ============================================================================
# THEME - follows Windows light/dark app mode + system accent
# ============================================================================
function Get-WindowsAccentColor {
    try {
        $dwm = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\DWM" -ErrorAction Stop
        $dword = $null
        if ($null -ne $dwm.AccentColor) { $dword = [int]$dwm.AccentColor }
        elseif ($null -ne $dwm.ColorizationColor) { $dword = [int]$dwm.ColorizationColor }
        if ($null -ne $dword) {
            # Stored as AABBGGRR
            $r = $dword -band 0xFF
            $g = ($dword -shr 8) -band 0xFF
            $b = ($dword -shr 16) -band 0xFF
            if ($r -gt 0 -or $g -gt 0 -or $b -gt 0) {
                return [System.Drawing.Color]::FromArgb(255, $r, $g, $b)
            }
        }
    } catch {}
    return [System.Drawing.Color]::FromArgb(255, 0, 120, 215)  # Windows blue fallback
}

function Test-WindowsAppsLightTheme {
    try {
        $p = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -ErrorAction Stop
        if ($null -ne $p.AppsUseLightTheme) { return ([int]$p.AppsUseLightTheme -eq 1) }
    } catch {}
    return $true
}

function Initialize-DefaultTheme {
    # App default: dark blue panel with cyan accent labels + green success text
    $script:theme = @{
        background  = [System.Drawing.Color]::FromArgb(30, 30, 50)
        panel       = [System.Drawing.Color]::FromArgb(40, 40, 65)
        border      = [System.Drawing.Color]::FromArgb(60, 60, 90)
        text        = [System.Drawing.Color]::FromArgb(220, 220, 230)
        textDim     = [System.Drawing.Color]::FromArgb(160, 160, 180)
        accent      = [System.Drawing.Color]::FromArgb(100, 200, 255)
        accentDark  = [System.Drawing.Color]::FromArgb(60, 120, 180)
        success     = [System.Drawing.Color]::FromArgb(80, 220, 100)
        error       = [System.Drawing.Color]::FromArgb(255, 100, 100)
        warning     = [System.Drawing.Color]::FromArgb(255, 200, 80)
        button      = [System.Drawing.Color]::FromArgb(60, 60, 90)
        buttonHover = [System.Drawing.Color]::FromArgb(80, 80, 120)
        editor      = [System.Drawing.Color]::FromArgb(20, 20, 40)
        terminal    = [System.Drawing.Color]::FromArgb(20, 20, 40)
    }
    $script:isLightTheme = $false
}

function Initialize-SteamTheme {
    # Separate Steam-inspired dark gray theme (not the app default)
    $script:theme = @{
        background  = [System.Drawing.Color]::FromArgb(27, 40, 56)
        panel       = [System.Drawing.Color]::FromArgb(23, 26, 33)
        border      = [System.Drawing.Color]::FromArgb(55, 65, 80)
        text        = [System.Drawing.Color]::FromArgb(198, 212, 223)
        textDim     = [System.Drawing.Color]::FromArgb(140, 155, 170)
        accent      = [System.Drawing.Color]::FromArgb(102, 192, 244)
        accentDark  = [System.Drawing.Color]::FromArgb(27, 140, 180)
        success     = [System.Drawing.Color]::FromArgb(90, 200, 120)
        error       = [System.Drawing.Color]::FromArgb(255, 110, 110)
        warning     = [System.Drawing.Color]::FromArgb(230, 180, 70)
        button      = [System.Drawing.Color]::FromArgb(42, 71, 94)
        buttonHover = [System.Drawing.Color]::FromArgb(55, 95, 125)
        editor      = [System.Drawing.Color]::FromArgb(18, 24, 32)
        terminal    = [System.Drawing.Color]::FromArgb(18, 24, 32)
    }
    $script:isLightTheme = $false
}

function Initialize-WindowsTheme {
    $light = Test-WindowsAppsLightTheme
    $accent = Get-WindowsAccentColor
    $accentDark = [System.Drawing.Color]::FromArgb(
        255,
        [Math]::Max(0, $accent.R - 40),
        [Math]::Max(0, $accent.G - 40),
        [Math]::Max(0, $accent.B - 40)
    )
    $script:isLightTheme = $light

    if ($light) {
        $script:theme = @{
            background  = [System.Drawing.Color]::FromArgb(245, 245, 250)
            panel       = [System.Drawing.Color]::FromArgb(255, 255, 255)
            border      = [System.Drawing.Color]::FromArgb(200, 200, 210)
            text        = [System.Drawing.Color]::FromArgb(30, 30, 40)
            textDim     = [System.Drawing.Color]::FromArgb(100, 100, 120)
            accent      = $accent
            accentDark  = $accentDark
            success     = [System.Drawing.Color]::FromArgb(16, 128, 64)
            error       = [System.Drawing.Color]::FromArgb(200, 40, 40)
            warning     = [System.Drawing.Color]::FromArgb(180, 120, 0)
            button      = [System.Drawing.Color]::FromArgb(230, 230, 240)
            buttonHover = [System.Drawing.Color]::FromArgb(
                255,
                [Math]::Min(255, $accent.R + 40),
                [Math]::Min(255, $accent.G + 40),
                [Math]::Min(255, $accent.B + 40)
            )
            editor      = [System.Drawing.Color]::FromArgb(255, 255, 255)
            terminal    = [System.Drawing.Color]::FromArgb(250, 250, 252)
        }
    } else {
        $script:theme = @{
            background  = [System.Drawing.Color]::FromArgb(32, 32, 36)
            panel       = [System.Drawing.Color]::FromArgb(45, 45, 50)
            border      = [System.Drawing.Color]::FromArgb(70, 70, 80)
            text        = [System.Drawing.Color]::FromArgb(240, 240, 245)
            textDim     = [System.Drawing.Color]::FromArgb(160, 160, 175)
            accent      = $accent
            accentDark  = $accentDark
            success     = [System.Drawing.Color]::FromArgb(80, 200, 120)
            error       = [System.Drawing.Color]::FromArgb(255, 100, 100)
            warning     = [System.Drawing.Color]::FromArgb(255, 190, 70)
            button      = [System.Drawing.Color]::FromArgb(55, 55, 62)
            buttonHover = [System.Drawing.Color]::FromArgb(
                255,
                [Math]::Min(255, [int]($accent.R * 0.55 + 40)),
                [Math]::Min(255, [int]($accent.G * 0.55 + 40)),
                [Math]::Min(255, [int]($accent.B * 0.55 + 40))
            )
            editor      = [System.Drawing.Color]::FromArgb(25, 25, 30)
            terminal    = [System.Drawing.Color]::FromArgb(25, 25, 30)
        }
    }
}

function Initialize-LightTheme {
    # Explicit light theme (not tied to Windows accent)
    $script:isLightTheme = $true
    $script:theme = @{
        background  = [System.Drawing.Color]::FromArgb(245, 246, 250)
        panel       = [System.Drawing.Color]::FromArgb(255, 255, 255)
        border      = [System.Drawing.Color]::FromArgb(190, 195, 210)
        text        = [System.Drawing.Color]::FromArgb(25, 28, 40)
        textDim     = [System.Drawing.Color]::FromArgb(90, 95, 115)
        accent      = [System.Drawing.Color]::FromArgb(0, 120, 215)
        accentDark  = [System.Drawing.Color]::FromArgb(0, 90, 170)
        success     = [System.Drawing.Color]::FromArgb(16, 128, 64)
        error       = [System.Drawing.Color]::FromArgb(200, 40, 40)
        warning     = [System.Drawing.Color]::FromArgb(180, 120, 0)
        button      = [System.Drawing.Color]::FromArgb(232, 234, 242)
        buttonHover = [System.Drawing.Color]::FromArgb(210, 220, 245)
        editor      = [System.Drawing.Color]::FromArgb(255, 255, 255)
        terminal    = [System.Drawing.Color]::FromArgb(250, 250, 252)
    }
}

function Initialize-HighContrastTheme {
    # High contrast: black / white / cyan accents (same cyan family as Default)
    $script:isLightTheme = $false
    $script:theme = @{
        background  = [System.Drawing.Color]::FromArgb(0, 0, 0)
        panel       = [System.Drawing.Color]::FromArgb(0, 0, 0)
        border      = [System.Drawing.Color]::FromArgb(255, 255, 255)
        text        = [System.Drawing.Color]::FromArgb(255, 255, 255)
        textDim     = [System.Drawing.Color]::FromArgb(220, 220, 220)
        accent      = [System.Drawing.Color]::FromArgb(100, 200, 255)
        accentDark  = [System.Drawing.Color]::FromArgb(60, 120, 180)
        success     = [System.Drawing.Color]::FromArgb(0, 255, 0)
        error       = [System.Drawing.Color]::FromArgb(255, 80, 80)
        warning     = [System.Drawing.Color]::FromArgb(255, 200, 80)
        button      = [System.Drawing.Color]::FromArgb(20, 20, 20)
        buttonHover = [System.Drawing.Color]::FromArgb(60, 60, 60)
        editor      = [System.Drawing.Color]::FromArgb(0, 0, 0)
        terminal    = [System.Drawing.Color]::FromArgb(0, 0, 0)
    }
}

function Initialize-SystemTheme {
    if (-not $script:themeMode) { $script:themeMode = "Default" }
    switch ($script:themeMode) {
        "Steam"        { Initialize-SteamTheme }
        "Windows"      { Initialize-WindowsTheme }
        "Light"        { Initialize-LightTheme }
        "HighContrast" { Initialize-HighContrastTheme }
        default        { Initialize-DefaultTheme }  # Default = cyan/green accent look
    }
}

function Apply-ThemeToControl {
    param($ctrl)
    if ($null -eq $ctrl) { return }
    try {
        $t = $script:theme
        $n = $ctrl.GetType().Name
        $role = $null
        try { if ($null -ne $ctrl.Tag) { $role = [string]$ctrl.Tag } } catch {}
        if ($n -eq "Form" -or $n -eq "Panel" -or $n -eq "TableLayoutPanel" -or $n -eq "StatusStrip") {
            $ctrl.BackColor = $t.background
            try { $ctrl.ForeColor = $t.text } catch {}
        } elseif ($n -eq "GroupBox") {
            $ctrl.BackColor = $t.background
            $ctrl.ForeColor = $t.text
        } elseif ($n -eq "Button") {
            $ctrl.BackColor = $t.button
            $btnName = ""
            try { $btnName = [string]$ctrl.Name } catch {}
            if ($role -eq "accent" -or $btnName -eq "mrtAccentBtn") {
                $ctrl.ForeColor = $t.accent
            } elseif ($role -eq "success" -or $btnName -eq "mrtSuccessBtn") {
                $ctrl.ForeColor = $t.success
            } else {
                $ctrl.ForeColor = $t.text
            }
            try {
                $ctrl.FlatAppearance.MouseOverBackColor = $t.buttonHover
                $ctrl.FlatAppearance.BorderColor = $t.border
            } catch {}
        } elseif ($n -eq "TextBox" -or $n -eq "RichTextBox" -or $n -eq "ListBox") {
            if ($script:logBox -and [object]::ReferenceEquals($ctrl, $script:logBox)) {
                $ctrl.BackColor = $t.terminal
            } else {
                $ctrl.BackColor = $t.editor
            }
            $ctrl.ForeColor = $t.text
        } elseif ($n -eq "Label") {
            try {
                if ($ctrl.Name -eq "countLabel" -or $role -eq "success") {
                    $ctrl.ForeColor = $t.success
                } elseif ($role -eq "accent") {
                    $ctrl.ForeColor = $t.accent
                } elseif ($role -eq "dim" -or $role -eq "hint") {
                    $ctrl.ForeColor = $t.textDim
                } else {
                    $ctrl.ForeColor = $t.text
                }
            } catch {
                $ctrl.ForeColor = $t.text
            }
        } elseif ($n -eq "RadioButton" -or $n -eq "CheckBox") {
            $ctrl.BackColor = $t.background
            $ctrl.ForeColor = $t.text
        }
        foreach ($c in @($ctrl.Controls)) { Apply-ThemeToControl $c }
    } catch {}
}

function Set-AppThemeMode {
    param([ValidateSet("Default","Steam","Light","HighContrast","Windows")][string]$Mode)
    $script:themeMode = $Mode
    Initialize-SystemTheme
    try { Save-Config } catch {}
    if ($script:mainForm) {
        try {
            $script:mainForm.BackColor = $script:theme.background
            $script:mainForm.ForeColor = $script:theme.text
            Apply-ThemeToControl $script:mainForm
            if ($script:logBox) {
                $script:logBox.BackColor = $script:theme.terminal
                $script:logBox.ForeColor = $script:theme.text
            }
            if ($script:editorBox) {
                $script:editorBox.BackColor = $script:theme.editor
                $script:editorBox.ForeColor = $script:theme.text
            }
            if ($script:countLabel) {
                $script:countLabel.ForeColor = $script:theme.success
            }
            if ($script:btnTheme) {
                $script:btnTheme.Text = "Theme"
                try {
                    $tt = $script:themeTip
                    if ($tt) { $tt.SetToolTip($script:btnTheme, "Theme: $Mode (open Settings for all themes)") }
                } catch {}
            }
        } catch {}
    }
    Log-Message ("Theme: {0}" -f $Mode) "Cyan"
}

# Default until config loads
$script:themeMode = "Default"
Initialize-SystemTheme


# ============================================================================
# CONFIG FUNCTIONS
# ============================================================================
function Ensure-CollectionsHashtable {
    if ($null -eq $script:collections -or $script:collections -isnot [System.Collections.Hashtable]) {
        $newHash = @{}
        if ($null -ne $script:collections) {
            $script:collections.PSObject.Properties | ForEach-Object {
                $val = $_.Value
                if ($val -is [PSCustomObject]) {
                    $entry = @{}
                    $val.PSObject.Properties | ForEach-Object { $entry[$_.Name] = $_.Value }
                    $newHash[$_.Name] = $entry
                } else {
                    $newHash[$_.Name] = $val
                }
            }
        }
        $script:collections = $newHash
    }
}

function Load-Config {
    if (Test-Path $script:configPath) {
        try {
            $raw = Get-Content $script:configPath -Raw -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace($raw)) {
                $script:collections = @{}
                return $false
            }
            $config = $raw | ConvertFrom-Json
            if ($null -ne $config.themeMode) {
                $tm = [string]$config.themeMode
                if ($tm -in @("Default", "Steam", "Light", "HighContrast", "Windows")) {
                    $script:themeMode = $tm
                }
            }
            if ($null -ne $config.pegasusPath -and -not [string]::IsNullOrWhiteSpace([string]$config.pegasusPath)) {
                $script:pegasusPath = [string]$config.pegasusPath
            }
            $script:collections = @{}
            if ($null -ne $config.collections) {
                $config.collections.PSObject.Properties | ForEach-Object {
                    $v = $_.Value
                    $script:collections[$_.Name] = @{
                        name         = $v.name
                        metadataPath = $v.metadataPath
                        mediaPath    = $v.mediaPath
                        imageFolder  = $(if ($v.imageFolder) { $v.imageFolder } else { "box2dfront" })
                        thumbFolder  = $(if ($v.thumbFolder) { $v.thumbFolder } else { "box2dThumb" })
                        lastModified = $v.lastModified
                    }
                }
            }
            return $true
        } catch {
            $script:collections = @{}
            return $false
        }
    }
    $script:collections = @{}
    return $false
}

function Save-Config {
    try {
        Ensure-CollectionsHashtable
        $dir = Split-Path $script:configPath -Parent
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $config = @{
            collections = $script:collections
            themeMode   = $(if ($script:themeMode) { $script:themeMode } else { "Default" })
            pegasusPath = $(if ($script:pegasusPath) { [string]$script:pegasusPath } else { "" })
        }
        $json = $config | ConvertTo-Json -Depth 6
        $json | Out-File $script:configPath -Encoding UTF8 -Force
    } catch {
        Log-Message "Save-Config ERROR: $_" "Red"
    }
}

function Add-Collection {
    param($name, $metadataPath, $mediaPath)
    try {
        Ensure-CollectionsHashtable
        $script:collections[[string]$name] = @{
            name         = [string]$name
            metadataPath = [string]$metadataPath
            mediaPath    = [string]$mediaPath
            imageFolder  = "box2dfront"
            thumbFolder  = "box2dThumb"
            lastModified = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
        if (-not $script:collections.ContainsKey([string]$name)) {
            Log-Message "Add-Collection: key was NOT stored in hashtable!" "Red"
            return $false
        }
        Save-Config
        return $true
    } catch {
        Log-Message "Add-Collection ERROR: $_" "Red"
        return $false
    }
}

function Remove-Collection {
    param($name)
    Ensure-CollectionsHashtable
    if ($script:collections.ContainsKey($name)) {
        $script:collections.Remove($name)
        Save-Config
        return $true
    }
    return $false
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
function Create-Button {
    param($text, $x, $y, $w, $h)
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $text
    $btn.Location = New-Object System.Drawing.Point($x, $y)
    $btn.Size = New-Object System.Drawing.Size($w, $h)
    $btn.FlatStyle = "Flat"
    $btn.FlatAppearance.BorderColor = $script:theme.border
    $btn.FlatAppearance.MouseOverBackColor = $script:theme.buttonHover
    $btn.BackColor = $script:theme.button
    $btn.ForeColor = $script:theme.text
    $btn.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $btn
}

function Log-Message {
    param($msg, $color = "White")
    $ts = (Get-Date).ToString("HH:mm:ss")
    $f = "[$ts] $msg"
    if ($script:logBox) {
        $script:logBox.AppendText("$f`r`n")
        $script:logBox.SelectionStart = $script:logBox.Text.Length
        $script:logBox.ScrollToCaret()
    }
    if ($script:statusBar) { $script:statusBar.Text = $msg }
}

function RefreshCollectionList {
    try {
        Ensure-CollectionsHashtable
        if ($null -eq $script:collectionList) {
            Log-Message "RefreshCollectionList: collectionList control is null!" "Red"
            return
        }

        $script:collectionList.BeginUpdate()
        $script:collectionList.Items.Clear()

        $keys = @($script:collections.Keys)
        foreach ($key in $keys) {
            if (-not [string]::IsNullOrWhiteSpace([string]$key)) {
                [void]$script:collectionList.Items.Add([string]$key)
            }
        }

        $script:collectionList.EndUpdate()
        $script:collectionList.Refresh()

        if ($null -ne $script:countLabel -and -not $script:currentCollection) {
            $script:countLabel.Text = "Ready  |  Collections: $($script:collections.Count)"
        }

        Log-Message "List refreshed: $($script:collections.Count) collection(s) | ListBox items: $($script:collectionList.Items.Count)" "Cyan"
    } catch {
        Log-Message "RefreshCollectionList ERROR: $_" "Red"
    }
}

function Get-Col {
    if (-not $script:collectionList.SelectedItem) {
        Log-Message "No collection selected" "Red"
        return $null
    }
    $name = $script:collectionList.SelectedItem.ToString()
    return $script:collections[$name]
}

function Get-ToolsFolder {
    # Tools output files live in <media>\Tools, not next to metadata.txt
    # and not mixed in with ROMs, so they never get mistaken for a
    # curated import list or picked up by a folder scan again.
    param([string]$MediaPath)
    if ([string]::IsNullOrWhiteSpace($MediaPath)) { return $null }
    $toolsDir = Join-Path $MediaPath "Tools"
    if (-not (Test-Path $toolsDir)) {
        try { New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null } catch { return $MediaPath }
    }
    return $toolsDir
}

function Resolve-ToolsFile {
    # Looks for $FileName in <media>\Tools first (current convention),
    # then falls back to older locations (media root, metadata folder)
    # in case the file was generated before this convention existed.
    param([string]$MediaPath, [string]$FileName, [string]$MetaDir = "")
    if (-not [string]::IsNullOrWhiteSpace($MediaPath)) {
        $inTools = Join-Path (Join-Path $MediaPath "Tools") $FileName
        if (Test-Path $inTools) { return $inTools }
        $legacyMedia = Join-Path $MediaPath $FileName
        if (Test-Path $legacyMedia) { return $legacyMedia }
    }
    if (-not [string]::IsNullOrWhiteSpace($MetaDir)) {
        $legacyMeta = Join-Path $MetaDir $FileName
        if (Test-Path $legacyMeta) { return $legacyMeta }
    }
    if (-not [string]::IsNullOrWhiteSpace($MediaPath)) {
        return (Join-Path (Join-Path $MediaPath "Tools") $FileName)
    }
    return (Join-Path $MetaDir $FileName)
}

function Normalize-Newlines {
    param([string]$text)
    if ([string]::IsNullOrEmpty($text)) { return $text }
    $text = $text -replace "`r`n", "`n" -replace "`r", "`n"
    return ($text -replace "`n", "`r`n")
}

# ============================================================================
# COLLAPSIBLE LEFT SECTIONS
# ============================================================================
function Register-LeftSection {
    param(
        [System.Windows.Forms.GroupBox]$Group,
        [int]$ExpandedHeight,
        [bool]$Collapsible = $false,
        [bool]$StartExpanded = $true,
        [string]$Title = ""
    )
    $entry = [PSCustomObject]@{
        Group           = $Group
        ExpandedHeight  = $ExpandedHeight
        Collapsible     = $Collapsible
        Expanded        = $StartExpanded
        Title           = $(if ($Title) { $Title } else { $Group.Text.Trim() })
        ToggleBtn       = $null
    }
    
    if ($Collapsible) {
        $btn = New-Object System.Windows.Forms.Button
        $btn.Size = New-Object System.Drawing.Size(22, 18)
        $btn.Location = New-Object System.Drawing.Point(6, 1)
        $btn.FlatStyle = "Flat"
        $btn.FlatAppearance.BorderSize = 0
        $btn.BackColor = $script:theme.button
        $btn.ForeColor = $script:theme.accent
        $btn.Name = "mrtAccentBtn"
        $btn.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
        $btn.TabStop = $false
        $btn.Text = if ($StartExpanded) { "-" } else { "+" }
        $btn.Tag = $entry
        $btn.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
        $btn.Add_Click({
            param($sender, $e)
            $ent = $sender.Tag
            Toggle-LeftSection $ent
        })
        $Group.Controls.Add($btn)
        $btn.BringToFront()
        $entry.ToggleBtn = $btn
        
        # Also toggle by double-clicking the group header area
        $Group.Add_DoubleClick({
            param($sender, $e)
            $found = $script:leftSections | Where-Object { $_.Group -eq $sender } | Select-Object -First 1
            if ($found -and $found.Collapsible) { Toggle-LeftSection $found }
        })
        
        # Title padded; escape & for GroupBox accelerator rules
        $disp = $entry.Title -replace '&', '&&'
        $Group.Text = "      $disp "
        if (-not $StartExpanded) {
            foreach ($ctrl in @($Group.Controls)) {
                if ($ctrl -ne $btn) { $ctrl.Visible = $false }
            }
            $Group.Height = $script:collapsedHeaderH
        }
    }
    
    [void]$script:leftSections.Add($entry)
    return $entry
}

function Toggle-LeftSection {
    param($entry)
    if (-not $entry -or -not $entry.Collapsible) { return }
    $entry.Expanded = -not $entry.Expanded
    $grp = $entry.Group
    $btn = $entry.ToggleBtn
    
    if ($entry.Expanded) {
        $grp.Height = $entry.ExpandedHeight
        $grp.Text = ("      " + ($entry.Title -replace '&', '&&') + " ")
        if ($btn) { $btn.Text = "-" }
        foreach ($ctrl in @($grp.Controls)) {
            if ($ctrl -ne $btn) { $ctrl.Visible = $true }
        }
    } else {
        foreach ($ctrl in @($grp.Controls)) {
            if ($ctrl -ne $btn) { $ctrl.Visible = $false }
        }
        $grp.Height = $script:collapsedHeaderH
        $grp.Text = ("      " + ($entry.Title -replace '&', '&&') + " ")
        if ($btn) { $btn.Text = "+" }
    }
    if ($btn) {
        $btn.Location = New-Object System.Drawing.Point(6, 1)
        $btn.BringToFront()
    }
    Relayout-LeftSections
}

function Relayout-LeftSections {
    if ($null -eq $script:leftPanelRef -or $script:leftSections.Count -eq 0) { return }
    $y = 40
    $first = $true
    foreach ($sec in $script:leftSections) {
        if ($first) {
            $y = $sec.Group.Location.Y
            $first = $false
        }
    }
    $y = 40
    foreach ($sec in $script:leftSections) {
        $sec.Group.Location = New-Object System.Drawing.Point(5, $y)
        $h = if ($sec.Collapsible -and -not $sec.Expanded) {
            $script:collapsedHeaderH
        } else {
            $sec.ExpandedHeight
        }
        $sec.Group.Height = $h
        if ($sec.ToggleBtn) {
            $sec.ToggleBtn.Location = New-Object System.Drawing.Point(6, 1)
            $sec.ToggleBtn.BringToFront()
        }
        $y += $h + $script:sectionGap
    }
}

# ============================================================================
# GET COLLECTION NAME FROM FILENAME
# ============================================================================
function Get-CollectionNameFromFile {
    param($filePath)
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
    if ($fileName -match '^(.+)\.metadata\.pegasus$') {
        return $matches[1]
    } elseif ($fileName -match '^(.+)\.pegasus$') {
        return $matches[1]
    } elseif ($fileName -match '^(.+)\.metadata$') {
        return $matches[1]
    } else {
        return $fileName
    }
}

# ============================================================================
# ADD COLLECTION DIALOG
# ============================================================================
function Show-CreateCollectionDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Create New Collection"
    $dlg.Size = New-Object System.Drawing.Size(500, 320)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.BackColor = $script:theme.background
    $dlg.ForeColor = $script:theme.text
    
    $y = 18
    $sp = 38
    
    $lName = New-Object System.Windows.Forms.Label
    $lName.Text = "Collection Name:"
    $lName.Location = New-Object System.Drawing.Point(20, $y)
    $lName.Size = New-Object System.Drawing.Size(130, 25)
    $lName.ForeColor = $script:theme.text
    $dlg.Controls.Add($lName)
    
    $tName = New-Object System.Windows.Forms.TextBox
    $tName.Location = New-Object System.Drawing.Point(155, $y)
    $tName.Size = New-Object System.Drawing.Size(300, 25)
    $tName.BackColor = $script:theme.editor
    $tName.ForeColor = $script:theme.text
    $tName.BorderStyle = "FixedSingle"
    $dlg.Controls.Add($tName)
    
    $y += $sp
    $lFolder = New-Object System.Windows.Forms.Label
    $lFolder.Text = "Collection Folder:"
    $lFolder.Location = New-Object System.Drawing.Point(20, $y)
    $lFolder.Size = New-Object System.Drawing.Size(130, 25)
    $lFolder.ForeColor = $script:theme.text
    $dlg.Controls.Add($lFolder)
    
    $tFolder = New-Object System.Windows.Forms.TextBox
    $tFolder.Location = New-Object System.Drawing.Point(155, $y)
    $tFolder.Size = New-Object System.Drawing.Size(255, 25)
    $tFolder.BackColor = $script:theme.editor
    $tFolder.ForeColor = $script:theme.text
    $tFolder.BorderStyle = "FixedSingle"
    $dlg.Controls.Add($tFolder)
    
    $bFolder = Create-Button "..." 420 $y 35 25
    $bFolder.Add_Click({
        $fd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fd.Description = "Select folder for the new collection (metadata + media)"
        $fd.ShowNewFolderButton = $true
        if ($fd.ShowDialog() -eq "OK") {
            $tFolder.Text = $fd.SelectedPath
            if ([string]::IsNullOrWhiteSpace($tName.Text)) {
                $tName.Text = [System.IO.Path]::GetFileName($fd.SelectedPath)
            }
        }
    })
    $dlg.Controls.Add($bFolder)
    
    $y += $sp
    $lShort = New-Object System.Windows.Forms.Label
    $lShort.Text = "Shortname:"
    $lShort.Location = New-Object System.Drawing.Point(20, $y)
    $lShort.Size = New-Object System.Drawing.Size(130, 25)
    $lShort.ForeColor = $script:theme.text
    $dlg.Controls.Add($lShort)
    
    $tShort = New-Object System.Windows.Forms.TextBox
    $tShort.Location = New-Object System.Drawing.Point(155, $y)
    $tShort.Size = New-Object System.Drawing.Size(300, 25)
    $tShort.BackColor = $script:theme.editor
    $tShort.ForeColor = $script:theme.text
    $tShort.BorderStyle = "FixedSingle"
    $dlg.Controls.Add($tShort)
    
    $y += $sp
    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = "Creates metadata .txt, media\box2dfront, media\box2dThumb, and adds the collection."
    $hint.Location = New-Object System.Drawing.Point(20, $y)
    $hint.Size = New-Object System.Drawing.Size(440, 40)
    $hint.ForeColor = $script:theme.textDim
    $dlg.Controls.Add($hint)
    
    $y += 50
    $ok = Create-Button "Create" 150 $y 120 35
    $ok.BackColor = $script:theme.success
    $ok.ForeColor = [System.Drawing.Color]::White
    $ok.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $ok.Add_Click({
        $name = $tName.Text.Trim()
        $folder = $tFolder.Text.Trim()
        $short = $tShort.Text.Trim()
        
        if ([string]::IsNullOrWhiteSpace($name)) {
            [System.Windows.Forms.MessageBox]::Show("Enter a collection name.", "Error", "OK", "Error")
            return
        }
        if ([string]::IsNullOrWhiteSpace($folder)) {
            [System.Windows.Forms.MessageBox]::Show("Select a collection folder.", "Error", "OK", "Error")
            return
        }
        if (-not (Test-Path $folder)) {
            try {
                New-Item -ItemType Directory -Path $folder -Force | Out-Null
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Could not create folder: $folder", "Error", "OK", "Error")
                return
            }
        }
        if ([string]::IsNullOrWhiteSpace($short)) {
            $short = ($name -replace '[^A-Za-z0-9]', '').ToLower()
            if ([string]::IsNullOrWhiteSpace($short)) { $short = "collection" }
        }
        
        Ensure-CollectionsHashtable
        if ($script:collections.ContainsKey($name)) {
            $result = [System.Windows.Forms.MessageBox]::Show("Collection '$name' already exists. Overwrite metadata file?", "Warning", "YesNo", "Warning")
            if ($result -eq "No") { return }
        }
        
        try {
            $metaFile = Join-Path $folder "$name.txt"
            $mediaPath = Join-Path $folder "media"
            $frontPath = Join-Path $mediaPath "box2dfront"
            $thumbPath = Join-Path $mediaPath "box2dThumb"
            
            foreach ($d in @($mediaPath, $frontPath, $thumbPath)) {
                if (-not (Test-Path $d)) {
                    New-Item -ItemType Directory -Path $d -Force | Out-Null
                }
            }
            
            $header = @"
collection: $name
shortname: $short
launch: 
assets.box_front: 
assets.logo: 
description: 

"@
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText($metaFile, $header, $utf8NoBom)
            
            $okAdd = Add-Collection $name $metaFile $mediaPath
            RefreshCollectionList
            
            if ($null -ne $script:collectionList) {
                if (-not $script:collectionList.Items.Contains($name)) {
                    [void]$script:collectionList.Items.Add($name)
                }
                $idx = $script:collectionList.Items.IndexOf($name)
                if ($idx -ge 0) { $script:collectionList.SelectedIndex = $idx }
            }
            
            $script:currentCollection = $script:collections[$name]
            UpdateEditor
            UpdateStats
            
            Log-Message "Created collection: $name" "Green"
            Log-Message "Metadata: $metaFile" "Cyan"
            Log-Message "Media: $mediaPath" "Cyan"
            $dlg.Close()
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Create failed: $_", "Error", "OK", "Error")
            Log-Message "Create collection ERROR: $_" "Red"
        }
    })
    $dlg.Controls.Add($ok)
    
    $cn = Create-Button "Cancel" 285 $y 100 35
    $cn.Add_Click({ $dlg.Close() })
    $dlg.Controls.Add($cn)
    
    $dlg.ShowDialog()
}

function Show-AddCollectionDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Add Collection"
    $dlg.Size = New-Object System.Drawing.Size(480, 260)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.BackColor = $script:theme.background
    $dlg.ForeColor = $script:theme.text
    
    $y = 20
    $sp = 40
    
    $l2 = New-Object System.Windows.Forms.Label
    $l2.Text = "Metadata File:"
    $l2.Location = New-Object System.Drawing.Point(20, $y)
    $l2.Size = New-Object System.Drawing.Size(120, 25)
    $l2.ForeColor = $script:theme.text
    $dlg.Controls.Add($l2)
    
    $t2 = New-Object System.Windows.Forms.TextBox
    $t2.Location = New-Object System.Drawing.Point(150, $y)
    $t2.Size = New-Object System.Drawing.Size(240, 25)
    $t2.BackColor = $script:theme.editor
    $t2.ForeColor = $script:theme.text
    $t2.BorderStyle = "FixedSingle"
    $dlg.Controls.Add($t2)
    
    $b2 = Create-Button "..." 395 $y 35 25
    $b2.Add_Click({
        $of = New-Object System.Windows.Forms.OpenFileDialog
        $of.Title = "Select Pegasus Metadata File"
        $of.Filter = "Metadata Files (*.txt)|*.txt|All Files (*.*)|*.*"
        $of.InitialDirectory = [Environment]::GetFolderPath("Desktop")
        if ($of.ShowDialog() -eq "OK") { 
            $t2.Text = $of.FileName
        }
    })
    $dlg.Controls.Add($b2)
    
    $y += $sp
    $l3 = New-Object System.Windows.Forms.Label
    $l3.Text = "Media Folder:"
    $l3.Location = New-Object System.Drawing.Point(20, $y)
    $l3.Size = New-Object System.Drawing.Size(120, 25)
    $l3.ForeColor = $script:theme.text
    $dlg.Controls.Add($l3)
    
    $t3 = New-Object System.Windows.Forms.TextBox
    $t3.Location = New-Object System.Drawing.Point(150, $y)
    $t3.Size = New-Object System.Drawing.Size(240, 25)
    $t3.BackColor = $script:theme.editor
    $t3.ForeColor = $script:theme.text
    $t3.BorderStyle = "FixedSingle"
    $dlg.Controls.Add($t3)
    
    $b3 = Create-Button "..." 395 $y 35 25
    $b3.Add_Click({
        $fd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fd.Description = "Select media folder (contains box2dfront, box2dThumb)"
        $metaPath = $t2.Text.Trim()
        if (-not [string]::IsNullOrWhiteSpace($metaPath)) {
            $defaultPath = Split-Path $metaPath -Parent
            $mediaPath = Join-Path $defaultPath "media"
            if (Test-Path $mediaPath) {
                $fd.SelectedPath = $mediaPath
            } else {
                $fd.SelectedPath = $defaultPath
            }
        }
        if ($fd.ShowDialog() -eq "OK") { 
            $t3.Text = $fd.SelectedPath
        }
    })
    $dlg.Controls.Add($b3)
    
    $y += $sp + 10
    $ok = Create-Button "Add Collection" 150 $y 120 35
    $ok.BackColor = $script:theme.success
    $ok.ForeColor = [System.Drawing.Color]::White
    $ok.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $ok.Add_Click({
        $meta = $t2.Text.Trim()
        $media = $t3.Text.Trim()
        
        if (-not (Test-Path $meta)) {
            [System.Windows.Forms.MessageBox]::Show("Metadata file not found: $meta", "Error", "OK", "Error")
            return
        }
        
        if ([string]::IsNullOrWhiteSpace($media)) {
            [System.Windows.Forms.MessageBox]::Show("Please select a Media Folder.", "Error", "OK", "Error")
            return
        }
        
        if (-not (Test-Path $media)) {
            [System.Windows.Forms.MessageBox]::Show("Media folder not found: $media", "Error", "OK", "Error")
            return
        }
        
        $name = Get-CollectionNameFromFile $meta
        
        if (-not $name) {
            [System.Windows.Forms.MessageBox]::Show("Could not determine collection name from filename.", "Error", "OK", "Error")
            return
        }
        
        Ensure-CollectionsHashtable
        
        if ($script:collections.ContainsKey($name)) {
            $result = [System.Windows.Forms.MessageBox]::Show("Collection '$name' already exists. Overwrite?", "Warning", "YesNo", "Warning")
            if ($result -eq "No") {
                return
            }
            $script:collections.Remove($name)
        }
        
        $okAdd = Add-Collection $name $meta $media
        Log-Message "Add-Collection returned: $okAdd | Keys now: $(@($script:collections.Keys) -join ', ')" "Cyan"
        
        RefreshCollectionList
        
        if ($null -ne $script:collectionList) {
            if (-not $script:collectionList.Items.Contains($name)) {
                [void]$script:collectionList.Items.Add($name)
                Log-Message "Direct-added '$name' to ListBox (Refresh missed it)" "Yellow"
            }
            $idx = $script:collectionList.Items.IndexOf($name)
            if ($idx -ge 0) {
                $script:collectionList.SelectedIndex = $idx
            }
            $script:collectionList.Refresh()
        } else {
            Log-Message "ERROR: collectionList control is null after add!" "Red"
        }
        
        if ($null -ne $script:countLabel) {
            $script:countLabel.Text = "Ready  |  Collections: $($script:collections.Count)"
        }
        
        $script:currentCollection = $script:collections[$name]
        UpdateEditor
        UpdateStats
        
        Log-Message "Added: $name  (hashtable: $($script:collections.Count) | listbox: $($script:collectionList.Items.Count))" "Green"
        Log-Message "Media folder: $media" "Cyan"
        $dlg.Close()
    })
    $dlg.Controls.Add($ok)
    
    $cn = Create-Button "Cancel" 280 $y 100 35
    $cn.Add_Click({ $dlg.Close() })
    $dlg.Controls.Add($cn)
    
    $dlg.ShowDialog()
}

# ============================================================================
# CORE FUNCTIONS
# ============================================================================
function UpdateStats {
    if (-not $script:currentCollection) {
        if ($script:countLabel) {
            $script:countLabel.Text = "Ready  |  Collections: $($script:collections.Count)"
        }
        return
    }
    try {
        $path = $script:currentCollection.metadataPath
        if (Test-Path $path) {
            $c = Get-Content $path -Raw
            $total = ([regex]::Matches($c, '(?m)^game:\s*')).Count
            if ($total -eq 0) { $total = ([regex]::Matches($c, 'game:\s*')).Count }
            $art = ([regex]::Matches($c, 'assets\.box_front:')).Count
            $missing = [Math]::Max(0, $total - $art)
            $bp = $script:currentCollection.mediaPath
            $fp = Join-Path $bp "box2dfront"
            $tp = Join-Path $bp "box2dThumb"
            $imgPng = @(Get-ChildItem $fp -Filter "*.png" -ErrorAction SilentlyContinue).Count
            $imgJpg = @(Get-ChildItem $fp -Filter "*.jpg" -ErrorAction SilentlyContinue).Count
            $img = $imgPng + $imgJpg
            $thPng = @(Get-ChildItem $tp -Filter "*.png" -ErrorAction SilentlyContinue).Count
            $thJpg = @(Get-ChildItem $tp -Filter "*.jpg" -ErrorAction SilentlyContinue).Count
            $thumbs = $thPng + $thJpg
            
            if ($script:countLabel) {
                $script:countLabel.Text = "Games: $total  |  Box Art: $art  |  Missing: $missing  |  Images: $img"
            }
            if ($script:statusBar) {
                $script:statusBar.Text = "Loaded: $($script:currentCollection.name) | Games: $total | Box Art: $art | Missing: $missing | Images: $img"
            }
        }
    } catch {
        if ($script:statusBar) { $script:statusBar.Text = "Error loading stats" }
    }
}

function UpdateEditor {
    if (-not $script:collectionList.SelectedItem) {
        if ($script:editorBox) { $script:editorBox.Text = "No collection selected." }
        if ($script:gameListBox) { $script:gameListBox.Items.Clear() }
        $script:parsedGames = @()
        return
    }
    $name = $script:collectionList.SelectedItem.ToString()
    $collection = $script:collections[$name]
    $script:currentCollection = $collection
    try {
        $path = $collection.metadataPath
        if (Test-Path $path) {
            $raw = Get-Content $path -Raw -ErrorAction Stop
            $normalized = Normalize-Newlines $raw
            if ($null -ne $script:editorBox) {
                $script:editorBox.Text = $normalized
            }
            
            try {
                Parse-PegasusMetadata $raw
                FilterGameList
            } catch {
                Log-Message "Parse warning: $_" "Yellow"
                $script:parsedGames = @()
            }
            
            if (-not $script:rawMode) {
                if ($script:rawSearchBar) { $script:rawSearchBar.Visible = $false }
                if ($script:editorBox) { $script:editorBox.Visible = $false }
                if ($script:metaOuter) { $script:metaOuter.Visible = $true }
                # Respect collapse: Item Metadata + Games (list/search) stay in sync
                Apply-MetaAndGamesCollapseState
            } else {
                if ($script:rawSearchBar) { $script:rawSearchBar.Visible = $true }
                if ($script:editorBox) {
                    $script:editorBox.Visible = $true
                    try { $script:editorBox.Location = New-Object System.Drawing.Point(5, 80) } catch {}
                }
                if ($script:gameListBox) { $script:gameListBox.Visible = $false }
                if ($script:detailPanel) { $script:detailPanel.Visible = $false }
                if ($script:metaOuter) { $script:metaOuter.Visible = $false }
                if ($script:gamesOuter) { $script:gamesOuter.Visible = $false }
                if ($script:gameSearchBox) { $script:gameSearchBox.Visible = $false }
                if ($script:searchLabel) { $script:searchLabel.Visible = $false }
            }
            
            $cnt = 0
            if ($null -ne $script:parsedGames) { $cnt = @($script:parsedGames).Count }
            if ($script:statusBar) { $script:statusBar.Text = "Loaded: $name ($cnt games)" }
            Log-Message "Loaded: $name - $cnt games" "Green"
            UpdateStats
        } else {
            if ($script:editorBox) {
                $script:editorBox.Text = "ERROR: File not found`r`n$path"
                $script:editorBox.Visible = $true
            }
            Log-Message "ERROR: File not found" "Red"
        }
    } catch {
        if ($script:editorBox) {
            $script:editorBox.Text = "ERROR: $_"
            $script:editorBox.Visible = $true
        }
        Log-Message "ERROR: $_" "Red"
    }
}

function SaveMeta {
    if (-not $script:collectionList.SelectedItem) {
        Log-Message "No collection selected" "Red"
        return
    }
    $name = $script:collectionList.SelectedItem.ToString()
    $c = $script:collections[$name]
    try {
        # Remember place so Save does not jump the list / caret
        $prevTitle = $null
        $prevTop = -1
        $prevSelStart = -1
        $prevSelLen = 0
        if ($script:gameListBox) {
            if ($script:gameListBox.SelectedIndex -ge 0 -and $script:gameListBox.SelectedItem) {
                $prevTitle = $script:gameListBox.SelectedItem.ToString()
            }
            try { $prevTop = $script:gameListBox.TopIndex } catch { $prevTop = -1 }
        }
        if ($script:rawMode -and $script:editorBox) {
            try {
                $prevSelStart = $script:editorBox.SelectionStart
                $prevSelLen = $script:editorBox.SelectionLength
            } catch {}
        }

        if (-not $script:rawMode) {
            Apply-HeaderFieldsFromUI
            if ($script:gameListBox.SelectedIndex -ge 0) {
                ApplyGameFields
            }
        }
        
        if ($script:rawMode) {
            $text = $script:editorBox.Text
            $text = $text -replace "`r`n", "`n" -replace "`r", "`n"
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText($c.metadataPath, $text, $utf8NoBom)
        } else {
            $text = Build-PegasusMetadata
            $text = $text -replace "`r`n", "`n" -replace "`r", "`n"
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText($c.metadataPath, $text, $utf8NoBom)
        }
        Log-Message "Saved: $name ($($script:parsedGames.Count) games)" "Green"

        $script:suppressGameSelect = $true
        try {
            UpdateEditor
            # Restore list selection + scroll position
            if (-not $script:rawMode -and $script:gameListBox -and $script:gameListBox.Items.Count -gt 0) {
                $idx = -1
                if ($prevTitle) {
                    $idx = $script:gameListBox.Items.IndexOf($prevTitle)
                }
                if ($idx -ge 0) {
                    $script:gameListBox.SelectedIndex = $idx
                }
                if ($prevTop -ge 0) {
                    try {
                        $maxTop = [Math]::Max(0, $script:gameListBox.Items.Count - 1)
                        $script:gameListBox.TopIndex = [Math]::Min($prevTop, $maxTop)
                    } catch {}
                }
            }
            # Restore raw editor caret / selection
            if ($script:rawMode -and $script:editorBox -and $prevSelStart -ge 0) {
                try {
                    $len = $script:editorBox.Text.Length
                    $start = [Math]::Min($prevSelStart, $len)
                    $selLen = [Math]::Min($prevSelLen, [Math]::Max(0, $len - $start))
                    $script:editorBox.SelectionStart = $start
                    $script:editorBox.SelectionLength = $selLen
                    $script:editorBox.ScrollToCaret()
                } catch {}
            }
        } finally {
            $script:suppressGameSelect = $false
        }
    } catch {
        Log-Message "ERROR saving: $_" "Red"
    }
}

# ============================================================================
# PARSE FUNCTIONS
# ============================================================================
function Parse-HeaderFields {
    param([string]$headerText)
    $fields = @{}
    if ([string]::IsNullOrWhiteSpace($headerText)) { return $fields }
    
    $lines = $headerText -split "`n"
    $currentKey = $null
    $currentVals = @()
    
    foreach ($line in $lines) {
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        if ($line -match '^([^\s][^:]*):\s*(.*)$') {
            if ($null -ne $currentKey) {
                $fields[$currentKey] = ($currentVals -join "`n").Trim()
            }
            $currentKey = $matches[1].Trim()
            $val = $matches[2]
            $currentVals = @()
            if (-not [string]::IsNullOrWhiteSpace($val)) {
                $currentVals += $val.Trim()
            }
        } elseif ($null -ne $currentKey -and $line -match '^\s+(.+)$') {
            $currentVals += $matches[1].Trim()
        }
    }
    if ($null -ne $currentKey) {
        $fields[$currentKey] = ($currentVals -join "`n").Trim()
    }
    return $fields
}

function Parse-GameBlock {
    param([string]$block)
    $block = $block.Trim()
    if (-not ($block -match '(?m)^game:\s*')) { return $null }
    
    $fields = @{}
    $lines = $block -split "`n"
    $currentKey = $null
    $currentVals = @()
    
    foreach ($line in $lines) {
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        
        if ($line -match '^([^\s][^:]*):\s*(.*)$') {
            if ($null -ne $currentKey) {
                $fields[$currentKey] = ($currentVals -join "`n").Trim()
            }
            $currentKey = $matches[1].Trim()
            $val = $matches[2]
            $currentVals = @()
            if (-not [string]::IsNullOrWhiteSpace($val)) {
                $currentVals += $val.Trim()
            }
        } elseif ($null -ne $currentKey -and $line -match '^\s+(.+)$') {
            $currentVals += $matches[1].Trim()
        }
    }
    if ($null -ne $currentKey) {
        $fields[$currentKey] = ($currentVals -join "`n").Trim()
    }
    
    if (-not $fields.ContainsKey("game")) { return $null }
    
    return [PSCustomObject]@{
        Fields = $fields
        Title  = [string]$fields["game"]
    }
}

function Parse-PegasusMetadata {
    param([string]$content)
    $script:parsedHeader = ""
    $script:parsedHeaderFields = @{}
    $script:parsedGames = @()
    
    if ([string]::IsNullOrWhiteSpace($content)) { return }
    
    $content = $content -replace "`r`n", "`n" -replace "`r", "`n"
    $parts = [regex]::Split($content, '(?m)(?=^game:\s*)')
    
    $headerParts = New-Object System.Collections.ArrayList
    $games = New-Object System.Collections.ArrayList
    
    foreach ($part in $parts) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        if ($part -match '(?m)^game:\s*') {
            $gameObj = Parse-GameBlock $part
            if ($null -ne $gameObj) { [void]$games.Add($gameObj) }
        } else {
            [void]$headerParts.Add($part.TrimEnd())
        }
    }
    
    $script:parsedHeader = ($headerParts -join "`n").Trim()
    $script:parsedHeaderFields = Parse-HeaderFields $script:parsedHeader
    $script:parsedGames = @($games.ToArray())
    
    Load-HeaderFieldsIntoUI
}

function Load-HeaderFieldsIntoUI {
    if ($null -eq $script:headerControls) { return }
    $keys = @("collection", "shortname", "launch", "assets.box_front", "assets.logo", "description")
    foreach ($k in $keys) {
        if ($script:headerControls.ContainsKey($k)) {
            $val = ""
            if ($script:parsedHeaderFields -and $script:parsedHeaderFields.ContainsKey($k)) {
                $val = [string]$script:parsedHeaderFields[$k]
            }
            $script:headerControls[$k].Text = $val
        }
    }
}

function Apply-HeaderFieldsFromUI {
    if ($null -eq $script:headerControls) { return }
    if ($null -eq $script:parsedHeaderFields) { $script:parsedHeaderFields = @{} }
    $keys = @("collection", "shortname", "launch", "assets.box_front", "assets.logo", "description")
    foreach ($k in $keys) {
        if ($script:headerControls.ContainsKey($k)) {
            $script:parsedHeaderFields[$k] = $script:headerControls[$k].Text
        }
    }
    $sb = New-Object System.Text.StringBuilder
    $order = @("collection", "shortname", "launch", "assets.box_front", "assets.logo", "description")
    $written = @{}
    foreach ($k in $order) {
        if ($script:parsedHeaderFields.ContainsKey($k) -and -not [string]::IsNullOrWhiteSpace([string]$script:parsedHeaderFields[$k])) {
            $val = [string]$script:parsedHeaderFields[$k]
            if ($val -match "`n") {
                [void]$sb.AppendLine("${k}:")
                foreach ($line in ($val -split "`n")) {
                    [void]$sb.AppendLine("  $line")
                }
            } else {
                [void]$sb.AppendLine("${k}: $val")
            }
            $written[$k] = $true
        }
    }
    foreach ($k in @($script:parsedHeaderFields.Keys)) {
        if (-not $written.ContainsKey($k) -and -not [string]::IsNullOrWhiteSpace([string]$script:parsedHeaderFields[$k])) {
            $val = [string]$script:parsedHeaderFields[$k]
            if ($val -match "`n") {
                [void]$sb.AppendLine("${k}:")
                foreach ($line in ($val -split "`n")) {
                    [void]$sb.AppendLine("  $line")
                }
            } else {
                [void]$sb.AppendLine("${k}: $val")
            }
        }
    }
    $script:parsedHeader = $sb.ToString().TrimEnd()
}

function Build-PegasusMetadata {
    $sb = New-Object System.Text.StringBuilder
    
    if (-not [string]::IsNullOrWhiteSpace($script:parsedHeader)) {
        [void]$sb.AppendLine($script:parsedHeader.TrimEnd())
        [void]$sb.AppendLine("")
    }
    
    foreach ($g in $script:parsedGames) {
        $fields = $g.Fields
        $title = if ($fields.ContainsKey("game")) { $fields["game"] } else { $g.Title }
        [void]$sb.AppendLine("game: $title")
        
        $preferredOrder = @(
            "sort_title", "sort-title", "file", "developer", "publisher",
            "genre", "players", "release", "rating", "description",
            "game_id", 
            "assets.box_front", "assets.box_full", "assets.boxFull", 
            "assets.box_back", "assets.box_front_thumb",
            "assets.screenshot", "assets.video", "assets.logo",
            "assets.titlescreen", "assets.fanart", "assets.cartridge",
            "assets.steamgrid", "assets.marquee", "assets.banner"
        )
        
        $written = @{ "game" = $true }
        foreach ($key in $preferredOrder) {
            $actualKey = $null
            if ($fields.ContainsKey($key)) { $actualKey = $key }
            elseif ($key -eq "sort_title" -and $fields.ContainsKey("sort-title")) { $actualKey = "sort-title" }
            elseif ($key -eq "sort-title" -and $fields.ContainsKey("sort_title")) { $actualKey = "sort_title" }
            
            if ($null -ne $actualKey -and -not $written.ContainsKey($actualKey)) {
                $val = $fields[$actualKey]
                if (-not [string]::IsNullOrWhiteSpace($val)) {
                    if ($val -match "`n") {
                        [void]$sb.AppendLine("${actualKey}:")
                        foreach ($vline in ($val -split "`n")) {
                            [void]$sb.AppendLine("  $($vline.Trim())")
                        }
                    } else {
                        [void]$sb.AppendLine("${actualKey}: $val")
                    }
                }
                $written[$actualKey] = $true
            }
        }
        
        foreach ($key in @($fields.Keys)) {
            if ($written.ContainsKey($key)) { continue }
            $val = $fields[$key]
            if ([string]::IsNullOrWhiteSpace($val)) { continue }
            if ($val -match "`n") {
                [void]$sb.AppendLine("${key}:")
                foreach ($vline in ($val -split "`n")) {
                    [void]$sb.AppendLine("  $($vline.Trim())")
                }
            } else {
                [void]$sb.AppendLine("${key}: $val")
            }
        }
        [void]$sb.AppendLine("")
    }
    
    return $sb.ToString().TrimEnd() + "`n"
}

function FilterGameList {
    if ($null -eq $script:gameListBox) { return }
    $filter = ""
    if ($null -ne $script:gameSearchBox) {
        $filter = $script:gameSearchBox.Text.Trim().ToLower()
    }
    
    # Remember current selection so Add Box Art / refresh does not jump away
    $prevTitle = $null
    if ($script:gameListBox.SelectedIndex -ge 0 -and $script:gameListBox.SelectedItem) {
        $prevTitle = $script:gameListBox.SelectedItem.ToString()
    }
    
    $script:suppressGameSelect = $true
    $script:gameListBox.BeginUpdate()
    $script:gameListBox.Items.Clear()
    
    foreach ($g in $script:parsedGames) {
        $title = [string]$g.Title
        if ([string]::IsNullOrWhiteSpace($filter) -or $title.ToLower().Contains($filter)) {
            [void]$script:gameListBox.Items.Add($title)
        }
    }
    
    $script:gameListBox.EndUpdate()
    $script:suppressGameSelect = $false
    
    if ($script:gameListBox.Items.Count -gt 0) {
        $restored = $false
        if ($prevTitle) {
            $idx = $script:gameListBox.Items.IndexOf($prevTitle)
            if ($idx -ge 0) {
                $script:gameListBox.SelectedIndex = $idx
                $restored = $true
            }
        }
        if (-not $restored -and $script:gameListBox.SelectedIndex -lt 0) {
            $script:gameListBox.SelectedIndex = 0
        }
    }
}

function LoadSelectedGameFields {
    if ($null -eq $script:gameListBox -or $script:gameListBox.SelectedIndex -lt 0) { return }
    $title = $script:gameListBox.SelectedItem.ToString()
    
    $game = $script:parsedGames | Where-Object { $_.Title -eq $title } | Select-Object -First 1
    if ($null -eq $game) { return }
    
    $fields = $game.Fields
    foreach ($key in @($script:fieldControls.Keys)) {
        $ctrl = $script:fieldControls[$key]
        $val = ""
        if ($fields.ContainsKey($key)) {
            $val = $fields[$key]
        } elseif ($key -eq "sort_title" -and $fields.ContainsKey("sort-title")) {
            $val = $fields["sort-title"]
        }
        $ctrl.Text = $val
    }
}

function ApplyGameFields {
    Apply-HeaderFieldsFromUI
    
    if ($null -eq $script:gameListBox -or $script:gameListBox.SelectedIndex -lt 0) {
        Log-Message "Collection metadata applied (no game selected)" "Cyan"
        return
    }
    $oldTitle = $script:gameListBox.SelectedItem.ToString()
    $game = $null
    $idx = -1
    for ($i = 0; $i -lt $script:parsedGames.Count; $i++) {
        if ($script:parsedGames[$i].Title -eq $oldTitle) {
            $game = $script:parsedGames[$i]
            $idx = $i
            break
        }
    }
    if ($null -eq $game) {
        Log-Message "Game not found in parsed data" "Red"
        return
    }
    
    $fields = @{}
    foreach ($k in @($game.Fields.Keys)) { $fields[$k] = $game.Fields[$k] }
    
    foreach ($key in @($script:fieldControls.Keys)) {
        $val = $script:fieldControls[$key].Text
        if ([string]::IsNullOrWhiteSpace($val)) {
            if ($fields.ContainsKey($key)) { $fields.Remove($key) }
            if ($key -eq "sort_title" -and $fields.ContainsKey("sort-title")) { $fields.Remove("sort-title") }
        } else {
            $fields[$key] = $val.Trim()
            if ($key -eq "sort_title" -and $fields.ContainsKey("sort-title")) { $fields.Remove("sort-title") }
        }
    }
    
    $newTitle = if ($fields.ContainsKey("game")) { $fields["game"] } else { $oldTitle }
    $script:parsedGames[$idx] = [PSCustomObject]@{ Fields = $fields; Title = $newTitle }
    
    FilterGameList
    $newIdx = $script:gameListBox.Items.IndexOf($newTitle)
    if ($newIdx -ge 0) { $script:gameListBox.SelectedIndex = $newIdx }
    
    Log-Message "Applied collection + game fields for: $newTitle" "Green"
}

function Apply-RawEditorLayout {
    # Size Find bar + raw editor + terminal so nothing overlaps and the
    # terminal header + drag grip stay visible/usable.
    if (-not $script:rawMode) { return }
    $gap = 6
    $fullW = if ($script:contentFullW) { $script:contentFullW } else { 1132 }
    $editorTop = 80
    $searchTop = 48
    $searchH = 30

    # Available height inside the right panel (prefer client size)
    $avail = 700
    try {
        if ($script:rightPanelRef -and $script:rightPanelRef.ClientSize.Height -gt 100) {
            $avail = $script:rightPanelRef.ClientSize.Height
        } elseif ($script:mainForm) {
            $avail = [Math]::Max(400, $script:mainForm.ClientSize.Height - 80)
        }
    } catch {}

    # Terminal height (expanded or collapsed), capped so editor keeps room
    if ($script:termExpanded) {
        $termH = if ($script:termExpandedH -and $script:termExpandedH -ge 100) { $script:termExpandedH } else { 220 }
        $maxTerm = [Math]::Max(120, [int]($avail * 0.40))
        if ($termH -gt $maxTerm) { $termH = $maxTerm }
        if ($termH -lt 100) { $termH = 100 }
    } else {
        $termH = if ($script:termCollapsedH) { $script:termCollapsedH } else { 28 }
    }

    $termY = $avail - $termH - 8
    if ($termY -lt ($editorTop + 120)) {
        # Not enough room - shrink terminal further
        $termY = $editorTop + 120
        $termH = [Math]::Max(80, $avail - $termY - 8)
    }

    $editorH = $termY - $editorTop - $gap
    if ($editorH -lt 100) { $editorH = 100 }

    if ($script:rawSearchBar) {
        $script:rawSearchBar.Location = New-Object System.Drawing.Point(5, $searchTop)
        $script:rawSearchBar.Size = New-Object System.Drawing.Size($fullW, $searchH)
        $script:rawSearchBar.Visible = $true
        $script:rawSearchBar.BringToFront()
    }
    if ($script:editorBox) {
        $script:editorBox.Location = New-Object System.Drawing.Point(5, $editorTop)
        $script:editorBox.Size = New-Object System.Drawing.Size($fullW, $editorH)
        $script:editorBox.Visible = $true
        $script:editorBox.BringToFront()
    }
    if ($script:termOuter) {
        $script:termOuter.Location = New-Object System.Drawing.Point(5, $termY)
        $script:termOuter.Size = New-Object System.Drawing.Size($fullW, $termH)
        $script:termOuter.Visible = $true
        $script:termOuter.BringToFront()
        if ($script:termExpanded) { $script:termExpandedH = $termH }
        Apply-TerminalInnerLayout
    }
}

function Relayout-TerminalPosition {
    # Sit terminal just under Item Metadata / raw editor. Full width of right content area.
    if ($null -eq $script:termOuter) { return }

    # Raw mode uses its own shared layout (editor + terminal)
    if ($script:rawMode) {
        Apply-RawEditorLayout
        return
    }

    $gap = 6
    $fullW = if ($script:contentFullW) { $script:contentFullW } else { 1132 }
    $metaTop = 48
    if ($script:metaOuter) { $metaTop = $script:metaOuter.Location.Y }
    $metaH = if ($script:metaExpanded) {
        $script:metaExpandedH
    } else {
        $script:metaCollapsedH
    }
    $termY = $metaTop + $metaH + $gap
    $script:termOuter.Location = New-Object System.Drawing.Point(5, $termY)
    $script:termOuter.Width = $fullW

    # Expanded terminal uses last drag height; collapsed stays header-only
    if ($script:termExpanded) {
        $h = if ($script:termExpandedH -and $script:termExpandedH -ge 100) { $script:termExpandedH } else { 360 }
        $script:termOuter.Height = $h
    } else {
        $script:termOuter.Height = $script:termCollapsedH
    }
    Apply-TerminalInnerLayout

    try {
        $f = $script:mainForm
        if ($f -and $f.WindowState -eq "Normal") {
            $bottom = $script:termOuter.Bottom + 58
            $needed = [Math]::Max($f.MinimumSize.Height, $bottom)
            # Never grow past the screen working area (keeps window above the taskbar)
            $waH = [System.Windows.Forms.Screen]::FromControl($f).WorkingArea.Height
            $maxH = [Math]::Max($f.MinimumSize.Height, $waH - 8)
            if ($needed -gt $maxH) { $needed = $maxH }
            if ($f.Height -lt $needed) {
                $f.Height = $needed
            } elseif (-not $script:metaExpanded -and $f.Height -gt ($needed + 30)) {
                $f.Height = $needed
            }
            # Keep top of window inside working area after height changes
            $wa = [System.Windows.Forms.Screen]::FromControl($f).WorkingArea
            if ($f.Bottom -gt $wa.Bottom) {
                $f.Top = [Math]::Max($wa.Top, $wa.Bottom - $f.Height)
            }
        }
    } catch {}
}

function Apply-TerminalInnerLayout {
    # Size log box + bottom drag grip to current terminal height.
    if ($null -eq $script:termOuter) { return }
    $h = $script:termOuter.Height
    $fullW = if ($script:contentFullW) { $script:contentFullW } else { 1132 }
    $script:termOuter.Width = $fullW

    if ($script:termGrip) {
        $script:termGrip.Width = $fullW - 4
        $script:termGrip.Location = New-Object System.Drawing.Point(2, [Math]::Max(2, $h - 8))
        $script:termGrip.Visible = $true
        $script:termGrip.BringToFront()
    }

    if (-not $script:termExpanded) { return }

    if ($script:logBox) {
        $script:logBox.Width = $fullW - 24
        # Log buttons live on the top action bar now - use full terminal height
        $script:logBox.Height = [Math]::Max(40, $h - 32)
        $script:logBox.Visible = $true
    }
}

function Apply-MetaInnerLayout {
    # Size detail panel + bottom drag grip to current Item Metadata height.
    # Also keep the Games list box filling its GroupBox (fixes blank area at bottom).
    if ($null -eq $script:metaOuter) { return }
    $h = $script:metaOuter.Height
    $nw = if ($script:metaNarrowW) { $script:metaNarrowW } else { 700 }

    if ($script:metaGrip) {
        $script:metaGrip.Width = $nw - 4
        $script:metaGrip.Location = New-Object System.Drawing.Point(2, [Math]::Max(2, $h - 8))
        $script:metaGrip.Visible = $true
        $script:metaGrip.BringToFront()
    }

    if (-not $script:metaExpanded) { return }

    if ($script:detailPanel) {
        $script:detailPanel.Height = [Math]::Max(80, $h - 28)
        $script:detailPanel.Visible = $true
    }
    # Keep Games list height in sync when expanded, and stretch the ListBox
    # so it fills the GroupBox instead of leaving a blank strip at the bottom.
    if ($script:gamesOuter -and $script:gamesOuter.Visible) {
        $script:gamesOuter.Height = $h
        $script:gamesExpandedH = $h
        $gw = $script:gamesOuter.ClientSize.Width
        if ($gw -lt 40) { $gw = $script:gamesOuter.Width - 16 }
        if ($script:gameSearchBox) {
            $script:gameSearchBox.Width = [Math]::Max(80, $gw - 58 - 8)
        }
        if ($script:gameListBox) {
            $listH = [Math]::Max(40, $h - 44 - 8)
            $listW = [Math]::Max(40, $gw - 16)
            $script:gameListBox.Size = New-Object System.Drawing.Size($listW, $listH)
            $script:gameListBox.Location = New-Object System.Drawing.Point(8, 44)
        }
    }
}

function Apply-MetaAndGamesCollapseState {
    # Item Metadata collapse also collapses Games to a header strip (stays visible on the right).
    # Raw View hides both entirely via Set-EditorMode.
    if ($script:rawMode) { return }

    $tb = $script:btnMetaToggle
    $nw = if ($script:metaNarrowW) { $script:metaNarrowW } else { 700 }
    $gCollapsed = if ($script:gamesCollapsedH) { $script:gamesCollapsedH } else { 28 }
    $gExpanded = if ($script:gamesExpandedH) { $script:gamesExpandedH } else { 924 }

    if ($script:metaExpanded) {
        if ($script:metaOuter) {
            $script:metaOuter.Visible = $true
            $script:metaOuter.Height = $script:metaExpandedH
            $script:metaOuter.Width = $nw
            $script:metaOuter.Text = "      Item Metadata "
            foreach ($ctrl in @($script:metaOuter.Controls)) {
                if ($null -eq $tb -or $ctrl -ne $tb) { $ctrl.Visible = $true }
            }
        }
        if ($script:detailPanel) { $script:detailPanel.Visible = $true }
        if ($script:gamesOuter) {
            $script:gamesOuter.Visible = $true
            $script:gamesOuter.Height = $script:metaExpandedH
            $script:gamesExpandedH = $script:metaExpandedH
            $script:gamesOuter.Text = " Games "
            foreach ($ctrl in @($script:gamesOuter.Controls)) { $ctrl.Visible = $true }
        }
        Apply-MetaInnerLayout
        if ($script:gameListBox) { $script:gameListBox.Visible = $true }
        if ($script:gameSearchBox) { $script:gameSearchBox.Visible = $true }
        if ($script:searchLabel) { $script:searchLabel.Visible = $true }
        if ($tb) { $tb.Text = "-"; $tb.Visible = $true; $tb.BringToFront() }
    } else {
        if ($script:detailPanel) { $script:detailPanel.Visible = $false }
        if ($script:metaOuter) {
            $script:metaOuter.Visible = $true
            $script:metaOuter.Height = $script:metaCollapsedH
            $script:metaOuter.Width = $nw
            $script:metaOuter.Text = "      Item Metadata "
            foreach ($ctrl in @($script:metaOuter.Controls)) {
                if ($null -eq $tb -or $ctrl -ne $tb) { $ctrl.Visible = $false }
            }
        }
        # Games stays visible as a collapsed header strip on the right
        if ($script:gamesOuter) {
            $script:gamesOuter.Visible = $true
            $script:gamesOuter.Height = $gCollapsed
            $script:gamesOuter.Text = " Games "
            foreach ($ctrl in @($script:gamesOuter.Controls)) { $ctrl.Visible = $false }
        }
        if ($script:gameListBox) { $script:gameListBox.Visible = $false }
        if ($script:gameSearchBox) { $script:gameSearchBox.Visible = $false }
        if ($script:searchLabel) { $script:searchLabel.Visible = $false }
        if ($tb) {
            $tb.Text = "+"
            $tb.Visible = $true
            $tb.BringToFront()
        }
        if ($script:metaGrip) { $script:metaGrip.Visible = $true; $script:metaGrip.BringToFront() }
        Apply-MetaInnerLayout
    }
    Relayout-TerminalPosition
}

function Find-InRawEditor {
    param([bool]$Forward = $true)
    if (-not $script:editorBox -or -not $script:rawSearchBox) { return }
    $needle = $script:rawSearchBox.Text
    if ([string]::IsNullOrEmpty($needle)) {
        if ($script:rawSearchStatus) { $script:rawSearchStatus.Text = "Enter text to find" }
        return
    }
    $hay = $script:editorBox.Text
    if ([string]::IsNullOrEmpty($hay)) {
        if ($script:rawSearchStatus) { $script:rawSearchStatus.Text = "Editor is empty" }
        return
    }
    $start = $script:editorBox.SelectionStart
    $idx = -1
    if ($Forward) {
        $from = $start + $script:editorBox.SelectionLength
        if ($from -ge $hay.Length) { $from = 0 }
        $idx = $hay.IndexOf($needle, $from, [System.StringComparison]::OrdinalIgnoreCase)
        if ($idx -lt 0 -and $from -gt 0) {
            $idx = $hay.IndexOf($needle, 0, [System.StringComparison]::OrdinalIgnoreCase)
        }
    } else {
        $from = $start - 1
        if ($from -lt 0) { $from = $hay.Length - 1 }
        if ($from -ge 0) {
            $idx = $hay.LastIndexOf($needle, $from, [System.StringComparison]::OrdinalIgnoreCase)
        }
        if ($idx -lt 0) {
            $idx = $hay.LastIndexOf($needle, $hay.Length - 1, [System.StringComparison]::OrdinalIgnoreCase)
        }
    }
    if ($idx -ge 0) {
        $script:editorBox.SelectionStart = $idx
        $script:editorBox.SelectionLength = $needle.Length
        $script:editorBox.ScrollToCaret()
        $script:editorBox.Focus()
        if ($script:rawSearchStatus) { $script:rawSearchStatus.Text = "Match at position $idx" }
    } else {
        if ($script:rawSearchStatus) { $script:rawSearchStatus.Text = "No matches" }
    }
}

function Set-EditorMode {
    param([bool]$raw)
    
    if ($raw) {
        if (-not $script:rawMode) {
            Apply-HeaderFieldsFromUI
            if ($script:gameListBox -and $script:gameListBox.SelectedIndex -ge 0) {
                try { ApplyGameFields } catch {}
            }
            $built = Build-PegasusMetadata
            if ($script:editorBox) { $script:editorBox.Text = Normalize-Newlines $built }
        }
        $script:rawMode = $true
        if ($script:gameListBox) { $script:gameListBox.Visible = $false }
        if ($script:detailPanel) { $script:detailPanel.Visible = $false }
        if ($script:metaOuter) { $script:metaOuter.Visible = $false }
        if ($script:gamesOuter) { $script:gamesOuter.Visible = $false }
        if ($script:gameSearchBox) { $script:gameSearchBox.Visible = $false }
        if ($script:searchLabel) { $script:searchLabel.Visible = $false }
        # Layout Find bar + editor + terminal without overlap
        Apply-RawEditorLayout
        Log-Message "Switched to Raw View" "Cyan"
    } else {
        if ($script:rawMode -and $script:editorBox) {
            Parse-PegasusMetadata $script:editorBox.Text
            FilterGameList
        }
        $script:rawMode = $false
        if ($script:rawSearchBar) { $script:rawSearchBar.Visible = $false }
        if ($script:editorBox) { $script:editorBox.Visible = $false }
        if ($script:metaOuter) { $script:metaOuter.Visible = $true }
        # Show/hide fields + Games based on collapse state (also moves terminal)
        Apply-MetaAndGamesCollapseState
        $cnt = 0
        if ($null -ne $script:parsedGames) { $cnt = @($script:parsedGames).Count }
        Log-Message "Switched to Form View ($cnt games)" "Cyan"
    }
}

function Get-DeveloperLogText {
    # Built-in developer log shown in Settings -> Dev Log.
    # Always append new versions here when shipping changes.
    return @"
Developer Log
Policy: All changes and updates must always be listed here.

2.5.10 - 2026-08-30
- Cover Pack Only-missing: also checks assets.boxFull / assets.box_full / assets.box_back
  (not only assets.box_front) so Unicovers / Box Full themes work
- Collection-only: filter game_ids against the chosen platform titles list
  (stops Wii collection IDs driving DS downloads, etc.)
- Cover Pack dialog shows the currently selected collection name
- Guide: when a collection is required vs optional for Cover Pack
- Guide: only-missing covers front / boxFull / box_full / back

2.5.9 - 2026-08-30
- Cover Pack: boxFull (Unicovers), rename to game title, convert PNG

2.5.8 - 2026-08-30
- GameTDB Cover Pack: collection-only filter (game_id)
- Only missing art; region fallback (US/EN/...)
- Multi cover-type select in one run
- Save into media folders (box2dfront / box2dback / disc)
- Write asset paths into metadata after download
- failed_covers.csv report for retries

2.5.7 - 2026-08-29
- GameTDB: Download Cover Pack dialog (System + Cover type + Region)
- Systems: Wii, GameCube, Wii U, Switch, 3DS, DS, PS3
- Cover types per system (cover, coverHQ, coverfullHQ, coverM, back*, disc, cover3D)
- Correct PNG/JPG extension by type

2.5.6 - 2026-08-29
- Add Box Art: better matching for long titles with dashes/colons
  (e.g. Super Mario RPG - Legend of the Seven Stars)
- Do not skip games that only have an empty assets.box_front: line
- Fuzzy match: subtitle short form, starts-with, word overlap

2.5.5 - 2026-08-29
- Settings: separate Pegasus, Guide, and Theme sections
- Settings: Pegasus path, Dev Log, Workflow Guide, Apply Theme
- Toolbar: Launch Pegasus; Theme and Guide moved into Settings
- Config stores pegasusPath with theme mode

2.5.4 - 2026-08-28
- Raw mode Find bar (Find Next / Prev)
- Save keeps game list scroll/selection and raw caret
- Raw editor paste (Ctrl+V) fix
- Themes: Steam, Light, High Contrast, Windows
- UTF-8 BOM for Windows PowerShell 5.1
- Raw layout: editor + terminal no overlap; terminal drag works

2.5.3 - 2026-08-28
- Remove Games w/ No File
- Guide: SNES ROM headers explained
- Sort Games A-Z; Games list fills GroupBox height

2.5.2 - 2026-08-28
- Sort Games A-Z in Build and Repair Tools
- Games list height syncs with Item Metadata panel

2.5.1 / 2.5.0 - prior
- ROM header detection, spaces preserved for matching,
  boxFull support, bad header filtering, and core features

When shipping a new version: bump the version number and add
an entry at the top of this log.
"@
}

function Show-DeveloperLogDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Developer Log"
    $dlg.Size = New-Object System.Drawing.Size(560, 480)
    $dlg.StartPosition = "CenterParent"
    $dlg.MinimizeBox = $false
    $dlg.MaximizeBox = $true
    $dlg.BackColor = $script:theme.background
    $dlg.ForeColor = $script:theme.text

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Multiline = $true
    $tb.ReadOnly = $true
    $tb.ScrollBars = "Both"
    $tb.WordWrap = $false
    $tb.Font = New-Object System.Drawing.Font("Consolas", 9)
    $tb.BackColor = $script:theme.editor
    $tb.ForeColor = $script:theme.text
    $tb.BorderStyle = "FixedSingle"
    $tb.Dock = "Fill"
    $tb.Text = Get-DeveloperLogText
    $dlg.Controls.Add($tb)

    $btnPanel = New-Object System.Windows.Forms.Panel
    $btnPanel.Dock = "Bottom"
    $btnPanel.Height = 40
    $btnPanel.BackColor = $script:theme.background
    $dlg.Controls.Add($btnPanel)

    $btnClose = Create-Button "Close" 220 7 100 26
    $btnClose.Add_Click({ $dlg.Close() })
    $btnPanel.Controls.Add($btnClose)

    [void]$dlg.ShowDialog($script:mainForm)
}

function Show-SettingsDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Settings"
    $dlg.Size = New-Object System.Drawing.Size(480, 360)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.BackColor = $script:theme.background
    $dlg.ForeColor = $script:theme.text

    # Uniform button size used everywhere in this dialog
    $btnW = 100
    $btnH = 26
    $secW = 440
    $secX = 16
    $gap = 6

    # ========== Section 1: Pegasus ==========
    $grpPeg = New-Object System.Windows.Forms.GroupBox
    $grpPeg.Text = " Pegasus "
    $grpPeg.Location = New-Object System.Drawing.Point($secX, 12)
    $grpPeg.Size = New-Object System.Drawing.Size($secW, 100)
    $grpPeg.ForeColor = $script:theme.text
    $grpPeg.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $grpPeg.BackColor = $script:theme.background
    $dlg.Controls.Add($grpPeg)

    $txtPegasus = New-Object System.Windows.Forms.TextBox
    $txtPegasus.Location = New-Object System.Drawing.Point(12, 28)
    $txtPegasus.Size = New-Object System.Drawing.Size(($secW - 24), 22)
    $txtPegasus.BackColor = $script:theme.editor
    $txtPegasus.ForeColor = $script:theme.text
    $txtPegasus.BorderStyle = "FixedSingle"
    $txtPegasus.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $txtPegasus.Text = $(if ($script:pegasusPath) { $script:pegasusPath } else { "" })
    $grpPeg.Controls.Add($txtPegasus)

    $btnBrowsePeg = Create-Button "Browse" 12 60 $btnW $btnH
    $btnBrowsePeg.Add_Click({
        $of = New-Object System.Windows.Forms.OpenFileDialog
        $of.Title = "Select Pegasus Frontend executable"
        $of.Filter = "Executable (*.exe)|*.exe|All Files (*.*)|*.*"
        $of.FileName = "pegasus-fe.exe"
        if ($txtPegasus.Text -and (Test-Path $txtPegasus.Text)) {
            try { $of.InitialDirectory = [System.IO.Path]::GetDirectoryName($txtPegasus.Text) } catch {}
        } else {
            foreach ($try in @(
                "$env:LOCALAPPDATA\Programs\Pegasus",
                "$env:ProgramFiles\Pegasus",
                "${env:ProgramFiles(x86)}\Pegasus",
                "C:\Pegasus"
            )) {
                if ($try -and (Test-Path $try)) { $of.InitialDirectory = $try; break }
            }
        }
        if ($of.ShowDialog() -eq "OK") { $txtPegasus.Text = $of.FileName }
    })
    $grpPeg.Controls.Add($btnBrowsePeg)

    $btnSavePeg = Create-Button "Save Path" (12 + $btnW + $gap) 60 $btnW $btnH
    $btnSavePeg.Add_Click({
        $script:pegasusPath = $txtPegasus.Text.Trim()
        try { Save-Config } catch {}
        Log-Message ("Pegasus path saved: {0}" -f $(if ($script:pegasusPath) { $script:pegasusPath } else { "(cleared)" })) "Cyan"
    })
    $grpPeg.Controls.Add($btnSavePeg)

    # ========== Section 2: Guide ==========
    $grpGuide = New-Object System.Windows.Forms.GroupBox
    $grpGuide.Text = " Guide "
    $grpGuide.Location = New-Object System.Drawing.Point($secX, 122)
    $grpGuide.Size = New-Object System.Drawing.Size($secW, 70)
    $grpGuide.ForeColor = $script:theme.text
    $grpGuide.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $grpGuide.BackColor = $script:theme.background
    $dlg.Controls.Add($grpGuide)

    $btnGuide = Create-Button "Workflow Guide" 12 28 $btnW $btnH
    $btnGuide.Add_Click({ ShowWorkflowDialog })
    $grpGuide.Controls.Add($btnGuide)

    $btnDevLog = Create-Button "Dev Log" (12 + $btnW + $gap) 28 $btnW $btnH
    $btnDevLog.Add_Click({ Show-DeveloperLogDialog })
    $grpGuide.Controls.Add($btnDevLog)

    # ========== Section 3: Theme (horizontal equal buttons) ==========
    $grpTheme = New-Object System.Windows.Forms.GroupBox
    $grpTheme.Text = " Theme "
    $grpTheme.Location = New-Object System.Drawing.Point($secX, 202)
    $grpTheme.Size = New-Object System.Drawing.Size($secW, 70)
    $grpTheme.ForeColor = $script:theme.text
    $grpTheme.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $grpTheme.BackColor = $script:theme.background
    $dlg.Controls.Add($grpTheme)

    $themes = @(
        @{ Name = "Default"; Mode = "Default" },
        @{ Name = "Steam"; Mode = "Steam" },
        @{ Name = "Light"; Mode = "Light" },
        @{ Name = "Contrast"; Mode = "HighContrast" },
        @{ Name = "Windows"; Mode = "Windows" }
    )
    # 5 equal buttons across the group width
    $themeCount = $themes.Count
    $themePad = 12
    $themeInner = $secW - (2 * $themePad)
    $themeBw = [Math]::Floor(($themeInner - ($gap * ($themeCount - 1))) / $themeCount)
    $tx = $themePad
    $themeBtns = New-Object System.Collections.ArrayList
    foreach ($th in $themes) {
        $tb = Create-Button $th.Name $tx 28 $themeBw $btnH
        $tb.Tag = $th.Mode
        $tb.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
        if ($script:themeMode -eq $th.Mode) {
            $tb.BackColor = $script:theme.accentDark
            $tb.ForeColor = [System.Drawing.Color]::White
        }
        $tb.Add_Click({
            param($sender, $e)
            $chosen = [string]$sender.Tag
            if ([string]::IsNullOrWhiteSpace($chosen)) { return }
            if ($script:themeMode -eq $chosen) { return }
            Set-AppThemeMode -Mode $chosen
            try {
                $form = $sender.FindForm()
                if ($form) {
                    Apply-ThemeToControl $form
                    # Re-highlight the active theme button after full theme apply
                    foreach ($c in @($form.Controls)) {
                        if ($c -isnot [System.Windows.Forms.GroupBox]) { continue }
                        if ($c.Text -notmatch 'Theme') { continue }
                        foreach ($b in @($c.Controls)) {
                            if ($b -isnot [System.Windows.Forms.Button]) { continue }
                            $mode = [string]$b.Tag
                            if ($mode -eq $script:themeMode) {
                                $b.BackColor = $script:theme.accentDark
                                $b.ForeColor = [System.Drawing.Color]::White
                            } else {
                                $b.BackColor = $script:theme.button
                                $b.ForeColor = $script:theme.text
                            }
                        }
                    }
                }
            } catch {}
            Log-Message "Theme: $chosen" "Cyan"
        })
        $grpTheme.Controls.Add($tb)
        [void]$themeBtns.Add($tb)
        $tx += $themeBw + $gap
    }

    # ========== Close ==========
    $btnClose = Create-Button "Close" ([Math]::Floor(($dlg.ClientSize.Width - $btnW) / 2)) 290 $btnW $btnH
    # Fixed position relative to dialog content
    $btnClose.Location = New-Object System.Drawing.Point( (16 + [Math]::Floor(($secW - $btnW) / 2)) , 290)
    $btnClose.Tag = $txtPegasus
    $btnClose.Add_Click({
        param($sender, $e)
        $tb = $sender.Tag
        if ($tb -and $tb -is [System.Windows.Forms.TextBox]) {
            $script:pegasusPath = $tb.Text.Trim()
            try { Save-Config } catch {}
        }
        $sender.FindForm().Close()
    })
    $dlg.Controls.Add($btnClose)

    [void]$dlg.ShowDialog($script:mainForm)
}

function Launch-Pegasus {
    $path = $script:pegasusPath
    if ([string]::IsNullOrWhiteSpace($path)) {
        $r = [System.Windows.Forms.MessageBox]::Show(
            "Pegasus location is not set.`n`nOpen Settings to choose pegasus-fe.exe?",
            "Launch Pegasus", "YesNo", "Question")
        if ($r -eq "Yes") { Show-SettingsDialog }
        return
    }
    if (-not (Test-Path -LiteralPath $path)) {
        $r = [System.Windows.Forms.MessageBox]::Show(
            "Pegasus not found at:`n$path`n`nOpen Settings to pick the correct path?",
            "Launch Pegasus", "YesNo", "Warning")
        if ($r -eq "Yes") { Show-SettingsDialog }
        return
    }
    try {
        $workDir = [System.IO.Path]::GetDirectoryName($path)
        Start-Process -FilePath $path -WorkingDirectory $workDir
        Log-Message "Launched Pegasus: $path" "Green"
    } catch {
        Log-Message "Failed to launch Pegasus: $_" "Red"
        [System.Windows.Forms.MessageBox]::Show("Could not start Pegasus:`n$($_.Exception.Message)", "Launch Pegasus", "OK", "Error") | Out-Null
    }
}

# ============================================================================
# UPDATE SNS CODE LIST
# ============================================================================
function Update-SnsCodeList {
    param([array]$codes, [string]$savedFile = $null)
    $script:lastSnsCodes = @($codes)
    $script:lastSnsCodesFile = $savedFile
    if ($null -ne $script:snsCodeList) {
        $script:snsCodeList.BeginUpdate()
        $script:snsCodeList.Items.Clear()
        foreach ($code in $codes) {
            [void]$script:snsCodeList.Items.Add($code)
        }
        $script:snsCodeList.EndUpdate()
        if ($null -ne $script:snsInfoLabel) {
            $script:snsInfoLabel.Text = "$($codes.Count) codes loaded"
            if ($savedFile) {
                $script:snsInfoLabel.Text += "  |  Source: $(Split-Path $savedFile -Leaf)"
            }
        }
    }
}

# ============================================================================
# ADD ALL MEDIA TYPES
# ============================================================================
function Get-MatchTitleKey {
    # Normalize a title/filename for fuzzy media matching.
    # Handles No-Intro: "Legend of Zelda, The - A Link to the Past (USA)"
    # vs clean metadata: "The Legend of Zelda: A Link to the Past"
    # Also: "Super Mario RPG - Legend of the Seven Stars" vs colon/underscore variants.
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return "" }
    $n = $Name.Trim()
    # Remove bracket dump tags: [!], [b1], [T+Eng], etc.
    $n = $n -replace '\[[^\]]*\]', ''
    # Remove parenthetical region / revision tags: (USA), (Europe), (Rev 1), etc.
    $n = $n -replace '\([^)]*\)', ''
    # "Title, The" / "Title, A" / "Title, An" -> "The Title" (No-Intro article form)
    if ($n -match '^(.+),\s+(The|A|An)\s*([-:].*)?$') {
        $rest = if ($matches[3]) { $matches[3] } else { '' }
        $n = ($matches[2] + ' ' + $matches[1] + ' ' + $rest).Trim()
    } elseif ($n -match '^(.+),\s+(The|A|An)\s*$') {
        $n = ($matches[2] + ' ' + $matches[1]).Trim()
    }
    # Unify separators: colon, underscore, any dash style -> space
    $n = $n -replace '[_:]+', ' '
    $n = $n -replace '[\u2010-\u2015\u2212\-]+', ' '
    $n = $n -replace '&', ' and '
    # Drop remaining punctuation
    $n = $n -replace '[^a-zA-Z0-9\s]', ''
    # Collapse whitespace
    $n = $n -replace '\s+', ' '
    return $n.Trim().ToLowerInvariant()
}

function Get-MatchTitleKeyVariants {
    # Primary key plus shorter form before " - " / ": " subtitle.
    param([string]$Name)
    $keys = New-Object System.Collections.ArrayList
    $primary = Get-MatchTitleKey $Name
    if ($primary) { [void]$keys.Add($primary) }
    if ([string]::IsNullOrWhiteSpace($Name)) { return @($keys) }
    $parts = $Name -split '\s*[-:\u2013\u2014]\s+', 2
    if ($parts.Count -ge 2 -and $parts[0].Trim().Length -ge 4) {
        $short = Get-MatchTitleKey $parts[0]
        if ($short -and -not $keys.Contains($short)) { [void]$keys.Add($short) }
    }
    return @($keys)
}

function Find-ImageByMatchKeys {
    param(
        [string[]]$TitleKeys,
        [hashtable]$ImageByKey
    )
    if (-not $ImageByKey -or $ImageByKey.Count -eq 0) { return $null }
    if (-not $TitleKeys -or $TitleKeys.Count -eq 0) { return $null }
    foreach ($tk in $TitleKeys) {
        if ($tk -and $ImageByKey.ContainsKey($tk)) { return $ImageByKey[$tk] }
    }
    foreach ($tk in $TitleKeys) {
        if ([string]::IsNullOrWhiteSpace($tk) -or $tk.Length -lt 8) { continue }
        foreach ($ik in @($ImageByKey.Keys)) {
            if (-not $ik -or $ik.Length -lt 8) { continue }
            if ($ik.StartsWith($tk) -or $tk.StartsWith($ik)) { return $ImageByKey[$ik] }
        }
    }
    foreach ($tk in $TitleKeys) {
        if ([string]::IsNullOrWhiteSpace($tk)) { continue }
        $tWords = @($tk -split '\s+' | Where-Object { $_.Length -ge 3 })
        if ($tWords.Count -lt 2) { continue }
        $best = $null
        $bestScore = 0
        foreach ($ik in @($ImageByKey.Keys)) {
            $iWords = @($ik -split '\s+' | Where-Object { $_.Length -ge 3 })
            if ($iWords.Count -lt 2) { continue }
            $hits = 0
            foreach ($w in $tWords) {
                if ($iWords -contains $w) { $hits++ }
            }
            $need = [Math]::Max(2, [Math]::Ceiling($tWords.Count * 0.7))
            if ($hits -ge $need -and $hits -gt $bestScore) {
                $bestScore = $hits
                $best = $ImageByKey[$ik]
            }
        }
        if ($best) { return $best }
    }
    return $null
}

function Find-MediaFileForGame {
    # Locate a media file for a game inside a folder.
    # Pegasus auto-discovery (Skraper-style media/<type>/) matches the ROM basename
    # or game title, typically WITH spaces: "Super Mario World.png", "Contra (U).png".
    # Explicit assets.* paths in metadata can point to any real file; we still prefer
    # the on-disk name Pegasus expects so packs stay consistent.
    param(
        [string]$FolderPath,
        [string]$GameTitle,
        [string]$RomPath = $null,
        [string[]]$Extensions = @('png', 'jpg', 'jpeg', 'webp', 'mp4', 'webm')
    )
    if ([string]::IsNullOrWhiteSpace($FolderPath) -or -not (Test-Path $FolderPath)) { return $null }
    
    $candidates = New-Object System.Collections.ArrayList
    
    function Add-Candidate([string]$name) {
        if ([string]::IsNullOrWhiteSpace($name)) { return }
        $n = $name.Trim()
        if (-not $n) { return }
        if ($candidates -notcontains $n) { [void]$candidates.Add($n) }
    }
    
    # 1) ROM basename (Skraper / Pegasus media auto-match primary)
    if (-not [string]::IsNullOrWhiteSpace($RomPath)) {
        try {
            $romBase = [System.IO.Path]::GetFileNameWithoutExtension($RomPath)
            Add-Candidate $romBase
        } catch {}
    }
    
    # 2) Exact game title with spaces (Pegasus-native)
    $trimmed = if ($GameTitle) { $GameTitle.Trim() } else { "" }
    Add-Candidate $trimmed
    
    # 3) Mild cleanups that KEEP spaces (strip only illegal path chars)
    if ($trimmed) {
        $spacey = $trimmed -replace '[<>:"/\\|?*]', '' -replace '\s+', ' '
        Add-Candidate $spacey.Trim()
    }
    
    # 4) Fallbacks for older packs / this tool's prior underscore naming
    if ($trimmed) {
        $underscored = $trimmed -replace '[^\w\s-]', '' -replace '\s+', ' ' -replace ' ', '_'
        Add-Candidate $underscored
        $hyphen = $trimmed -replace '[^\w\s-]', '' -replace '\s+', '-'
        Add-Candidate $hyphen
        $nospace = ($trimmed -replace '[^\w-]', '')
        Add-Candidate $nospace
    }
    
    if ($candidates.Count -eq 0) { return $null }
    
    # Fast path: literal existence checks (preserves exact on-disk path including spaces)
    foreach ($base in $candidates) {
        foreach ($ext in $Extensions) {
            $tryPath = Join-Path $FolderPath "$base.$ext"
            if (Test-Path -LiteralPath $tryPath) { return $tryPath }
        }
    }
    
    # Slow path: case-insensitive + region-tag-aware scan
    # Matches "Super Mario World" to "Super Mario World (USA).jpg"
    try {
        $files = @(Get-ChildItem -LiteralPath $FolderPath -File -ErrorAction SilentlyContinue)
        if ($files.Count -eq 0) { return $null }
        $wanted = @{}
        foreach ($base in $candidates) {
            foreach ($ext in $Extensions) {
                $wanted[("$base.$ext").ToLowerInvariant()] = $true
            }
        }
        $wantedKeys = @{}
        foreach ($base in $candidates) {
            $k = Get-MatchTitleKey $base
            if ($k) { $wantedKeys[$k] = $true }
        }
        foreach ($f in $files) {
            if ($wanted.ContainsKey($f.Name.ToLowerInvariant())) {
                return $f.FullName
            }
        }
        foreach ($f in $files) {
            $ext = $f.Extension.TrimStart('.').ToLowerInvariant()
            if ($Extensions -notcontains $ext) { continue }
            $fileKey = Get-MatchTitleKey ([System.IO.Path]::GetFileNameWithoutExtension($f.Name))
            if ($fileKey -and $wantedKeys.ContainsKey($fileKey)) {
                return $f.FullName
            }
        }
        # Fuzzy fallback for long titles with dashes/colons (e.g. Super Mario RPG - ...)
        $imageByKey = @{}
        foreach ($f in $files) {
            $ext = $f.Extension.TrimStart('.').ToLowerInvariant()
            if ($Extensions -notcontains $ext) { continue }
            $fk = Get-MatchTitleKey ([System.IO.Path]::GetFileNameWithoutExtension($f.Name))
            if ($fk -and -not $imageByKey.ContainsKey($fk)) { $imageByKey[$fk] = $f.FullName }
        }
        $titleKeys = New-Object System.Collections.ArrayList
        foreach ($c in $candidates) {
            foreach ($k in @(Get-MatchTitleKeyVariants $c)) {
                if ($k -and -not $titleKeys.Contains($k)) { [void]$titleKeys.Add($k) }
            }
        }
        $fuzzy = Find-ImageByMatchKeys -TitleKeys @($titleKeys) -ImageByKey $imageByKey
        if ($fuzzy) { return $fuzzy }
    } catch {}
    return $null
}

function Add-AllMediaTypes {
    # Safely link media files into Pegasus asset fields without string-mangling the metadata.
    # Uses Parse -> mutate Fields hashtables -> Build-PegasusMetadata (same path as Save).
    # Writes BOTH assets.box_full (common scrapers) and assets.boxFull (many themes) when files exist.
    $c = Get-Col
    if (-not $c) { return }
    
    Log-Message "========================================" "Cyan"
    Log-Message "ADDING ALL MEDIA TYPES - $($c.name)" "Cyan"
    Log-Message "========================================" "Cyan"
    
    try {
        $p = $c.metadataPath
        $bp = $c.mediaPath
        
        if ([string]::IsNullOrWhiteSpace($p) -or -not (Test-Path $p)) {
            Log-Message "ERROR: Metadata file not found: $p" "Red"
            return
        }
        if ([string]::IsNullOrWhiteSpace($bp)) {
            Log-Message "ERROR: Media folder path is empty!" "Red"
            Log-Message "Re-add the collection and select a Media Folder (parent of box2dfront, boxFull, etc.)." "Yellow"
            return
        }
        if (-not (Test-Path $bp)) {
            Log-Message "ERROR: Media folder does not exist: $bp" "Red"
            return
        }
        
        Log-Message "Metadata: $p" "White"
        Log-Message "Media: $bp" "White"
        
        # --- Structured parse (never regex-edit the whole file) ---
        $content = Get-Content $p -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($content)) {
            Log-Message "ERROR: Metadata file is empty." "Red"
            return
        }
        
        Parse-PegasusMetadata $content
        if ($null -eq $script:parsedGames -or @($script:parsedGames).Count -eq 0) {
            Log-Message "No game entries found after parse." "Yellow"
            return
        }
        
        # Primary folder map. box_full and boxFull are SEPARATE keys on purpose:
        # - assets.box_full  -> scrapers / Skraper-style packs often use box2dfull
        # - assets.boxFull   -> many Pegasus themes (incl. yours) look for boxFull
        # Alternate folders are tried so either layout still fills both fields when possible.
        $assetMap = [ordered]@{
            "assets.box_front"       = @{ Primary = "box2dfront";     Alts = @("boxFront", "covers", "box") }
            "assets.box_full"        = @{ Primary = "box2dfull";      Alts = @("boxFull", "boxfull", "box3d") }
            "assets.boxFull"         = @{ Primary = "boxFull";        Alts = @("box2dfull", "boxfull", "box3d") }
            "assets.box_back"        = @{ Primary = "box2dback";      Alts = @("boxBack", "back") }
            "assets.screenshot"      = @{ Primary = "screenshot";     Alts = @("screenshots", "snap", "snaps") }
            "assets.video"           = @{ Primary = "videos";         Alts = @("video", "movies") }
            "assets.logo"            = @{ Primary = "wheel";          Alts = @("logo", "logos", "wheels") }
            "assets.titlescreen"     = @{ Primary = "titlescreen";    Alts = @("titlescreens", "title") }
            "assets.fanart"          = @{ Primary = "fanart";         Alts = @("fanarts", "background", "bg") }
            "assets.cartridge"       = @{ Primary = "cartridge";      Alts = @("cart", "cartridges") }
            "assets.steamgrid"       = @{ Primary = "steamgrid";      Alts = @("grid", "grids") }
            "assets.marquee"         = @{ Primary = "marquee";        Alts = @("marquees") }
            "assets.banner"          = @{ Primary = "banner";         Alts = @("banners", "steamgrid") }
            "assets.box_front_thumb" = @{ Primary = "box2dThumb";     Alts = @("box2dthumb", "thumbs", "thumb") }
        }
        
        $imageExts = @('png', 'jpg', 'jpeg', 'webp')
        $videoExts = @('mp4', 'webm', 'avi', 'mkv')
        
        $folderStatus = @{}
        foreach ($assetKey in $assetMap.Keys) {
            $info = $assetMap[$assetKey]
            $allNames = @($info.Primary) + @($info.Alts)
            $resolved = $null
            foreach ($fn in $allNames) {
                $try = Join-Path $bp $fn
                if (Test-Path $try) { $resolved = $try; break }
            }
            $folderStatus[$assetKey] = $resolved
        }
        
        $present = @($folderStatus.GetEnumerator() | Where-Object { $_.Value } | ForEach-Object { Split-Path $_.Value -Leaf } | Select-Object -Unique)
        $absentKeys = @($folderStatus.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
        Log-Message "Media folders found: $(if ($present.Count) { $present -join ', ' } else { '(none)' })" "Cyan"
        if ($absentKeys.Count -gt 0) {
            Log-Message "No folder for: $($absentKeys -join ', ') (those fields skipped)" "Yellow"
        }
        if ($present.Count -eq 0) {
            Log-Message "No known media subfolders under: $bp" "Red"
            Log-Message "Expected e.g. box2dfront, boxFull, box2dfull, screenshot, wheel..." "Yellow"
            return
        }
        
        $gamesTouched = 0
        $totalAssets = 0
        $perField = @{}
        foreach ($k in $assetMap.Keys) { $perField[$k] = 0 }
        
        for ($i = 0; $i -lt $script:parsedGames.Count; $i++) {
            $game = $script:parsedGames[$i]
            $fields = @{}
            foreach ($k in @($game.Fields.Keys)) { $fields[$k] = $game.Fields[$k] }
            $title = if ($fields.ContainsKey("game")) { [string]$fields["game"] } else { [string]$game.Title }
            if ([string]::IsNullOrWhiteSpace($title)) { continue }
            
            # ROM path helps match Skraper-style names: "Contra (U).png"
            $romPath = $null
            if ($fields.ContainsKey("file") -and -not [string]::IsNullOrWhiteSpace([string]$fields["file"])) {
                $romPath = [string]$fields["file"]
            } elseif ($fields.ContainsKey("files") -and -not [string]::IsNullOrWhiteSpace([string]$fields["files"])) {
                # multi-line files: use first line
                $romPath = ([string]$fields["files"] -split "`n")[0].Trim()
            }
            
            $addedThisGame = 0
            $addedKeys = @()
            
            foreach ($assetKey in $assetMap.Keys) {
                # Never overwrite an existing non-empty value
                if ($fields.ContainsKey($assetKey) -and -not [string]::IsNullOrWhiteSpace([string]$fields[$assetKey])) {
                    continue
                }
                
                $folderPath = $folderStatus[$assetKey]
                if (-not $folderPath) { continue }
                
                $exts = if ($assetKey -eq "assets.video") { $videoExts + $imageExts } else { $imageExts }
                $found = Find-MediaFileForGame -FolderPath $folderPath -GameTitle $title -RomPath $romPath -Extensions $exts
                if (-not $found) { continue }
                
                # Store the real on-disk path (spaces preserved). Pegasus accepts absolute
                # or metadata-relative paths; absolute is unambiguous across setups.
                $fields[$assetKey] = $found
                $addedThisGame++
                $totalAssets++
                $perField[$assetKey]++
                $addedKeys += $assetKey
            }
            
            if ($addedThisGame -eq 0) { continue }
            
            $script:parsedGames[$i] = [PSCustomObject]@{
                Fields = $fields
                Title  = $title
            }
            $gamesTouched++
            Log-Message "  +$addedThisGame  $title  ($($addedKeys -join ', '))" "Green"
        }
        
        if ($gamesTouched -eq 0) {
            Log-Message "No new media matched." "Yellow"
            Log-Message "Pegasus / Skraper expect names like the ROM or game title, usually WITH spaces:" "Yellow"
            Log-Message "  Super Mario World.png" "Yellow"
            Log-Message "  Contra (U).png" "Yellow"
            Log-Message "Underscore names still match as a fallback if that is how your pack is named." "Cyan"
            return
        }
        
        # Rebuild metadata from structured data (safe, ordered, no partial regex edits)
        Apply-HeaderFieldsFromUI
        $text = Build-PegasusMetadata
        $text = $text -replace "`r`n", "`n" -replace "`r", "`n"
        
        CreateBackup
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($p, $text, $utf8NoBom)
        
        Log-Message "----------------------------------------" "Cyan"
        Log-Message "Updated $gamesTouched game(s), $totalAssets new asset path(s)" "Green"
        foreach ($k in $assetMap.Keys) {
            if ($perField[$k] -gt 0) {
                Log-Message ("  {0,-28} {1}" -f $k, $perField[$k]) "White"
            }
        }
        Log-Message "Note: assets.box_full and assets.boxFull are both written when files exist" "Cyan"
        Log-Message "  (scraper packs often use box_full; many themes use boxFull)." "Cyan"
        
        UpdateEditor
        UpdateStats
        
    } catch {
        Log-Message "ERROR in Add-AllMediaTypes: $($_.Exception.Message)" "Red"
        if ($_.InvocationInfo -and $_.InvocationInfo.ScriptLineNumber) {
            Log-Message "At line: $($_.InvocationInfo.ScriptLineNumber)" "Yellow"
        }
        if ($_.ScriptStackTrace) {
            Log-Message "Stack: $($_.ScriptStackTrace)" "Yellow"
        }
    }
}

# ============================================================================
# MAIN WINDOW
# ============================================================================
function Show-MainWindow {
    try { Load-Config } catch { $script:collections = @{} }
    # Apply saved theme mode (Steam / Windows) after config load
    try { Initialize-SystemTheme } catch {}
    
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Metadata Repair Tool"
    # Fit primary screen working area (excludes taskbar) so the window never opens underneath it
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $initW = [Math]::Min(1600, [Math]::Max(1100, $wa.Width - 40))
    $initH = [Math]::Min(980, [Math]::Max(700, $wa.Height - 20))
    $form.Size = New-Object System.Drawing.Size($initW, $initH)
    $form.MinimumSize = New-Object System.Drawing.Size(1100, 420)
    $form.MaximizeBox = $true
    $form.StartPosition = "Manual"
    $form.Location = New-Object System.Drawing.Point(
        [Math]::Max(0, $wa.Left + (($wa.Width - $initW) / 2)),
        [Math]::Max(0, $wa.Top + (($wa.Height - $initH) / 2))
    )
    $script:mainForm = $form
    $form.BackColor = $script:theme.background
    
    # ============================================================
    # TABLE LAYOUT PANEL - left tools | right editor + terminal
    # ============================================================
    $tableLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $tableLayout.Dock = "Fill"
    $tableLayout.ColumnCount = 2
    $tableLayout.RowCount = 1
    $tableLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 410)))
    $tableLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $tableLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $tableLayout.BackColor = $script:theme.background
    $form.Controls.Add($tableLayout)
    
    # ============================================================
    # LEFT PANEL
    # ============================================================
    $leftPanel = New-Object System.Windows.Forms.Panel
    $leftPanel.Dock = "Fill"
    $leftPanel.AutoScroll = $true
    $leftPanel.AutoScrollMargin = New-Object System.Drawing.Size(12, 20)
    $leftPanel.BackColor = $script:theme.background
    $leftPanel.Padding = New-Object System.Windows.Forms.Padding(6, 4, 18, 8)
    $tableLayout.Controls.Add($leftPanel, 0, 0)
    $script:leftPanelRef = $leftPanel
    $script:leftSections = New-Object System.Collections.ArrayList
    $leftW = 378
    
    # Title (single clean header row - same height/border as top action bar)
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "Metadata Repair Tool"
    $titleLabel.Location = New-Object System.Drawing.Point(5, 2)
    $titleLabel.Size = New-Object System.Drawing.Size($leftW, 36)
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
    $titleLabel.ForeColor = $script:theme.accent
    $titleLabel.Tag = "accent"
    $titleLabel.BackColor = $script:theme.background
    $titleLabel.BorderStyle = "FixedSingle"
    $titleLabel.TextAlign = "MiddleCenter"
    $leftPanel.Controls.Add($titleLabel)
    
    # ============================================================
    # COLLECTIONS GROUP
    # ============================================================
    $colGroup = New-Object System.Windows.Forms.GroupBox
    $colGroup.Text = " Collections "
    $colGroup.Location = New-Object System.Drawing.Point(5, 40)
    $colGroup.Size = New-Object System.Drawing.Size($leftW, 230)
    $colGroup.ForeColor = $script:theme.text
    $colGroup.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $leftPanel.Controls.Add($colGroup)
    
    $collectionList = New-Object System.Windows.Forms.ListBox
    $collectionList.Location = New-Object System.Drawing.Point(8, 22)
    $collectionList.Size = New-Object System.Drawing.Size(($leftW - 16), 155)
    $collectionList.BackColor = $script:theme.editor
    $collectionList.ForeColor = $script:theme.text
    $collectionList.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $collectionList.BorderStyle = "FixedSingle"
    $colGroup.Controls.Add($collectionList)
    $script:collectionList = $collectionList
    
    $colBtnY = 182
    $colBtnH = 26
    $colBtnGap = 5
    $colBtnW = [Math]::Floor(($leftW - 16 - 4 * $colBtnGap) / 5)
    $cx = 8
    
    $btnCreate = Create-Button "Create" $cx $colBtnY $colBtnW $colBtnH
    $btnCreate.Add_Click({ Show-CreateCollectionDialog })
    $colGroup.Controls.Add($btnCreate)
    $cx += $colBtnW + $colBtnGap
    
    $btnAdd = Create-Button "Add" $cx $colBtnY $colBtnW $colBtnH
    $btnAdd.Add_Click({ Show-AddCollectionDialog })
    $colGroup.Controls.Add($btnAdd)
    $cx += $colBtnW + $colBtnGap
    
    $btnRemove = Create-Button "Remove" $cx $colBtnY $colBtnW $colBtnH
    $btnRemove.Add_Click({
        if ($collectionList.SelectedItem) {
            $name = $collectionList.SelectedItem.ToString()
            if (Remove-Collection $name) {
                RefreshCollectionList
                Log-Message "Removed: $name" "Yellow"
                if ($collectionList.Items.Count -gt 0) {
                    $collectionList.SelectedIndex = 0
                    UpdateEditor
                } else {
                    $script:editorBox.Text = "No collections. Click 'Create' or 'Add' to add one."
                    $script:statusBar.Text = "No collections loaded"
                    $script:currentCollection = $null
                }
            }
        }
    })
    $colGroup.Controls.Add($btnRemove)
    $cx += $colBtnW + $colBtnGap
    
    $btnRefresh = Create-Button "Refresh" $cx $colBtnY $colBtnW $colBtnH
    $btnRefresh.Add_Click({
        RefreshCollectionList
        Log-Message "Refreshed" "Cyan"
    })
    $colGroup.Controls.Add($btnRefresh)
    $cx += $colBtnW + $colBtnGap
    
    $btnLoad = Create-Button "Load" $cx $colBtnY $colBtnW $colBtnH
    
    $btnLoad.Add_Click({
        if ($collectionList.SelectedItem) {
            UpdateEditor
            UpdateStats
            Log-Message "Loaded: $($collectionList.SelectedItem)" "Green"
        }
    })
    $colGroup.Controls.Add($btnLoad)
    
    $collectionList.Add_SelectedIndexChanged({
        if ($collectionList.SelectedItem) {
            $name = $collectionList.SelectedItem.ToString()
            $script:currentCollection = $script:collections[$name]
            UpdateEditor
            UpdateStats
        }
    })
    
    # ============================================================
    # SECTION 1: METADATA TOOLS
    # ============================================================
    $toolsGroup = New-Object System.Windows.Forms.GroupBox
    $toolsGroup.Text = " Metadata Tools "
    $toolsGroup.Location = New-Object System.Drawing.Point(5, 294)
    $toolsGroup.Size = New-Object System.Drawing.Size($leftW, 120)
    $toolsGroup.ForeColor = $script:theme.text
    $toolsGroup.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $leftPanel.Controls.Add($toolsGroup)
    
    $ty = 22
    $ts = 30
    $bw = [Math]::Floor(($leftW - 24) / 2)
    $col2X = 8 + $bw + 6
    $row4W = [Math]::Floor(($leftW - 16 - 18) / 4)
    $row4Gap = 6
    
    $btn1 = Create-Button "Check Health" 8 $ty $bw 26
    $btn1.Add_Click({ CheckHealth })
    $toolsGroup.Controls.Add($btn1)
    
    $btn2 = Create-Button "Statistics" $col2X $ty $bw 26
    $btn2.Add_Click({ ShowStats })
    $toolsGroup.Controls.Add($btn2)
    
    $ty += $ts
    $btn3 = Create-Button "Find Missing Covers" 8 $ty $bw 26
    $btn3.Add_Click({ FindMissing })
    $toolsGroup.Controls.Add($btn3)
    
    $btn4 = Create-Button "Fix Duplicates" $col2X $ty $bw 26
    $btn4.Add_Click({ FixDup })
    $toolsGroup.Controls.Add($btn4)
    
    $ty += $ts
    $row3W = [Math]::Floor(($leftW - 16 - 12) / 3)
    $row3Gap = 6
    $btn5 = Create-Button "Backup" 8 $ty $row3W 26
    $btn5.Add_Click({ CreateBackup })
    $toolsGroup.Controls.Add($btn5)
    
    $btn6 = Create-Button "Restore" (8 + $row3W + $row3Gap) $ty $row3W 26
    $btn6.Add_Click({ RestoreBackup })
    $toolsGroup.Controls.Add($btn6)
    
    $btn7 = Create-Button "Refresh" (8 + 2 * ($row3W + $row3Gap)) $ty $row3W 26
    $btn7.Add_Click({
        RefreshCollectionList
        Log-Message "Refreshed" "Cyan"
    })
    $toolsGroup.Controls.Add($btn7)
    
    # ============================================================
    # SECTION 2: IMAGE TOOLS
    # ============================================================
    $imageGroup = New-Object System.Windows.Forms.GroupBox
    $imageGroup.Text = " Image Tools "
    $imageGroup.Location = New-Object System.Drawing.Point(5, 422)
    $imageGroup.Size = New-Object System.Drawing.Size($leftW, 340)
    $imageGroup.ForeColor = $script:theme.text
    $imageGroup.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $leftPanel.Controls.Add($imageGroup)
    
    $iy = 22
    $is = 28
    $fullW = $leftW - 16
    
    $btnImg3 = Create-Button "Add Box Art to Metadata" 8 $iy $fullW 26
    $btnImg3.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnImg3.Add_Click({ AddBoxArt })
    $imageGroup.Controls.Add($btnImg3)
    
    $iy += $is
    $btnImgAll = Create-Button "Add All Media Types (boxFull, logo, etc.)" 8 $iy $fullW 26
    $btnImgAll.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnImgAll.Add_Click({ Add-AllMediaTypes })
    $imageGroup.Controls.Add($btnImgAll)
    
    $iy += $is
    $btnImg1 = Create-Button "Rename Images to Game Titles (strip USA/EUR/JPN)" 8 $iy $fullW 26
    $btnImg1.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnImg1.Add_Click({ RenameImages })
    $imageGroup.Controls.Add($btnImg1)
    
    $iy += $is
    $btnImgSns = Create-Button "Rename SNS-Coded Images to Titles" 8 $iy $fullW 26
    $btnImgSns.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnImgSns.Add_Click({ Rename-ImagesFromSnsCodes })
    $imageGroup.Controls.Add($btnImgSns)
    
    $iy += $is
    $btnImg2 = Create-Button "Update Metadata Names from Images" 8 $iy $fullW 26
    $btnImg2.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnImg2.Add_Click({ UpdateMetadataNames })
    $imageGroup.Controls.Add($btnImg2)
    
    $iy += $is
    $btnImg4 = Create-Button "Convert All PNG Images to JPG" 8 $iy $fullW 26
    $btnImg4.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnImg4.Add_Click({ ConvertImagesPNGtoJPG $true })
    $imageGroup.Controls.Add($btnImg4)
    
    $iy += $is
    $btnImg5 = Create-Button "Convert All JPG Images to PNG" 8 $iy $fullW 26
    $btnImg5.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnImg5.Add_Click({ ConvertImagesJPGtoPNG $true })
    $imageGroup.Controls.Add($btnImg5)
    
    $iy += $is
    $btnImg6 = Create-Button "Convert Selected PNG Images to JPG" 8 $iy $fullW 26
    $btnImg6.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnImg6.Add_Click({ ConvertImagesPNGtoJPG $false })
    $imageGroup.Controls.Add($btnImg6)
    
    $iy += $is
    $btnImg7 = Create-Button "Convert Selected JPG Images to PNG" 8 $iy $fullW 26
    $btnImg7.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnImg7.Add_Click({ ConvertImagesJPGtoPNG $false })
    $imageGroup.Controls.Add($btnImg7)
    
    $iy += $is
    $btnImg8 = Create-Button "Update Metadata Extensions to JPG" 8 $iy $fullW 26
    $btnImg8.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnImg8.Add_Click({ UpdateMetadataExtensions "jpg" })
    $imageGroup.Controls.Add($btnImg8)
    
    $iy += $is
    $btnImg9 = Create-Button "Update Metadata Extensions to PNG" 8 $iy $fullW 26
    $btnImg9.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnImg9.Add_Click({ UpdateMetadataExtensions "png" })
    $imageGroup.Controls.Add($btnImg9)
    
    # ============================================================
    # SECTION 3: SNS CODE TOOLS
    # ============================================================
    # 7 button rows below list+info, last row (SNS Stats) bottoms at y=384
    $snsExpandedH = 396
    $snsGroup = New-Object System.Windows.Forms.GroupBox
    $snsGroup.Text = " SNS Code Tools "
    $snsGroup.Location = New-Object System.Drawing.Point(5, 720)
    $snsGroup.Size = New-Object System.Drawing.Size($leftW, $snsExpandedH)
    $snsGroup.ForeColor = $script:theme.text
    $snsGroup.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $leftPanel.Controls.Add($snsGroup)
    
    $snsCodeList = New-Object System.Windows.Forms.ListBox
    $snsCodeList.Location = New-Object System.Drawing.Point(8, 20)
    $snsCodeList.Size = New-Object System.Drawing.Size(($leftW - 16), 130)
    $snsCodeList.BackColor = $script:theme.editor
    $snsCodeList.ForeColor = $script:theme.text
    $snsCodeList.Font = New-Object System.Drawing.Font("Consolas", 8)
    $snsCodeList.BorderStyle = "FixedSingle"
    $snsGroup.Controls.Add($snsCodeList)
    $script:snsCodeList = $snsCodeList
    
    $snsInfo = New-Object System.Windows.Forms.Label
    $snsInfo.Text = "0 codes loaded"
    $snsInfo.Location = New-Object System.Drawing.Point(8, 152)
    $snsInfo.Size = New-Object System.Drawing.Size(($leftW - 16), 16)
    $snsInfo.ForeColor = $script:theme.textDim
    $snsInfo.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $snsGroup.Controls.Add($snsInfo)
    $script:snsInfoLabel = $snsInfo
    
    $sy = 172
    $btnH = 26
    $gap = 5
    $snsBtnW = [Math]::Floor(($leftW - 16 - $gap) / 2)
    $snsCol2X = 8 + $snsBtnW + $gap
    
    $btnX = Create-Button "From XML" 8 $sy $snsBtnW $btnH
    $btnX.Add_Click({ ExtractXML })
    $snsGroup.Controls.Add($btnX)
    
    $btnI = Create-Button "From Images" $snsCol2X $sy $snsBtnW $btnH
    $btnI.Add_Click({ ExtractImages })
    $snsGroup.Controls.Add($btnI)
    
    $sy += $btnH + $gap
    $btnMapCode = Create-Button "Map by Product Code" 8 $sy $snsBtnW $btnH
    $btnMapCode.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnMapCode.Add_Click({ CreateIDMapping -OutputFileName "sns_mappings.txt" -MatchMode ProductCode })
    $snsGroup.Controls.Add($btnMapCode)
    
    $btnMapTitles = Create-Button "Map by Titles File" $snsCol2X $sy $snsBtnW $btnH
    $btnMapTitles.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnMapTitles.Add_Click({ CreateIDMapping -OutputFileName "sns_mappings.txt" -MatchMode Titles })
    $snsGroup.Controls.Add($btnMapTitles)
    
    $sy += $btnH + $gap
    $btnSnsMap = Create-Button "Create SNS Mapping" 8 $sy $snsBtnW $btnH
    $btnSnsMap.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnSnsMap.Add_Click({ CreateIDMapping -OutputFileName "sns_mappings.txt" -MatchMode Auto })
    $snsGroup.Controls.Add($btnSnsMap)
    
    $btnViewMapping = Create-Button "View SNS Mapping" $snsCol2X $sy $snsBtnW $btnH
    $btnViewMapping.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnViewMapping.Add_Click({
        $c = Get-Col
        if (-not $c) { return }
        $mapFile = Join-Path (Split-Path $c.metadataPath -Parent) "sns_mappings.txt"
        if (Test-Path $mapFile) {
            $content = Get-Content $mapFile -Raw
            if (-not [string]::IsNullOrWhiteSpace($content)) {
                [System.Windows.Forms.MessageBox]::Show($content, "SNS Mappings", "OK", "Information")
            } else {
                [System.Windows.Forms.MessageBox]::Show("Mapping file is empty.", "SNS Mappings", "OK", "Information")
            }
        } else {
            [System.Windows.Forms.MessageBox]::Show("No mapping file found. Run a Map / Create SNS Mapping first.", "SNS Mappings", "OK", "Information")
        }
    })
    $snsGroup.Controls.Add($btnViewMapping)

    $sy += $btnH + $gap
    $btnDlSnsTitles = Create-Button "DL SNS Titles DB" 8 $sy $snsBtnW $btnH
    $btnDlSnsTitles.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnDlSnsTitles.Add_Click({ Download-SnsTitlesDatabase })
    $snsGroup.Controls.Add($btnDlSnsTitles)

    $btnChecksumMatch = Create-Button "Match ROMs by Checksum" $snsCol2X $sy $snsBtnW $btnH
    $btnChecksumMatch.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnChecksumMatch.Add_Click({ Match-RomsByChecksum })
    $snsGroup.Controls.Add($btnChecksumMatch)
    
    $sy += $btnH + $gap
    $btnSnsBox = Create-Button "Add Box Art (Mapping)" 8 $sy $snsBtnW $btnH
    $btnSnsBox.Add_Click({ AddBoxArt -Mode Mapping })
    $snsGroup.Controls.Add($btnSnsBox)
    
    $btnSnsBoxName = Create-Button "Add Box Art (Game Name)" $snsCol2X $sy $snsBtnW $btnH
    $btnSnsBoxName.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnSnsBoxName.Add_Click({ AddBoxArt -Mode GameName })
    $snsGroup.Controls.Add($btnSnsBoxName)
    
    $sy += $btnH + $gap
    $btnLoadSns = Create-Button "Load SNS File" 8 $sy $snsBtnW $btnH
    $btnLoadSns.Add_Click({
        $of = New-Object System.Windows.Forms.OpenFileDialog
        $of.Title = "Load SNS Codes from File"
        $of.Filter = "Text Files (*.txt)|*.txt|All Files (*.*)|*.*"
        if ($of.ShowDialog() -eq "OK") {
            $codes = @(Get-Content $of.FileName | Where-Object { $_ -match '^SNS-' } | ForEach-Object { $_.Trim() })
            if ($codes.Count -gt 0) {
                Update-SnsCodeList $codes $of.FileName
                Log-Message "Loaded $($codes.Count) SNS codes from: $($of.FileName)" "Green"
            } else {
                Log-Message "No SNS codes found in file" "Yellow"
            }
        }
    })
    $snsGroup.Controls.Add($btnLoadSns)
    
    $btnClearSns = Create-Button "Clear List" $snsCol2X $sy $snsBtnW $btnH
    $btnClearSns.Add_Click({ 
        $script:lastSnsCodes = @()
        $script:lastSnsCodesFile = $null
        if ($null -ne $script:snsCodeList) {
            $script:snsCodeList.Items.Clear()
            if ($null -ne $script:snsInfoLabel) {
                $script:snsInfoLabel.Text = "0 codes loaded"
            }
        }
        Log-Message "SNS list cleared" "Yellow"
    })
    $snsGroup.Controls.Add($btnClearSns)
    
    $sy += $btnH + $gap
    $btnSnsStats = Create-Button "SNS Stats" 8 $sy ($leftW - 16) $btnH
    $btnSnsStats.Add_Click({
        $count = $script:lastSnsCodes.Count
        $file = if ($script:lastSnsCodesFile) { $script:lastSnsCodesFile } else { "None" }
        [System.Windows.Forms.MessageBox]::Show("SNS Codes Loaded: $count`nSource File: $file", "SNS Statistics", "OK", "Information")
    })
    $snsGroup.Controls.Add($btnSnsStats)
    
    # ============================================================
    # SECTION 4: GAME ID TOOLS
    # ============================================================
    $gameIDGroup = New-Object System.Windows.Forms.GroupBox
    $gameIDGroup.Text = " Game ID Tools "
    $gameIDGroup.Location = New-Object System.Drawing.Point(5, 1098)
    $gameIDGroup.Size = New-Object System.Drawing.Size($leftW, 90)
    $gameIDGroup.ForeColor = $script:theme.text
    $gameIDGroup.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $leftPanel.Controls.Add($gameIDGroup)
    
    $gy = 22
    $idBw = [Math]::Floor(($leftW - 24) / 2)
    $btnID1 = Create-Button "Extract Game IDs" 8 $gy $idBw 26
    $btnID1.Add_Click({ ExtractGameIDsFromImages })
    $gameIDGroup.Controls.Add($btnID1)
    
    $btnID2 = Create-Button "Create Game ID Mapping" (8 + $idBw + 6) $gy $idBw 26
    $btnID2.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnID2.Add_Click({ CreateIDMapping -OutputFileName "game_id_mappings.txt" })
    $gameIDGroup.Controls.Add($btnID2)
    
    $gy += 28
    $btnID3 = Create-Button "Apply Game IDs" 8 $gy $idBw 26
    $btnID3.Add_Click({ ApplyGameIDsToMetadata })
    $gameIDGroup.Controls.Add($btnID3)
    
    $btnID4 = Create-Button "Console ID Reference" (8 + $idBw + 6) $gy $idBw 26
    $btnID4.Add_Click({ ShowConsoleIDList })
    $gameIDGroup.Controls.Add($btnID4)
    
    # ============================================================
    # SECTION 5: GAMETDB TOOLS
    # ============================================================
    # 4 rows x 2 equal half-width buttons
    $gtdbExpandedH = 148
    $gtdbGroup = New-Object System.Windows.Forms.GroupBox
    $gtdbGroup.Text = " GameTDB Tools "
    $gtdbGroup.Location = New-Object System.Drawing.Point(5, 1196)
    $gtdbGroup.Size = New-Object System.Drawing.Size($leftW, $gtdbExpandedH)
    $gtdbGroup.ForeColor = $script:theme.text
    $gtdbGroup.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $leftPanel.Controls.Add($gtdbGroup)
    
    $gty = 22
    $gtBw = [Math]::Floor(($leftW - 24) / 2)
    $gtCol2 = 8 + $gtBw + 6
    $btnGt1 = Create-Button "Download Titles DB" 8 $gty $gtBw 26
    $btnGt1.Add_Click({ Download-GameTDBTitles })
    $gtdbGroup.Controls.Add($btnGt1)
    
    $btnGt2 = Create-Button "Download Covers by ID" $gtCol2 $gty $gtBw 26
    $btnGt2.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnGt2.Add_Click({ Download-GameTDBCovers })
    $gtdbGroup.Controls.Add($btnGt2)
    
    $gty += 30
    $btnGtPack = Create-Button "Download Cover Pack..." 8 $gty $gtBw 26
    $btnGtPack.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnGtPack.Add_Click({ Show-GameTDBCoverPackDialog })
    $gtdbGroup.Controls.Add($btnGtPack)
    
    $btnGt3 = Create-Button "Lookup Title by ID" $gtCol2 $gty $gtBw 26
    $btnGt3.Add_Click({ Lookup-GameTDBTitle })
    $gtdbGroup.Controls.Add($btnGt3)
    
    $gty += 30
    $btnGt4 = Create-Button "Open GameTDB Page" 8 $gty $gtBw 26
    $btnGt4.Add_Click({ Open-GameTDBPage })
    $gtdbGroup.Controls.Add($btnGt4)
    
    $btnGt5 = Create-Button "Apply Titles from GameTDB" $gtCol2 $gty $gtBw 26
    $btnGt5.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnGt5.Add_Click({ Apply-GameTDBTitles })
    $gtdbGroup.Controls.Add($btnGt5)
    
    $gty += 30
    $btnGt7 = Create-Button "Fill Missing Box Art Paths" 8 $gty $gtBw 26
    $btnGt7.Add_Click({ Fill-GameTDBBoxArtPaths })
    $gtdbGroup.Controls.Add($btnGt7)
    
    $btnGt8 = Create-Button "DL Covers from Game List" $gtCol2 $gty $gtBw 26
    $btnGt8.Add_Click({ Download-CoversFromGameList })
    $gtdbGroup.Controls.Add($btnGt8)
    
    # ============================================================
    # SECTION 6: BUILDER / REPAIR TOOLS
    # ============================================================
    # 11 button rows: y=22, step 30, btn h=26 -> last bottom 22+10*30+26=348 -> height 386 (extra row for Sort)
    $builderExpandedH = 386
    $builderGroup = New-Object System.Windows.Forms.GroupBox
    $builderGroup.Text = " Build & Repair Tools "
    $builderGroup.Location = New-Object System.Drawing.Point(5, 1384)
    $builderGroup.Size = New-Object System.Drawing.Size($leftW, $builderExpandedH)
    $builderGroup.ForeColor = $script:theme.text
    $builderGroup.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $leftPanel.Controls.Add($builderGroup)
    
    $by = 22
    $bBw = [Math]::Floor(($leftW - 24) / 2)
    $bCol2 = 8 + $bBw + 6
    
    $btnB1 = Create-Button "Scan Folder for Games" 8 $by $bBw 26
    $btnB1.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnB1.Add_Click({ Scan-GamesFromFolder })
    $builderGroup.Controls.Add($btnB1)
    
    $btnB2 = Create-Button "Titles from Covers" $bCol2 $by $bBw 26
    $btnB2.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnB2.Add_Click({ Scan-TitlesFromCoverImages })
    $builderGroup.Controls.Add($btnB2)
    
    $by += 30
    $btnB3 = Create-Button "Build Meta from Folder" 8 $by $bBw 26
    $btnB3.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnB3.Add_Click({ Build-MetadataFromFolder })
    $builderGroup.Controls.Add($btnB3)
    
    $btnB4 = Create-Button "Import Games from List" $bCol2 $by $bBw 26
    $btnB4.Add_Click({ Import-GamesFromList })
    $builderGroup.Controls.Add($btnB4)
    
    $by += 30
    $btnB5 = Create-Button "Sync File Paths" 8 $by $bBw 26
    $btnB5.Add_Click({ Sync-FilePathsFromFolder })
    $builderGroup.Controls.Add($btnB5)
    
    $btnB6 = Create-Button "Export Game List" $bCol2 $by $bBw 26
    $btnB6.Add_Click({ Export-GameList })
    $builderGroup.Controls.Add($btnB6)
    
    $by += 30
    $btnB7 = Create-Button "DL Covers from Mapping" 8 $by $bBw 26
    $btnB7.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnB7.Add_Click({ Download-CoversFromMapping })
    $builderGroup.Controls.Add($btnB7)
    
    $btnB8 = Create-Button "Export Missing List" $bCol2 $by $bBw 26
    $btnB8.Add_Click({ Export-MissingCoversList })
    $builderGroup.Controls.Add($btnB8)
    
    $by += 30
    $btnB9 = Create-Button "Read SNES ROM Headers" 8 $by $bBw 26
    $btnB9.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnB9.Add_Click({ Read-SnesRomHeaders })
    $builderGroup.Controls.Add($btnB9)
    
    $btnB11 = Create-Button "Strip All Box Art Paths" $bCol2 $by $bBw 26
    $btnB11.Add_Click({ Strip-BoxArtPaths })
    $builderGroup.Controls.Add($btnB11)
    
    $by += 30
    $btnB12 = Create-Button "Clean Bogus Games" 8 $by $bBw 26
    $btnB12.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnB12.Add_Click({ CleanBogusGames })
    $builderGroup.Controls.Add($btnB12)
    
    $btnB13 = Create-Button "Hide Multi-Disc + M3U" $bCol2 $by $bBw 26
    $btnB13.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnB13.Add_Click({ Hide-MultiDiscAndBuildM3U })
    $builderGroup.Controls.Add($btnB13)
    
    $by += 30
    $btnB14 = Create-Button "Strip All Assets" 8 $by $bBw 26
    $btnB14.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnB14.Add_Click({ Strip-AllAssetPaths })
    $builderGroup.Controls.Add($btnB14)
    
    $btnB15 = Create-Button "Backup All Meta (Zip)" $bCol2 $by $bBw 26
    $btnB15.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnB15.Add_Click({ Backup-AllMetadataZip })
    $builderGroup.Controls.Add($btnB15)
    
    $by += 30
    $btnB16 = Create-Button "Edit Genres" 8 $by $bBw 26
    $btnB16.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnB16.Add_Click({ Edit-Genres })
    $builderGroup.Controls.Add($btnB16)
    
    $btnB17 = Create-Button "Full File Check Report" $bCol2 $by $bBw 26
    $btnB17.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnB17.Add_Click({ Check-AllFilesReport })
    $builderGroup.Controls.Add($btnB17)
    
    $by += 30
    $btnB18 = Create-Button "Export EmulationStation XML" 8 $by $bBw 26
    $btnB18.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnB18.Add_Click({ Export-EmulationStationXml })
    $builderGroup.Controls.Add($btnB18)
    
    $btnB19 = Create-Button "Import EmulationStation XML" $bCol2 $by $bBw 26
    $btnB19.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnB19.Add_Click({ Import-EmulationStationXml })
    $builderGroup.Controls.Add($btnB19)
    
    $by += 30
    $btnB20 = Create-Button "Backup Orphan Media" 8 $by $bBw 26
    $btnB20.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnB20.Add_Click({ Backup-OrphanMedia })
    $builderGroup.Controls.Add($btnB20)
    
    $btnB21 = Create-Button "Batch Import Library" $bCol2 $by $bBw 26
    $btnB21.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnB21.Add_Click({ Batch-ImportFromLibraryRoot })
    $builderGroup.Controls.Add($btnB21)
    
    $by += 30
    $btnB22 = Create-Button "Sort Games A-Z" 8 $by $bBw 26
    $btnB22.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnB22.Add_Click({ Sort-GamesAlphabetically })
    $builderGroup.Controls.Add($btnB22)
    
    $btnB23 = Create-Button "Remove Games w/ No File" $bCol2 $by $bBw 26
    $btnB23.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnB23.Add_Click({ Remove-GamesWithoutFile })
    $builderGroup.Controls.Add($btnB23)
    
    # Register left sections
    Register-LeftSection -Group $colGroup -ExpandedHeight 230 -Collapsible $true -StartExpanded $true -Title "Collections"
    Register-LeftSection -Group $toolsGroup -ExpandedHeight 120 -Collapsible $true -StartExpanded $true -Title "Metadata Tools"
    Register-LeftSection -Group $imageGroup -ExpandedHeight 340 -Collapsible $true -StartExpanded $false -Title "Image Tools"
    Register-LeftSection -Group $snsGroup -ExpandedHeight $snsExpandedH -Collapsible $true -StartExpanded $false -Title "SNS Code Tools"
    Register-LeftSection -Group $gameIDGroup -ExpandedHeight 90 -Collapsible $true -StartExpanded $false -Title "Game ID Tools"
    Register-LeftSection -Group $gtdbGroup -ExpandedHeight $gtdbExpandedH -Collapsible $true -StartExpanded $false -Title "GameTDB Tools"
    Register-LeftSection -Group $builderGroup -ExpandedHeight $builderExpandedH -Collapsible $true -StartExpanded $true -Title "Build & Repair Tools"
    
    # Delay relayout until after form is shown to avoid layout issues
    $form.Add_Shown({
        Relayout-LeftSections
        try {
            Apply-MetaAndGamesCollapseState
            Relayout-TerminalPosition
        } catch {}
    })
    
    # ============================================================
    # RIGHT PANEL - Fields (left) + Game list (right)
    # ============================================================
    $rightPanel = New-Object System.Windows.Forms.Panel
    $rightPanel.Dock = "Fill"
    $rightPanel.BackColor = $script:theme.background
    $rightPanel.Padding = New-Object System.Windows.Forms.Padding(6, 6, 22, 8)
    $rightPanel.AutoScroll = $true
    $tableLayout.Controls.Add($rightPanel, 1, 0)
    $script:rightPanelRef = $rightPanel
    $rightPanel.Add_Resize({
        if ($script:rawMode) { Apply-RawEditorLayout }
        else { Relayout-TerminalPosition }
    })
    
    # ---- Item Metadata (GroupBox includes fields + action buttons) ----
    # Tall enough to show all fields through Description without inner scrolling
    $script:metaExpandedH = 640
    $script:metaCollapsedH = 28
    $script:metaExpanded = $true
    $script:metaNarrowW = 800
    $script:contentFullW = 1132
    $metaOuter = New-Object System.Windows.Forms.GroupBox
    $metaOuter.Text = "      Item Metadata "
    $metaOuter.Location = New-Object System.Drawing.Point(5, 48)
    $metaOuter.Size = New-Object System.Drawing.Size($script:metaNarrowW, $script:metaExpandedH)
    $metaOuter.ForeColor = $script:theme.text
    $metaOuter.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $metaOuter.BackColor = $script:theme.background
    $rightPanel.Controls.Add($metaOuter)
    
    $btnMetaToggle = New-Object System.Windows.Forms.Button
    $btnMetaToggle.Size = New-Object System.Drawing.Size(22, 18)
    $btnMetaToggle.Location = New-Object System.Drawing.Point(6, 1)
    $btnMetaToggle.FlatStyle = "Flat"
    $btnMetaToggle.FlatAppearance.BorderSize = 0
    $btnMetaToggle.BackColor = $script:theme.button
    $btnMetaToggle.ForeColor = $script:theme.accent
    $btnMetaToggle.Tag = "accent"
    $btnMetaToggle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btnMetaToggle.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnMetaToggle.TabStop = $false
    $btnMetaToggle.Text = "-"
    $btnMetaToggle.Add_Click({
        $script:metaExpanded = -not $script:metaExpanded
        Apply-MetaAndGamesCollapseState
    })
    $metaOuter.Controls.Add($btnMetaToggle)
    $btnMetaToggle.BringToFront()
    $script:btnMetaToggle = $btnMetaToggle

    # Bottom edge drag grip - resize Item Metadata (and Games) height
    $script:metaDragging = $false
    $script:metaDragStartY = 0
    $script:metaDragStartH = 0
    $metaGrip = New-Object System.Windows.Forms.Panel
    $metaGrip.Size = New-Object System.Drawing.Size(696, 8)
    $metaGrip.Location = New-Object System.Drawing.Point(2, 916)
    $metaGrip.BackColor = [System.Drawing.Color]::FromArgb(45, 50, 75)
    $metaGrip.Cursor = [System.Windows.Forms.Cursors]::SizeNS
    $metaOuter.Controls.Add($metaGrip)
    $script:metaGrip = $metaGrip
    $metaGrip.BringToFront()

    $metaGrip.Add_MouseDown({
        param($sender, $e)
        if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
        if (-not $script:metaExpanded) {
            $script:metaExpanded = $true
            Apply-MetaAndGamesCollapseState
        }
        $script:metaDragging = $true
        $script:metaDragStartY = [System.Windows.Forms.Cursor]::Position.Y
        $script:metaDragStartH = $script:metaOuter.Height
        $sender.Capture = $true
    })
    $metaGrip.Add_MouseMove({
        param($sender, $e)
        if (-not $script:metaDragging) { return }
        $dy = [System.Windows.Forms.Cursor]::Position.Y - $script:metaDragStartY
        $newH = $script:metaDragStartH + $dy
        if ($newH -lt 160) { $newH = 160 }
        if ($newH -gt 1200) { $newH = 1200 }
        $script:metaExpandedH = $newH
        $script:metaOuter.Height = $newH
        $script:gamesExpandedH = $newH
        if ($script:gamesOuter -and $script:gamesOuter.Visible) {
            $script:gamesOuter.Height = $newH
        }
        Apply-MetaInnerLayout
        Relayout-TerminalPosition
        try {
            $f = $script:mainForm
            if ($f -and $f.WindowState -eq "Normal") {
                $bottom = $script:termOuter.Bottom + 58
                $needed = [Math]::Max($f.MinimumSize.Height, $bottom)
                if ($f.Height -lt $needed) { $f.Height = $needed }
            }
        } catch {}
    })
    $metaGrip.Add_MouseUp({
        param($sender, $e)
        $script:metaDragging = $false
        $sender.Capture = $false
        if ($script:metaOuter) {
            $script:metaExpandedH = $script:metaOuter.Height
            $script:gamesExpandedH = $script:metaOuter.Height
        }
        Relayout-TerminalPosition
    })
    
    # ---- Detail panel (collection header + game fields) ----
    # Leave ~22px on the right inside the panel for the vertical scrollbar so it
    # never covers field text. Content width is kept under the client area so a
    # horizontal scrollbar does not appear over the description box.
    $detailPanel = New-Object System.Windows.Forms.Panel
    $detailPanel.Location = New-Object System.Drawing.Point(8, 18)
    $detailPanel.Size = New-Object System.Drawing.Size(784, 612)
    $detailPanel.BackColor = $script:theme.editor
    $detailPanel.BorderStyle = "FixedSingle"
    $detailPanel.AutoScroll = $true
    # Extra right padding so the vertical scrollbar does not cover field text
    $detailPanel.Padding = New-Object System.Windows.Forms.Padding(0, 0, 28, 4)
    $metaOuter.Controls.Add($detailPanel)
    $script:detailPanel = $detailPanel
    $script:metaOuter = $metaOuter
    $btnMetaToggle.BringToFront()
    
    $script:fieldControls = @{}
    $script:headerControls = @{}
    $fy = 6
    
    # Collection header section
    $hdrTitle = New-Object System.Windows.Forms.Label
    $hdrTitle.Text = "Collection Metadata"
    $hdrTitle.Location = New-Object System.Drawing.Point(6, $fy)
    $hdrTitle.Size = New-Object System.Drawing.Size(520, 20)
    $hdrTitle.ForeColor = $script:theme.success
    $hdrTitle.Tag = "success"
    $hdrTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $detailPanel.Controls.Add($hdrTitle)
    $fy += 24
    
    $headerDefs = @(
        @{ Label = "Collection"; FieldName = "collection"; IsMulti = $false; Hint = "collection" },
        @{ Label = "Shortname"; FieldName = "shortname"; IsMulti = $false; Hint = "shortname" },
        @{ Label = "Launch"; FieldName = "launch"; IsMulti = $false; Hint = "launch" },
        @{ Label = "Box Front"; FieldName = "assets.box_front"; IsMulti = $false; Hint = "box2dfront" },
        @{ Label = "Logo"; FieldName = "assets.logo"; IsMulti = $false; Hint = "wheel" },
        @{ Label = "Description"; FieldName = "description"; IsMulti = $true; Hint = "description" }
    )
    
    # Label (blue) + folder hint (gray) + field
    # Wide enough for "Title Screen" / "Steam Grid" without clipping
    $labelW = 102
    $hintW  = 90
    $hintX  = 6 + $labelW
    $fieldX = 200
    $fieldW = 559
    $hintColor = [System.Drawing.Color]::FromArgb(150, 155, 175)
    
    foreach ($fd in $headerDefs) {
        $fLabel = $fd["Label"]
        $fName  = $fd["FieldName"]
        $fMulti = $fd["IsMulti"]
        $fHint  = $fd["Hint"]
        
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $fLabel
        $lbl.Location = New-Object System.Drawing.Point(6, $fy)
        $lbl.Size = New-Object System.Drawing.Size($labelW, 20)
        $lbl.ForeColor = $script:theme.accent
        $lbl.Tag = "accent"
        $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
        $lbl.AutoSize = $false
        $lbl.AutoEllipsis = $false
        $detailPanel.Controls.Add($lbl)
        
        if ($fHint) {
            $hintLbl = New-Object System.Windows.Forms.Label
            $hintLbl.Text = $fHint
            $hintLbl.Location = New-Object System.Drawing.Point($hintX, ($fy + 1))
            $hintLbl.Size = New-Object System.Drawing.Size($hintW, 18)
            $hintLbl.ForeColor = $hintColor
            $hintLbl.Tag = "hint"
            $hintLbl.Font = New-Object System.Drawing.Font("Consolas", 8)
            $hintLbl.AutoSize = $false
            $hintLbl.AutoEllipsis = $false
            $detailPanel.Controls.Add($hintLbl)
        }
        
        $tb = New-Object System.Windows.Forms.TextBox
        $tb.Location = New-Object System.Drawing.Point($fieldX, $fy)
        $tb.BackColor = $script:theme.panel
        $tb.ForeColor = $script:theme.text
        $tb.BorderStyle = "FixedSingle"
        $tb.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $tb.Tag = "header:$fName"
        
        if ($fMulti) {
            $tb.Size = New-Object System.Drawing.Size($fieldW, 48)
            $tb.Multiline = $true
            $tb.ScrollBars = "Vertical"
            $tb.AcceptsReturn = $true
            $fy += 52
        } else {
            $tb.Size = New-Object System.Drawing.Size($fieldW, 22)
            $fy += 24
        }
        $detailPanel.Controls.Add($tb)
        $script:headerControls[$fName] = $tb
    }
    
    $fy += 6
    $gameTitle = New-Object System.Windows.Forms.Label
    $gameTitle.Text = "Game Metadata"
    $gameTitle.Location = New-Object System.Drawing.Point(6, $fy)
    $gameTitle.Size = New-Object System.Drawing.Size(520, 20)
    $gameTitle.ForeColor = $script:theme.success
    $gameTitle.Tag = "success"
    $gameTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $detailPanel.Controls.Add($gameTitle)
    $fy += 24
    
    # Asset fields include BOTH box_full (scrapers) and boxFull (themes)
    # Hint = media subfolder name shown in light gray next to the blue label
    $fieldDefs = @(
        @{ Label = "Title"; FieldName = "game"; IsMulti = $false; Hint = "game" },
        @{ Label = "Sort Title"; FieldName = "sort_title"; IsMulti = $false; Hint = "sort-title" },
        @{ Label = "File"; FieldName = "file"; IsMulti = $false; Hint = "file" },
        @{ Label = "Developer"; FieldName = "developer"; IsMulti = $false; Hint = "developer" },
        @{ Label = "Publisher"; FieldName = "publisher"; IsMulti = $false; Hint = "publisher" },
        @{ Label = "Genre"; FieldName = "genre"; IsMulti = $false; Hint = "genre" },
        @{ Label = "Players"; FieldName = "players"; IsMulti = $false; Hint = "players" },
        @{ Label = "Release"; FieldName = "release"; IsMulti = $false; Hint = "release" },
        @{ Label = "Rating"; FieldName = "rating"; IsMulti = $false; Hint = "rating" },
        @{ Label = "Game ID"; FieldName = "game_id"; IsMulti = $false; Hint = "game_id" },
        @{ Label = "Box Front"; FieldName = "assets.box_front"; IsMulti = $false; Hint = "box2dfront" },
        @{ Label = "Box Full"; FieldName = "assets.box_full"; IsMulti = $false; Hint = "box2dfull" },
        @{ Label = "boxFull"; FieldName = "assets.boxFull"; IsMulti = $false; Hint = "boxFull" },
        @{ Label = "Box Back"; FieldName = "assets.box_back"; IsMulti = $false; Hint = "box2dback" },
        @{ Label = "Screenshot"; FieldName = "assets.screenshot"; IsMulti = $false; Hint = "screenshot" },
        @{ Label = "Video"; FieldName = "assets.video"; IsMulti = $false; Hint = "videos" },
        @{ Label = "Logo"; FieldName = "assets.logo"; IsMulti = $false; Hint = "wheel" },
        @{ Label = "Title Screen"; FieldName = "assets.titlescreen"; IsMulti = $false; Hint = "titlescreen" },
        @{ Label = "Fanart"; FieldName = "assets.fanart"; IsMulti = $false; Hint = "fanart" },
        @{ Label = "Cartridge"; FieldName = "assets.cartridge"; IsMulti = $false; Hint = "cartridge" },
        @{ Label = "Steam Grid"; FieldName = "assets.steamgrid"; IsMulti = $false; Hint = "steamgrid" },
        @{ Label = "Marquee"; FieldName = "assets.marquee"; IsMulti = $false; Hint = "marquee" },
        @{ Label = "Banner"; FieldName = "assets.banner"; IsMulti = $false; Hint = "banner" },
        @{ Label = "Box Thumb"; FieldName = "assets.box_front_thumb"; IsMulti = $false; Hint = "box2dThumb" },
        @{ Label = "Description"; FieldName = "description"; IsMulti = $true; Hint = "description" }
    )
    
    foreach ($fd in $fieldDefs) {
        $fLabel = $fd["Label"]
        $fName  = $fd["FieldName"]
        $fMulti = $fd["IsMulti"]
        $fHint  = $fd["Hint"]
        
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $fLabel
        $lbl.Location = New-Object System.Drawing.Point(6, $fy)
        $lbl.Size = New-Object System.Drawing.Size($labelW, 20)
        $lbl.ForeColor = $script:theme.accent
        $lbl.Tag = "accent"
        $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
        $lbl.AutoSize = $false
        $lbl.AutoEllipsis = $false
        $detailPanel.Controls.Add($lbl)
        
        if ($fHint) {
            $hintLbl = New-Object System.Windows.Forms.Label
            $hintLbl.Text = $fHint
            $hintLbl.Location = New-Object System.Drawing.Point($hintX, ($fy + 1))
            $hintLbl.Size = New-Object System.Drawing.Size($hintW, 18)
            $hintLbl.ForeColor = $hintColor
            $hintLbl.Tag = "hint"
            $hintLbl.Font = New-Object System.Drawing.Font("Consolas", 8)
            $hintLbl.AutoSize = $false
            $hintLbl.AutoEllipsis = $false
            $detailPanel.Controls.Add($hintLbl)
        }
        
        $tb = New-Object System.Windows.Forms.TextBox
        $tb.Location = New-Object System.Drawing.Point($fieldX, $fy)
        $tb.BackColor = $script:theme.panel
        $tb.ForeColor = $script:theme.text
        $tb.BorderStyle = "FixedSingle"
        $tb.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $tb.Tag = $fName
        
        if ($fMulti) {
            $tb.Size = New-Object System.Drawing.Size($fieldW, 80)
            $tb.Multiline = $true
            $tb.ScrollBars = "Vertical"
            $tb.AcceptsReturn = $true
            $fy += 84
        } else {
            $tb.Size = New-Object System.Drawing.Size($fieldW, 22)
            $fy += 24
        }
        $detailPanel.Controls.Add($tb)
        $script:fieldControls[$fName] = $tb
    }
    
    # Prevent horizontal scrollbar from covering the description area
    try {
        $detailPanel.HorizontalScroll.Maximum = 0
        $detailPanel.AutoScroll = $false
        $detailPanel.HorizontalScroll.Visible = $false
        $detailPanel.AutoScroll = $true
        $detailPanel.HorizontalScroll.Enabled = $false
    } catch {}
    
    # ---- Games list (GroupBox border) ----
    # Collapses with Item Metadata via Apply-MetaAndGamesCollapseState
    $script:gamesExpandedH = 640
    $script:gamesCollapsedH = 28
    $gamesOuter = New-Object System.Windows.Forms.GroupBox
    $gamesOuter.Text = " Games "
    $gamesOuter.Location = New-Object System.Drawing.Point(812, 48)
    $gamesOuter.Size = New-Object System.Drawing.Size(320, $script:gamesExpandedH)
    $gamesOuter.ForeColor = $script:theme.text
    $gamesOuter.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $gamesOuter.BackColor = $script:theme.background
    $rightPanel.Controls.Add($gamesOuter)
    $script:gamesOuter = $gamesOuter
    
    $searchLabel = New-Object System.Windows.Forms.Label
    $searchLabel.Text = "Search:"
    $searchLabel.Location = New-Object System.Drawing.Point(8, 18)
    $searchLabel.Size = New-Object System.Drawing.Size(50, 20)
    $searchLabel.ForeColor = $script:theme.textDim
    $gamesOuter.Controls.Add($searchLabel)
    $script:searchLabel = $searchLabel
    
    $gameSearchBox = New-Object System.Windows.Forms.TextBox
    $gameSearchBox.Location = New-Object System.Drawing.Point(58, 16)
    $gameSearchBox.Size = New-Object System.Drawing.Size(252, 22)
    $gameSearchBox.BackColor = $script:theme.editor
    $gameSearchBox.ForeColor = $script:theme.text
    $gameSearchBox.BorderStyle = "FixedSingle"
    $gameSearchBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $gamesOuter.Controls.Add($gameSearchBox)
    $script:gameSearchBox = $gameSearchBox
    $gameSearchBox.Add_TextChanged({ FilterGameList })
    
    $gameListBox = New-Object System.Windows.Forms.ListBox
    $gameListBox.Location = New-Object System.Drawing.Point(8, 44)
    $gameListBox.Size = New-Object System.Drawing.Size(304, 590)
    $gameListBox.BackColor = $script:theme.editor
    $gameListBox.ForeColor = $script:theme.text
    $gameListBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $gameListBox.BorderStyle = "FixedSingle"
    $gameListBox.IntegralHeight = $false
    $gamesOuter.Controls.Add($gameListBox)
    $script:gameListBox = $gameListBox
    $gameListBox.Add_SelectedIndexChanged({
        if (-not $script:suppressGameSelect) { LoadSelectedGameFields }
    })
    
    # Raw editor (hidden by default)
    $editorBox = New-Object System.Windows.Forms.TextBox
    $editorBox.Location = New-Object System.Drawing.Point(5, 80)
    $editorBox.Size = New-Object System.Drawing.Size(1132, 598)
    $editorBox.Multiline = $true
    $editorBox.ScrollBars = "Both"
    $editorBox.WordWrap = $false
    $editorBox.AcceptsTab = $true
    $editorBox.AcceptsReturn = $true
    $editorBox.ShortcutsEnabled = $true
    $editorBox.Font = New-Object System.Drawing.Font("Consolas", 9)
    $editorBox.BackColor = $script:theme.editor
    $editorBox.ForeColor = $script:theme.text
    $editorBox.BorderStyle = "FixedSingle"
    $editorBox.Visible = $false
    $editorBox.Text = "Select a collection to view metadata..."
    # Explicit paste handling - some hosts block default Ctrl+V on multiline TextBox
    $editorBox.Add_KeyDown({
        param($sender, $e)
        if ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::V) {
            try {
                if ([System.Windows.Forms.Clipboard]::ContainsText()) {
                    $clip = [System.Windows.Forms.Clipboard]::GetText()
                    $start = $sender.SelectionStart
                    $len = $sender.SelectionLength
                    $txt = $sender.Text
                    if ($null -eq $txt) { $txt = "" }
                    $before = if ($start -gt 0) { $txt.Substring(0, $start) } else { "" }
                    $after = if (($start + $len) -lt $txt.Length) { $txt.Substring($start + $len) } else { "" }
                    $sender.Text = $before + $clip + $after
                    $sender.SelectionStart = $start + $clip.Length
                    $sender.SelectionLength = 0
                    $e.SuppressKeyPress = $true
                    $e.Handled = $true
                }
            } catch {}
        }
    })
    $rightPanel.Controls.Add($editorBox)
    $script:editorBox = $editorBox

    # ---- Raw editor search bar (under action buttons; shown only in Raw mode) ----
    $rawSearchBar = New-Object System.Windows.Forms.Panel
    $rawSearchBar.Location = New-Object System.Drawing.Point(5, 48)
    $rawSearchBar.Size = New-Object System.Drawing.Size(1132, 30)
    $rawSearchBar.BackColor = $script:theme.background
    $rawSearchBar.Visible = $false
    $rightPanel.Controls.Add($rawSearchBar)
    $script:rawSearchBar = $rawSearchBar

    $rawSearchLbl = New-Object System.Windows.Forms.Label
    $rawSearchLbl.Text = "Find:"
    $rawSearchLbl.Location = New-Object System.Drawing.Point(4, 5)
    $rawSearchLbl.Size = New-Object System.Drawing.Size(40, 20)
    $rawSearchLbl.ForeColor = $script:theme.textDim
    $rawSearchBar.Controls.Add($rawSearchLbl)

    $rawSearchBox = New-Object System.Windows.Forms.TextBox
    $rawSearchBox.Location = New-Object System.Drawing.Point(48, 3)
    $rawSearchBox.Size = New-Object System.Drawing.Size(420, 24)
    $rawSearchBox.BackColor = $script:theme.editor
    $rawSearchBox.ForeColor = $script:theme.text
    $rawSearchBox.BorderStyle = "FixedSingle"
    $rawSearchBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $rawSearchBar.Controls.Add($rawSearchBox)
    $script:rawSearchBox = $rawSearchBox
    $rawSearchBox.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            Find-InRawEditor -Forward $true
            $e.SuppressKeyPress = $true
            $e.Handled = $true
        }
    })

    $btnRawFindNext = Create-Button "Find Next" 478 2 90 24
    $btnRawFindNext.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnRawFindNext.Add_Click({ Find-InRawEditor -Forward $true })
    $rawSearchBar.Controls.Add($btnRawFindNext)

    $btnRawFindPrev = Create-Button "Find Prev" 574 2 90 24
    $btnRawFindPrev.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $btnRawFindPrev.Add_Click({ Find-InRawEditor -Forward $false })
    $rawSearchBar.Controls.Add($btnRawFindPrev)

    $rawSearchStatus = New-Object System.Windows.Forms.Label
    $rawSearchStatus.Text = ""
    $rawSearchStatus.Location = New-Object System.Drawing.Point(674, 5)
    $rawSearchStatus.Size = New-Object System.Drawing.Size(440, 20)
    $rawSearchStatus.ForeColor = $script:theme.textDim
    $rawSearchBar.Controls.Add($rawSearchStatus)
    $script:rawSearchStatus = $rawSearchStatus
    
    # ---- Top header row: action buttons (left) + stats (right) ----
    # Single clean row across the full content width
    $actionBarLabels = @(
        "Apply", "Refresh",
        "Form", "Raw", "Save", "Guide"
    )
    $actionFont = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btnW = 0
    foreach ($lab in $actionBarLabels) {
        $m = [System.Windows.Forms.TextRenderer]::MeasureText($lab, $actionFont)
        $need = $m.Width + 14
        if ($need -gt $btnW) { $btnW = $need }
    }
    if ($btnW -lt 56) { $btnW = 56 }
    $btnY = 5
    $bg = 6
    $pad = 6
    $actionBarW = if ($script:contentFullW) { $script:contentFullW } else { 1132 }
    $actionBar = New-Object System.Windows.Forms.Panel
    $actionBar.Location = New-Object System.Drawing.Point(5, 2)
    $actionBar.Size = New-Object System.Drawing.Size($actionBarW, 36)
    $actionBar.BackColor = $script:theme.background
    $actionBar.BorderStyle = "FixedSingle"
    $rightPanel.Controls.Add($actionBar)
    $script:actionBar = $actionBar
    $actionBar.BringToFront()
    
    # Left group: Apply / Refresh / Form / Raw / Save / Launch / Guide
    $bx = $pad
    $btnApplyFields = Create-Button "Apply" $bx $btnY $btnW 26
    $btnApplyFields.Add_Click({ ApplyGameFields })
    $actionBar.Controls.Add($btnApplyFields)
    $bx += $btnW + $bg
    $btnRef = Create-Button "Refresh" $bx $btnY $btnW 26
    $btnRef.Add_Click({ UpdateEditor })
    $actionBar.Controls.Add($btnRef)
    $bx += $btnW + $bg
    $btnFormView = Create-Button "Form" $bx $btnY $btnW 26
    $btnFormView.Add_Click({ Set-EditorMode $false })
    $actionBar.Controls.Add($btnFormView)
    $bx += $btnW + $bg
    $btnRaw = Create-Button "Raw" $bx $btnY $btnW 26
    $btnRaw.Add_Click({ Set-EditorMode $true })
    $actionBar.Controls.Add($btnRaw)
    $script:btnRaw = $btnRaw
    $bx += $btnW + $bg
    $btnSave = Create-Button "Save" $bx $btnY $btnW 26
    $btnSave.Add_Click({ SaveMeta })
    $actionBar.Controls.Add($btnSave)
    
    $bx += $btnW + $bg
    $btnLaunch = Create-Button "Launch" $bx $btnY $btnW 26
    $btnLaunch.Add_Click({ Launch-Pegasus })
    $ttLaunch = New-Object System.Windows.Forms.ToolTip
    $ttLaunch.SetToolTip($btnLaunch, "Launch Pegasus Frontend (set path in Settings)")
    $actionBar.Controls.Add($btnLaunch)
    $script:btnLaunch = $btnLaunch
    
    # Log tools - compact widths, just right of Launch (Guide is in Settings)
    $logFont = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $logLabels = @("Clear Log", "Copy Log", "Export Log")
    $logWidths = @{}
    foreach ($lab in $logLabels) {
        $m = [System.Windows.Forms.TextRenderer]::MeasureText($lab, $logFont)
        $logWidths[$lab] = [Math]::Max(52, $m.Width + 12)
    }
    $bx += $btnW + $bg
    $btnClear = Create-Button "Clear Log" $bx $btnY $logWidths["Clear Log"] 26
    $btnClear.Add_Click({ if ($script:logBox) { $script:logBox.Clear() } })
    $actionBar.Controls.Add($btnClear)
    $script:btnClearLog = $btnClear
    $bx += $logWidths["Clear Log"] + $bg
    $btnCopyLog = Create-Button "Copy Log" $bx $btnY $logWidths["Copy Log"] 26
    $btnCopyLog.Add_Click({
        if ($script:logBox -and -not [string]::IsNullOrEmpty($script:logBox.Text)) {
            [System.Windows.Forms.Clipboard]::SetText($script:logBox.Text)
            Log-Message "Log copied to clipboard" "Green"
        } else {
            Log-Message "Log is empty" "Yellow"
        }
    })
    $actionBar.Controls.Add($btnCopyLog)
    $script:btnCopyLog = $btnCopyLog
    $bx += $logWidths["Copy Log"] + $bg
    $btnExport = Create-Button "Export Log" $bx $btnY $logWidths["Export Log"] 26
    $btnExport.Add_Click({
        $save = New-Object System.Windows.Forms.SaveFileDialog
        $save.Title = "Export Log"
        $save.Filter = "Text Files (*.txt)|*.txt|All Files (*.*)|*.*"
        $save.FileName = "metadata_repair_log.txt"
        if ($save.ShowDialog() -eq "OK") {
            if ($script:logBox) {
                $script:logBox.Text | Out-File $save.FileName -Encoding UTF8
                Log-Message "Log exported to: $($save.FileName)" "Green"
            }
        }
    })
    $actionBar.Controls.Add($btnExport)
    $script:btnExportLog = $btnExport

    $bx += $logWidths["Export Log"] + $bg
    $btnSettings = Create-Button "Settings" $bx $btnY 72 26
    $btnSettings.Add_Click({ Show-SettingsDialog })
    $actionBar.Controls.Add($btnSettings)
    $script:btnSettings = $btnSettings
    
    # Stats right-aligned on the same row
    $countLabel = New-Object System.Windows.Forms.Label
    $countLabel.Text = "Ready  |  Collections: 0"
    $countLabel.Size = New-Object System.Drawing.Size(420, 26)
    $countLabel.Location = New-Object System.Drawing.Point(($actionBarW - 426), 5)
    $countLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $countLabel.ForeColor = $script:theme.success
    $countLabel.TextAlign = "MiddleRight"
    $countLabel.Name = "countLabel"
    $actionBar.Controls.Add($countLabel)
    $script:countLabel = $countLabel
    
    # ============================================================
    # TERMINAL
    # ============================================================
    $script:termExpandedH = 220
    $script:termCollapsedH = 28
    $script:termExpanded = $true    # start expanded (matches preferred default layout)
    $termOuter = New-Object System.Windows.Forms.GroupBox
    $termOuter.Text = "      Terminal Output "
    $termOuter.Location = New-Object System.Drawing.Point(5, 978)
    $termOuter.Size = New-Object System.Drawing.Size(1132, $script:termExpandedH)
    $termOuter.ForeColor = $script:theme.text
    $termOuter.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $termOuter.BackColor = $script:theme.background
    $rightPanel.Controls.Add($termOuter)
    $script:termOuter = $termOuter
    
    $btnTermToggle = New-Object System.Windows.Forms.Button
    $btnTermToggle.Size = New-Object System.Drawing.Size(22, 18)
    $btnTermToggle.Location = New-Object System.Drawing.Point(6, 1)
    $btnTermToggle.FlatStyle = "Flat"
    $btnTermToggle.FlatAppearance.BorderSize = 0
    $btnTermToggle.BackColor = $script:theme.button
    $btnTermToggle.ForeColor = $script:theme.accent
    $btnTermToggle.Tag = "accent"
    $btnTermToggle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btnTermToggle.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnTermToggle.TabStop = $false
    $btnTermToggle.Text = "-"
    $btnTermToggle.Add_Click({
        $script:termExpanded = -not $script:termExpanded
        $tb = $script:btnTermToggle
        if ($script:termExpanded) {
            if (-not $script:termExpandedH -or $script:termExpandedH -lt 120) { $script:termExpandedH = 360 }
            $script:termOuter.Height = $script:termExpandedH
            $script:termOuter.Text = "      Terminal Output "
            if ($tb) { $tb.Text = "-" }
            foreach ($ctrl in @($script:termOuter.Controls)) {
                if ($null -eq $tb -or $ctrl -ne $tb) { $ctrl.Visible = $true }
            }
            if ($tb) { $tb.Visible = $true; $tb.BringToFront() }
            if ($script:termGrip) { $script:termGrip.Visible = $true; $script:termGrip.BringToFront() }
        } else {
            foreach ($ctrl in @($script:termOuter.Controls)) {
                if ($null -eq $tb -or $ctrl -ne $tb) { $ctrl.Visible = $false }
            }
            $script:termOuter.Height = $script:termCollapsedH
            $script:termOuter.Text = "      Terminal Output "
            if ($tb) {
                $tb.Text = "+"
                $tb.Visible = $true
                $tb.BringToFront()
            }
            # Keep bottom grip visible so user can drag to expand
            if ($script:termGrip) { $script:termGrip.Visible = $true; $script:termGrip.BringToFront() }
        }
        Relayout-TerminalPosition
    })
    $termOuter.Controls.Add($btnTermToggle)
    $btnTermToggle.BringToFront()
    $script:btnTermToggle = $btnTermToggle

    # Bottom edge drag grip - click and drag up/down to resize terminal height
    $script:termDragging = $false
    $script:termDragStartY = 0
    $script:termDragStartH = 0
    $termGrip = New-Object System.Windows.Forms.Panel
    $termGrip.Size = New-Object System.Drawing.Size(963, 8)
    $termGrip.Location = New-Object System.Drawing.Point(2, 20)
    $termGrip.BackColor = [System.Drawing.Color]::FromArgb(45, 50, 75)
    $termGrip.Cursor = [System.Windows.Forms.Cursors]::SizeNS
    $termGrip.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
    $termOuter.Controls.Add($termGrip)
    $script:termGrip = $termGrip
    $termGrip.BringToFront()

    $termGrip.Add_MouseDown({
        param($sender, $e)
        if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
        if (-not $script:termExpanded) {
            $script:termExpanded = $true
            $tb = $script:btnTermToggle
            if ($tb) { $tb.Text = "-" }
            if ($script:termOuter.Height -lt 100) {
                $script:termExpandedH = 360
                $script:termOuter.Height = 360
            }
            foreach ($ctrl in @($script:termOuter.Controls)) {
                if ($script:btnTermToggle -and $ctrl -eq $script:btnTermToggle) { continue }
                $ctrl.Visible = $true
            }
        }
        $script:termDragging = $true
        $script:termDragStartY = [System.Windows.Forms.Cursor]::Position.Y
        $script:termDragStartH = $script:termOuter.Height
        $sender.Capture = $true
    })
    $termGrip.Add_MouseMove({
        param($sender, $e)
        if (-not $script:termDragging) { return }
        $dy = [System.Windows.Forms.Cursor]::Position.Y - $script:termDragStartY
        $newH = $script:termDragStartH + $dy
        # Min ~ header+log; max ~ large log view
        if ($newH -lt 120) { $newH = 120 }
        if ($newH -gt 900) { $newH = 900 }
        $script:termExpandedH = $newH
        if ($script:rawMode) {
            # Keep editor and terminal sharing the panel without overlap
            Apply-RawEditorLayout
        } else {
            $script:termOuter.Height = $newH
            Apply-TerminalInnerLayout
            try {
                $f = $script:mainForm
                if ($f -and $f.WindowState -eq "Normal") {
                    $bottom = $script:termOuter.Bottom + 58
                    $needed = [Math]::Max($f.MinimumSize.Height, $bottom)
                    if ($f.Height -lt $needed) { $f.Height = $needed }
                }
            } catch {}
        }
    })
    $termGrip.Add_MouseUp({
        param($sender, $e)
        $script:termDragging = $false
        $sender.Capture = $false
        if ($script:termOuter) {
            $script:termExpandedH = $script:termOuter.Height
        }
        Relayout-TerminalPosition
    })
    
    $logBox = New-Object System.Windows.Forms.TextBox
    $logBox.Location = New-Object System.Drawing.Point(8, 20)
    $logBox.Size = New-Object System.Drawing.Size(951, 300)
    $logBox.Multiline = $true
    $logBox.ScrollBars = "Vertical"
    $logBox.ReadOnly = $true
    $logBox.Font = New-Object System.Drawing.Font("Consolas", 9)
    $logBox.BackColor = $script:theme.terminal
    $logBox.ForeColor = $script:theme.text
    $logBox.BorderStyle = "FixedSingle"
    $logBox.Text = "Ready. Select a collection to begin..."
    $termOuter.Controls.Add($logBox)
    $script:logBox = $logBox
    
    # Log action buttons are on the top action bar (Clear / Copy / Export Log)
    
    # Terminal starts expanded by default; toggle still works
    if ($btnTermToggle) {
        $btnTermToggle.Visible = $true
        $btnTermToggle.BringToFront()
    }
    
    # ============================================================
    # STATUS BAR
    # ============================================================
    $statusStrip = New-Object System.Windows.Forms.StatusStrip
    $statusStrip.BackColor = $script:theme.panel
    $statusStrip.ForeColor = $script:theme.text
    $statusStrip.SizingGrip = $false
    $form.Controls.Add($statusStrip)
    
    $statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
    $statusLabel.Text = "Ready"
    $statusLabel.ForeColor = $script:theme.text
    $statusLabel.Spring = $true
    $statusStrip.Items.Add($statusLabel)
    $script:statusBar = $statusLabel
    
    $statusCount = New-Object System.Windows.Forms.ToolStripStatusLabel
    $statusCount.Text = "Collections: $($script:collections.Count)"
    $statusCount.ForeColor = $script:theme.textDim
    $statusStrip.Items.Add($statusCount)
    
    $statusColl = New-Object System.Windows.Forms.ToolStripStatusLabel
    $statusColl.Text = "No collection loaded"
    $statusColl.ForeColor = $script:theme.textDim
    $statusStrip.Items.Add($statusColl)
    
    # ============================================================
    # INIT
    # ============================================================
    try {
        RefreshCollectionList
        
        if ($collectionList.Items.Count -gt 0) {
            $collectionList.SelectedIndex = 0
            $name = $collectionList.SelectedItem.ToString()
            $script:currentCollection = $script:collections[$name]
            $statusColl.Text = "Loaded: $name"
            UpdateEditor
            UpdateStats
            Log-Message "Loaded collection: $name" "Green"
        } else {
            Log-Message "No collections found. Click 'Add' to add one." "Yellow"
        }
    } catch {
        Log-Message "Init warning: $_" "Yellow"
    }
    
    $form.ShowDialog() | Out-Null
}

# ============================================================================
# WORKFLOW DIALOG
# ============================================================================
function ShowWorkflowDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Workflow Guide"
    $dlg.Size = New-Object System.Drawing.Size(980, 720)
    $dlg.MinimumSize = New-Object System.Drawing.Size(800, 500)
    $dlg.StartPosition = "CenterParent"
    $dlg.BackColor = $script:theme.background
    $dlg.ForeColor = $script:theme.text
    
    $root = New-Object System.Windows.Forms.TableLayoutPanel
    $root.Dock = "Fill"
    $root.ColumnCount = 2
    $root.RowCount = 2
    $root.BackColor = $script:theme.background
    [void]$root.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 280)))
    [void]$root.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 56)))
    $dlg.Controls.Add($root)
    
    $tree = New-Object System.Windows.Forms.TreeView
    $tree.Dock = "Fill"
    $tree.BackColor = $script:theme.editor
    $tree.ForeColor = $script:theme.text
    $tree.BorderStyle = "FixedSingle"
    $tree.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $tree.HideSelection = $false
    $tree.FullRowSelect = $true
    $tree.ShowLines = $true
    $tree.ShowPlusMinus = $true
    $tree.ShowRootLines = $true
    $root.Controls.Add($tree, 0, 0)
    
    $detail = New-Object System.Windows.Forms.RichTextBox
    $detail.Dock = "Fill"
    $detail.ReadOnly = $true
    $detail.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $detail.BackColor = $script:theme.editor
    $detail.ForeColor = $script:theme.text
    $detail.BorderStyle = "FixedSingle"
    $detail.DetectUrls = $false
    $detail.ScrollBars = "Vertical"
    $root.Controls.Add($detail, 1, 0)
    
    $script:__wfContent = @{}
    
    $nIntro = $tree.Nodes.Add("Introduction")
    [void]$tree.Nodes.Add("About")
    $script:__wfContent["Introduction"] = @"
WORKFLOW GUIDE

Use the expandable list on the left. Click a topic to read steps on the right.

This tool repairs and builds Pegasus frontend metadata: collections, game entries, box art paths, SNS/Game IDs, and GameTDB helpers.

Version $($script:version)

ASSET FOLDER REFERENCE:
- box2dfront/  -> assets.box_front (fallback)
- box2dfull/   -> assets.box_full (standard)
- boxFull/     -> assets.boxFull (YOUR THEME USES THIS)
- box2dback/   -> assets.box_back
- screenshot/  -> assets.screenshot
- videos/      -> assets.video
- wheel/       -> assets.logo
- titlescreen/ -> assets.titlescreen
- fanart/      -> assets.fanart
- cartridge/   -> assets.cartridge
- steamgrid/   -> assets.steamgrid
- marquee/     -> assets.marquee
- banner/      -> assets.banner
"@
    
    $nScen = $tree.Nodes.Add("Scenarios")
    

    $script:__wfContent["About"] = @"
ABOUT - Metadata Repair Tool

Version: see app title bar / status (v$($script:version) at runtime)

Application developed by jacktrabblt72380

Complete metadata management tool for Pegasus Frontend.

Features
  Add / Remove / Edit Pegasus collections
  View and edit metadata files (Form + Raw modes)
  Auto-load collections on selection
  Workflow Guide for common scenarios
  Metadata health checks and statistics
  Find missing cover art
  Add box art and all media types automatically
  Rename images to match game names
  Update metadata names to match images
  Fix duplicate game entries
  SNS Code Tools (product codes, titles, box art mapping)
  Game ID Tools (Extract, Create Mapping, Apply)
  GameTDB Tools (Titles, Covers by ID, Covers from Game List)
  Build & Repair Tools (scan, build, import, sync, ES XML)
  Import EmulationStation / Skraper gamelist.xml
  Batch Import Library and Backup Orphan Media
  PNG <-> JPG conversion
  Backup / Restore (.bkup.txt)
  Collapsible tool sections

Sections
  Collections - Create / Add / Remove / Load
  Metadata Tools - Health, Stats, Missing, Duplicates, Backup
  Image Tools - Rename, Box Art, All Media Types, Conversion
  SNS Code Tools - Extract, Map, Add Box Art
  Game ID Tools - Extract, Map, Apply, Console Reference
  GameTDB Tools - Titles, Covers, Lookup
  Build & Repair Tools - Scan, Build, Import, Sync, ES XML, orphan cleanup

Theme
  Use Settings -> Theme to choose Default / Steam / Light / High Contrast / Windows (applies immediately).

Developer note
  All changes and updates must always be listed in the developer log
  (Settings -> Dev Log). Include version, date, and a short description.

Developed by jacktrabblt72380
"@

    $script:__wfContent["SNS covers already on disk"] = @"
SCENARIO: SNS / product-code cover images on disk (e.g. SNS-XXXX-USA.png)

1. SNS Code Tools -> From Images
   - Pick the folder with cover images
   - Builds SNS list + sns_codes_from_images.txt

2. Choose a mapping method:
   - Map by Product Code
   - Map by Titles File (needs sns_titles.txt)
   - Create SNS Mapping (Auto)

3. SNS Code Tools -> Add Box Art (Mapping)
   - Writes assets.box_front from sns_mappings.txt

4. Save Changes
"@
    [void]$nScen.Nodes.Add("SNS covers already on disk")
    
    $script:__wfContent["Covers named like game titles"] = @"
SCENARIO: Images already named like the game (Super_Mario_World.png)

1. SNS Code Tools -> Add Box Art (Game Name)
   OR Image Tools -> Add Box Art to Metadata

2. Save Changes
"@
    [void]$nScen.Nodes.Add("Covers named like game titles")
    
    $script:__wfContent["Build collection from ROM folder"] = @"
SCENARIO: Build or expand a collection from a ROM folder

1. Collections -> Create (or Add existing metadata)

2. Build & Repair Tools -> Scan Folder for Games

3. Build & Repair Tools -> Build Meta from Folder

4. Optional: Sync File Paths if ROMs moved

5. Add box art using SNS or GameTDB flows

6. Save Changes
"@
    [void]$nScen.Nodes.Add("Build collection from ROM folder")
    
    $script:__wfContent["SNES ROM headers explained"] = @"
SCENARIO: How Read SNES ROM Headers works (and what not to do)

What the tool does
  Build & Repair -> Read SNES ROM Headers scans .sfc/.smc (and similar)
  files and reads the internal title stored in the ROM header.

  Those internal names are usually SHORT and ALL CAPS, e.g.:
    SUPER MARIOWORLD
    ACCELEBRID
    ARKANOID DOH IT AGAIN

  That is normal for SNES dumps - it is NOT the pretty display title
  from the box or No-Intro filename.

What it writes (under media\Tools\ when possible)
  snes_rom_headers.txt
    filename_title|internal_header|status|full_path
  titles_from_rom_headers.txt
    unique internal titles only (for reference / mapping)
  bad_rom_headers.txt
    ROMs with BAD or EMPTY headers (consider clean dumps)

What it does NOT do
  It does not add game: blocks to your metadata by itself.
  It does not set file: paths on existing games.

Common mistake
  Importing titles_from_rom_headers.txt (or similar) via
  Import Games from List creates game entries that are ALL CAPS
  and have NO file: path. In the Games list they appear after your
  real titles (or mixed in after Sort A-Z). Clicking them shows an
  empty File field.

  Clean Bogus Games will NOT remove them - those titles look like
  valid words, just uppercase.

How to fix it
  1. Metadata Tools -> Backup (optional; the next step also backs up)
  2. Build & Repair -> Remove Games w/ No File
  3. Confirm the list of titles to delete, then Yes
  4. Save / reload and confirm File paths on remaining games

Correct uses for header data
  - Cross-check which ROMs have valid vs bad headers
  - Build mappings (filename <-> internal name) for other tools
  - Do NOT treat the internal title list as a full game list

Build Meta from Folder uses ROM filenames for game: and file: -
prefer that when creating a collection from a ROM directory.
"@
    [void]$nScen.Nodes.Add("SNES ROM headers explained")
    
    $script:__wfContent["Add all media types"] = @"
SCENARIO: Add all asset types (boxFull, logo, fanart, etc.)

1. Image Tools -> Add All Media Types (boxFull, logo, etc.)

2. This scans all asset folders and adds paths for:
   - assets.box_front (box2dfront/)
   - assets.box_full (box2dfull/)
   - assets.boxFull (boxFull/) <- YOUR THEME
   - assets.box_back (box2dback/)
   - assets.screenshot (screenshot/)
   - assets.video (videos/)
   - assets.logo (wheel/)
   - assets.titlescreen (titlescreen/)
   - assets.fanart (fanart/)
   - assets.cartridge (cartridge/)
   - assets.steamgrid (steamgrid/)
   - assets.marquee (marquee/)
   - assets.banner (banner/)

3. Apply Changes -> Save Changes
"@
    [void]$nScen.Nodes.Add("Add all media types")
    
    $nTools = $tree.Nodes.Add("Tool reference")
    
    $script:__wfContent["Collections"] = @"
COLLECTIONS

Create  - New folder + metadata .txt + media subfolders
Add     - Attach an existing Pegasus metadata file
Remove  - Drop collection from the list (does not delete files)
Refresh - Reload list
Load    - Open selected collection into the editor
"@
    [void]$nTools.Nodes.Add("Collections")
    
    $script:__wfContent["Metadata Tools"] = @"
METADATA TOOLS

Check Health         - Counts games, box art, missing images
Statistics           - Collection stats
Find Missing Covers  - missing_covers.txt report
Fix Duplicates       - Clean duplicate game blocks
Backup / Restore     - .bkup.txt safety copies
Refresh              - Reload collection list

See the About page in this Guide for version and credits.
"@
    [void]$nTools.Nodes.Add("Metadata Tools")
    
    $script:__wfContent["Image Tools"] = @"
IMAGE TOOLS

Rename Images to Match Game Names
Update Metadata Names from Images
Add Box Art to Metadata
Add All Media Types (boxFull, logo, etc.)  <- NEW
Convert PNG/JPG (all or selected)
Update Metadata Extensions to PNG/JPG
"@
    [void]$nTools.Nodes.Add("Image Tools")
    
    $script:__wfContent["SNS Code Tools"] = @"
SNS CODE TOOLS

From XML / From Images  - Build SNS code list
Map by Product Code     - Match 4-letter code inside title
Map by Titles File      - sns_titles.txt: SNS-XXXX-USA=Game Title
Create SNS Mapping      - Auto (titles then product code)
View SNS Mapping
DL SNS Titles DB        - Downloads GameDB-SNES checksum database
Match ROMs by Checksum  - Matches ROMs to real titles by CRC32,
                          since SNES has no SNS-code database online
Add Box Art (Mapping)   - Paths from mapping
Add Box Art (Game Name) - Paths from game-named images
Load SNS File / Clear List / SNS Stats
"@
    [void]$nTools.Nodes.Add("SNS Code Tools")
    
    $script:__wfContent["Game ID Tools"] = @"
GAME ID TOOLS

Extract Game IDs from image filenames
Create Game ID Mapping
Apply Game IDs into metadata
Console ID Reference
"@
    [void]$nTools.Nodes.Add("Game ID Tools")
    
    $script:__wfContent["GameTDB Tools"] = @"
GAMETDB TOOLS

GameTDB (gametdb.com) has no official REST API.
This tool uses their public downloads and art CDN.

Platforms
  Wii, GameCube, Wii U, Switch, 3DS, DS, PS3

Download Titles DB
  - Fetches platform titles list (e.g. wiitdb.txt)
  - Saves gametdb_<platform>_titles.txt under media/Tools

Download Covers by ID
  - For each game with game_id in the current collection
  - Downloads cover from art.gametdb.com into box2dfront

Download Cover Pack...
  - System + multi cover types + primary region
  - Dialog shows the currently selected collection name
  - Options: current collection only (game_id on this platform),
    only missing art (front / boxFull / box_full / back),
    region fallback, save into media folders, write asset paths,
    full covers -> boxFull (Unicovers) or box2dfull
  - Media folders: box2dfront / boxFull or box2dfull / box2dback / disc
  - Writes assets.box_front / boxFull or box_full / box_back / cartridge
  - Failures logged to failed_covers.csv (media/Tools or out folder)
  - Skips files that already exist; abortable progress window

  When is a collection required?
  - YES if any of these are checked (defaults are on):
      Current collection only
      Save into media folders
      Write asset paths into metadata
  - NO if all three are unchecked: downloads the full platform
    list into the Output folder you choose
  - Only missing art uses the selected collection's metadata
    to decide what is already present. With no collection,
    it cannot skip by metadata (still skips if the image file
    already exists on disk).

  Collection only + platform
  - Only game_id values that also appear in the chosen system's
    titles list are downloaded. A Wii collection will not drive
    Nintendo DS downloads. Pick the system that matches the
    selected collection.

Lookup Title by ID / Open GameTDB Page / Apply Titles
Fill Missing Box Art Paths / DL Covers from Game List

SNES (SNS-XXXX-USA) is not on GameTDB art CDN -
use SNS Code Tools for those.
"@
    [void]$nTools.Nodes.Add("GameTDB Tools")
    
    $script:__wfContent["Build & Repair Tools"] = @"
BUILD & REPAIR TOOLS

Scan Folder for Games - list ROM filenames from a folder
Titles from Covers - build a title list from box art names
Build Meta from Folder - create game: entries from ROMs on disk
Import Games from List - import titles from a text list
Sync File Paths - match file: paths to ROMs in the folder
Export Game List / Export Missing List
DL Covers from Mapping - download covers using a mapping file
Read SNES ROM Headers - scan SNES ROM internal titles into Tools files
  (does NOT add games to metadata - see scenario "SNES ROM headers explained")

Strip All Box Art Paths - remove assets.box_front lines only
Strip All Assets - remove every assets.* line
Hide Multi-Disc + M3U - (disc N) files -> .m3u + ignore-files
Backup All Meta (Zip) - zip all metadata under a root folder
Edit Genres - multi-select rename/merge genre tags
Full File Check Report - ROMs vs metadata vs media gaps
Clean Bogus Games - remove garbled/junk titles
  (symbol-heavy garbage only - does NOT remove ALL CAPS header titles)
Sort Games A-Z - reorder all game blocks alphabetically by title
  (uses sort_title when set, otherwise game title; case-insensitive)
Remove Games w/ No File - delete game: blocks that have no file: path
  Use this when the Games list has extra ALL CAPS names (SNES internal
  headers) that show no ROM path when selected.

Import EmulationStation XML
  Imports from gamelist.xml into the current collection.
  Prompt: "Only import games whose ROM exists on disk?"
  Yes (recommended) = skip XML entries with no matching file
  No = import every game from the XML
  Also converts ES ratings (0.85) to percent (85%).

Export EmulationStation XML
  Writes gamelist.xml next to the collection metadata.

Backup Orphan Media
  Finds media files that do not match any ROM or game title
  and moves them to: <collection>\media.backup\<type>\
  Files are moved, not deleted (safe cleanup after scraping).

Batch Import Library
  Pick a library root folder (contains system folders).
  Finds every gamelist.xml, creates/adds collections as needed,
  and imports games. Same "ROM must exist" option as single import.
  After batch import: open a collection -> Image Tools ->
  Add All Media Types to link box art, screenshots, etc.

Typical post-scrape workflow
  1. Batch Import Library (or Import ES XML on one collection)
  2. Image Tools -> Add All Media Types
  3. Full File Check Report
  4. Backup Orphan Media (optional cleanup)
"@
    [void]$nTools.Nodes.Add("Build & Repair Tools")

    $script:__wfContent["Import from EmulationStation / Skraper"] = @"
IMPORT FROM EMULATIONSTATION / SKRAPER

Bellerophon-style workflow built into this tool:

1. Scrape with Skraper (or similar) so each system folder has:
   - ROMs
   - gamelist.xml
   - media\ (box2dfront, screenshot, wheel, etc.)

2. Single collection:
   Build & Repair -> Import EmulationStation XML
   Choose Yes when asked to only import games whose ROM exists.

3. Whole library at once:
   Build & Repair -> Batch Import Library
   Select the root folder that contains your system folders.

4. Link media:
   Image Tools -> Add All Media Types
   Matches files in media subfolders to game titles / ROM names.

5. Verify:
   Full File Check Report

6. Optional cleanup:
   Backup Orphan Media
   Moves unmatched art to media.backup (not deleted).
"@
    [void]$nTools.Nodes.Add("Import from EmulationStation / Skraper")
    
    $nFiles = $tree.Nodes.Add("Files created")
    $script:__wfContent["Files created"] = @"
FILES WRITTEN NEXT TO YOUR METADATA

sns_codes_from_images.txt
sns_codes_from_xml.txt
sns_mappings.txt
sns_titles.txt
game_ids_from_images.txt
game_id_mappings.txt
missing_covers.txt
games_list_export.txt
games_from_folder.txt
games_from_folder_paths.txt
unresolved_cover_names.txt
titles_from_covers.txt
titles_from_rom_headers.txt
filename.bkup.txt
media.backup\ (orphan media moved by Backup Orphan Media)
full_file_check_report.txt
"@
    
    # Select intro by default
    if ($nIntro) { $tree.SelectedNode = $nIntro }
    $tree.ExpandAll()
    
    if ($script:__wfContent.ContainsKey("Introduction")) {
        $detail.Clear()
        $detail.AppendText([string]$script:__wfContent["Introduction"])
    }
    
    $tree.Add_AfterSelect({
        $node = $this.SelectedNode
        if ($null -eq $node) { return }
        $title = $node.Text
        $d = $script:__wfDetail
        if ($null -eq $d) { return }
        $d.Clear()
        if ($script:__wfContent -and $script:__wfContent.ContainsKey($title)) {
            $d.SelectionColor = $script:theme.text
            $d.AppendText([string]$script:__wfContent[$title])
        } else {
            $d.SelectionColor = $script:theme.textDim
            $d.AppendText("Select a topic on the left.")
        }
        $d.SelectionStart = 0
        $d.ScrollToCaret()
    })
    $script:__wfDetail = $detail
    
    $footer = New-Object System.Windows.Forms.Panel
    $footer.Dock = "Fill"
    $footer.BackColor = $script:theme.background
    $root.Controls.Add($footer, 0, 1)
    $root.SetColumnSpan($footer, 2)
    
    $lblDev = New-Object System.Windows.Forms.Label
    $lblDev.Text = "Developed by jacktrabblt72380  |  v$($script:version)"
    $lblDev.Location = New-Object System.Drawing.Point(12, 16)
    $lblDev.Size = New-Object System.Drawing.Size(500, 24)
    $lblDev.ForeColor = $script:theme.textDim
    $lblDev.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $footer.Controls.Add($lblDev)
    
    $btnExpand = Create-Button "Expand All" 520 12 100 30
    $btnExpand.Add_Click({ $tree.ExpandAll() })
    $footer.Controls.Add($btnExpand)
    
    $btnCollapse = Create-Button "Collapse All" 630 12 100 30
    $btnCollapse.Add_Click({ $tree.CollapseAll() })
    $footer.Controls.Add($btnCollapse)
    
    $btnOK = Create-Button "Close" 850 12 100 30
    $btnOK.Add_Click({ $dlg.Close() })
    $footer.Controls.Add($btnOK)
    
    $dlg.ShowDialog()
}

# ============================================================================
# ABOUT DIALOG
# ============================================================================
function ShowAboutDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "About Metadata Repair Tool"
    $dlg.Size = New-Object System.Drawing.Size(500, 550)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.BackColor = $script:theme.background
    $dlg.ForeColor = $script:theme.text
    
    $mainPanel = New-Object System.Windows.Forms.Panel
    $mainPanel.Dock = "Fill"
    $mainPanel.BackColor = $script:theme.background
    $mainPanel.Padding = New-Object System.Windows.Forms.Padding(15)
    $dlg.Controls.Add($mainPanel)
    
    $textBox = New-Object System.Windows.Forms.RichTextBox
    $textBox.Dock = "Fill"
    $textBox.ReadOnly = $true
    $textBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $textBox.BackColor = $script:theme.editor
    $textBox.ForeColor = $script:theme.text
    $textBox.BorderStyle = "FixedSingle"
    $textBox.ScrollBars = "Vertical"
    
    $textBox.SelectionColor = $script:theme.accent
    $textBox.AppendText("Metadata Repair Tool  v$($script:version)" + "`n`n")
    
    $textBox.SelectionColor = $script:theme.success
    $textBox.AppendText("Application developed by jacktrabblt72380" + "`n`n")
    
    $textBox.SelectionColor = $script:theme.textDim
    $textBox.AppendText("Complete metadata management tool for Pegasus frontend." + "`n`n")
    
    $textBox.SelectionColor = $script:theme.accent
    $textBox.AppendText("Features:" + "`n")
    $textBox.SelectionColor = $script:theme.text
    $textBox.AppendText("  Add/Remove/Edit Pegasus collections" + "`n")
    $textBox.AppendText("  View and edit metadata files directly" + "`n")
    $textBox.AppendText("  Auto-load collections on selection" + "`n")
    $textBox.AppendText("  Complete workflow guide for all scenarios" + "`n")
    $textBox.AppendText("  Check metadata health and find issues" + "`n")
    $textBox.AppendText("  Show detailed statistics" + "`n")
    $textBox.AppendText("  Find missing cover art" + "`n")
    $textBox.AppendText("  Add box art to games automatically" + "`n")
    $textBox.AppendText("  Rename images to match game names" + "`n")
    $textBox.AppendText("  Update metadata names to match images" + "`n")
    $textBox.AppendText("  Fix duplicate game entries" + "`n")
    $textBox.AppendText("  SNS Code Tools (map by product code, titles, dual Add Box Art)" + "`n")
    $textBox.AppendText("  Game ID Tools (Extract, Create Mapping, Apply)" + "`n")
    $textBox.AppendText("  GameTDB Tools (Titles, Covers by ID, Covers from Game List)" + "`n")
    $textBox.AppendText("  Build & Repair Tools (scan folder, build meta, import list, sync paths)" + "`n")
    $textBox.AppendText("  Download covers from mapping or game list" + "`n")
    $textBox.AppendText("  PNG to JPG and JPG to PNG conversion" + "`n")
    $textBox.AppendText("  Backup / Restore (.bkup.txt)" + "`n")
    $textBox.AppendText("  Collapsible tool sections + workflow guide" + "`n")
    $textBox.AppendText("  ALL ASSET TYPES SUPPORTED: boxFront, boxFull, boxFull (theme), boxBack, screenshot, video, logo, titlescreen, fanart, cartridge, steamgrid, marquee, banner" + "`n")
    $textBox.AppendText("  ALL SCRIPTS EMBEDDED - No external files!" + "`n`n")
    
    $textBox.SelectionColor = $script:theme.accentDark
    $textBox.AppendText("Sections:" + "`n")
    $textBox.SelectionColor = $script:theme.text
    $textBox.AppendText("  Collections - Create/Add/Remove/Load" + "`n")
    $textBox.AppendText("  Metadata Tools - Health, Stats, Missing, Duplicates, Backup" + "`n")
    $textBox.AppendText("  Image Tools - Rename, Update Names, Add Box Art, All Media Types, Conversion" + "`n")
    $textBox.AppendText("  SNS Code Tools - Extract, Map, Add Box Art" + "`n")
    $textBox.AppendText("  Game ID Tools - Extract, Map, Apply, Console Reference" + "`n")
    $textBox.AppendText("  GameTDB Tools - Titles, Covers, Lookup, Apply Titles" + "`n")
    $textBox.AppendText("  Build & Repair Tools - Scan, Build, Import, Sync, DL covers" + "`n`n")
    
    $textBox.SelectionColor = $script:theme.success
    $textBox.AppendText("Developed by jacktrabblt72380" + "`n`n")
    $textBox.SelectionColor = $script:theme.textDim
    $textBox.AppendText("Note: All changes and updates should always be listed in the developer log (Settings -> Dev Log)." + "`n")
    
    $mainPanel.Controls.Add($textBox)
    
    $btnPanel = New-Object System.Windows.Forms.Panel
    $btnPanel.Dock = "Bottom"
    $btnPanel.Height = 50
    $btnPanel.BackColor = $script:theme.background
    $btnPanel.Padding = New-Object System.Windows.Forms.Padding(10)
    $mainPanel.Controls.Add($btnPanel)

    $btnOK = Create-Button "OK" 200 8 100 35
    $btnOK.BackColor = $script:theme.accentDark
    $btnOK.ForeColor = [System.Drawing.Color]::White
    $btnOK.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnOK.Add_Click({ $dlg.Close() })
    $btnPanel.Controls.Add($btnOK)

    # Small theme switch icon: Steam (S) <-> Windows (W)
    $btnTheme = New-Object System.Windows.Forms.Button
    $btnTheme.Size = New-Object System.Drawing.Size(36, 32)
    $btnTheme.Location = New-Object System.Drawing.Point(12, 8)
    $btnTheme.FlatStyle = "Flat"
    $btnTheme.FlatAppearance.BorderSize = 1
    $btnTheme.FlatAppearance.BorderColor = $script:theme.border
    $btnTheme.BackColor = $script:theme.button
    $btnTheme.ForeColor = [System.Drawing.Color]::White
    $btnTheme.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $btnTheme.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnTheme.TabStop = $false
    $tt = New-Object System.Windows.Forms.ToolTip
    $lblTheme = New-Object System.Windows.Forms.Label
    $lblTheme.Text = "Theme"
    $lblTheme.Location = New-Object System.Drawing.Point(50, 14)
    $lblTheme.Size = New-Object System.Drawing.Size(50, 20)
    $lblTheme.ForeColor = $script:theme.textDim
    $lblTheme.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    if ($script:themeMode -eq "Windows") {
        $btnTheme.Text = "W"
        $tt.SetToolTip($btnTheme, "Theme: Windows (click for Steam)")
    } else {
        $btnTheme.Text = "S"
        $tt.SetToolTip($btnTheme, "Theme: Steam (click for Windows)")
    }
    $btnTheme.Add_Click({
        if ($script:themeMode -eq "Windows") {
            Set-AppThemeMode -Mode "Steam"
            $btnTheme.Text = "S"
            $tt.SetToolTip($btnTheme, "Theme: Steam (click for Windows)")
        } else {
            Set-AppThemeMode -Mode "Windows"
            $btnTheme.Text = "W"
            $tt.SetToolTip($btnTheme, "Theme: Windows (click for Steam)")
        }
        $dlg.BackColor = $script:theme.background
        $dlg.ForeColor = $script:theme.text
        $mainPanel.BackColor = $script:theme.background
        $btnPanel.BackColor = $script:theme.background
        $textBox.BackColor = $script:theme.editor
        $textBox.ForeColor = $script:theme.text
        $btnTheme.BackColor = $script:theme.button
        $btnTheme.ForeColor = [System.Drawing.Color]::White
        $btnTheme.FlatAppearance.BorderColor = $script:theme.border
        $btnOK.BackColor = $script:theme.accentDark
        $lblTheme.ForeColor = $script:theme.textDim
    })
    $btnPanel.Controls.Add($btnTheme)
    $btnPanel.Controls.Add($lblTheme)
    
    $dlg.ShowDialog()
}

# ============================================================================
# CONSOLE ID LIST
# ============================================================================
function ShowConsoleIDList {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Console ID Reference"
    $dlg.Size = New-Object System.Drawing.Size(500, 600)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.BackColor = $script:theme.background
    $dlg.ForeColor = $script:theme.text
    
    $mainPanel = New-Object System.Windows.Forms.Panel
    $mainPanel.Dock = "Fill"
    $mainPanel.BackColor = $script:theme.background
    $mainPanel.Padding = New-Object System.Windows.Forms.Padding(15)
    $dlg.Controls.Add($mainPanel)
    
    $textBox = New-Object System.Windows.Forms.RichTextBox
    $textBox.Dock = "Fill"
    $textBox.ReadOnly = $true
    $textBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $textBox.BackColor = $script:theme.editor
    $textBox.ForeColor = $script:theme.text
    $textBox.BorderStyle = "FixedSingle"
    $textBox.ScrollBars = "Vertical"
    
    $textBox.SelectionColor = $script:theme.accent
    $textBox.AppendText("CONSOLE ID REFERENCE" + "`n`n")
    $textBox.SelectionColor = $script:theme.textDim
    $textBox.AppendText("GameTDB Console ID Prefixes:" + "`n`n")
    
    $textBox.SelectionColor = $script:theme.text
    foreach ($key in $script:consoleIDs.Keys | Sort-Object) {
        $textBox.AppendText("  " + $key + "  ->  " + $script:consoleIDs[$key] + "`n")
    }
    
    $textBox.AppendText("`n")
    $textBox.SelectionColor = $script:theme.accentDark
    $textBox.AppendText("Example Game IDs:" + "`n")
    $textBox.SelectionColor = $script:theme.text
    $textBox.AppendText("  SNS-ABCD-USA  ->  SNES game, USA region" + "`n")
    $textBox.AppendText("  NUS-ABCD-USA  ->  N64 game, USA region" + "`n")
    $textBox.AppendText("  RVL-ABCD-USA  ->  Wii game, USA region" + "`n")
    $textBox.AppendText("  HAC-ABCD-USA  ->  Switch game, USA region" + "`n")
    
    $mainPanel.Controls.Add($textBox)
    
    $btnPanel = New-Object System.Windows.Forms.Panel
    $btnPanel.Dock = "Bottom"
    $btnPanel.Height = 50
    $btnPanel.BackColor = $script:theme.background
    $btnPanel.Padding = New-Object System.Windows.Forms.Padding(10)
    $mainPanel.Controls.Add($btnPanel)
    
    $btnOK = Create-Button "Close" 200 8 100 35
    $btnOK.BackColor = $script:theme.accentDark
    $btnOK.ForeColor = [System.Drawing.Color]::White
    $btnOK.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnOK.Add_Click({ $dlg.Close() })
    $btnPanel.Controls.Add($btnOK)
    
    $dlg.ShowDialog()
}

# ============================================================================
# EXTRACT GAME IDs FROM IMAGES
# ============================================================================
function ExtractGameIDsFromImages {
    $c = Get-Col
    if (-not $c) { return }
    
    $fd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fd.Description = "Select the folder that contains the game ID image files (PNG/JPG)"
    $fd.ShowNewFolderButton = $false
    
    $startPath = $null
    $bp = [string]$c.mediaPath
    $meta = [string]$c.metadataPath
    if (-not [string]::IsNullOrWhiteSpace($bp)) {
        $tryFront = Join-Path $bp "box2dfront"
        if (Test-Path $tryFront) { $startPath = $tryFront }
        elseif (Test-Path $bp) { $startPath = $bp }
    }
    if (-not $startPath -and -not [string]::IsNullOrWhiteSpace($meta) -and (Test-Path $meta)) {
        $startPath = Split-Path $meta -Parent
    }
    if ($startPath) { $fd.SelectedPath = $startPath }
    
    if ($fd.ShowDialog() -ne "OK") {
        Log-Message "Extract Game IDs cancelled." "Yellow"
        return
    }
    
    $fp = $fd.SelectedPath
    Log-Message "========================================" "Cyan"
    Log-Message "EXTRACTING GAME IDs FROM IMAGES" "Cyan"
    Log-Message "========================================" "Cyan"
    Log-Message "Looking in: $fp" "White"
    
    try {
        if (-not (Test-Path $fp)) {
            Log-Message "Folder not found: $fp" "Red"
            return
        }
        
        $images = @(Get-ChildItem $fp -Filter "*.png" -ErrorAction SilentlyContinue)
        $images += @(Get-ChildItem $fp -Filter "*.jpg" -ErrorAction SilentlyContinue)
        $images += @(Get-ChildItem $fp -Filter "*.jpeg" -ErrorAction SilentlyContinue)
        
        if ($images.Count -eq 0) {
            Log-Message "No images found in: $fp" "Yellow"
            Log-Message "Looking for Game ID patterns like: SNS-ABCD-USA.png" "Yellow"
            return
        }
        
        Log-Message "Found $($images.Count) image file(s)" "Cyan"
        
        $codes = @()
        $pattern = '^([A-Z]{3,4})-([A-Z0-9]{4})-(USA|EUR|JPN|AUS|FRA|GER|ITA|SPA|UK|ASIA|KOR|CAN|MEX|BRA|CHN|TWN|RUS|SAF|IND|NZL|DEN|SWE|NOR|FIN|POL|CZE|HUN|AUT|CHE|NLD|BEL|POR|GRE|TUR|ISR|UAE|SAU|ZAF|ARG|CHL|COL|PER|VEN|MYS|SGP|PHL|IDN|THA|VNM|PAK|NGA|KEN|MAR|EGY|TUN|LBN|JOR|KWT|QAT|BHR|OMN)\.(png|jpg|jpeg)$'
        
        foreach ($img in $images) {
            if ($img.Name -match $pattern) {
                $fullID = $matches[1] + "-" + $matches[2] + "-" + $matches[3]
                $codes += $fullID
                Log-Message "  Found: $fullID" "Green"
            }
        }
        
        $codes = @($codes | Sort-Object -Unique)
        
        $outDir = $fp
        if (-not [string]::IsNullOrWhiteSpace($bp)) {
            $outDir = Get-ToolsFolder $bp
        } elseif (-not [string]::IsNullOrWhiteSpace($meta) -and (Test-Path $meta)) {
            $parent = Split-Path $meta -Parent
            if (-not [string]::IsNullOrWhiteSpace($parent)) { $outDir = $parent }
        }
        $file = Join-Path $outDir "game_ids_from_images.txt"
        $codes | Out-File -FilePath $file -Encoding UTF8
        
        if ($codes.Count -eq 0) {
            Log-Message "No Game IDs found in image filenames" "Yellow"
            Log-Message "Expected pattern: SNS-ABCD-USA.png (or any console prefix)" "Yellow"
            Log-Message "Example: SNS-ABCD-USA.png, NUS-ABCD-USA.png, RVL-ABCD-USA.png" "Yellow"
        } else {
            Log-Message "Extracted: $($codes.Count) Game IDs" "Green"
            Log-Message "Saved: $file" "Cyan"
            $codes | Select-Object -First 20 | ForEach-Object { Log-Message "  $_" "White" }
        }
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

# ============================================================================
# GAME ID FUNCTIONS
# ============================================================================
function CreateIDMapping {
    param(
        [string]$OutputFileName = "sns_mappings.txt",
        [ValidateSet("Auto", "ProductCode", "Titles")]
        [string]$MatchMode = "Auto"
    )
    $c = Get-Col
    if (-not $c) { return }
    
    $isSns = ($OutputFileName -match 'sns')
    $label = if ($isSns) { "SNS MAPPING ($MatchMode)" } else { "GAME ID MAPPING" }
    
    Log-Message "========================================" "Cyan"
    Log-Message "CREATING $label" "Cyan"
    Log-Message "========================================" "Cyan"
    
    try {
        $p = [string]$c.metadataPath
        if ([string]::IsNullOrWhiteSpace($p) -or -not (Test-Path $p)) {
            Log-Message "ERROR: Metadata file path is missing or invalid." "Red"
            return
        }
        $bp = [string]$c.mediaPath
        $metaDir = Split-Path $p -Parent
        
        $content = Get-Content $p -Raw
        $games = $content -split '(?=game: )' | Where-Object { $_ -match '^game: ' }
        
        $imageIDs = @()
        if ($isSns) {
            if ($script:lastSnsCodes -and @($script:lastSnsCodes).Count -gt 0) {
                $imageIDs = @($script:lastSnsCodes)
                Log-Message "Using $($imageIDs.Count) SNS codes from last extraction" "Cyan"
            }
            if ($imageIDs.Count -eq 0) {
                foreach ($fname in @("sns_codes_from_images.txt", "sns_codes_from_xml.txt")) {
                    $tryFile = Resolve-ToolsFile $bp $fname $metaDir
                    if ($tryFile -and (Test-Path $tryFile)) {
                        $imageIDs = @(Get-Content $tryFile | Where-Object { $_ -match '^SNS-' } | ForEach-Object { $_.Trim() })
                        if ($imageIDs.Count -gt 0) {
                            Log-Message "Loaded $($imageIDs.Count) SNS codes from $fname" "Cyan"
                            break
                        }
                    }
                }
            }
        } else {
            $tryFile = Resolve-ToolsFile $bp "game_ids_from_images.txt" $metaDir
            if ($tryFile -and (Test-Path $tryFile)) {
                $imageIDs = @(Get-Content $tryFile | Where-Object { $_ -match '^[A-Z]{3,4}-' } | ForEach-Object { $_.Trim() })
                if ($imageIDs.Count -gt 0) {
                    Log-Message "Loaded $($imageIDs.Count) Game IDs from game_ids_from_images.txt" "Cyan"
                }
            }
        }
        
        if ($imageIDs.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($bp)) {
            $fp = Join-Path $bp "box2dfront"
            if (Test-Path $fp) {
                $images = @(Get-ChildItem $fp -Filter "*.png" -ErrorAction SilentlyContinue)
                $images += @(Get-ChildItem $fp -Filter "*.jpg" -ErrorAction SilentlyContinue)
                $pattern = if ($isSns) {
                    '^(SNS)-([A-Z0-9]{4})-(USA|EUR|JPN|AUS|FRA|GER|ITA|SPA|UK|ASIA|KOR|CAN|MEX|BRA|CHN|TWN|RUS)\.(png|jpg)$'
                } else {
                    '^([A-Z]{3,4})-([A-Z0-9]{4})-(USA|EUR|JPN|AUS|FRA|GER|ITA|SPA|UK|ASIA|KOR|CAN|MEX|BRA|CHN|TWN|RUS|SAF|IND|NZL|DEN|SWE|NOR|FIN|POL|CZE|HUN|AUT|CHE|NLD|BEL|POR|GRE|TUR|ISR|UAE|SAU|ZAF|ARG|CHL|COL|PER|VEN|MYS|SGP|PHL|IDN|THA|VNM|PAK|NGA|KEN|MAR|EGY|TUN|LBN|JOR|KWT|QAT|BHR|OMN)\.(png|jpg)$'
                }
                foreach ($img in $images) {
                    if ($img.Name -match $pattern) {
                        $imageIDs += ($matches[1] + "-" + $matches[2] + "-" + $matches[3])
                    }
                }
                $imageIDs = @($imageIDs | Sort-Object -Unique)
                Log-Message "Scanned images: $($imageIDs.Count) codes" "Cyan"
            }
        }
        
        if ($imageIDs.Count -eq 0) {
            if ($isSns) {
                Log-Message "ERROR: No SNS codes available." "Red"
                Log-Message "Run SNS Code Tools -> From Images (or From XML) first." "Yellow"
            } else {
                Log-Message "ERROR: No Game IDs available." "Red"
                Log-Message "Run Game ID Tools -> Extract Game IDs first." "Yellow"
            }
            return
        }
        
        function Normalize-MatchTitle([string]$s) {
            if ([string]::IsNullOrWhiteSpace($s)) { return "" }
            $s = $s.ToLowerInvariant()
            $s = $s -replace '\(.*?\)', '' -replace '\[.*?\]', ''
            $s = $s -replace '\b(the|a|an|and|of|usa|eur|jpn|europe|japan|world)\b', ''
            $s = $s -replace '[^a-z0-9]', ''
            return $s
        }
        
        $idToTitle = @{}
        if ($isSns -and $MatchMode -ne "ProductCode") {
            $titleFiles = @(
                (Resolve-ToolsFile $bp "sns_titles.txt" $metaDir),
                (Resolve-ToolsFile $bp "snes_titles.txt" $metaDir),
                (Resolve-ToolsFile $bp "gametdb_titles.txt" $metaDir),
                (Resolve-ToolsFile $bp "titles.txt" $metaDir)
            )
            if (-not [string]::IsNullOrWhiteSpace($bp)) {
                $titleFiles += (Join-Path $bp "sns_titles.txt")
                $titleFiles += (Join-Path $bp "snes_titles.txt")
            }
            foreach ($tf in $titleFiles) {
                if (-not (Test-Path $tf)) { continue }
                foreach ($line in Get-Content $tf) {
                    if ($line -match '^(SNS-[A-Z0-9]{4}-[A-Z]{3,4})\s*[=:\t]\s*(.+)$') {
                        $idToTitle[$matches[1]] = $matches[2].Trim()
                    }
                }
                if ($idToTitle.Count -gt 0) {
                    Log-Message "Loaded $($idToTitle.Count) titles from $(Split-Path $tf -Leaf)" "Cyan"
                    break
                }
            }
        }
        
        Log-Message "Matching $($imageIDs.Count) codes to games (mode: $MatchMode)..." "Cyan"
        
        $mappings = @()
        $matched = 0
        $usedIds = @{}
        
        foreach ($g in $games) {
            if ($g -match 'game: (.+?)(?:\r?\n|$)') {
                $name = $matches[1].Trim()
            } else { continue }
            
            if ($g -match 'assets\.box_front:') { continue }
            
            $found = $null
            $normGame = Normalize-MatchTitle $name
            
            if ($MatchMode -eq "Titles" -or $MatchMode -eq "Auto") {
                if (-not $found -and $idToTitle.Count -gt 0 -and $normGame.Length -ge 3) {
                    $bestId = $null
                    $bestScore = 0
                    foreach ($kv in $idToTitle.GetEnumerator()) {
                        $id = $kv.Key
                        if ($usedIds.ContainsKey($id)) { continue }
                        if ($imageIDs -notcontains $id) { continue }
                        $normTitle = Normalize-MatchTitle $kv.Value
                        if ($normTitle.Length -lt 3) { continue }
                        $score = 0
                        if ($normGame -eq $normTitle) { $score = 100 }
                        elseif ($normGame.Contains($normTitle) -or $normTitle.Contains($normGame)) {
                            $score = [Math]::Min($normGame.Length, $normTitle.Length)
                        }
                        if ($score -gt $bestScore) {
                            $bestScore = $score
                            $bestId = $id
                        }
                    }
                    if ($bestId -and $bestScore -ge 6) { $found = $bestId }
                }
                
                if (-not $found -and -not [string]::IsNullOrWhiteSpace($bp)) {
                    $fpTry = Join-Path $bp "box2dfront"
                    if (Test-Path $fpTry) {
                        $safe = $name -replace '[^\w\s-]', '' -replace '\s+', ' ' -replace ' ', '_'
                        foreach ($ext in @('png', 'jpg', 'jpeg')) {
                            if (Test-Path (Join-Path $fpTry "$safe.$ext")) {
                                $found = $safe
                                break
                            }
                        }
                    }
                }
            }
            
            if (-not $found -and ($MatchMode -eq "ProductCode" -or $MatchMode -eq "Auto")) {
                $cleanName = ($name -replace '[^A-Za-z0-9]', '').ToUpperInvariant()
                foreach ($id in $imageIDs) {
                    if ($usedIds.ContainsKey($id)) { continue }
                    if ($id -match '^[A-Z]{3,4}-([A-Z0-9]{4})') {
                        $code = $matches[1]
                        if ($cleanName.Length -ge 4 -and $cleanName.Contains($code)) {
                            $found = $id
                            break
                        }
                    }
                }
            }
            
            if ($found) {
                $mappings += "$name=$found"
                $matched++
                $usedIds[$found] = $true
                Log-Message "  MATCH: $name -> $found" "Green"
            }
        }
        
        $file = Resolve-ToolsFile $bp $OutputFileName $metaDir
        $existing = @{}
        if (Test-Path $file) {
            foreach ($line in Get-Content $file) {
                if ($line -match '^(.+?)=(.+)$') {
                    $existing[$matches[1].Trim()] = $matches[2].Trim()
                }
            }
        }
        foreach ($line in $mappings) {
            if ($line -match '^(.+?)=(.+)$') {
                $existing[$matches[1].Trim()] = $matches[2].Trim()
            }
        }
        $merged = @($existing.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } | Sort-Object)
        $merged | Out-File -FilePath $file -Encoding UTF8
        
        Log-Message "Created/updated: $($merged.Count) total mappings ($matched new this run)" "Green"
        Log-Message "Saved to: $file" "Cyan"
        if ($matched -eq 0 -and $isSns) {
            if ($MatchMode -eq "ProductCode") {
                Log-Message "No product-code-in-name matches. Try 'Map by Titles' or rename covers." "Yellow"
            } elseif ($MatchMode -eq "Titles") {
                Log-Message "No title-file matches. Add sns_titles.txt (SNS-XXXX-USA=Game Title) or use Map by Product Code." "Yellow"
            } else {
                Log-Message "No matches in Auto mode. Try Map by Product Code or Map by Titles separately." "Yellow"
            }
        }
        
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

function ApplyGameIDsToMetadata {
    $c = Get-Col
    if (-not $c) { return }
    
    Log-Message "========================================" "Cyan"
    Log-Message "APPLYING GAME IDs TO METADATA" "Cyan"
    Log-Message "========================================" "Cyan"
    
    try {
        $p = $c.metadataPath
        $content = Get-Content $p -Raw
        $games = $content -split '(?=game: )' | Where-Object { $_ -match '^game: ' }
        
        $count = 0
        $updated = $content
        
        $bp = $c.mediaPath
        $mapFile = Resolve-ToolsFile $bp "game_id_mappings.txt" (Split-Path $p -Parent)
        if (-not ($mapFile -and (Test-Path $mapFile))) {
            Log-Message "ERROR: No mapping file found. Run 'Create Mapping' first." "Red"
            return
        }
        
        $mappings = Get-Content $mapFile
        $mapHash = @{}
        foreach ($line in $mappings) {
            if ($line -match '^(.+)=(.+)$') {
                $mapHash[$matches[1]] = $matches[2]
            }
        }
        
        foreach ($g in $games) {
            if ($g -match 'game: (.+?)(?:\r?\n|$)') {
                $name = $matches[1].Trim()
            } else { continue }
            
            if ($g -match 'game_id:') { continue }
            
            if ($mapHash.ContainsKey($name)) {
                $gameID = $mapHash[$name]
                $new = "`ngame_id: $gameID"
                $updated = $updated -replace "($name.*?)(?=\r?\nfile:|\Z)", ('$1' + $new)
                $count++
                Log-Message "  Added game_id: $gameID -> $name" "Green"
            }
        }
        
        CreateBackup
        $updated | Out-File -FilePath $p -Encoding UTF8
        Log-Message "Applied game_ids to: $count games" "Green"
        UpdateEditor
        
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

# ============================================================================
# IMAGE CONVERSION FUNCTIONS
# ============================================================================
function ConvertImagesPNGtoJPG {
    param($allImages)
    $c = Get-Col
    if (-not $c) { return }
    
    Log-Message "========================================" "Cyan"
    Log-Message "CONVERTING PNG TO JPG" "Cyan"
    Log-Message "========================================" "Cyan"
    
    try {
        $bp = $c.mediaPath
        
        if ([string]::IsNullOrWhiteSpace($bp)) {
            Log-Message "ERROR: Media folder path is empty!" "Red"
            Log-Message "Please re-add your collection and make sure to select a Media Folder." "Yellow"
            Log-Message "The Media Folder should contain: box2dfront\ and box2dThumb\" "Yellow"
            return
        }
        
        $fp = Join-Path $bp "box2dfront"
        $tp = Join-Path $bp "box2dThumb"
        
        if (-not (Test-Path $fp)) {
            Log-Message "ERROR: box2dfront folder not found: $fp" "Red"
            Log-Message "Please make sure your Media Folder contains a 'box2dfront' folder with images." "Yellow"
            return
        }
        
        $folders = @($fp, $tp)
        $converted = 0
        
        foreach ($folder in $folders) {
            if (-not (Test-Path $folder)) { continue }
            
            $pngFiles = Get-ChildItem $folder -Filter "*.png" -ErrorAction SilentlyContinue
            
            if (-not $allImages) {
                $ofd = New-Object System.Windows.Forms.OpenFileDialog
                $ofd.Title = "Select PNG files to convert"
                $ofd.Filter = "PNG Files (*.png)|*.png"
                $ofd.Multiselect = $true
                $ofd.InitialDirectory = $folder
                
                if ($ofd.ShowDialog() -eq "OK") {
                    $selectedFiles = $ofd.FileNames
                    foreach ($file in $selectedFiles) {
                        ConvertSinglePNGtoJPG $file
                        $converted++
                    }
                }
            } else {
                foreach ($png in $pngFiles) {
                    ConvertSinglePNGtoJPG $png.FullName
                    $converted++
                }
            }
        }
        
        Log-Message "Converted: $converted images to JPG" "Green"
        
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

function ConvertSinglePNGtoJPG {
    param($pngPath)
    try {
        $jpgPath = $pngPath -replace '\.png$', '.jpg'
        
        $img = [System.Drawing.Image]::FromFile($pngPath)
        $jpg = New-Object System.Drawing.Bitmap($img)
        $jpg.Save($jpgPath, [System.Drawing.Imaging.ImageFormat]::Jpeg)
        $jpg.Dispose()
        $img.Dispose()
        
        Remove-Item $pngPath -Force
        
        Log-Message "  Converted: $(Split-Path $pngPath -Leaf) -> $(Split-Path $jpgPath -Leaf)" "Green"
        
    } catch {
        Log-Message "  ERROR converting: $(Split-Path $pngPath -Leaf)" "Red"
    }
}

function ConvertImagesJPGtoPNG {
    param($allImages)
    $c = Get-Col
    if (-not $c) { return }
    
    Log-Message "========================================" "Cyan"
    Log-Message "CONVERTING JPG TO PNG" "Cyan"
    Log-Message "========================================" "Cyan"
    
    try {
        $bp = $c.mediaPath
        
        if ([string]::IsNullOrWhiteSpace($bp)) {
            Log-Message "ERROR: Media folder path is empty!" "Red"
            Log-Message "Please re-add your collection and make sure to select a Media Folder." "Yellow"
            return
        }
        
        $fp = Join-Path $bp "box2dfront"
        $tp = Join-Path $bp "box2dThumb"
        
        if (-not (Test-Path $fp)) {
            Log-Message "ERROR: box2dfront folder not found: $fp" "Red"
            return
        }
        
        $folders = @($fp, $tp)
        $converted = 0
        
        foreach ($folder in $folders) {
            if (-not (Test-Path $folder)) { continue }
            
            $jpgFiles = Get-ChildItem $folder -Filter "*.jpg" -ErrorAction SilentlyContinue
            
            if (-not $allImages) {
                $ofd = New-Object System.Windows.Forms.OpenFileDialog
                $ofd.Title = "Select JPG files to convert"
                $ofd.Filter = "JPG Files (*.jpg)|*.jpg"
                $ofd.Multiselect = $true
                $ofd.InitialDirectory = $folder
                
                if ($ofd.ShowDialog() -eq "OK") {
                    $selectedFiles = $ofd.FileNames
                    foreach ($file in $selectedFiles) {
                        ConvertSingleJPGtoPNG $file
                        $converted++
                    }
                }
            } else {
                foreach ($jpg in $jpgFiles) {
                    ConvertSingleJPGtoPNG $jpg.FullName
                    $converted++
                }
            }
        }
        
        Log-Message "Converted: $converted images to PNG" "Green"
        
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

function ConvertSingleJPGtoPNG {
    param($jpgPath)
    try {
        $pngPath = $jpgPath -replace '\.jpg$', '.png'
        
        $img = [System.Drawing.Image]::FromFile($jpgPath)
        $png = New-Object System.Drawing.Bitmap($img)
        $png.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $png.Dispose()
        $img.Dispose()
        
        Remove-Item $jpgPath -Force
        
        Log-Message "  Converted: $(Split-Path $jpgPath -Leaf) -> $(Split-Path $pngPath -Leaf)" "Green"
        
    } catch {
        Log-Message "  ERROR converting: $(Split-Path $jpgPath -Leaf)" "Red"
    }
}

function UpdateMetadataExtensions {
    param($ext)
    $c = Get-Col
    if (-not $c) { return }
    
    Log-Message "========================================" "Cyan"
    Log-Message "UPDATING METADATA EXTENSIONS TO .$ext" "Cyan"
    Log-Message "========================================" "Cyan"
    
    try {
        $p = $c.metadataPath
        $content = Get-Content $p -Raw
        $oldExt = if ($ext -eq "png") { "jpg" } else { "png" }
        
        $newContent = $content -replace "\.$oldExt(?=`"|'|\s|$)", ".$ext"
        $newContent = $newContent -replace "\.$oldExt_thumb", ".$ext`_thumb"
        
        CreateBackup
        $newContent | Out-File -FilePath $p -Encoding UTF8
        
        Log-Message "Updated metadata: .$oldExt -> .$ext" "Green"
        UpdateEditor
        
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

# ============================================================================
# BACKUP FUNCTIONS
# ============================================================================
function CreateBackup {
    $c = Get-Col
    if (-not $c) { return }
    
    Log-Message "========================================" "Cyan"
    Log-Message "CREATING BACKUP - $($c.name)" "Cyan"
    Log-Message "========================================" "Cyan"
    
    try {
        $originalPath = $c.metadataPath
        
        if (-not (Test-Path $originalPath)) {
            Log-Message "ERROR: Metadata file not found" "Red"
            return
        }
        
        $backupPath = $originalPath -replace '\.txt$', '.bkup.txt'
        
        Copy-Item -Path $originalPath -Destination $backupPath -Force
        
        Log-Message "Backup created: $backupPath" "Green"
        Log-Message "Original: $originalPath" "White"
        Log-Message "Done!" "Green"
        
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

function RestoreBackup {
    $c = Get-Col
    if (-not $c) { return }
    
    Log-Message "========================================" "Cyan"
    Log-Message "RESTORING BACKUP - $($c.name)" "Cyan"
    Log-Message "========================================" "Cyan"
    
    try {
        $originalPath = $c.metadataPath
        
        if (-not (Test-Path $originalPath)) {
            Log-Message "ERROR: Metadata file not found" "Red"
            return
        }
        
        $backupPath = $originalPath -replace '\.txt$', '.bkup.txt'
        
        if (-not (Test-Path $backupPath)) {
            Log-Message "ERROR: Backup file not found: $backupPath" "Red"
            Log-Message "Please use 'Backup' first to create a backup" "Yellow"
            return
        }
        
        $backupInfo = Get-Item $backupPath
        $originalInfo = Get-Item $originalPath
        
        Log-Message "Backup file: $backupPath" "Cyan"
        Log-Message "Backup date: $($backupInfo.LastWriteTime)" "White"
        Log-Message "Original date: $($originalInfo.LastWriteTime)" "White"
        
        Copy-Item -Path $backupPath -Destination $originalPath -Force
        
        Log-Message "Backup restored: $backupPath -> $originalPath" "Green"
        Log-Message "Done!" "Green"
        
        UpdateEditor
        
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

# ============================================================================
# UPDATE METADATA NAMES
# ============================================================================
function UpdateMetadataNames {
    $c = Get-Col
    if (-not $c) { return }
    Log-Message "========================================" "Cyan"
    Log-Message "UPDATING METADATA NAMES - $($c.name)" "Cyan"
    Log-Message "========================================" "Cyan"
    try {
        $p = $c.metadataPath
        $content = Get-Content $p -Raw
        $games = $content -split '(?=game: )' | Where-Object { $_ -match '^game: ' }
        $count = 0
        
        foreach ($g in $games) {
            if ($g -match 'game: (.+?)(?:\r?\n|$)') {
                $name = $matches[1].Trim()
            } else { continue }
            
            if ($g -match 'assets\.box_front:.*?([^\\]+\.(png|jpg))') {
                $oldName = $matches[1]
                $oldExt = $matches[2]
                $safe = $name -replace '[^\w\s-]', '' -replace '\s+', ' ' -replace ' ', '_'
                $newName = "$safe.$oldExt"
                
                if ($oldName -ne $newName) {
                    $content = $content -replace $oldName, $newName
                    $oldThumb = $oldName -replace "\.$oldExt$", "_thumb.$oldExt"
                    $newThumb = $newName -replace "\.$oldExt$", "_thumb.$oldExt"
                    if ($oldThumb -ne $newThumb) {
                        $content = $content -replace $oldThumb, $newThumb
                    }
                    $count++
                    Log-Message "  Updated: $oldName -> $newName" "Green"
                }
            }
        }
        
        $content | Out-File -FilePath $p -Encoding UTF8
        Log-Message "Updated: $count metadata entries" "Green"
        UpdateEditor
    } catch { Log-Message "ERROR: $_" "Red" }
}

# ============================================================================
# CORE FUNCTIONS
# ============================================================================
function CheckHealth {
    $c = Get-Col
    if (-not $c) { return }
    Log-Message "========================================" "Cyan"
    Log-Message "CHECKING HEALTH - $($c.name)" "Cyan"
    Log-Message "========================================" "Cyan"
    try {
        $p = $c.metadataPath
        if (-not (Test-Path $p)) { Log-Message "ERROR: File not found" "Red"; return }
        $content = Get-Content $p -Raw
        $games = $content -split '(?=game: )' | Where-Object { $_ -match '^game: ' }
        $total = $games.Count
        $art = 0
        $missing = 0
        $gameIDs = 0
        
        foreach ($g in $games) {
            if ($g -match 'assets\.box_front:') {
                $art++
                if ($g -match 'assets\.box_front: (.+?\.(png|jpg))') {
                    if (-not (Test-Path $matches[1])) { $missing++ }
                }
            }
            if ($g -match 'game_id:') {
                $gameIDs++
            }
        }
        Log-Message "Total games: $total" "White"
        Log-Message "With box art: $art" "Green"
        Log-Message "Without box art: $($total - $art)" "Yellow"
        Log-Message "Missing images: $missing" "Red"
        Log-Message "With game_id: $gameIDs" "Cyan"
        Log-Message "Done!" "Green"
    } catch { Log-Message "ERROR: $_" "Red" }
}

function ShowStats {
    $c = Get-Col
    if (-not $c) { return }
    Log-Message "========================================" "Cyan"
    Log-Message "STATISTICS - $($c.name)" "Cyan"
    Log-Message "========================================" "Cyan"
    try {
        $p = $c.metadataPath
        $content = Get-Content $p -Raw
        $total = ([regex]::Matches($content, 'game: ')).Count
        $art = ([regex]::Matches($content, 'assets\.box_front:')).Count
        $gameIDs = ([regex]::Matches($content, 'game_id:')).Count
        $bp = $c.mediaPath
        $fp = Join-Path $bp "box2dfront"
        $tp = Join-Path $bp "box2dThumb"
        $img = (Get-ChildItem $fp -Filter "*.png" -ErrorAction SilentlyContinue).Count
        $imgJPG = (Get-ChildItem $fp -Filter "*.jpg" -ErrorAction SilentlyContinue).Count
        $thumb = (Get-ChildItem $tp -Filter "*.png" -ErrorAction SilentlyContinue).Count
        $thumbJPG = (Get-ChildItem $tp -Filter "*.jpg" -ErrorAction SilentlyContinue).Count
        Log-Message "Total Games: $total" "White"
        Log-Message "Box Art entries: $art" "Green"
        Log-Message "Game IDs: $gameIDs" "Cyan"
        Log-Message "Images (PNG): $img" "Cyan"
        Log-Message "Images (JPG): $imgJPG" "Cyan"
        Log-Message "Thumbnails (PNG): $thumb" "Cyan"
        Log-Message "Thumbnails (JPG): $thumbJPG" "Cyan"
        Log-Message "Done!" "Green"
    } catch { Log-Message "ERROR: $_" "Red" }
}

function FindMissing {
    $c = Get-Col
    if (-not $c) { return }
    Log-Message "========================================" "Cyan"
    Log-Message "FINDING MISSING COVERS - $($c.name)" "Cyan"
    Log-Message "========================================" "Cyan"
    try {
        $p = $c.metadataPath
        $bp = $c.mediaPath
        
        if ([string]::IsNullOrWhiteSpace($bp)) {
            Log-Message "ERROR: Media folder path is empty!" "Red"
            Log-Message "Please re-add your collection and make sure to select a Media Folder." "Yellow"
            return
        }
        
        $fp = Join-Path $bp "box2dfront"
        
        if (-not (Test-Path $fp)) {
            Log-Message "ERROR: box2dfront folder not found: $fp" "Red"
            Log-Message "Please make sure your Media Folder contains a 'box2dfront' folder with images." "Yellow"
            return
        }
        
        $content = Get-Content $p -Raw
        $games = $content -split '(?=game: )' | Where-Object { $_ -match '^game: ' }
        $imagesPNG = Get-ChildItem $fp -Filter "*.png" -ErrorAction SilentlyContinue | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) }
        $imagesJPG = Get-ChildItem $fp -Filter "*.jpg" -ErrorAction SilentlyContinue | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) }
        $images = $imagesPNG + $imagesJPG
        $missing = @()
        foreach ($g in $games) {
            if ($g -match 'game: (.+?)(?:\r?\n|$)') {
                $name = $matches[1].Trim()
            } else { continue }
            if ($g -match 'assets\.box_front:') { continue }
            $safe = $name -replace '[^\w\s-]', '' -replace '\s+', ' ' -replace ' ', '_'
            if (-not ($images -contains $safe)) { $missing += $name }
        }
        $file = Join-Path (Get-ToolsFolder $bp) "missing_covers.txt"
        $missing | Out-File -FilePath $file -Encoding UTF8
        Log-Message "Found: $($missing.Count) missing" "Yellow"
        Log-Message "Saved to: $file" "Cyan"
        $missing | Select-Object -First 20 | ForEach-Object { Log-Message "  $_" "White" }
        if ($missing.Count -gt 20) { Log-Message "  ... and $($missing.Count - 20) more" "White" }
    } catch { Log-Message "ERROR: $_" "Red" }
}

function AddBoxArt {
    param(
        [ValidateSet("Mapping", "GameName", "MappingOnly")]
        [string]$Mode = "Mapping"
    )
    $c = Get-Col
    if (-not $c) { return }
    
    Log-Message "========================================" "Cyan"
    Log-Message "ADDING BOX ART - $($c.name) [mode=$Mode]" "Cyan"
    Log-Message "========================================" "Cyan"
    try {
        $p = $c.metadataPath
        $bp = $c.mediaPath
        
        if ([string]::IsNullOrWhiteSpace($bp)) {
            Log-Message "ERROR: Media folder path is empty!" "Red"
            Log-Message "Please re-add your collection and make sure to select a Media Folder." "Yellow"
            Log-Message "The Media Folder should contain: box2dfront\ and box2dThumb\" "Yellow"
            return
        }
        
        Log-Message "Metadata file: $p" "White"
        Log-Message "Media folder: $bp" "White"
        
        $tp = Join-Path $bp "box2dThumb"
        $fp = Join-Path $bp "box2dfront"
        
        if (-not (Test-Path $fp)) {
            Log-Message "ERROR: box2dfront folder not found: $fp" "Red"
            Log-Message "Please make sure your Media Folder contains a 'box2dfront' folder with images." "Yellow"
            return
        }
        if (-not (Test-Path $tp)) {
            Log-Message "Creating folder: $tp" "Yellow"
            New-Item -ItemType Directory -Path $tp -Force | Out-Null
        }
        
        $content = Get-Content $p -Raw
        $games = $content -split '(?=game: )' | Where-Object { $_ -match '^game: ' }
        
        # Index by exact basename AND by region-stripped key so
        # "Super Mario World" matches "Super Mario World (USA).jpg"
        $imageFiles = @{}
        $imageByKey = @{}
        foreach ($img in @(Get-ChildItem $fp -File -ErrorAction SilentlyContinue)) {
            if ($img.Extension -match '\.(png|jpg|jpeg)$') {
                $base = [System.IO.Path]::GetFileNameWithoutExtension($img.Name)
                $imageFiles[$base] = $img.FullName
                $key = Get-MatchTitleKey $base
                if ($key -and -not $imageByKey.ContainsKey($key)) {
                    $imageByKey[$key] = $img.FullName
                }
            }
        }
        Log-Message "Images found in box2dfront: $($imageFiles.Count)" "Cyan"
        
        $mapHash = @{}
        $metaDir = Split-Path $p -Parent
        foreach ($mf in @("sns_mappings.txt", "game_id_mappings.txt")) {
            $mapPath = Resolve-ToolsFile $bp $mf $metaDir
            if (-not ($mapPath -and (Test-Path $mapPath))) { continue }
            $lines = Get-Content $mapPath | Where-Object { $_ -match '=' }
            foreach ($line in $lines) {
                if ($line -match '^(.+?)=(.+)$') {
                    $mapHash[$matches[1].Trim()] = $matches[2].Trim()
                }
            }
            if ($mapHash.Count -gt 0) {
                Log-Message "Loaded $($mapHash.Count) entries from $mf" "Cyan"
                break
            }
        }
        
        function Find-ImageForToken([string]$token, $imageFiles, $fp) {
            if ([string]::IsNullOrWhiteSpace($token)) { return $null }
            if ($imageFiles.ContainsKey($token)) { return $imageFiles[$token] }
            foreach ($ext in @('png', 'jpg', 'jpeg')) {
                $try = Join-Path $fp "$token.$ext"
                if (Test-Path $try) { return $try }
            }
            foreach ($k in $imageFiles.Keys) {
                if ($k -eq $token -or $k.Equals($token, [StringComparison]::OrdinalIgnoreCase)) {
                    return $imageFiles[$k]
                }
            }
            # Region-tag aware: "Super Mario World" <-> "Super Mario World (USA)"
            $tokKey = Get-MatchTitleKey $token
            if ($tokKey -and $imageByKey.ContainsKey($tokKey)) {
                return $imageByKey[$tokKey]
            }
            return $null
        }
        
        $updated = $content
        $count = 0
        $missSamples = New-Object System.Collections.ArrayList
        
        foreach ($g in $games) {
            if ($g -match 'game: (.+?)(?:\r?\n|$)') {
                $name = $matches[1].Trim()
            } else { continue }
            
            # Skip only when box_front already has a non-empty path
            if ($g -match '(?m)^assets\.box_front:\s*(.+)$') {
                $existingFront = $matches[1].Trim()
                if (-not [string]::IsNullOrWhiteSpace($existingFront)) { continue }
            }
            
            # ROM basename often matches cover filenames better than clean game titles
            $romBase = $null
            if ($g -match '(?m)^file:\s*(.+)$') {
                try {
                    $romBase = [System.IO.Path]::GetFileNameWithoutExtension($matches[1].Trim().Trim('"'))
                } catch { $romBase = $null }
            }
            
            $frontPath = $null
            
            if ($Mode -ne "GameName" -and $mapHash.ContainsKey($name)) {
                $token = $mapHash[$name]
                $frontPath = Find-ImageForToken $token $imageFiles $fp
            }
            
            # Match order: ROM basename -> game title -> cleaned variants -> fuzzy keys
            if (-not $frontPath -and $Mode -ne "MappingOnly") {
                if ($romBase) {
                    $frontPath = Find-ImageForToken $romBase $imageFiles $fp
                }
                if (-not $frontPath) {
                    $frontPath = Find-ImageForToken $name $imageFiles $fp
                }
                if (-not $frontPath) {
                    $spaced = ($name -replace '[^\w\s\-]', '' -replace '\s+', ' ').Trim()
                    $frontPath = Find-ImageForToken $spaced $imageFiles $fp
                }
                if (-not $frontPath) {
                    $safe = ($name -replace '[^\w\s\-]', '' -replace '\s+', ' ' -replace ' ', '_').Trim()
                    $frontPath = Find-ImageForToken $safe $imageFiles $fp
                }
                # Fuzzy: normalized keys, subtitle-short form, starts-with, word overlap
                if (-not $frontPath) {
                    $tryKeys = New-Object System.Collections.ArrayList
                    foreach ($src in @($name, $romBase)) {
                        if (-not $src) { continue }
                        foreach ($k in @(Get-MatchTitleKeyVariants $src)) {
                            if ($k -and -not $tryKeys.Contains($k)) { [void]$tryKeys.Add($k) }
                        }
                    }
                    $frontPath = Find-ImageByMatchKeys -TitleKeys @($tryKeys) -ImageByKey $imageByKey
                }
            }
            
            if (-not $frontPath) {
                if ($missSamples.Count -lt 8) {
                    [void]$missSamples.Add([PSCustomObject]@{ Title = $name; Rom = $romBase })
                }
                continue
            }
            
            $ext = [System.IO.Path]::GetExtension($frontPath).TrimStart('.')
            if ([string]::IsNullOrWhiteSpace($ext)) { $ext = "png" }
            $base = [System.IO.Path]::GetFileNameWithoutExtension($frontPath)
            $thumb = Join-Path $tp ($base + "_thumb." + $ext)
            
            # Prefer replacing empty box_front line; else insert after game: line
            $escaped = [regex]::Escape($name)
            $blockPat = "(?ms)(^game:\s*$escaped\r?\n)(.*?)(?=^game:\s*|\z)"
            $m = [regex]::Match($updated, $blockPat)
            if ($m.Success) {
                $head = $m.Groups[1].Value
                $body = $m.Groups[2].Value
                if ($body -match '(?m)^assets\.box_front:\s*.*$') {
                    $body = [regex]::Replace($body, '(?m)^assets\.box_front:\s*.*$', "assets.box_front: $frontPath", 1)
                    if ($body -match '(?m)^assets\.box_front_thumb:\s*.*$') {
                        $body = [regex]::Replace($body, '(?m)^assets\.box_front_thumb:\s*.*$', "assets.box_front_thumb: $thumb", 1)
                    } else {
                        $body = "assets.box_front: $frontPath`nassets.box_front_thumb: $thumb`n" + ($body -replace '(?m)^assets\.box_front:\s*.*\r?\n?', '')
                        # already replaced front; ensure thumb present
                        if ($body -notmatch '(?m)^assets\.box_front_thumb:') {
                            $body = $body -replace '(?m)^(assets\.box_front:.*)$', ('$1' + "`nassets.box_front_thumb: $thumb")
                        }
                    }
                } else {
                    $body = "assets.box_front: $frontPath`nassets.box_front_thumb: $thumb`n" + $body
                }
                $updated = $updated.Remove($m.Index, $m.Length).Insert($m.Index, $head + $body)
            } else {
                $pattern = "(game: $escaped(?:\r?\n))"
                if ($updated -match $pattern) {
                    $updated = [regex]::Replace($updated, $pattern, ('$1' + "assets.box_front: $frontPath`nassets.box_front_thumb: $thumb`n"), 1)
                } else {
                    Log-Message "  WARN: could not locate game block for: $name" "Yellow"
                    continue
                }
            }
            $count++
            Log-Message "  Added: $name -> $(Split-Path $frontPath -Leaf)" "Green"
        }
        
        Log-Message "Added box art to: $count games" "Green"
        if ($missSamples.Count -gt 0) {
            Log-Message "Sample games with no matching image:" "Yellow"
            foreach ($s in $missSamples) {
                Log-Message ("  title: {0}" -f $s.Title) "White"
                if ($s.Rom) { Log-Message ("  rom:   {0}" -f $s.Rom) "White" }
                Log-Message ("  key:   {0}" -f (Get-MatchTitleKey $s.Title)) "White"
            }
            $imgSample = @($imageFiles.Keys | Select-Object -First 8)
            if ($imgSample.Count -gt 0) {
                Log-Message "Sample image basenames in box2dfront:" "Cyan"
                foreach ($im in $imgSample) {
                    Log-Message ("  img:   {0}" -f $im) "White"
                    Log-Message ("  key:   {0}" -f (Get-MatchTitleKey $im)) "White"
                }
            }
        }
        
        CreateBackup
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($p, $updated, $utf8NoBom)
        UpdateEditor
        # Selection is preserved by FilterGameList; refresh form fields for current game
        try { LoadSelectedGameFields } catch {}
        
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

function Rename-ImagesFromSnsCodes {
    # Rename images that are named by their SNS/GameTDB ID (e.g. SNS-AMSE-USA.png)
    # to the matching game title, using sns_mappings.txt / game_id_mappings.txt
    # and any downloaded title-lookup files (sns_titles.txt, gametdb_*_titles.txt).
    $c = Get-Col
    if (-not $c) { return }
    $bp = $c.mediaPath
    if ([string]::IsNullOrWhiteSpace($bp) -or -not (Test-Path $bp)) {
        Log-Message "ERROR: Media folder path is missing or invalid." "Red"
        return
    }

    $fd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fd.Description = "Select the media subfolder with SNS-code-named images (e.g. box2dfront)"
    $fd.ShowNewFolderButton = $false
    $defaultTry = Join-Path $bp "box2dfront"
    if (Test-Path $defaultTry) { $fd.SelectedPath = $defaultTry } else { $fd.SelectedPath = $bp }
    if ($fd.ShowDialog() -ne "OK") { return }
    $folder = $fd.SelectedPath

    Log-Message "========================================" "Cyan"
    Log-Message "RENAME SNS-CODED IMAGES TO TITLES" "Cyan"
    Log-Message "========================================" "Cyan"
    Log-Message "Folder: $folder" "White"

    try {
        $metaDir = Split-Path $c.metadataPath -Parent
        $idToName = @{}

        # sns_mappings.txt / game_id_mappings.txt are "Name=ID" - invert to ID->Name
        foreach ($mf in @("sns_mappings.txt", "game_id_mappings.txt")) {
            $mp = Resolve-ToolsFile $bp $mf $metaDir
            if (-not ($mp -and (Test-Path $mp))) { continue }
            foreach ($line in Get-Content $mp) {
                if ($line -match '^(.+?)=(.+)$') {
                    $name = $matches[1].Trim()
                    $id = $matches[2].Trim()
                    if ($id -and $name -and -not $idToName.ContainsKey($id)) {
                        $idToName[$id] = $name
                    }
                }
            }
        }
        # sns_titles.txt / gametdb_*_titles.txt are "ID=Title" already
        $titleFileNames = @("sns_titles.txt", "sns_checksum_titles.txt", "snes_titles.txt", "gametdb_titles.txt", "titles.txt")
        foreach ($tf in $titleFileNames) {
            $tp = Resolve-ToolsFile $bp $tf $metaDir
            if (-not ($tp -and (Test-Path $tp))) { continue }
            foreach ($line in Get-Content $tp) {
                if ($line -match '^\s*([A-Za-z0-9-]+)\s*[=:\t]\s*(.+)$') {
                    $id = $matches[1].Trim()
                    $name = $matches[2].Trim()
                    if ($id -and $name -and -not $idToName.ContainsKey($id)) {
                        $idToName[$id] = $name
                    }
                }
            }
        }
        # Also cache any gametdb_<plat>_titles.txt regardless of platform prefix
        foreach ($f in @(Get-ChildItem (Get-ToolsFolder $bp) -Filter "gametdb_*_titles.txt" -File -ErrorAction SilentlyContinue)) {
            foreach ($line in Get-Content $f.FullName) {
                if ($line -match '^\s*([A-Za-z0-9-]+)\s*=\s*(.+)$') {
                    $id = $matches[1].Trim()
                    $name = $matches[2].Trim()
                    if ($id -and $name -and -not $idToName.ContainsKey($id)) {
                        $idToName[$id] = $name
                    }
                }
            }
        }

        if ($idToName.Count -eq 0) {
            Log-Message "No ID -> Title mapping found." "Red"
            Log-Message "Run 'Create Mapping' (SNS Code Tools) or, if your image filenames" "Yellow"
            Log-Message "match your ROM filenames, 'Match ROMs by Checksum' first." "Yellow"
            return
        }
        Log-Message "Loaded $($idToName.Count) ID -> Title mappings" "Cyan"

        $allFiles = @(Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue | Where-Object {
            $e = $_.Extension.ToLowerInvariant()
            $e -eq ".png" -or $e -eq ".jpg" -or $e -eq ".jpeg" -or $e -eq ".webp"
        })
        Log-Message "Images found: $($allFiles.Count)" "Cyan"

        $p = $c.metadataPath
        $content = Get-Content $p -Raw -ErrorAction SilentlyContinue
        if ($null -eq $content) { $content = "" }
        $pathMap = @{}
        $renamed = 0
        $skipped = 0
        $conflicts = 0

        foreach ($img in $allFiles) {
            $base = [System.IO.Path]::GetFileNameWithoutExtension($img.Name)
            $ext = $img.Extension

            # Try exact filename as an ID, then strip a trailing region tag
            # like "-USA" / "-EUR" / "-JPN" / "-World" and try again.
            $candidates = @($base)
            if ($base -match '^(.+?)-(USA|EUR|EU|JPN|JAP|JP|World|Unk|Unknown)$') {
                $candidates += $matches[1]
            }

            $name = $null
            foreach ($cand in $candidates) {
                if ($idToName.ContainsKey($cand)) { $name = $idToName[$cand]; break }
            }

            if (-not $name) {
                $skipped++
                continue
            }

            $safeTitle = ($name -replace '[<>:"/\\|?*]', '').Trim()
            if (-not $safeTitle) { $skipped++; continue }

            $newName = $safeTitle + $ext
            $newPath = Join-Path $folder $newName

            if ($img.Name -eq $newName) { continue }

            if (Test-Path -LiteralPath $newPath) {
                Log-Message "  Conflict (exists): $($img.Name) -> $newName" "Yellow"
                $conflicts++
                continue
            }

            try {
                Rename-Item -LiteralPath $img.FullName -NewName $newName -ErrorAction Stop
                $pathMap[$img.FullName] = $newPath
                $renamed++
                Log-Message "  Renamed: $($img.Name) -> $newName" "Green"
            } catch {
                Log-Message "  Failed: $($img.Name) - $_" "Red"
            }
        }

        $metaUpdated = 0
        if ($pathMap.Count -gt 0 -and $content) {
            $updated = $content
            foreach ($oldFull in @($pathMap.Keys)) {
                $newFull = $pathMap[$oldFull]
                $oldName = [System.IO.Path]::GetFileName($oldFull)
                $newNameOnly = [System.IO.Path]::GetFileName($newFull)
                if ($updated.IndexOf($oldFull) -ge 0) {
                    $updated = $updated.Replace($oldFull, $newFull)
                    $metaUpdated++
                } elseif ($updated.IndexOf($oldName) -ge 0) {
                    $updated = $updated.Replace($oldName, $newNameOnly)
                    $metaUpdated++
                }
            }
            if ($metaUpdated -gt 0) {
                CreateBackup
                $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                [System.IO.File]::WriteAllText($p, $updated, $utf8NoBom)
                Log-Message "Updated $metaUpdated path reference(s) in metadata" "Cyan"
                UpdateEditor
            }
        }

        Log-Message "----------------------------------------" "Cyan"
        Log-Message "Renamed: $renamed | No mapping match: $skipped | Conflicts: $conflicts" "Green"
        if ($renamed -gt 0 -and $metaUpdated -eq 0) {
            Log-Message "Next: Image Tools -> Add Box Art to Metadata (to link the new filenames)" "Cyan"
        }
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

function RenameImages {
    # Rename box2dfront images to match metadata game titles.
    # e.g. "Super Mario World (USA).jpg" -> "Super Mario World.jpg"
    $c = Get-Col
    if (-not $c) { return }
    
    $msg = "Rename images in box2dfront to match game titles?`n`n"
    $msg += "1. Strips region tags: (USA), (Europe), (Japan), etc.`n"
    $msg += "2. Matches them to game titles in metadata`n"
    $msg += "3. Renames to exact game title (keeps spaces)`n"
    $msg += "   Super Mario World (USA).jpg  ->  Super Mario World.jpg`n`n"
    $msg += "Also updates assets.box_front paths when needed.`n"
    $msg += "A metadata backup is created first. Continue?"
    
    $choice = [System.Windows.Forms.MessageBox]::Show(
        $msg,
        "Rename Images to Game Titles",
        "YesNo",
        "Question"
    )
    if ($choice -ne "Yes") {
        Log-Message "Rename cancelled." "Yellow"
        return
    }
    
    Log-Message "========================================" "Cyan"
    Log-Message "RENAME IMAGES TO GAME TITLES - $($c.name)" "Cyan"
    Log-Message "========================================" "Cyan"
    try {
        $p = $c.metadataPath
        $bp = $c.mediaPath
        
        if ([string]::IsNullOrWhiteSpace($bp)) {
            Log-Message "ERROR: Media folder path is empty!" "Red"
            Log-Message "Re-add the collection and select a Media Folder." "Yellow"
            return
        }
        
        $fp = Join-Path $bp "box2dfront"
        if (-not (Test-Path $fp)) {
            Log-Message "ERROR: box2dfront folder not found: $fp" "Red"
            return
        }
        
        $content = Get-Content $p -Raw -ErrorAction Stop
        $games = $content -split '(?=game: )' | Where-Object { $_ -match '^game: ' }
        $gameByKey = @{}
        $gameCount = 0
        foreach ($g in $games) {
            if ($g -match 'game: (.+?)(?:\r?\n|$)') {
                $title = $matches[1].Trim()
                if (-not $title) { continue }
                $gameCount++
                $key = Get-MatchTitleKey $title
                if ($key -and -not $gameByKey.ContainsKey($key)) {
                    $gameByKey[$key] = $title
                }
            }
        }
        Log-Message "Games in metadata: $gameCount" "Cyan"
        
        $allFiles = @(Get-ChildItem -LiteralPath $fp -File -ErrorAction SilentlyContinue)
        $images = @()
        foreach ($f in $allFiles) {
            $e = $f.Extension.ToLowerInvariant()
            if ($e -eq ".png" -or $e -eq ".jpg" -or $e -eq ".jpeg" -or $e -eq ".webp") {
                $images += $f
            }
        }
        Log-Message "Images in box2dfront: $($images.Count)" "Cyan"
        
        if ($images.Count -eq 0) {
            Log-Message "No images found to rename." "Yellow"
            return
        }
        
        $renamed = 0
        $skipped = 0
        $conflicts = 0
        $pathMap = @{}
        
        foreach ($img in $images) {
            $oldBase = [System.IO.Path]::GetFileNameWithoutExtension($img.Name)
            $ext = $img.Extension
            $key = Get-MatchTitleKey $oldBase
            
            if (-not $key -or -not $gameByKey.ContainsKey($key)) {
                $skipped++
                continue
            }
            
            $targetTitle = $gameByKey[$key]
            $safeTitle = ($targetTitle -replace '[<>:"/\\|?*]', '').Trim()
            if (-not $safeTitle) { $skipped++; continue }
            
            $newName = $safeTitle + $ext
            $newPath = Join-Path $fp $newName
            
            if ($img.Name -eq $newName) { continue }
            
            if (Test-Path -LiteralPath $newPath) {
                Log-Message "  Conflict (exists): $($img.Name) -> $newName" "Yellow"
                $conflicts++
                continue
            }
            
            try {
                Rename-Item -LiteralPath $img.FullName -NewName $newName -ErrorAction Stop
                $pathMap[$img.FullName] = $newPath
                $renamed++
                Log-Message "  Renamed: $($img.Name) -> $newName" "Green"
            } catch {
                Log-Message "  Failed: $($img.Name) - $_" "Red"
            }
        }
        
        $metaUpdated = 0
        if ($pathMap.Count -gt 0) {
            $updated = $content
            foreach ($oldFull in @($pathMap.Keys)) {
                $newFull = $pathMap[$oldFull]
                if ($updated.IndexOf($oldFull) -ge 0) {
                    $updated = $updated.Replace($oldFull, $newFull)
                    $metaUpdated++
                } else {
                    $oldName = [System.IO.Path]::GetFileName($oldFull)
                    $newNameOnly = [System.IO.Path]::GetFileName($newFull)
                    if ($oldName -and $updated.IndexOf($oldName) -ge 0) {
                        $updated = $updated.Replace($oldName, $newNameOnly)
                        $metaUpdated++
                    }
                }
            }
            if ($metaUpdated -gt 0) {
                CreateBackup
                $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                [System.IO.File]::WriteAllText($p, $updated, $utf8NoBom)
                Log-Message "Updated $metaUpdated path reference(s) in metadata" "Cyan"
                UpdateEditor
            }
        }
        
        Log-Message "----------------------------------------" "Cyan"
        Log-Message "Renamed: $renamed | No match / skipped: $skipped | Conflicts: $conflicts" "Green"
        if ($renamed -gt 0) {
            Log-Message "Next: Image Tools -> Add Box Art to Metadata (if paths still missing)" "Cyan"
        }
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

function Is-BogusGameTitle {
    param([string]$Title)
    $t = "$Title".Trim()
    if ($t.Length -lt 2) { return $true }

    $letters = ([regex]::Matches($t, '[A-Za-z0-9]')).Count
    $ratio = $letters / [double]$t.Length

    # Real titles are mostly alphanumeric. Junk lines from corrupted
    # filenames / stray text files are heavy on symbols and spaces.
    if ($ratio -lt 0.5) { return $true }

    # Needs at least one run of 2+ letters somewhere (a real "word")
    if ($t -notmatch '[A-Za-z]{2,}') { return $true }

    return $false
}

function CleanBogusGames {
    $c = Get-Col
    if (-not $c) { return }

    Log-Message "========================================" "Cyan"
    Log-Message "CLEAN BOGUS GAMES - $($c.name)" "Cyan"
    Log-Message "========================================" "Cyan"

    try {
        $p = $c.metadataPath
        $content = Get-Content $p -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($content)) {
            Log-Message "Metadata file is empty." "Yellow"
            return
        }

        $norm = $content -replace "`r`n", "`n" -replace "`r", "`n"
        $parts = [regex]::Split($norm, '(?m)(?=^game:\s*)')

        $keepParts = New-Object System.Collections.ArrayList
        $bogusTitles = New-Object System.Collections.ArrayList

        foreach ($part in $parts) {
            if ([string]::IsNullOrWhiteSpace($part)) { continue }
            if ($part -match '(?m)^game:\s*(.*)$') {
                $title = $matches[1].Trim()
                if (Is-BogusGameTitle $title) {
                    [void]$bogusTitles.Add($title)
                    continue
                }
            }
            [void]$keepParts.Add($part.TrimEnd())
        }

        if ($bogusTitles.Count -eq 0) {
            Log-Message "No bogus-looking game entries found." "Green"
            return
        }

        Log-Message "Found $($bogusTitles.Count) bogus-looking entries:" "Yellow"
        $bogusTitles | Select-Object -First 20 | ForEach-Object { Log-Message "  [$_]" "Yellow" }
        if ($bogusTitles.Count -gt 20) {
            Log-Message "  ... and $($bogusTitles.Count - 20) more" "Yellow"
        }

        $msg = "Found $($bogusTitles.Count) entries that look like garbage " +
               "(garbled/corrupted names) rather than real game titles.`n`n" +
               "A backup of metadata.txt will be created before anything is changed.`n`n" +
               "Remove these $($bogusTitles.Count) entries now?"
        $result = [System.Windows.Forms.MessageBox]::Show($msg, "Clean Bogus Games", "YesNo", "Question")
        if ($result -ne "Yes") {
            Log-Message "Cancelled - no changes made." "Yellow"
            return
        }

        CreateBackup

        $newContent = ($keepParts -join "`n").Trim() + "`n"
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($p, $newContent, $utf8NoBom)

        Log-Message "Removed $($bogusTitles.Count) bogus entries." "Green"
        Log-Message "Done!" "Green"

        UpdateEditor
        UpdateStats
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

function FixDup {
    $c = Get-Col
    if (-not $c) { return }
    Log-Message "========================================" "Cyan"
    Log-Message "FIXING DUPLICATES - $($c.name)" "Cyan"
    Log-Message "========================================" "Cyan"
    try {
        $p = $c.metadataPath
        $content = Get-Content $p -Raw
        $games = $content -split '(?=game: )' | Where-Object { $_ -match '^game: ' }
        $seen = @{}
        $unique = @()
        $dup = 0
        foreach ($g in $games) {
            if ($g -match 'game: (.+?)(?:\r?\n|$)') {
                $name = $matches[1].Trim()
                if (-not $seen.ContainsKey($name)) {
                    $seen[$name] = $true
                    $unique += $g
                } else {
                    $dup++
                    Log-Message "  Removed: $name" "Yellow"
                }
            }
        }
        if ($dup -gt 0) {
            $header = $content -replace 'game: .*', ''
            $new = $header + ($unique -join "`r`n")
            CreateBackup
            $new | Out-File -FilePath $p -Encoding UTF8
            Log-Message "Removed: $dup duplicates" "Green"
            UpdateEditor
        } else {
            Log-Message "No duplicates found" "Green"
        }
    } catch { Log-Message "ERROR: $_" "Red" }
}

# ============================================================================
# SNS EXTRACTION FUNCTIONS
# ============================================================================
function ExtractXML {
    $c = Get-Col
    if (-not $c) { return }
    Log-Message "========================================" "Cyan"
    Log-Message "EXTRACTING SNS CODES FROM XML" "Cyan"
    Log-Message "========================================" "Cyan"
    try {
        $bp = [string]$c.mediaPath
        $meta = [string]$c.metadataPath
        
        $xml = $null
        if (-not [string]::IsNullOrWhiteSpace($bp)) {
            $tryXml = Join-Path $bp "coversdb-snes_files.xml"
            if (Test-Path $tryXml) { $xml = $tryXml }
        }
        if (-not $xml) {
            $of = New-Object System.Windows.Forms.OpenFileDialog
            $of.Title = "Select coversdb SNES XML file"
            $of.Filter = "XML Files (*.xml)|*.xml|All Files (*.*)|*.*"
            if (-not [string]::IsNullOrWhiteSpace($bp) -and (Test-Path $bp)) {
                $of.InitialDirectory = $bp
            }
            if ($of.ShowDialog() -ne "OK") {
                Log-Message "Extract from XML cancelled." "Yellow"
                return
            }
            $xml = $of.FileName
        }
        
        Log-Message "XML: $xml" "White"
        $content = Get-Content $xml -Raw
        $pattern = 'name="(SNS-[A-Z0-9]{4}-[A-Z]{3,4})\.jpg"'
        $codes = @([regex]::Matches($content, $pattern) | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        
        $outDir = $null
        if (-not [string]::IsNullOrWhiteSpace($bp)) {
            $outDir = Get-ToolsFolder $bp
        }
        if (-not $outDir) { $outDir = Split-Path $xml -Parent }
        $file = Join-Path $outDir "sns_codes_from_xml.txt"
        $codes | Out-File -FilePath $file -Encoding UTF8
        
        Update-SnsCodeList $codes $file
        
        Log-Message "Extracted: $($codes.Count) SNS codes" "Green"
        Log-Message "Saved: $file" "Cyan"
        Log-Message "SNS list updated ($($codes.Count) codes shown in SNS Code Tools)" "Cyan"
        if ($codes.Count -eq 0) {
            Log-Message "No SNS codes found in XML" "Yellow"
        }
    } catch { Log-Message "ERROR: $_" "Red" }
}

function ExtractImages {
    $c = Get-Col
    if (-not $c) { return }
    
    $fd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fd.Description = "Select the folder that contains the SNS image files (PNG/JPG)"
    $fd.ShowNewFolderButton = $false
    
    $startPath = $null
    $bp = [string]$c.mediaPath
    $meta = [string]$c.metadataPath
    if (-not [string]::IsNullOrWhiteSpace($bp)) {
        $tryFront = Join-Path $bp "box2dfront"
        if (Test-Path $tryFront) { $startPath = $tryFront }
        elseif (Test-Path $bp) { $startPath = $bp }
    }
    if (-not $startPath -and -not [string]::IsNullOrWhiteSpace($meta) -and (Test-Path $meta)) {
        $startPath = Split-Path $meta -Parent
    }
    if ($startPath) { $fd.SelectedPath = $startPath }
    
    if ($fd.ShowDialog() -ne "OK") {
        Log-Message "Extract from Images cancelled." "Yellow"
        return
    }
    
    $fp = $fd.SelectedPath
    Log-Message "========================================" "Cyan"
    Log-Message "EXTRACTING SNS CODES FROM IMAGES" "Cyan"
    Log-Message "========================================" "Cyan"
    Log-Message "Looking in: $fp" "White"
    
    try {
        if (-not (Test-Path $fp)) {
            Log-Message "Folder not found: $fp" "Red"
            return
        }
        
        $images = @(Get-ChildItem $fp -Filter "*.png" -ErrorAction SilentlyContinue)
        $images += @(Get-ChildItem $fp -Filter "*.jpg" -ErrorAction SilentlyContinue)
        $images += @(Get-ChildItem $fp -Filter "*.jpeg" -ErrorAction SilentlyContinue)
        
        if ($images.Count -eq 0) {
            Log-Message "No images found in: $fp" "Yellow"
            Log-Message "Looking for SNS patterns like: SNS-XXXX-USA.png" "Yellow"
            return
        }
        
        Log-Message "Found $($images.Count) image file(s)" "Cyan"
        
        $codes = @()
        $pattern = '^(SNS)-([A-Z0-9]{4})-(USA|EUR|JPN|AUS|FRA|GER|ITA|SPA|UK|ASIA|KOR|CAN|MEX|BRA|CHN|TWN|RUS|SAF|IND|NZL|DEN|SWE|NOR|FIN|POL|CZE|HUN|AUT|CHE|NLD|BEL|POR|GRE|TUR|ISR|UAE|SAU|ZAF|ARG|CHL|COL|PER|VEN|MYS|SGP|PHL|IDN|THA|VNM|PAK|NGA|KEN|MAR|EGY|TUN|LBN|JOR|KWT|QAT|BHR|OMN)\.(png|jpg|jpeg)$'
        
        foreach ($img in $images) {
            if ($img.Name -match $pattern) {
                $fullID = $matches[1] + "-" + $matches[2] + "-" + $matches[3]
                $codes += $fullID
                Log-Message "  Found: $fullID" "Green"
            }
        }
        
        $codes = @($codes | Sort-Object -Unique)
        
        $outDir = $fp
        if (-not [string]::IsNullOrWhiteSpace($bp)) {
            $outDir = Get-ToolsFolder $bp
        } elseif (-not [string]::IsNullOrWhiteSpace($meta) -and (Test-Path $meta)) {
            $parent = Split-Path $meta -Parent
            if (-not [string]::IsNullOrWhiteSpace($parent)) { $outDir = $parent }
        }
        $file = Join-Path $outDir "sns_codes_from_images.txt"
        $codes | Out-File -FilePath $file -Encoding UTF8
        
        Update-SnsCodeList $codes $file
        
        if ($codes.Count -eq 0) {
            Log-Message "No SNS codes found in image filenames" "Yellow"
            Log-Message "Expected pattern: SNS-XXXX-USA.png" "Yellow"
            Log-Message "Example: SNS-ABCD-USA.png" "Yellow"
        } else {
            Log-Message "Extracted: $($codes.Count) SNS codes" "Green"
            Log-Message "Saved: $file" "Cyan"
            Log-Message "SNS list updated ($($codes.Count) codes shown in SNS Code Tools)" "Cyan"
        }
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

# ============================================================================
# GAMETDB HELPERS
# ============================================================================
function Get-GameTDBRegionCode {
    param([string]$GameId)
    if ([string]::IsNullOrWhiteSpace($GameId)) { return "US" }
    $id = $GameId.Trim().ToUpper()
    if ($id -match '^[A-Z0-9]{6}$') {
        $r = $id[3]
        switch ($r) {
            'E' { return "US" }
            'J' { return "JA" }
            'K' { return "KO" }
            'W' { return "TW" }
            'R' { return "RU" }
            'A' { return "US" }
            default { return "EN" }
        }
    }
    if ($id -match '-(USA|EUR|JPN|AUS|FRA|GER|ITA|SPA|UK|KOR|CAN)$') {
        switch ($matches[1]) {
            'USA' { return "US" }
            'JPN' { return "JA" }
            'KOR' { return "KO" }
            'EUR' { return "EN" }
            'UK'  { return "EN" }
            'FRA' { return "FR" }
            'GER' { return "DE" }
            'ITA' { return "IT" }
            'SPA' { return "ES" }
            'AUS' { return "AU" }
            'CAN' { return "US" }
            default { return "EN" }
        }
    }
    return "US"
}

function Get-GameTDBPlatformKey {
    param([string]$GameId)
    if ([string]::IsNullOrWhiteSpace($GameId)) { return $script:lastGameTdbPlatform }
    $id = $GameId.Trim().ToUpper()
    if ($id -match '^(BLES|BLUS|BLAS|BLJM|NPUB|NPEB|NPHB)') { return "ps3" }
    if ($id -match '^(HAC|XCI)') { return "switch" }
    if ($id -match '^[A-Z0-9]{16}$') { return "switch" }
    if ($id -match '^[A-Z0-9]{4}$' -and $id -notmatch '^[A-Z]{3}[EJP]') {
        return "ds"
    }
    if ($id -match '^[A-Z0-9]{6}$') {
        $first = $id[0]
        if ($first -eq 'G') { return "wii" }
        if ($first -eq 'R' -or $first -eq 'S' -or $first -eq 'H') { return "wii" }
        return "wii"
    }
    if ($id -match '^SNS-') { return $null }
    return $script:lastGameTdbPlatform
}

function Get-GameTDBShortId {
    param([string]$GameId)
    if ([string]::IsNullOrWhiteSpace($GameId)) { return $null }
    $id = $GameId.Trim().ToUpper()
    if ($id -match '^[A-Z]{3,4}-([A-Z0-9]{4})-') { return $matches[1] }
    if ($id -match '^[A-Z0-9]{4,16}$') { return $id }
    return $id
}

function Select-GameTDBPlatform {
    $keys = @($script:gameTdbPlatforms.Keys | Sort-Object)
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Select GameTDB Platform"
    $dlg.Size = New-Object System.Drawing.Size(360, 220)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.BackColor = $script:theme.background
    $dlg.ForeColor = $script:theme.text
    
    $lb = New-Object System.Windows.Forms.ListBox
    $lb.Location = New-Object System.Drawing.Point(20, 20)
    $lb.Size = New-Object System.Drawing.Size(300, 110)
    $lb.BackColor = $script:theme.editor
    $lb.ForeColor = $script:theme.text
    foreach ($k in $keys) {
        [void]$lb.Items.Add("$k  -  $($script:gameTdbPlatforms[$k].Label)")
    }
    $idx = [array]::IndexOf($keys, $script:lastGameTdbPlatform)
    if ($idx -ge 0) { $lb.SelectedIndex = $idx } else { $lb.SelectedIndex = 0 }
    $dlg.Controls.Add($lb)
    
    $chosen = $null
    $ok = Create-Button "OK" 80 140 90 30
    $ok.Add_Click({
        if ($lb.SelectedIndex -ge 0) {
            $script:__gtdbPick = $keys[$lb.SelectedIndex]
            $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $dlg.Close()
        }
    })
    $dlg.Controls.Add($ok)
    $cn = Create-Button "Cancel" 190 140 90 30
    $cn.Add_Click({ $dlg.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $dlg.Close() })
    $dlg.Controls.Add($cn)
    
    $script:__gtdbPick = $null
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and $script:__gtdbPick) {
        $script:lastGameTdbPlatform = $script:__gtdbPick
        return $script:__gtdbPick
    }
    return $null
}

function Download-GameTDBTitles {
    $c = Get-Col
    if (-not $c) { return }
    
    $plat = Select-GameTDBPlatform
    if (-not $plat) {
        Log-Message "GameTDB titles download cancelled." "Yellow"
        return
    }
    
    $info = $script:gameTdbPlatforms[$plat]
    Log-Message "========================================" "Cyan"
    Log-Message "DOWNLOADING GAMETDB TITLES - $($info.Label)" "Cyan"
    Log-Message "========================================" "Cyan"
    
    try {
        $outDir = Get-ToolsFolder $c.mediaPath
        if (-not $outDir) { $outDir = Split-Path $c.metadataPath -Parent }
        $outFile = Join-Path $outDir "gametdb_${plat}_titles.txt"
        
        Log-Message "Fetching: $($info.TitlesUrl)" "White"
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "MetadataRepairTool/$($script:version)")
        $data = $wc.DownloadString($info.TitlesUrl)
        $wc.Dispose()
        
        $data | Out-File -FilePath $outFile -Encoding UTF8
        $lines = @($data -split "`r?`n" | Where-Object { $_ -match '^\s*[A-Z0-9]' })
        $map = @{}
        foreach ($line in $lines) {
            if ($line -match '^\s*([A-Z0-9]+)\s*=\s*(.+)$') {
                $map[$matches[1].Trim()] = $matches[2].Trim()
            }
        }
        $script:gameTdbTitlesCache[$plat] = $map
        $script:lastGameTdbPlatform = $plat
        
        Log-Message "Saved: $outFile" "Green"
        Log-Message "Parsed: $($map.Count) titles" "Green"
        Log-Message "Platform set to: $plat" "Cyan"
    } catch {
        Log-Message "ERROR downloading titles: $_" "Red"
        Log-Message "Check internet access and that GameTDB is reachable." "Yellow"
    }
}

function Load-GameTDBTitlesCache {
    param([string]$Platform)
    if ($script:gameTdbTitlesCache.ContainsKey($Platform) -and $script:gameTdbTitlesCache[$Platform].Count -gt 0) {
        return $script:gameTdbTitlesCache[$Platform]
    }
    $c = Get-Col
    if ($c) {
        $metaDir = Split-Path $c.metadataPath -Parent
        $outFile = Resolve-ToolsFile $c.mediaPath "gametdb_${Platform}_titles.txt" $metaDir
        if ($outFile -and (Test-Path $outFile)) {
            $map = @{}
            Get-Content $outFile | ForEach-Object {
                if ($_ -match '^\s*([A-Z0-9]+)\s*=\s*(.+)$') {
                    $map[$matches[1].Trim()] = $matches[2].Trim()
                }
            }
            $script:gameTdbTitlesCache[$Platform] = $map
            return $map
        }
    }
    return @{}
}

function Lookup-GameTDBTitle {
    $c = Get-Col
    if (-not $c) { return }
    
    $gameId = ""
    if ($script:fieldControls -and $script:fieldControls.ContainsKey("game_id")) {
        $gameId = $script:fieldControls["game_id"].Text.Trim()
    }
    if ([string]::IsNullOrWhiteSpace($gameId) -and $script:gameListBox -and $script:gameListBox.SelectedItem) {
        $title = $script:gameListBox.SelectedItem.ToString()
        $g = $script:parsedGames | Where-Object { $_.Title -eq $title } | Select-Object -First 1
        if ($g -and $g.Fields.ContainsKey("game_id")) { $gameId = [string]$g.Fields["game_id"] }
    }
    
    if ([string]::IsNullOrWhiteSpace($gameId)) {
        $input = Show-InputBox "Enter GameTDB / product Game ID (e.g. RMGE01):" "Lookup Title" ""
        if ([string]::IsNullOrWhiteSpace($input)) { return }
        $gameId = $input.Trim()
    }
    
    $shortId = Get-GameTDBShortId $gameId
    $plat = Get-GameTDBPlatformKey $gameId
    if (-not $plat) {
        Log-Message "No GameTDB platform mapping for: $gameId (SNES codes use SNS tools)" "Yellow"
        return
    }
    
    $map = Load-GameTDBTitlesCache $plat
    if ($map.Count -eq 0) {
        Log-Message "No titles cache for $plat. Run 'Download Titles DB' first." "Yellow"
        return
    }
    
    $found = $null
    if ($map.ContainsKey($shortId)) { $found = $map[$shortId] }
    elseif ($map.ContainsKey($gameId)) { $found = $map[$gameId] }
    
    if ($found) {
        Log-Message "GameTDB: $shortId -> $found  [$plat]" "Green"
        [System.Windows.Forms.MessageBox]::Show("ID: $shortId`nPlatform: $plat`nTitle: $found", "GameTDB Lookup", "OK", "Information")
    } else {
        Log-Message "No title found for $shortId on $plat" "Yellow"
    }
}

function Get-GameTDBCoverExt {
    param([string]$Platform, [string]$ArtType = "cover")
    if ($ArtType -match '^(disc|discHQ|discCustom|discCustomHQ|cover3D)$') { return "png" }
    $info = $script:gameTdbPlatforms[$Platform]
    if ($info -and $info.Ext) { return $info.Ext }
    return "jpg"
}

function Build-GameTDBCoverUrl {
    param(
        [string]$GameId,
        [string]$ArtType = "cover",
        [string]$Platform = $null,
        [string]$Region = $null
    )
    $plat = if ($Platform) { $Platform } else { Get-GameTDBPlatformKey $GameId }
    if (-not $plat) { return $null }
    if ($plat -eq "gamecube") { $plat = "wii" }  # art host is shared
    $info = $script:gameTdbPlatforms[$plat]
    if (-not $info) { $info = $script:gameTdbPlatforms["wii"] }
    $shortId = Get-GameTDBShortId $GameId
    if (-not $Region) { $Region = Get-GameTDBRegionCode $GameId }
    $ext = Get-GameTDBCoverExt $plat $ArtType
    return "https://art.gametdb.com/$($info.ArtPath)/$ArtType/$Region/$shortId.$ext"
}


function Get-GameTDBCoverTypeDescription {
    param([string]$CoverType)
    $map = @{
        "cover"        = "Standard box front covers (typical ~512px). Use for Box Front / box2dfront entries."
        "coverHQ"      = "High quality box front covers (768x680). Use for Box Front / box2dfront entries."
        "coverfullHQ"  = "High quality full box art (front + spine + back wrap). Best for boxFull / box2dfull."
        "coverM"       = "Medium-size box front covers. Lighter downloads; fine for thumbs or box2dfront."
        "cover3D"      = "3D rendered game box images (PNG). Decorative; not a flat 2D box front."
        "back"         = "Standard box back covers. Use for Box Back / box2dback entries."
        "backHQ"       = "High quality box back covers. Use for Box Back / box2dback entries."
        "backM"        = "Medium-size box back covers. Use for Box Back / box2dback entries."
        "disc"         = "Official disc / disc-label art (PNG). Use for disc / cartridge-style assets."
        "discCustom"   = "Custom / alternate disc art (PNG). Use for disc assets when official disc is missing."
    }
    if ($map.ContainsKey($CoverType)) { return $map[$CoverType] }
    return "GameTDB art type '$CoverType' from art.gametdb.com."
}

function Get-GameTDBCoverTypeFolder {
    param(
        [string]$CoverType,
        [switch]$UseBoxFull
    )
    switch -Regex ($CoverType) {
        '^(back|backHQ|backM)$' { return "box2dback" }
        '^(disc|discCustom|discHQ|discCustomHQ)$' { return "disc" }
        '^(coverfullHQ)$' {
            if ($UseBoxFull) { return "boxFull" }
            return "box2dfull"
        }
        default { return "box2dfront" }
    }
}

function Get-GameTDBCoverTypeAssetKey {
    param(
        [string]$CoverType,
        [switch]$UseBoxFull
    )
    switch -Regex ($CoverType) {
        '^(back|backHQ|backM)$' { return "assets.box_back" }
        '^(disc|discCustom|discHQ|discCustomHQ)$' { return "assets.cartridge" }
        '^(coverfullHQ)$' {
            if ($UseBoxFull) { return "assets.boxFull" }
            return "assets.box_full"
        }
        default { return "assets.box_front" }
    }
}

function Get-SafeGameFileName {
    param([string]$Title)
    if ([string]::IsNullOrWhiteSpace($Title)) { return $null }
    $n = $Title.Trim()
    $n = $n -replace '[\/:*?"<>|]', ''
    $n = $n -replace '\s+', ' '
    $n = $n.Trim().TrimEnd('.')
    if ($n.Length -gt 120) { $n = $n.Substring(0, 120).Trim().TrimEnd('.') }
    if ([string]::IsNullOrWhiteSpace($n)) { return $null }
    return $n
}

function Convert-ImageFileToPng {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $Path }
    if ($Path -match '\.png$') { return $Path }
    $pngPath = [System.IO.Path]::ChangeExtension($Path, ".png")
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $img = [System.Drawing.Image]::FromStream($fs)
            try {
                $bmp = New-Object System.Drawing.Bitmap $img
                try {
                    $bmp.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
                } finally { $bmp.Dispose() }
            } finally { $img.Dispose() }
        } finally { $fs.Close(); $fs.Dispose() }
        if ((Test-Path -LiteralPath $pngPath) -and ((Get-Item -LiteralPath $pngPath).Length -gt 0)) {
            Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
            return $pngPath
        }
    } catch {
        Log-Message ("PNG convert failed for {0}: {1}" -f $Path, $_.Exception.Message) "Yellow"
    }
    return $Path
}

function Test-CollectionAssetPathExists {
    # Resolve a metadata asset path (absolute or relative) against the collection.
    param(
        [string]$AssetPath,
        $Collection
    )
    if ([string]::IsNullOrWhiteSpace($AssetPath) -or -not $Collection) { return $false }
    $p = $AssetPath.Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($p)) { return $false }
    try {
        if ([System.IO.Path]::IsPathRooted($p)) {
            return (Test-Path -LiteralPath $p)
        }
        $try1 = Join-Path (Split-Path $Collection.metadataPath -Parent) $p
        if (Test-Path -LiteralPath $try1) { return $true }
        if ($Collection.mediaPath) {
            $try2 = Join-Path $Collection.mediaPath $p
            if (Test-Path -LiteralPath $try2) { return $true }
            $try3 = Join-Path (Split-Path $Collection.mediaPath -Parent) $p
            if (Test-Path -LiteralPath $try3) { return $true }
        }
    } catch {}
    return $false
}

function Get-CollectionGameIdMap {
    # Returns hashtable: shortId (upper) -> @{
    #   Title; GameId; HasBoxFront; HasBoxFull; HasBox_Full; HasBoxBack;
    #   BoxFrontPath; PresentAssets (hashtable of assetKey -> $true when file exists)
    # }
    $map = @{}
    $c = Get-Col
    if (-not $c -or -not $c.metadataPath -or -not (Test-Path $c.metadataPath)) { return $map }
    try {
        $content = Get-Content $c.metadataPath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($content)) { return $map }
        $games = $content -split '(?=game: )' | Where-Object { $_ -match '^game: ' }
        foreach ($g in $games) {
            $title = ""
            if ($g -match '(?m)^game:\s*(.+)$') { $title = $matches[1].Trim() }
            $gid = $null
            if ($g -match '(?m)^game_id:\s*(\S+)') { $gid = $matches[1].Trim() }
            if (-not $gid) { continue }
            $short = Get-GameTDBShortId $gid
            if (-not $short) { $short = $gid }
            $short = $short.ToUpperInvariant()

            $present = @{}
            $frontPath = ""
            $hasFront = $false
            $hasBoxFull = $false
            $hasBox_Full = $false
            $hasBack = $false

            foreach ($m in [regex]::Matches($g, '(?m)^(assets\.[^:]+):\s*(.+)$')) {
                $akey = $m.Groups[1].Value.Trim()
                $aval = $m.Groups[2].Value.Trim().Trim('"')
                if ([string]::IsNullOrWhiteSpace($aval)) { continue }
                if (Test-CollectionAssetPathExists -AssetPath $aval -Collection $c) {
                    $present[$akey] = $true
                    if ($akey -eq "assets.box_front") {
                        $hasFront = $true
                        $frontPath = $aval
                    } elseif ($akey -eq "assets.boxFull") {
                        $hasBoxFull = $true
                    } elseif ($akey -eq "assets.box_full") {
                        $hasBox_Full = $true
                    } elseif ($akey -eq "assets.box_back") {
                        $hasBack = $true
                    }
                }
            }

            if (-not $map.ContainsKey($short)) {
                $map[$short] = @{
                    Title         = $title
                    GameId        = $gid
                    HasBoxFront   = $hasFront
                    HasBoxFull    = $hasBoxFull
                    HasBox_Full   = $hasBox_Full
                    HasBoxBack    = $hasBack
                    BoxFrontPath  = $frontPath
                    PresentAssets = $present
                }
            }
        }
    } catch {
        Log-Message "Get-CollectionGameIdMap: $_" "Yellow"
    }
    return $map
}

function Show-GameTDBCoverPackDialog {
    # Matches Settings-style dialogs: GroupBoxes, tight layout, PS 5.1 safe
    try {
        $dlg = New-Object System.Windows.Forms.Form
        $dlg.Text = "GameTDB Cover Pack"
        $dlg.Size = New-Object System.Drawing.Size(500, 470)
        $dlg.StartPosition = "CenterParent"
        $dlg.FormBorderStyle = "FixedDialog"
        $dlg.MaximizeBox = $false
        $dlg.MinimizeBox = $false
        $dlg.ShowInTaskbar = $false
        $dlg.BackColor = $script:theme.background
        $dlg.ForeColor = $script:theme.text
        $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)

        $secX = 14
        $secW = 456
        $btnW = 100
        $btnH = 26
        $gap = 6

        # ========== Source ==========
        $grpSrc = New-Object System.Windows.Forms.GroupBox
        $grpSrc.Text = " Source "
        $grpSrc.Location = New-Object System.Drawing.Point($secX, 10)
        $grpSrc.Size = New-Object System.Drawing.Size($secW, 168)
        $grpSrc.ForeColor = $script:theme.text
        $grpSrc.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $grpSrc.BackColor = $script:theme.background
        $dlg.Controls.Add($grpSrc)

        $lblSys = New-Object System.Windows.Forms.Label
        $lblSys.Text = "System"
        $lblSys.Location = New-Object System.Drawing.Point(12, 22)
        $lblSys.Size = New-Object System.Drawing.Size(200, 16)
        $lblSys.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $lblSys.ForeColor = $script:theme.text
        $grpSrc.Controls.Add($lblSys)

        $lblTypes = New-Object System.Windows.Forms.Label
        $lblTypes.Text = "Cover types"
        $lblTypes.Location = New-Object System.Drawing.Point(230, 22)
        $lblTypes.Size = New-Object System.Drawing.Size(200, 16)
        $lblTypes.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $lblTypes.ForeColor = $script:theme.text
        $grpSrc.Controls.Add($lblTypes)

        $cmbSys = New-Object System.Windows.Forms.ComboBox
        $cmbSys.Location = New-Object System.Drawing.Point(12, 40)
        $cmbSys.Size = New-Object System.Drawing.Size(200, 24)
        $cmbSys.DropDownStyle = "DropDownList"
        $cmbSys.BackColor = $script:theme.editor
        $cmbSys.ForeColor = $script:theme.text
        $cmbSys.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $grpSrc.Controls.Add($cmbSys)

        $clbCover = New-Object System.Windows.Forms.CheckedListBox
        $clbCover.Location = New-Object System.Drawing.Point(230, 40)
        $clbCover.Size = New-Object System.Drawing.Size(210, 86)
        $clbCover.BackColor = $script:theme.editor
        $clbCover.ForeColor = $script:theme.text
        $clbCover.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $clbCover.CheckOnClick = $true
        $clbCover.BorderStyle = "FixedSingle"
        $clbCover.IntegralHeight = $true
        $grpSrc.Controls.Add($clbCover)

        $lblReg = New-Object System.Windows.Forms.Label
        $lblReg.Text = "Region"
        $lblReg.Location = New-Object System.Drawing.Point(12, 70)
        $lblReg.Size = New-Object System.Drawing.Size(200, 16)
        $lblReg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $lblReg.ForeColor = $script:theme.text
        $grpSrc.Controls.Add($lblReg)

        $cmbReg = New-Object System.Windows.Forms.ComboBox
        $cmbReg.Location = New-Object System.Drawing.Point(12, 88)
        $cmbReg.Size = New-Object System.Drawing.Size(90, 24)
        $cmbReg.DropDownStyle = "DropDownList"
        $cmbReg.BackColor = $script:theme.editor
        $cmbReg.ForeColor = $script:theme.text
        $cmbReg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $grpSrc.Controls.Add($cmbReg)

        # Description under system/region (full width of left column + wraps under list)
        $lblDesc = New-Object System.Windows.Forms.Label
        $lblDesc.Location = New-Object System.Drawing.Point(12, 120)
        $lblDesc.Size = New-Object System.Drawing.Size(428, 36)
        $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 8)
        $lblDesc.ForeColor = $script:theme.accent
        $lblDesc.Text = "Select a cover type to see its description."
        $grpSrc.Controls.Add($lblDesc)

        $platKeys = @($script:gameTdbPlatforms.Keys | Sort-Object)
        foreach ($k in $platKeys) {
            [void]$cmbSys.Items.Add($script:gameTdbPlatforms[$k].Label)
        }
        foreach ($r in $script:gameTdbRegions) {
            [void]$cmbReg.Items.Add($r)
        }
        $cmbReg.SelectedItem = "US"

        $script:__gtdbPackPlatKeys = $platKeys
        $script:__gtdbPackClb = $clbCover
        $script:__gtdbPackDesc = $lblDesc

        $fillTypes = {
            $clb = $script:__gtdbPackClb
            $keys = $script:__gtdbPackPlatKeys
            if (-not $clb -or -not $keys) { return }
            $clb.Items.Clear()
            $idx = $script:__gtdbPackCmb.SelectedIndex
            if ($idx -lt 0 -or $idx -ge $keys.Count) { return }
            $types = $script:gameTdbPlatforms[$keys[$idx]].CoverTypes
            if (-not $types) { $types = @("cover") }
            foreach ($t in $types) { [void]$clb.Items.Add([string]$t) }
            # Prefer a front cover type
            for ($i = 0; $i -lt $clb.Items.Count; $i++) {
                $t = [string]$clb.Items[$i]
                if ($t -eq "cover" -or $t -eq "coverHQ" -or $t -eq "coverfullHQ") {
                    $clb.SetItemChecked($i, $true)
                    $clb.SelectedIndex = $i
                    break
                }
            }
            if ($clb.CheckedItems.Count -eq 0 -and $clb.Items.Count -gt 0) {
                $clb.SetItemChecked(0, $true)
                $clb.SelectedIndex = 0
            }
            # Shrink list height to content (max ~6 rows)
            $rowH = 18
            try { $rowH = [Math]::Max(16, $clb.GetItemHeight(0)) } catch {}
            $rows = [Math]::Min(6, [Math]::Max(3, $clb.Items.Count))
            $clb.Height = ($rows * $rowH) + 4
        }

        $updateDesc = {
            $clb = $script:__gtdbPackClb
            $lbl = $script:__gtdbPackDesc
            if (-not $clb -or -not $lbl) { return }
            $t = $null
            if ($clb.SelectedIndex -ge 0) {
                $t = [string]$clb.Items[$clb.SelectedIndex]
            } elseif ($clb.CheckedItems.Count -gt 0) {
                $t = [string]$clb.CheckedItems[0]
            }
            if ($t) {
                $lbl.Text = Get-GameTDBCoverTypeDescription $t
            } else {
                $lbl.Text = "Select a cover type to see its description."
            }
        }

        $script:__gtdbPackCmb = $cmbSys
        $cmbSys.Add_SelectedIndexChanged({
            try {
                & $script:__gtdbPackFill
                & $script:__gtdbPackUpdateDesc
            } catch {}
        })
        $clbCover.Add_SelectedIndexChanged({
            try { & $script:__gtdbPackUpdateDesc } catch {}
        })
        $script:__gtdbPackFill = $fillTypes
        $script:__gtdbPackUpdateDesc = $updateDesc

        $selIdx = 0
        for ($i = 0; $i -lt $platKeys.Count; $i++) {
            if ($platKeys[$i] -eq $script:lastGameTdbPlatform) { $selIdx = $i; break }
        }
        if ($cmbSys.Items.Count -gt 0) {
            $cmbSys.SelectedIndex = $selIdx
            if ($clbCover.Items.Count -eq 0) {
                & $fillTypes
                & $updateDesc
            }
        }

        # ========== Options ==========
        $grpOpt = New-Object System.Windows.Forms.GroupBox
        $grpOpt.Text = " Options "
        $grpOpt.Location = New-Object System.Drawing.Point($secX, 184)
        $grpOpt.Size = New-Object System.Drawing.Size($secW, 198)
        $grpOpt.ForeColor = $script:theme.text
        $grpOpt.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $grpOpt.BackColor = $script:theme.background
        $dlg.Controls.Add($grpOpt)

        $colName = "(none selected)"
        try {
            $selCol = Get-Col
            if ($selCol -and $selCol.name) { $colName = [string]$selCol.name }
            elseif ($script:collectionList -and $script:collectionList.SelectedItem) {
                $colName = [string]$script:collectionList.SelectedItem
            }
        } catch {}

        $lblCol = New-Object System.Windows.Forms.Label
        $lblCol.Text = "Selected collection: $colName"
        $lblCol.Location = New-Object System.Drawing.Point(12, 18)
        $lblCol.Size = New-Object System.Drawing.Size(430, 16)
        $lblCol.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $lblCol.ForeColor = $script:theme.accent
        $grpOpt.Controls.Add($lblCol)

        $chkCollection = New-Object System.Windows.Forms.CheckBox
        $chkCollection.Text = "Current collection only (requires game_id on this platform)"
        $chkCollection.Location = New-Object System.Drawing.Point(12, 36)
        $chkCollection.Size = New-Object System.Drawing.Size(430, 18)
        $chkCollection.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $chkCollection.ForeColor = $script:theme.text
        $chkCollection.BackColor = $script:theme.background
        $chkCollection.Checked = $true
        $grpOpt.Controls.Add($chkCollection)

        $chkMissing = New-Object System.Windows.Forms.CheckBox
        $chkMissing.Text = "Only missing art (front / boxFull / back)"
        $chkMissing.Location = New-Object System.Drawing.Point(12, 56)
        $chkMissing.Size = New-Object System.Drawing.Size(200, 18)
        $chkMissing.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $chkMissing.ForeColor = $script:theme.text
        $chkMissing.BackColor = $script:theme.background
        $chkMissing.Checked = $true
        $grpOpt.Controls.Add($chkMissing)

        $chkFallback = New-Object System.Windows.Forms.CheckBox
        $chkFallback.Text = "Region fallback"
        $chkFallback.Location = New-Object System.Drawing.Point(220, 56)
        $chkFallback.Size = New-Object System.Drawing.Size(200, 18)
        $chkFallback.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $chkFallback.ForeColor = $script:theme.text
        $chkFallback.BackColor = $script:theme.background
        $chkFallback.Checked = $true
        $grpOpt.Controls.Add($chkFallback)

        $chkMedia = New-Object System.Windows.Forms.CheckBox
        $chkMedia.Text = "Save into media folders"
        $chkMedia.Location = New-Object System.Drawing.Point(12, 76)
        $chkMedia.Size = New-Object System.Drawing.Size(200, 18)
        $chkMedia.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $chkMedia.ForeColor = $script:theme.text
        $chkMedia.BackColor = $script:theme.background
        $chkMedia.Checked = $true
        $grpOpt.Controls.Add($chkMedia)

        $chkWrite = New-Object System.Windows.Forms.CheckBox
        $chkWrite.Text = "Write asset paths into metadata"
        $chkWrite.Location = New-Object System.Drawing.Point(220, 76)
        $chkWrite.Size = New-Object System.Drawing.Size(220, 18)
        $chkWrite.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $chkWrite.ForeColor = $script:theme.text
        $chkWrite.BackColor = $script:theme.background
        $chkWrite.Checked = $true
        $grpOpt.Controls.Add($chkWrite)

        $chkBoxFull = New-Object System.Windows.Forms.CheckBox
        $chkBoxFull.Text = "Full covers -> boxFull (Unicovers / theme)"
        $chkBoxFull.Location = New-Object System.Drawing.Point(12, 96)
        $chkBoxFull.Size = New-Object System.Drawing.Size(430, 18)
        $chkBoxFull.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $chkBoxFull.ForeColor = $script:theme.text
        $chkBoxFull.BackColor = $script:theme.background
        $chkBoxFull.Checked = $true
        $grpOpt.Controls.Add($chkBoxFull)

        $chkRename = New-Object System.Windows.Forms.CheckBox
        $chkRename.Text = "Rename images to game titles"
        $chkRename.Location = New-Object System.Drawing.Point(12, 116)
        $chkRename.Size = New-Object System.Drawing.Size(250, 18)
        $chkRename.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $chkRename.ForeColor = $script:theme.text
        $chkRename.BackColor = $script:theme.background
        $chkRename.Checked = $true
        $grpOpt.Controls.Add($chkRename)

        $chkPng = New-Object System.Windows.Forms.CheckBox
        $chkPng.Text = "Convert to PNG"
        $chkPng.Location = New-Object System.Drawing.Point(270, 116)
        $chkPng.Size = New-Object System.Drawing.Size(160, 18)
        $chkPng.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $chkPng.ForeColor = $script:theme.text
        $chkPng.BackColor = $script:theme.background
        $chkPng.Checked = $true
        $grpOpt.Controls.Add($chkPng)

        $lblOptHint = New-Object System.Windows.Forms.Label
        $lblOptHint.Text = "boxFull for coverfullHQ. Rename/PNG run after each successful download."
        $lblOptHint.Location = New-Object System.Drawing.Point(12, 140)
        $lblOptHint.Size = New-Object System.Drawing.Size(430, 16)
        $lblOptHint.Font = New-Object System.Drawing.Font("Segoe UI", 8)
        $lblOptHint.ForeColor = $script:theme.textDim
        $grpOpt.Controls.Add($lblOptHint)

        $chkCollection.Add_CheckedChanged({
            param($sender, $e)
            if (-not $sender.Checked) {
                $chkMedia.Checked = $false
                $chkWrite.Checked = $false
            }
        })

        # ========== Output ==========
        $grpOut = New-Object System.Windows.Forms.GroupBox
        $grpOut.Text = " Output folder "
        $grpOut.Location = New-Object System.Drawing.Point($secX, 388)
        $grpOut.Size = New-Object System.Drawing.Size($secW, 72)
        $grpOut.ForeColor = $script:theme.text
        $grpOut.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $grpOut.BackColor = $script:theme.background
        $dlg.Controls.Add($grpOut)

        $lblOutHint = New-Object System.Windows.Forms.Label
        $lblOutHint.Text = "Used only when not saving into media folders"
        $lblOutHint.Location = New-Object System.Drawing.Point(12, 20)
        $lblOutHint.Size = New-Object System.Drawing.Size(420, 14)
        $lblOutHint.Font = New-Object System.Drawing.Font("Segoe UI", 8)
        $lblOutHint.ForeColor = $script:theme.textDim
        $grpOut.Controls.Add($lblOutHint)

        $txtOut = New-Object System.Windows.Forms.TextBox
        $txtOut.Location = New-Object System.Drawing.Point(12, 38)
        $txtOut.Size = New-Object System.Drawing.Size(390, 22)
        $txtOut.BackColor = $script:theme.editor
        $txtOut.ForeColor = $script:theme.text
        $txtOut.BorderStyle = "FixedSingle"
        $txtOut.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $c = Get-Col
        if ($c -and $c.mediaPath) {
            $txtOut.Text = [string](Join-Path $c.mediaPath "Covers")
        } else {
            $txtOut.Text = [string](Join-Path $env:USERPROFILE "Downloads\GameTDB_Covers")
        }
        $grpOut.Controls.Add($txtOut)

        $btnBrowse = Create-Button "..." 408 36 36 $btnH
        $btnBrowse.Add_Click({
            $fd = New-Object System.Windows.Forms.FolderBrowserDialog
            $fd.Description = "Select folder for GameTDB covers"
            if ($fd.ShowDialog() -eq "OK") { $txtOut.Text = $fd.SelectedPath }
        })
        $grpOut.Controls.Add($btnBrowse)

        # ========== Buttons ==========
        $btnStart = Create-Button "Start" 155 470 100 $btnH
        $btnStart.Add_Click({
            try {
                $idx = $cmbSys.SelectedIndex
                if ($idx -lt 0 -or $idx -ge $platKeys.Count) { return }
                $types = @()
                foreach ($item in $clbCover.CheckedItems) { $types += [string]$item }
                if ($types.Count -eq 0) {
                    [System.Windows.Forms.MessageBox]::Show("Select at least one cover type.", "GameTDB", "OK", "Warning") | Out-Null
                    return
                }
                $region = [string]$cmbReg.SelectedItem
                $outBase = $txtOut.Text.Trim()
                $useMedia = [bool]$chkMedia.Checked
                $collectionOnly = [bool]$chkCollection.Checked
                $writeAssets = [bool]$chkWrite.Checked
                if ($writeAssets -or $useMedia -or $collectionOnly) {
                    $col = Get-Col
                    if (-not $col) {
                        [System.Windows.Forms.MessageBox]::Show(
                            "Select a collection first.", "GameTDB", "OK", "Warning") | Out-Null
                        return
                    }
                    if ($useMedia -and [string]::IsNullOrWhiteSpace($col.mediaPath)) {
                        [System.Windows.Forms.MessageBox]::Show("Collection has no media folder set.", "GameTDB", "OK", "Warning") | Out-Null
                        return
                    }
                }
                if (-not $useMedia -and [string]::IsNullOrWhiteSpace($outBase)) {
                    [System.Windows.Forms.MessageBox]::Show("Choose an output folder.", "GameTDB", "OK", "Warning") | Out-Null
                    return
                }
                if ([string]::IsNullOrWhiteSpace($region)) {
                    [System.Windows.Forms.MessageBox]::Show("Choose a region.", "GameTDB", "OK", "Warning") | Out-Null
                    return
                }
                $dlg.Tag = @{
                    Platform       = $platKeys[$idx]
                    CoverTypes     = $types
                    Region         = $region
                    OutBase        = $outBase
                    CollectionOnly = $collectionOnly
                    OnlyMissing    = [bool]$chkMissing.Checked
                    RegionFallback = [bool]$chkFallback.Checked
                    SaveIntoMedia  = $useMedia
                    WriteAssets    = $writeAssets
                    UseBoxFull     = [bool]$chkBoxFull.Checked
                    RenameToTitle  = [bool]$chkRename.Checked
                    ConvertToPng   = [bool]$chkPng.Checked
                }
                $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
                $dlg.Close()
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Error: $($_.Exception.Message)", "GameTDB", "OK", "Error") | Out-Null
            }
        })
        $dlg.Controls.Add($btnStart)

        $btnCancel = Create-Button "Cancel" 267 470 $btnW $btnH
        $btnCancel.Add_Click({ $dlg.Close() })
        $dlg.Controls.Add($btnCancel)

        # Fit dialog to bottom of buttons
        $dlg.ClientSize = New-Object System.Drawing.Size(484, 510)

        $result = $dlg.ShowDialog($script:mainForm)
        if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return }
        $opts = $dlg.Tag
        if (-not $opts) { return }

        Start-GameTDBCoverPackDownload `
            -Platform $opts.Platform `
            -CoverTypes $opts.CoverTypes `
            -Region $opts.Region `
            -OutBase $opts.OutBase `
            -CollectionOnly:$opts.CollectionOnly `
            -OnlyMissing:$opts.OnlyMissing `
            -RegionFallback:$opts.RegionFallback `
            -SaveIntoMedia:$opts.SaveIntoMedia `
            -WriteAssets:$opts.WriteAssets `
            -UseBoxFull:$opts.UseBoxFull `
            -RenameToTitle:$opts.RenameToTitle `
            -ConvertToPng:$opts.ConvertToPng
    } catch {
        $msg = "Cover Pack dialog error: $($_.Exception.Message)"
        try { Log-Message $msg "Red" } catch {}
        try {
            [System.Windows.Forms.MessageBox]::Show($msg, "GameTDB Cover Pack", "OK", "Error") | Out-Null
        } catch {}
    }
}

function Show-GameTDBProgressWindow {
    # Non-modal progress overlay so the main terminal stays visible underneath
    param(
        [string]$Title = "GameTDB Cover Pack"
    )
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.Size = New-Object System.Drawing.Size(420, 160)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true
    $form.ShowInTaskbar = $true
    $form.BackColor = $script:theme.background
    $form.ForeColor = $script:theme.text
    $form.ControlBox = $false

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Name = "statusLabel"
    $lbl.Text = "Starting..."
    $lbl.Location = New-Object System.Drawing.Point(16, 16)
    $lbl.Size = New-Object System.Drawing.Size(370, 36)
    $lbl.ForeColor = $script:theme.text
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.Controls.Add($lbl)

    $bar = New-Object System.Windows.Forms.ProgressBar
    $bar.Name = "progressBar"
    $bar.Location = New-Object System.Drawing.Point(16, 60)
    $bar.Size = New-Object System.Drawing.Size(370, 22)
    $bar.Minimum = 0
    $bar.Maximum = 100
    $bar.Value = 0
    $bar.Style = "Continuous"
    $form.Controls.Add($bar)

    $btnAbort = Create-Button "Abort" 150 95 100 26
    $btnAbort.Name = "abortButton"
    $btnAbort.Tag = $form
    $btnAbort.Add_Click({
        param($sender, $e)
        $script:gtdbCoverPackAbort = $true
        try {
            if ($sender.Text -eq "Close") {
                $f = $sender.Tag
                if ($f -and -not $f.IsDisposed) { $f.Close() }
                return
            }
            $sender.Enabled = $false
            $sender.Text = "Aborting..."
        } catch {}
    })
    $form.Controls.Add($btnAbort)

    $script:gtdbCoverPackAbort = $false
    $form.Show()
    $form.BringToFront()
    [System.Windows.Forms.Application]::DoEvents()
    return $form
}

function Update-GameTDBProgressWindow {
    param(
        $Form,
        [int]$Percent,
        [string]$Status,
        [switch]$Completed,
        [switch]$Aborted
    )
    if (-not $Form -or $Form.IsDisposed) { return }
    try {
        $bar = $Form.Controls["progressBar"]
        $lbl = $Form.Controls["statusLabel"]
        $btn = $Form.Controls["abortButton"]
        if ($Percent -lt 0) { $Percent = 0 }
        if ($Percent -gt 100) { $Percent = 100 }
        if ($bar) { $bar.Value = $Percent }
        if ($lbl -and $Status) { $lbl.Text = $Status }
        if ($Completed) {
            if ($bar) { $bar.Value = 100 }
            if ($lbl) {
                if ($Status) { $lbl.Text = "Completed`r`n$Status" }
                else { $lbl.Text = "Completed" }
            }
            if ($btn) {
                $btn.Text = "Close"
                $btn.Enabled = $true
            }
        } elseif ($Aborted) {
            if ($lbl) { $lbl.Text = $(if ($Status) { $Status } else { "Aborted" }) }
            if ($btn) {
                $btn.Text = "Close"
                $btn.Enabled = $true
            }
        }
        [System.Windows.Forms.Application]::DoEvents()
    } catch {}
}

function Start-GameTDBCoverPackDownload {
    param(
        [string]$Platform,
        [string[]]$CoverTypes,
        [string]$Region,
        [string]$OutBase,
        [switch]$CollectionOnly,
        [switch]$OnlyMissing,
        [switch]$RegionFallback,
        [switch]$SaveIntoMedia,
        [switch]$WriteAssets,
        [switch]$UseBoxFull,
        [switch]$RenameToTitle,
        [switch]$ConvertToPng
    )
    if (-not $CoverTypes -or $CoverTypes.Count -eq 0) {
        Log-Message "No cover types selected." "Red"
        return
    }

    $info = $script:gameTdbPlatforms[$Platform]
    if (-not $info) {
        Log-Message "Unknown platform: $Platform" "Red"
        return
    }
    $script:lastGameTdbPlatform = $Platform
    $artPlat = if ($Platform -eq "gamecube") { "wii" } else { $Platform }
    $artInfo = $script:gameTdbPlatforms[$artPlat]

    $col = $null
    if ($CollectionOnly -or $SaveIntoMedia -or $WriteAssets) {
        $col = Get-Col
        if (-not $col) {
            Log-Message "No collection selected." "Red"
            return
        }
    }

    $regionsToTry = New-Object System.Collections.ArrayList
    [void]$regionsToTry.Add($Region)
    if ($RegionFallback) {
        $prefer = @("US", "EN", "AU", "JP", "JA", "FR", "DE", "ES", "IT", "NL", "PT", "SE", "DK", "NO", "FI", "RU", "KO", "ZH", "CA")
        foreach ($r in $prefer) {
            if ($r -ne $Region -and -not $regionsToTry.Contains($r)) { [void]$regionsToTry.Add($r) }
        }
        foreach ($r in $script:gameTdbRegions) {
            if (-not $regionsToTry.Contains($r)) { [void]$regionsToTry.Add($r) }
        }
    }

    Log-Message "========================================" "Cyan"
    Log-Message "GAMETDB COVER PACK - $($info.Label)" "Cyan"
    Log-Message ("Types: " + ($CoverTypes -join ", ")) "White"
    Log-Message ("Region: $Region" + $(if ($RegionFallback) { " (+ fallback)" } else { "" })) "White"
    if ($CollectionOnly) { Log-Message "Scope: current collection only" "Cyan" }
    if ($OnlyMissing) { Log-Message "Mode: only missing art" "Cyan" }
    if ($SaveIntoMedia) { Log-Message "Output: collection media folders" "Cyan" }
    if ($WriteAssets) { Log-Message "Will write asset paths to metadata" "Cyan" }
    if ($UseBoxFull) { Log-Message "Full covers folder: boxFull (assets.boxFull)" "Cyan" }
    if ($RenameToTitle) { Log-Message "Rename to game titles: on" "Cyan" }
    if ($ConvertToPng) { Log-Message "Convert to PNG: on" "Cyan" }
    Log-Message "========================================" "Cyan"

    $prog = $null
    $assetUpdates = @{}
    $failRows = New-Object System.Collections.ArrayList
    $pct = 0

    try {
        $prog = Show-GameTDBProgressWindow -Title "GameTDB: $($info.Label)"
        Update-GameTDBProgressWindow -Form $prog -Percent 0 -Status "Fetching titles list..."

        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "MetadataRepairTool/$($script:version)")
        Log-Message "Fetching titles: $($info.TitlesUrl)" "White"
        $data = $wc.DownloadString($info.TitlesUrl)
        $lines = @($data -split "`r?`n" | Where-Object { $_ -match '^\s*[A-Z0-9]+\s*=' })
        $allIds = New-Object System.Collections.ArrayList
        $titleById = @{}
        foreach ($line in $lines) {
            if ($line -match '^\s*([A-Z0-9]+)\s*=\s*(.+)$') {
                $id = $matches[1].Trim()
                $title = $matches[2].Trim()
                if ($info.IdFilter -eq "gamecube") {
                    if ($id.Length -ne 6 -or $id[0] -ne 'G') { continue }
                } elseif ($Platform -eq "wii") {
                    if ($id.Length -eq 6 -and $id[0] -eq 'G') { continue }
                }
                [void]$allIds.Add($id)
                if ($title) { $titleById[$id.ToUpperInvariant()] = $title }
            } elseif ($line -match '^\s*([A-Z0-9]+)\s*=') {
                $id = $matches[1].Trim()
                if ($info.IdFilter -eq "gamecube") {
                    if ($id.Length -ne 6 -or $id[0] -ne 'G') { continue }
                } elseif ($Platform -eq "wii") {
                    if ($id.Length -eq 6 -and $id[0] -eq 'G') { continue }
                }
                [void]$allIds.Add($id)
            }
        }
        Log-Message "Titles list IDs: $($allIds.Count) (names: $($titleById.Count))" "Cyan"

        $collectionMap = @{}
        if ($CollectionOnly -or $OnlyMissing -or $WriteAssets) {
            $collectionMap = Get-CollectionGameIdMap
            Log-Message "Collection game_id entries: $($collectionMap.Count)" "Cyan"
        }

        $ids = New-Object System.Collections.ArrayList
        if ($CollectionOnly) {
            if ($collectionMap.Count -eq 0) {
                Log-Message "No game_id fields in this collection. Add IDs first or uncheck Collection only." "Yellow"
                Update-GameTDBProgressWindow -Form $prog -Percent 0 -Status "No game_id in collection" -Aborted
                $wc.Dispose()
                return
            }
            # Only keep collection game_ids that exist in THIS platform's titles list.
            # Prevents e.g. a Wii collection driving Nintendo DS cover downloads.
            $titleSet = @{}
            foreach ($id in $allIds) { $titleSet[$id.ToUpperInvariant()] = $true }
            $matched = 0
            $skippedPlat = 0
            foreach ($sid in @($collectionMap.Keys)) {
                $key = $sid.ToUpperInvariant()
                if ($titleSet.ContainsKey($key)) {
                    [void]$ids.Add($key)
                    $matched++
                } else {
                    $skippedPlat++
                }
            }
            $ids = [System.Collections.ArrayList]@($ids | Sort-Object -Unique)
            Log-Message ("Collection IDs on this platform: {0}  |  skipped (wrong platform / not in titles): {1}" -f $matched, $skippedPlat) "Cyan"
            if ($ids.Count -eq 0) {
                Log-Message "No collection game_id values match the selected platform ($Platform). Pick the matching system, or uncheck Collection only." "Yellow"
                Update-GameTDBProgressWindow -Form $prog -Percent 0 -Status "No matching IDs for platform" -Aborted
                $wc.Dispose()
                return
            }
        } else {
            foreach ($id in $allIds) { [void]$ids.Add($id) }
        }

        $total = $ids.Count * $CoverTypes.Count
        if ($total -eq 0) {
            Log-Message "Nothing to download." "Yellow"
            Update-GameTDBProgressWindow -Form $prog -Percent 0 -Status "Nothing to download" -Aborted
            $wc.Dispose()
            return
        }
        Log-Message "Jobs: $($ids.Count) ID(s) x $($CoverTypes.Count) type(s) = $total" "Cyan"
        Update-GameTDBProgressWindow -Form $prog -Percent 0 -Status "0 / $total  (starting...)"

        $ok = 0; $skip = 0; $fail = 0; $n = 0
        $aborted = $false

        foreach ($id in $ids) {
            if ($script:gtdbCoverPackAbort) {
                $aborted = $true
                Log-Message "Abort requested - stopping cover pack download." "Yellow"
                break
            }

            $idUpper = $id.ToUpperInvariant()
            $entry = $null
            if ($collectionMap.ContainsKey($idUpper)) { $entry = $collectionMap[$idUpper] }

            foreach ($coverType in $CoverTypes) {
                if ($script:gtdbCoverPackAbort) {
                    $aborted = $true
                    break
                }
                $n++
                $pct = if ($total -gt 0) { [int](($n * 100) / $total) } else { 100 }
                if ($n -eq 1 -or ($n % 10 -eq 0) -or $n -eq $total) {
                    Update-GameTDBProgressWindow -Form $prog -Percent $pct -Status (
                        "{0} / {1}   ok={2}  skip={3}  fail={4}" -f $n, $total, $ok, $skip, $fail)
                }
                if ($n % 50 -eq 0) {
                    Log-Message "Progress: $n / $total (ok=$ok skip=$skip fail=$fail)" "White"
                }
                [System.Windows.Forms.Application]::DoEvents()

                $ext = Get-GameTDBCoverExt $artPlat $coverType
                $folderName = Get-GameTDBCoverTypeFolder -CoverType $coverType -UseBoxFull:$UseBoxFull
                $assetKey = Get-GameTDBCoverTypeAssetKey -CoverType $coverType -UseBoxFull:$UseBoxFull

                # Only-missing: skip when this cover type's asset already exists for the game.
                # Supports box2dfront (assets.box_front), Unicovers boxFull (assets.boxFull),
                # alternate Box Full (assets.box_full), and box backs.
                if ($OnlyMissing -and $entry) {
                    $alreadyHas = $false
                    if ($entry.PresentAssets -and $entry.PresentAssets.ContainsKey($assetKey)) {
                        $alreadyHas = $true
                    } elseif ($assetKey -eq "assets.box_front" -and $entry.HasBoxFront) {
                        $alreadyHas = $true
                    } elseif ($assetKey -eq "assets.boxFull" -and $entry.HasBoxFull) {
                        $alreadyHas = $true
                    } elseif ($assetKey -eq "assets.box_full" -and $entry.HasBox_Full) {
                        $alreadyHas = $true
                    } elseif ($assetKey -eq "assets.box_back" -and $entry.HasBoxBack) {
                        $alreadyHas = $true
                    }
                    if ($alreadyHas) {
                        $skip++
                        continue
                    }
                }

                if ($SaveIntoMedia -and $col -and $col.mediaPath) {
                    $outDir = Join-Path $col.mediaPath $folderName
                } else {
                    $outDir = Join-Path $OutBase (Join-Path $info.Label (Join-Path $coverType $Region))
                }
                if (-not (Test-Path $outDir)) {
                    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
                }

                $dest = Join-Path $outDir "$id.$ext"
                if (Test-Path $dest) {
                    $skip++
                    if ($WriteAssets -and $col) {
                        if (-not $assetUpdates.ContainsKey($idUpper)) { $assetUpdates[$idUpper] = @{} }
                        $rel = $dest
                        try {
                            $metaParent = Split-Path $col.metadataPath -Parent
                            if ($dest.StartsWith($metaParent, [StringComparison]::OrdinalIgnoreCase)) {
                                $rel = $dest.Substring($metaParent.Length).TrimStart('\', '/').Replace('\', '/')
                            }
                        } catch {}
                        $assetUpdates[$idUpper][$assetKey] = $rel
                    }
                    continue
                }

                $saved = $false
                $lastUrl = ""
                foreach ($reg in $regionsToTry) {
                    $url = "https://art.gametdb.com/$($artInfo.ArtPath)/$coverType/$reg/$id.$ext"
                    $lastUrl = $url
                    try {
                        $wc.DownloadFile($url, $dest)
                        if ((Test-Path $dest) -and (Get-Item $dest).Length -gt 200) {
                            $ok++
                            $saved = $true
                            # Optional: rename to game title, then convert to PNG
                            $finalPath = $dest
                            try {
                                $gameTitle = $null
                                if ($titleById.ContainsKey($idUpper)) { $gameTitle = $titleById[$idUpper] }
                                elseif ($entry -and $entry.Title) { $gameTitle = $entry.Title }
                                if ($RenameToTitle -and $gameTitle) {
                                    $safe = Get-SafeGameFileName $gameTitle
                                    if ($safe) {
                                        $renamed = Join-Path $outDir ($safe + [System.IO.Path]::GetExtension($finalPath))
                                        if (-not (Test-Path -LiteralPath $renamed)) {
                                            Move-Item -LiteralPath $finalPath -Destination $renamed -Force
                                            $finalPath = $renamed
                                        } elseif ($renamed -ne $finalPath) {
                                            # Title file exists - keep ID name unless same path
                                        }
                                    }
                                }
                                if ($ConvertToPng) {
                                    $finalPath = Convert-ImageFileToPng -Path $finalPath
                                }
                                $dest = $finalPath
                            } catch {
                                Log-Message ("Post-process failed for {0}: {1}" -f $id, $_.Exception.Message) "Yellow"
                            }
                            if ($WriteAssets -and $col) {
                                if (-not $assetUpdates.ContainsKey($idUpper)) { $assetUpdates[$idUpper] = @{} }
                                $rel = $dest
                                try {
                                    $metaParent = Split-Path $col.metadataPath -Parent
                                    if ($dest.StartsWith($metaParent, [StringComparison]::OrdinalIgnoreCase)) {
                                        $rel = $dest.Substring($metaParent.Length).TrimStart('\', '/').Replace('\', '/')
                                    }
                                } catch {}
                                $assetUpdates[$idUpper][$assetKey] = $rel
                            }
                            break
                        } else {
                            if (Test-Path $dest) { Remove-Item $dest -Force -ErrorAction SilentlyContinue }
                        }
                    } catch {
                        if (Test-Path $dest) { Remove-Item $dest -Force -ErrorAction SilentlyContinue }
                    }
                }
                if (-not $saved) {
                    $fail++
                    [void]$failRows.Add([PSCustomObject]@{
                        Id     = $id
                        Type   = $coverType
                        Region = $Region
                        Url    = $lastUrl
                    })
                }
            }
        }
        $wc.Dispose()

        $reportDir = $null
        if ($SaveIntoMedia -and $col -and $col.mediaPath) {
            $reportDir = Get-ToolsFolder $col.mediaPath
        } elseif ($OutBase) {
            $reportDir = $OutBase
        }
        if ($failRows.Count -gt 0 -and $reportDir) {
            try {
                if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir -Force | Out-Null }
                $csvPath = Join-Path $reportDir "failed_covers.csv"
                $failRows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
                Log-Message "Fail report: $csvPath ($($failRows.Count) rows)" "Yellow"
            } catch {
                Log-Message "Could not write fail report: $_" "Yellow"
            }
        }

        if ($WriteAssets -and $col -and $assetUpdates.Count -gt 0) {
            try {
                Apply-GameTDBAssetUpdates -Updates $assetUpdates
            } catch {
                Log-Message "Asset path write error: $_" "Red"
            }
        }

        $summary = "Downloaded: $ok   Skipped: $skip   Missing: $fail"
        if ($aborted) {
            Log-Message "Aborted. $summary" "Yellow"
            Update-GameTDBProgressWindow -Form $prog -Percent $pct -Status "Aborted`n$summary" -Aborted
        } else {
            Log-Message "Done. $summary" "Green"
            if ($SaveIntoMedia -and $col) {
                Log-Message "Media: $($col.mediaPath)" "Cyan"
            } elseif ($OutBase) {
                Log-Message "Folder: $OutBase" "Cyan"
            }
            Update-GameTDBProgressWindow -Form $prog -Percent 100 -Status $summary -Completed
        }
        UpdateStats
    } catch {
        Log-Message "ERROR: $_" "Red"
        if ($prog -and -not $prog.IsDisposed) {
            Update-GameTDBProgressWindow -Form $prog -Percent 0 -Status "Error: $_" -Aborted
        }
    }
}

function Apply-GameTDBAssetUpdates {
    param([hashtable]$Updates)
    $c = Get-Col
    if (-not $c -or -not $Updates -or $Updates.Count -eq 0) { return }

    $p = $c.metadataPath
    if (-not (Test-Path $p)) { return }

    CreateBackup
    $content = Get-Content $p -Raw -ErrorAction Stop
    $norm = $content -replace "`r`n", "`n" -replace "`r", "`n"
    $parts = [regex]::Split($norm, '(?m)(?=^game:\s*)')
    $sb = New-Object System.Text.StringBuilder
    $count = 0

    foreach ($part in $parts) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        if ($part -match '(?m)^game:\s*') {
            $gid = $null
            if ($part -match '(?m)^game_id:\s*(\S+)') { $gid = $matches[1].Trim() }
            $short = $null
            if ($gid) {
                $short = Get-GameTDBShortId $gid
                if ($short) { $short = $short.ToUpperInvariant() }
            }
            if ($short -and $Updates.ContainsKey($short)) {
                $paths = $Updates[$short]
                foreach ($ak in @($paths.Keys)) {
                    $val = $paths[$ak]
                    if ([string]::IsNullOrWhiteSpace($val)) { continue }
                    $escapedKey = [regex]::Escape($ak)
                    if ($part -match "(?m)^${escapedKey}:\s*") {
                        $part = [regex]::Replace($part, "(?m)^${escapedKey}:\s*.*$", "${ak}: $val", 1)
                    } else {
                        if ($part -match '(?m)^game_id:\s*.+$') {
                            $part = [regex]::Replace($part, '((?m)^game_id:\s*.+$)', ('$1' + "`n${ak}: $val"), 1)
                        } else {
                            $part = [regex]::Replace($part, '((?m)^game:\s*.+$)', ('$1' + "`n${ak}: $val"), 1)
                        }
                    }
                    $count++
                }
            }
        }
        [void]$sb.Append($part.TrimEnd())
        [void]$sb.Append("`n")
    }

    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($p, ($sb.ToString().TrimEnd() + "`n"), $utf8)
    Log-Message "Wrote $count asset path field(s) for $($Updates.Count) game(s)" "Green"
    UpdateEditor
}

function Download-GameTDBCovers {
    $c = Get-Col
    if (-not $c) { return }
    
    Log-Message "========================================" "Cyan"
    Log-Message "DOWNLOADING GAMETDB COVERS" "Cyan"
    Log-Message "========================================" "Cyan"
    
    try {
        $bp = $c.mediaPath
        if ([string]::IsNullOrWhiteSpace($bp)) {
            Log-Message "ERROR: Media folder not set." "Red"
            return
        }
        $fp = Join-Path $bp "box2dfront"
        if (-not (Test-Path $fp)) {
            New-Item -ItemType Directory -Path $fp -Force | Out-Null
        }
        
        $p = $c.metadataPath
        $content = Get-Content $p -Raw
        $games = $content -split '(?=game: )' | Where-Object { $_ -match '^game: ' }
        
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "MetadataRepairTool/$($script:version)")
        $ok = 0
        $fail = 0
        $skip = 0
        
        foreach ($g in $games) {
            if ($g -match 'game: (.+?)(?:\r?\n|$)') {
                $name = $matches[1].Trim()
            } else { continue }
            
            if ($g -notmatch 'game_id:\s*(\S+)') {
                $skip++
                continue
            }
            $gid = $matches[1].Trim()
            $plat = Get-GameTDBPlatformKey $gid
            if (-not $plat) {
                $skip++
                continue
            }
            
            $safe = $name -replace '[^\w\s-]', '' -replace '\s+', ' ' -replace ' ', '_'
            $info = $script:gameTdbPlatforms[$plat]
            $dest = Join-Path $fp "$safe.$($info.Ext)"
            if (Test-Path $dest) {
                $skip++
                continue
            }
            
            $url = Build-GameTDBCoverUrl $gid "cover"
            if (-not $url) { $fail++; continue }
            
            try {
                $wc.DownloadFile($url, $dest)
                if ((Test-Path $dest) -and (Get-Item $dest).Length -gt 500) {
                    $ok++
                    Log-Message "  OK: $name <- $url" "Green"
                } else {
                    if (Test-Path $dest) { Remove-Item $dest -Force -ErrorAction SilentlyContinue }
                    $shortId = Get-GameTDBShortId $gid
                    $url2 = "https://art.gametdb.com/$($info.ArtPath)/cover/EN/$shortId.$($info.Ext)"
                    try {
                        $wc.DownloadFile($url2, $dest)
                        if ((Test-Path $dest) -and (Get-Item $dest).Length -gt 500) {
                            $ok++
                            Log-Message "  OK (EN): $name" "Green"
                        } else {
                            if (Test-Path $dest) { Remove-Item $dest -Force -ErrorAction SilentlyContinue }
                            $fail++
                            Log-Message "  MISS: $name ($gid)" "Yellow"
                        }
                    } catch {
                        if (Test-Path $dest) { Remove-Item $dest -Force -ErrorAction SilentlyContinue }
                        $fail++
                        Log-Message "  MISS: $name ($gid)" "Yellow"
                    }
                }
            } catch {
                $fail++
                Log-Message "  FAIL: $name - $_" "Red"
            }
        }
        
        $wc.Dispose()
        Log-Message "Downloaded: $ok  |  Missed: $fail  |  Skipped: $skip" "Cyan"
        Log-Message "Done!" "Green"
        UpdateStats
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

function Apply-GameTDBTitles {
    $c = Get-Col
    if (-not $c) { return }
    
    $plat = Select-GameTDBPlatform
    if (-not $plat) { return }
    
    $map = Load-GameTDBTitlesCache $plat
    if ($map.Count -eq 0) {
        Log-Message "No titles for $plat. Run Download Titles DB first." "Yellow"
        return
    }
    
    Log-Message "========================================" "Cyan"
    Log-Message "APPLYING GAMETDB TITLES ($plat)" "Cyan"
    Log-Message "========================================" "Cyan"
    
    try {
        $p = $c.metadataPath
        $content = Get-Content $p -Raw
        $games = $content -split '(?=game: )' | Where-Object { $_ -match '^game: ' }
        $updated = $content
        $count = 0
        
        foreach ($g in $games) {
            if ($g -match 'game: (.+?)(?:\r?\n|$)') {
                $name = $matches[1].Trim()
            } else { continue }
            if ($g -notmatch 'game_id:\s*(\S+)') { continue }
            $gid = $matches[1].Trim()
            $shortId = Get-GameTDBShortId $gid
            $newTitle = $null
            if ($map.ContainsKey($shortId)) { $newTitle = $map[$shortId] }
            elseif ($map.ContainsKey($gid)) { $newTitle = $map[$gid] }
            if (-not $newTitle) { continue }
            if ($newTitle -eq $name) { continue }
            
            $updated = $updated -replace [regex]::Escape("game: $name"), "game: $newTitle"
            $count++
            Log-Message "  $name -> $newTitle" "Green"
        }
        
        if ($count -gt 0) {
            CreateBackup
            $updated | Out-File -FilePath $p -Encoding UTF8
            Log-Message "Renamed: $count games from GameTDB titles" "Green"
            UpdateEditor
        } else {
            Log-Message "No title changes applied (need game_id matches)." "Yellow"
        }
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

function Open-GameTDBPage {
    $gameId = ""
    if ($script:fieldControls -and $script:fieldControls.ContainsKey("game_id")) {
        $gameId = $script:fieldControls["game_id"].Text.Trim()
    }
    if ([string]::IsNullOrWhiteSpace($gameId)) {
        $input = Show-InputBox "Enter Game ID (e.g. RMGE01):" "Open GameTDB" ""
        if ([string]::IsNullOrWhiteSpace($input)) { return }
        $gameId = $input.Trim()
    }
    
    $shortId = Get-GameTDBShortId $gameId
    $plat = Get-GameTDBPlatformKey $gameId
    if (-not $plat) {
        $url = "https://www.gametdb.com/Wii/$shortId"
    } else {
        $pathMap = @{
            "wii" = "Wii"; "wiiu" = "WiiU"; "switch" = "Switch"
            "3ds" = "3DS"; "ds" = "DS"; "ps3" = "PS3"
        }
        $seg = if ($pathMap.ContainsKey($plat)) { $pathMap[$plat] } else { "Wii" }
        $url = "https://www.gametdb.com/$seg/$shortId"
    }
    Log-Message "Opening: $url" "Cyan"
    Start-Process $url
}

function Fill-GameTDBBoxArtPaths {
    $c = Get-Col
    if (-not $c) { return }
    
    Log-Message "========================================" "Cyan"
    Log-Message "FILLING BOX ART PATHS FROM LOCAL FILES" "Cyan"
    Log-Message "========================================" "Cyan"
    
    try {
        $p = $c.metadataPath
        $bp = $c.mediaPath
        if ([string]::IsNullOrWhiteSpace($bp)) {
            Log-Message "ERROR: Media folder empty." "Red"
            return
        }
        $fp = Join-Path $bp "box2dfront"
        $tp = Join-Path $bp "box2dThumb"
        if (-not (Test-Path $fp)) {
            Log-Message "ERROR: box2dfront not found: $fp" "Red"
            return
        }
        if (-not (Test-Path $tp)) {
            New-Item -ItemType Directory -Path $tp -Force | Out-Null
        }
        
        $images = @()
        $images += @(Get-ChildItem $fp -Filter "*.png" -ErrorAction SilentlyContinue | ForEach-Object { $_.BaseName })
        $images += @(Get-ChildItem $fp -Filter "*.jpg" -ErrorAction SilentlyContinue | ForEach-Object { $_.BaseName })
        
        $content = Get-Content $p -Raw
        $games = $content -split '(?=game: )' | Where-Object { $_ -match '^game: ' }
        $updated = $content
        $count = 0
        
        foreach ($g in $games) {
            if ($g -match 'game: (.+?)(?:\r?\n|$)') {
                $name = $matches[1].Trim()
            } else { continue }
            if ($g -match 'assets\.box_front:') { continue }
            
            $safe = $name -replace '[^\w\s-]', '' -replace '\s+', ' ' -replace ' ', '_'
            if ($images -contains $safe) {
                $ext = "png"
                if (-not (Test-Path (Join-Path $fp "$safe.png"))) {
                    if (Test-Path (Join-Path $fp "$safe.jpg")) { $ext = "jpg" }
                }
                $front = Join-Path $fp "$safe.$ext"
                $thumb = Join-Path $tp "${safe}_thumb.$ext"
                $new = "`nassets.box_front: $front`nassets.box_front_thumb: $thumb"
                $updated = $updated -replace "($([regex]::Escape($name)).*?)(?=\r?\nfile:|\Z)", ('$1' + $new)
                $count++
                Log-Message "  Linked: $name" "Green"
            }
        }
        
        if ($count -gt 0) {
            CreateBackup
            $updated | Out-File -FilePath $p -Encoding UTF8
            Log-Message "Linked box art on $count games" "Green"
            UpdateEditor
        } else {
            Log-Message "No new box art links. Download covers first or match filenames to game names." "Yellow"
        }
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}



try {
    Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
} catch {}

function Show-InputBox {
    param([string]$Prompt, [string]$Title, [string]$Default = "")
    try {
        $r = [Microsoft.VisualBasic.Interaction]::InputBox($Prompt, $Title, $Default)
        return $r
    } catch {
        $dlg = New-Object System.Windows.Forms.Form
        $dlg.Text = $Title
        $dlg.Size = New-Object System.Drawing.Size(420, 160)
        $dlg.StartPosition = "CenterParent"
        $dlg.FormBorderStyle = "FixedDialog"
        $dlg.MaximizeBox = $false
        $dlg.BackColor = $script:theme.background
        $dlg.ForeColor = $script:theme.text
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $Prompt
        $lbl.Location = New-Object System.Drawing.Point(15, 15)
        $lbl.Size = New-Object System.Drawing.Size(380, 30)
        $dlg.Controls.Add($lbl)
        $tb = New-Object System.Windows.Forms.TextBox
        $tb.Location = New-Object System.Drawing.Point(15, 50)
        $tb.Size = New-Object System.Drawing.Size(375, 25)
        $tb.Text = $Default
        $tb.BackColor = $script:theme.editor
        $tb.ForeColor = $script:theme.text
        $dlg.Controls.Add($tb)
        $script:__inputResult = ""
        $ok = Create-Button "OK" 120 90 80 28
        $ok.Add_Click({ $script:__inputResult = $tb.Text; $dlg.Close() })
        $dlg.Controls.Add($ok)
        $cn = Create-Button "Cancel" 220 90 80 28
        $cn.Add_Click({ $script:__inputResult = ""; $dlg.Close() })
        $dlg.Controls.Add($cn)
        $dlg.ShowDialog() | Out-Null
        return $script:__inputResult
    }
}

# ============================================================================
# BUILDER / REPAIR HELPERS
# ============================================================================
function Get-GameNameFromFileName {
    param([string]$FileName)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $base = $base -replace '\(.*?\)', '' -replace '\[.*?\]', ''
    $base = $base -replace '_', ' '
    $base = $base.Trim()
    $base = $base -replace '\s+', ' '
    return $base
}

function Get-RomExtensions {
    return @(
        '.sfc', '.smc', '.fig', '.swc',
        '.nes', '.fds', '.unf',
        '.gb', '.gbc', '.gba',
        '.n64', '.z64', '.v64',
        '.iso', '.cso', '.chd', '.rvz', '.wud', '.wux', '.wbfs', '.gcm', '.gcz',
        '.nsp', '.xci',
        '.3ds', '.cia', '.nds',
        '.pce', '.sgx',
        '.md', '.gen', '.smd', '.bin',
        '.cue', '.gdi',
        '.ngp', '.ngc', '.npc', '.neo',
        '.pbp', '.vpk',
        '.zip', '.7z', '.rar'
    )
}

function Scan-GamesFromFolder {
    $c = Get-Col
    $start = $null
    if ($c -and $c.metadataPath) { $start = Split-Path $c.metadataPath -Parent }
    
    $fd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fd.Description = "Select folder with ROMs / game files (names become the game list)"
    $fd.ShowNewFolderButton = $false
    if ($start -and (Test-Path $start)) { $fd.SelectedPath = $start }
    if ($fd.ShowDialog() -ne "OK") { return }
    
    $folder = $fd.SelectedPath
    Log-Message "========================================" "Cyan"
    Log-Message "SCAN FOLDER FOR GAMES" "Cyan"
    Log-Message "========================================" "Cyan"
    Log-Message "Folder: $folder" "White"
    
    try {
        $exts = Get-RomExtensions
        $files = @(Get-ChildItem $folder -File -ErrorAction SilentlyContinue | Where-Object {
            $exts -contains $_.Extension.ToLowerInvariant()
        })
        $files += @(Get-ChildItem $folder -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            Get-ChildItem $_.FullName -File -ErrorAction SilentlyContinue | Where-Object {
                $exts -contains $_.Extension.ToLowerInvariant()
            }
        })
        
        $names = @()
        $seen = @{}
        foreach ($f in $files) {
            $n = Get-GameNameFromFileName $f.Name
            if ([string]::IsNullOrWhiteSpace($n)) { continue }
            $key = $n.ToLowerInvariant()
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $names += $n
        }
        $names = @($names | Sort-Object)
        
        $outDir = $folder
        if ($c -and $c.mediaPath) { $outDir = Get-ToolsFolder $c.mediaPath }
        $outFile = Join-Path $outDir "games_from_folder.txt"
        $names | Out-File -FilePath $outFile -Encoding UTF8
        
        $pathsFile = Join-Path $outDir "games_from_folder_paths.txt"
        $pathLines = @()
        foreach ($f in $files) {
            $n = Get-GameNameFromFileName $f.Name
            if ($n) { $pathLines += "$n|$($f.FullName)" }
        }
        $pathLines | Sort-Object -Unique | Out-File -FilePath $pathsFile -Encoding UTF8
        
        Log-Message "Found $($names.Count) unique game names from $($files.Count) files" "Green"
        Log-Message "Saved names: $outFile" "Cyan"
        Log-Message "Saved name|path: $pathsFile" "Cyan"
        $names | Select-Object -First 15 | ForEach-Object { Log-Message "  $_" "White" }
        if ($names.Count -gt 15) { Log-Message "  ... and $($names.Count - 15) more" "White" }
        Log-Message "Next: Builder -> Build Meta from Folder, or mapping + Download Covers" "Yellow"
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

function Export-GameList {
    $c = Get-Col
    if (-not $c) { return }
    try {
        $p = $c.metadataPath
        $content = Get-Content $p -Raw
        $games = $content -split '(?=game: )' | Where-Object { $_ -match '^game: ' }
        $names = @()
        foreach ($g in $games) {
            if ($g -match 'game: (.+?)(?:\r?\n|$)') {
                $names += $matches[1].Trim()
            }
        }
        $out = Join-Path (Get-ToolsFolder $c.mediaPath) "game_list_export.txt"
        $names | Out-File -FilePath $out -Encoding UTF8
        Log-Message "Exported $($names.Count) games to: $out" "Green"
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

function Export-MissingCoversList {
    $c = Get-Col
    if (-not $c) { return }
    FindMissing
    try {
        $p = $c.metadataPath
        $missingFile = Join-Path (Get-ToolsFolder $c.mediaPath) "missing_covers.txt"
        if (Test-Path $missingFile) {
            Log-Message "Missing list ready: $missingFile" "Cyan"
        }
    } catch {}
}

function Import-GamesFromList {
    $c = Get-Col
    if (-not $c) { return }
    $of = New-Object System.Windows.Forms.OpenFileDialog
    $of.Title = "Select game list (one title per line, or Name|path)"
    $of.Filter = "Text Files (*.txt)|*.txt|All Files (*.*)|*.*"
    $metaDir = Split-Path $c.metadataPath -Parent
    if (Test-Path $metaDir) { $of.InitialDirectory = $metaDir }
    if ($of.ShowDialog() -ne "OK") { return }
    
    Log-Message "========================================" "Cyan"
    Log-Message "IMPORT GAMES FROM LIST" "Cyan"
    Log-Message "========================================" "Cyan"
    try {
        $p = $c.metadataPath
        $content = Get-Content $p -Raw
        if ($null -eq $content) { $content = "" }
        $existing = @{}
        foreach ($m in [regex]::Matches($content, '(?m)^game: (.+)$')) {
            $existing[$m.Groups[1].Value.Trim().ToLowerInvariant()] = $true
        }
        
        $added = 0
        $blocks = New-Object System.Collections.ArrayList
        foreach ($line in Get-Content $of.FileName) {
            $line = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
            $name = $line
            $filePath = ""
            if ($line -match '^(.+?)\|(.+)$') {
                $name = $matches[1].Trim()
                $filePath = $matches[2].Trim()
            }
            $key = $name.ToLowerInvariant()
            if ($existing.ContainsKey($key)) { continue }
            $existing[$key] = $true
            $block = "game: $name`n"
            if ($filePath) { $block += "file: $filePath`n" }
            $block += "`n"
            [void]$blocks.Add($block)
            $added++
        }
        
        if ($added -eq 0) {
            Log-Message "No new games to import (all already present or list empty)." "Yellow"
            return
        }
        
        CreateBackup
        $newContent = $content.TrimEnd() + "`r`n`r`n" + ($blocks -join "")
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($p, $newContent, $utf8)
        Log-Message "Imported $added new game entries" "Green"
        UpdateEditor
        UpdateStats
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

function Build-MetadataFromFolder {
    $c = Get-Col
    if (-not $c) { return }
    
    $result = [System.Windows.Forms.MessageBox]::Show(
        "Scan a folder for ROM/game files and ADD any missing games to the current metadata?`n`nExisting games are left unchanged.",
        "Build Meta from Folder",
        "YesNo",
        "Question"
    )
    if ($result -ne "Yes") { return }
    
    Scan-GamesFromFolder
    
    $metaDir = Split-Path $c.metadataPath -Parent
    $toolsDir = Get-ToolsFolder $c.mediaPath
    $pathsFile = Join-Path $toolsDir "games_from_folder_paths.txt"
    if (-not (Test-Path $pathsFile)) {
        $of = New-Object System.Windows.Forms.OpenFileDialog
        $of.Title = "Select games_from_folder_paths.txt"
        $of.Filter = "Text (*.txt)|*.txt"
        $of.InitialDirectory = $toolsDir
        if ($of.ShowDialog() -eq "OK") { $pathsFile = $of.FileName }
        else { return }
    }
    
    try {
        $p = $c.metadataPath
        $content = Get-Content $p -Raw
        if ($null -eq $content) { $content = "" }
        $existing = @{}
        foreach ($m in [regex]::Matches($content, '(?m)^game: (.+)$')) {
            $existing[$m.Groups[1].Value.Trim().ToLowerInvariant()] = $true
        }
        $added = 0
        $blocks = New-Object System.Collections.ArrayList
        foreach ($line in Get-Content $pathsFile) {
            if ($line -match '^(.+?)\|(.+)$') {
                $name = $matches[1].Trim()
                $filePath = $matches[2].Trim()
                $key = $name.ToLowerInvariant()
                if ($existing.ContainsKey($key)) { continue }
                $existing[$key] = $true
                [void]$blocks.Add("game: $name`nfile: $filePath`n`n")
                $added++
            }
        }
        if ($added -eq 0) {
            Log-Message "No new games to add from folder scan." "Yellow"
            return
        }
        CreateBackup
        $newContent = $content.TrimEnd() + "`r`n`r`n" + ($blocks -join "")
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($p, $newContent, $utf8)
        Log-Message "Built metadata: added $added games from folder" "Green"
        UpdateEditor
        UpdateStats
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

function Sync-FilePathsFromFolder {
    $c = Get-Col
    if (-not $c) { return }
    
    $fd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fd.Description = "Select folder containing ROM files to match against game titles"
    if ($c.metadataPath) {
        $parent = Split-Path $c.metadataPath -Parent
        if (Test-Path $parent) { $fd.SelectedPath = $parent }
    }
    if ($fd.ShowDialog() -ne "OK") { return }
    
    Log-Message "========================================" "Cyan"
    Log-Message "SYNC FILE PATHS FROM FOLDER" "Cyan"
    Log-Message "========================================" "Cyan"
    try {
        $exts = Get-RomExtensions
        $files = @(Get-ChildItem $fd.SelectedPath -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
            $exts -contains $_.Extension.ToLowerInvariant()
        })
        $byNorm = @{}
        foreach ($f in $files) {
            $n = Get-GameNameFromFileName $f.Name
            $norm = ($n -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
            if ($norm.Length -ge 3 -and -not $byNorm.ContainsKey($norm)) {
                $byNorm[$norm] = $f.FullName
            }
        }
        
        $p = $c.metadataPath
        $content = Get-Content $p -Raw
        $games = $content -split '(?=game: )' | Where-Object { $_ -match '^game: ' }
        $updated = $content
        $count = 0
        
        foreach ($g in $games) {
            if ($g -match 'game: (.+?)(?:\r?\n|$)') { $name = $matches[1].Trim() } else { continue }
            $norm = ($name -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
            if (-not $byNorm.ContainsKey($norm)) { continue }
            $romPath = $byNorm[$norm]
            $escaped = [regex]::Escape($name)
            if ($g -match '(?m)^file:\s*.+$') {
                $updated = [regex]::Replace($updated, "(?m)(game: $escaped(?:\r?\n(?:(?!game: ).*\r?\n)*?)file:\s*).+", ('${1}' + $romPath), 1)
            } else {
                $updated = [regex]::Replace($updated, "(game: $escaped\r?\n)", ('${1}' + "file: $romPath`n"), 1)
            }
            $count++
            Log-Message "  $name -> $(Split-Path $romPath -Leaf)" "Green"
        }
        
        CreateBackup
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($p, $updated, $utf8)
        Log-Message "Synced file paths for $count games" "Green"
        UpdateEditor
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

function Download-CoversFromMapping {
    $c = Get-Col
    if (-not $c) { return }
    
    $metaDir = Split-Path $c.metadataPath -Parent
    $bp = $c.mediaPath
    $mapFile = Resolve-ToolsFile $bp "sns_mappings.txt" $metaDir
    if (-not ($mapFile -and (Test-Path $mapFile))) {
        $mapFile = Resolve-ToolsFile $bp "game_id_mappings.txt" $metaDir
    }
    if (-not ($mapFile -and (Test-Path $mapFile))) {
        Log-Message "No sns_mappings.txt or game_id_mappings.txt found. Create a mapping first." "Red"
        return
    }
    
    if ([string]::IsNullOrWhiteSpace($bp)) {
        Log-Message "Media folder not set." "Red"
        return
    }
    $fp = Join-Path $bp "box2dfront"
    if (-not (Test-Path $fp)) { New-Item -ItemType Directory -Path $fp -Force | Out-Null }
    
    Log-Message "========================================" "Cyan"
    Log-Message "DOWNLOAD COVERS FROM MAPPING" "Cyan"
    Log-Message "========================================" "Cyan"
    Log-Message "Mapping: $mapFile" "White"
    
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "MetadataRepairTool/$($script:version)")
        $ok = 0; $fail = 0; $skip = 0
        
        foreach ($line in Get-Content $mapFile) {
            if ($line -notmatch '^(.+?)=(.+)$') { continue }
            $name = $matches[1].Trim()
            $id = $matches[2].Trim()
            
            $have = $false
            foreach ($lc in @((Join-Path $fp "$id.png"), (Join-Path $fp "$id.jpg"))) {
                if (Test-Path $lc) { $have = $true; break }
            }
            if ($have) { $skip++; continue }
            
            $urls = @()
            if ($id -match '^SNS-') {
                $urls += "https://art.gametdb.com/snes/cover/US/$id.png"
                $urls += "https://art.gametdb.com/snes/cover/EN/$id.png"
                $urls += "https://art.gametdb.com/snes/coverfull/US/$id.png"
            } elseif ($id -match '^[A-Z0-9]{4,16}$') {
                $plat = Get-GameTDBPlatformKey $id
                $region = Get-GameTDBRegionCode $id
                $short = Get-GameTDBShortId $id
                if ($plat -and $short) {
                    $urls += "https://art.gametdb.com/$plat/cover/$region/$short.png"
                    $urls += "https://art.gametdb.com/$plat/cover/US/$short.png"
                    $urls += "https://art.gametdb.com/$plat/cover/EN/$short.png"
                }
            }
            
            $saved = $false
            foreach ($url in $urls) {
                $dest = Join-Path $fp "$id.png"
                try {
                    $wc.DownloadFile($url, $dest)
                    if ((Test-Path $dest) -and ((Get-Item $dest).Length -gt 500)) {
                        Log-Message "  OK: $name <- $url" "Green"
                        $ok++
                        $saved = $true
                        break
                    } else {
                        if (Test-Path $dest) { Remove-Item $dest -Force -ErrorAction SilentlyContinue }
                    }
                } catch {
                    if (Test-Path $dest) { Remove-Item $dest -Force -ErrorAction SilentlyContinue }
                }
            }
            if (-not $saved) {
                $fail++
                Log-Message "  FAIL: $name ($id)" "Yellow"
            }
        }
        
        Log-Message "Downloaded: $ok | Failed: $fail | Already had: $skip" "Cyan"
        Log-Message "Next: Add Box Art (Mapping) then Save Changes" "Yellow"
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

function Download-CoversFromGameList {
    $c = Get-Col
    if (-not $c) { return }
    
    $of = New-Object System.Windows.Forms.OpenFileDialog
    $of.Title = "Select game list (one name per line). Optional: Name=ID lines"
    $of.Filter = "Text Files (*.txt)|*.txt|All Files (*.*)|*.*"
    $metaDir = Split-Path $c.metadataPath -Parent
    $bp = $c.mediaPath
    $toolsDir = Get-ToolsFolder $bp
    if ($toolsDir -and (Test-Path $toolsDir)) { $of.InitialDirectory = $toolsDir }
    elseif (Test-Path $metaDir) { $of.InitialDirectory = $metaDir }
    if ($of.ShowDialog() -ne "OK") { return }
    
    Log-Message "========================================" "Cyan"
    Log-Message "DOWNLOAD COVERS FROM GAME LIST" "Cyan"
    Log-Message "========================================" "Cyan"
    
    $nameToId = @{}
    foreach ($mf in @("sns_mappings.txt", "game_id_mappings.txt")) {
        $mp = Resolve-ToolsFile $bp $mf $metaDir
        if (-not ($mp -and (Test-Path $mp))) { continue }
        foreach ($line in Get-Content $mp) {
            if ($line -match '^(.+?)=(.+)$') {
                $nameToId[$matches[1].Trim()] = $matches[2].Trim()
            }
        }
    }
    foreach ($tf in @("sns_titles.txt", "snes_titles.txt", "gametdb_titles.txt")) {
        $tp = Resolve-ToolsFile $bp $tf $metaDir
        if (-not ($tp -and (Test-Path $tp))) { continue }
        foreach ($line in Get-Content $tp) {
            if ($line -match '^(SNS-[A-Z0-9]{4}-[A-Z]{3,4})\s*[=:\t]\s*(.+)$') {
                $nameToId[$matches[2].Trim()] = $matches[1]
            }
        }
    }
    
    $toolsDir = Get-ToolsFolder $bp
    if (-not $toolsDir) { $toolsDir = $metaDir }
    $tempMap = Join-Path $toolsDir "_temp_cover_map.txt"
    $lines = @()
    $unresolved = @()
    foreach ($line in Get-Content $of.FileName) {
        $line = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
        if ($line -match '^(.+?)=(.+)$') {
            $lines += "$($matches[1].Trim())=$($matches[2].Trim())"
            continue
        }
        $name = $line
        if ($nameToId.ContainsKey($name)) {
            $lines += "$name=$($nameToId[$name])"
        } else {
            $unresolved += $name
        }
    }
    
    if ($lines.Count -eq 0) {
        Log-Message "No games with known IDs in the list." "Yellow"
        Log-Message "Create mapping/titles first so names resolve to SNS/Game IDs." "Yellow"
        if ($unresolved.Count -gt 0) {
            $u = Join-Path $toolsDir "unresolved_cover_names.txt"
            $unresolved | Out-File $u -Encoding UTF8
            Log-Message "Unresolved: $u" "Cyan"
        }
        return
    }
    
    $lines | Out-File $tempMap -Encoding UTF8
    Log-Message "Resolved $($lines.Count) names to IDs ($($unresolved.Count) unresolved)" "Cyan"
    
    $backupMap = Join-Path $toolsDir "sns_mappings.txt"
    $hadBackup = $false
    $bakPath = $null
    if (Test-Path $backupMap) {
        $bakPath = Join-Path $toolsDir "sns_mappings.txt.bak_tool"
        Copy-Item $backupMap $bakPath -Force
        $hadBackup = $true
    }
    try {
        Copy-Item $tempMap $backupMap -Force
        Download-CoversFromMapping
    } finally {
        if ($hadBackup -and $bakPath) {
            Copy-Item $bakPath $backupMap -Force
            Remove-Item $bakPath -Force -ErrorAction SilentlyContinue
        }
        Remove-Item $tempMap -Force -ErrorAction SilentlyContinue
        if ($unresolved.Count -gt 0) {
            $u = Join-Path $toolsDir "unresolved_cover_names.txt"
            $unresolved | Out-File $u -Encoding UTF8
            Log-Message "Unresolved names: $u" "Yellow"
        }
    }
}

function Strip-BoxArtPaths {
    $c = Get-Col
    if (-not $c) { return }
    $r = [System.Windows.Forms.MessageBox]::Show(
        "Remove ALL assets.box_front and assets.box_front_thumb lines from metadata?`nA backup will be created.",
        "Strip Box Art Paths",
        "YesNo",
        "Warning"
    )
    if ($r -ne "Yes") { return }
    try {
        $p = $c.metadataPath
        CreateBackup
        $content = Get-Content $p -Raw
        $updated = $content -replace '(?m)^assets\.box_front(_thumb)?:.*\r?\n', ''
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($p, $updated, $utf8)
        Log-Message "Stripped all box art paths from metadata" "Green"
        UpdateEditor
        UpdateStats
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

function Get-ImageExtensions {
    return @('.png', '.jpg', '.jpeg', '.bmp', '.gif', '.webp')
}

function Scan-TitlesFromCoverImages {
    $c = Get-Col
    $start = $null
    if ($c -and -not [string]::IsNullOrWhiteSpace($c.mediaPath)) {
        $try = Join-Path $c.mediaPath "box2dfront"
        if (Test-Path $try) { $start = $try }
        elseif (Test-Path $c.mediaPath) { $start = $c.mediaPath }
    }
    if (-not $start -and $c -and $c.metadataPath) {
        $start = Split-Path $c.metadataPath -Parent
    }
    
    $fd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fd.Description = "Select folder with cover images (names become titles)"
    $fd.ShowNewFolderButton = $false
    if ($start -and (Test-Path $start)) { $fd.SelectedPath = $start }
    if ($fd.ShowDialog() -ne "OK") { return }
    
    $folder = $fd.SelectedPath
    Log-Message "========================================" "Cyan"
    Log-Message "TITLES FROM COVER IMAGES" "Cyan"
    Log-Message "========================================" "Cyan"
    Log-Message "Folder: $folder" "White"
    
    try {
        $exts = Get-ImageExtensions
        $files = @(Get-ChildItem $folder -File -ErrorAction SilentlyContinue | Where-Object {
            $exts -contains $_.Extension.ToLowerInvariant()
        })
        
        $titles = @()
        $snsCodes = @()
        $seen = @{}
        foreach ($f in $files) {
            $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            if ($base -match '^(SNS|SNSP|SHVC|SFC)-[A-Z0-9]{2,6}(-[A-Z]{2,4})?$') {
                $snsCodes += $base.ToUpperInvariant()
                continue
            }
            $n = Get-GameNameFromFileName $f.Name
            if ([string]::IsNullOrWhiteSpace($n)) { continue }
            $key = $n.ToLowerInvariant()
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $titles += $n
        }
        $titles = @($titles | Sort-Object)
        $snsCodes = @($snsCodes | Sort-Object -Unique)
        
        $outDir = $folder
        if ($c -and $c.mediaPath) { $outDir = Get-ToolsFolder $c.mediaPath }
        
        $titlesFile = Join-Path $outDir "titles_from_covers.txt"
        $titles | Out-File -FilePath $titlesFile -Encoding UTF8
        
        if ($snsCodes.Count -gt 0) {
            $snsFile = Join-Path $outDir "sns_codes_from_images.txt"
            $snsCodes | Out-File -FilePath $snsFile -Encoding UTF8
            Update-SnsCodeList $snsCodes $snsFile
            Log-Message "Also found $($snsCodes.Count) SNS-style filenames -> SNS list updated" "Cyan"
        }
        
        Log-Message "Found $($titles.Count) game-title-style cover names" "Green"
        Log-Message "Saved: $titlesFile" "Cyan"
        $titles | Select-Object -First 15 | ForEach-Object { Log-Message "  $_" "White" }
        if ($titles.Count -gt 15) { Log-Message "  ... and $($titles.Count - 15) more" "White" }
        Log-Message "Next: Add Box Art (Game Name) if metadata titles match these names" "Yellow"
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

function Get-SnesHeaderOffsets {
    return @(0x7FC0, 0xFFC0, 0x81C0, 0x101C0, 0x40FFC0, 0x4101C0)
}

# ============================================================================
# READ SNES ROM HEADERS - FIXED VERSION (Detects bad headers)
# ============================================================================
function Read-SnesInternalTitle {
    param([string]$RomPath)
    try {
        $fi = Get-Item $RomPath -ErrorAction Stop
        if ($fi.Length -lt 0x8000) { return $null }
        $fs = [System.IO.File]::OpenRead($RomPath)
        try {
            $buf = New-Object byte[] 32
            foreach ($off in (Get-SnesHeaderOffsets)) {
                if ($off + 21 -gt $fi.Length) { continue }
                $fs.Position = $off
                $read = $fs.Read($buf, 0, 21)
                if ($read -lt 21) { continue }
                $chars = @()
                $ok = 0
                for ($i = 0; $i -lt 21; $i++) {
                    $b = $buf[$i]
                    if ($b -ge 32 -and $b -le 126) {
                        $chars += [char]$b
                        $ok++
                    } elseif ($b -eq 0) {
                        $chars += ' '
                    } else {
                        $chars += ' '
                    }
                }
                if ($ok -lt 4) { continue }
                $title = (-join $chars).Trim()
                if ($title.Length -lt 2) { continue }
                if ($title -match '[\x00-\x08\x0B\x0C\x0E-\x1F]') { continue }
                return $title
            }
        } finally {
            $fs.Close()
        }
    } catch {}
    return $null
}

function Test-ValidSnesHeader {
    param([string]$Header)
    
    if ([string]::IsNullOrWhiteSpace($Header)) { return $false }
    
    # Must be at least 3 characters
    if ($Header.Length -lt 3) { return $false }
    
    # Count letters (A-Z and a-z)
    $letters = ([regex]::Matches($Header, '[A-Za-z]')).Count
    if ($letters -lt 2) { return $false }
    
    # Check for control characters (ASCII 0-31)
    if ($Header -match '[\x00-\x1F]') { return $false }
    
    # Check for common garbage patterns
    $garbagePatterns = @(
        '^[^A-Za-z]+$',              # No letters at all
        '^[\s\.\-_,;:!?]+$',         # Only punctuation/spaces
        '^[0-9\s]+$',                # Only numbers/spaces
        '[\x7F-\xFF]'                # Extended ASCII (often garbage)
    )
    
    foreach ($pattern in $garbagePatterns) {
        if ($Header -match $pattern) { return $false }
    }
    
    return $true
}

function Read-SnesRomHeaders {
    $c = Get-Col
    $start = $null
    if ($c -and $c.metadataPath) {
        $start = Split-Path $c.metadataPath -Parent
    }
    
    $fd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fd.Description = "Select folder with SNES ROMs (.sfc/.smc) to read internal titles"
    $fd.ShowNewFolderButton = $false
    if ($start -and (Test-Path $start)) { $fd.SelectedPath = $start }
    if ($fd.ShowDialog() -ne "OK") { return }
    
    $folder = $fd.SelectedPath
    Log-Message "========================================" "Cyan"
    Log-Message "READ SNES ROM HEADERS" "Cyan"
    Log-Message "========================================" "Cyan"
    Log-Message "Folder: $folder" "White"
    
    try {
        $romExt = @('.sfc', '.smc', '.fig', '.swc')
        $files = @(Get-ChildItem $folder -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
            $romExt -contains $_.Extension.ToLowerInvariant()
        })
        if ($files.Count -eq 0) {
            Log-Message "No SNES ROM files found." "Yellow"
            return
        }
        
        $lines = @()
        $badHeaders = @()
        $ok = 0
        $bad = 0
        $empty = 0
        $badExamples = New-Object System.Collections.ArrayList
        
        foreach ($f in $files) {
            $internal = Read-SnesInternalTitle $f.FullName
            $fromName = Get-GameNameFromFileName $f.Name
            $isValid = Test-ValidSnesHeader $internal
            
            if ($internal) {
                if ($isValid) {
                    $ok++
                    $lines += "$fromName|$internal|VALID|$($f.FullName)"
                    Log-Message "  $fromName  <=  [$internal]  ✅ VALID" "Green"
                } else {
                    $bad++
                    $badHeaders += "$fromName|$internal|BAD|$($f.FullName)"
                    $lines += "$fromName|$internal|BAD|$($f.FullName)"
                    if ($badExamples.Count -lt 10) {
                        [void]$badExamples.Add("  $fromName -> [$internal]")
                    }
                    Log-Message "  $fromName  <=  [$internal]  ⚠️ BAD HEADER" "Red"
                }
            } else {
                $empty++
                $lines += "$fromName||EMPTY|$($f.FullName)"
                Log-Message "  $fromName  (header not read)  ⚠️ EMPTY HEADER" "Yellow"
            }
        }
        
        $outDir = $folder
        if ($c -and $c.mediaPath) { $outDir = Get-ToolsFolder $c.mediaPath }
        $outFile = Join-Path $outDir "snes_rom_headers.txt"
        $header = "# filename_title|internal_header_title|status|full_path"
        (@($header) + $lines) | Out-File -FilePath $outFile -Encoding UTF8
        
        $titleList = @()
        foreach ($line in $lines) {
            if ($line -match '^[^|]+\|([^|]+)\|') {
                $t = $matches[1].Trim()
                if ($t -and $t -ne "BAD" -and $t -ne "EMPTY") { $titleList += $t }
            }
        }
        $titleList = @($titleList | Sort-Object -Unique)
        $titlesOut = Join-Path $outDir "titles_from_rom_headers.txt"
        $titleList | Out-File -FilePath $titlesOut -Encoding UTF8
        
        # --- Bad headers list ---
        if ($badHeaders.Count -gt 0 -or $empty -gt 0) {
            $badOut = Join-Path $outDir "bad_rom_headers.txt"
            $badReport = @()
            $badReport += "# ROMs with BAD or EMPTY headers"
            $badReport += "# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            $badReport += "#"
            $badReport += "# These ROMs have corrupted or stripped headers."
            $badReport += "# Consider replacing them with clean No-Intro dumps."
            $badReport += "#"
            $badReport += "# format: filename|internal_header|status|full_path"
            $badReport += ""
            $badReport += $badHeaders
            $badReport | Out-File -FilePath $badOut -Encoding UTF8
            Log-Message "Bad headers list: $badOut" "Yellow"
        }
        
        Log-Message "----------------------------------------" "Cyan"
        Log-Message "READ SNES ROM HEADERS - COMPLETE" "Cyan"
        Log-Message "----------------------------------------" "Cyan"
        Log-Message "Total ROMs scanned: $($files.Count)" "White"
        Log-Message "Valid headers: $ok  ✅" "Green"
        Log-Message "Bad headers: $bad  ⚠️" "Red"
        Log-Message "Empty headers: $empty  ⚠️" "Yellow"
        
        if ($badExamples.Count -gt 0) {
            Log-Message "" "White"
            Log-Message "Bad header examples (first 10):" "Red"
            foreach ($ex in $badExamples) {
                Log-Message "  $ex" "Red"
            }
            if ($bad + $empty -gt 10) {
                Log-Message "  ... and $($bad + $empty - 10) more bad/empty headers" "Red"
            }
            Log-Message "" "White"
            Log-Message "Bad headers saved to: $badOut" "Yellow"
            Log-Message "Next: Replace bad ROMs with clean No-Intro dumps." "Yellow"
            Log-Message "Do NOT use bad headers to create metadata entries!" "Red"
        }
        
        Log-Message "Saved: $outFile" "Cyan"
        Log-Message "Titles list: $titlesOut" "Cyan"
        
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

function Download-SnsTitlesDatabase {
    $c = Get-Col
    $outDir = $null
    if ($c -and $c.mediaPath) { $outDir = Get-ToolsFolder $c.mediaPath }
    if (-not $outDir) {
        $fd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fd.Description = "Select folder to save sns_titles.txt"
        if ($fd.ShowDialog() -ne "OK") { return }
        $outDir = $fd.SelectedPath
    }
    
    Log-Message "========================================" "Cyan"
    Log-Message "DOWNLOAD SNS TITLES DATABASE" "Cyan"
    Log-Message "========================================" "Cyan"
    
    $outFile = Join-Path $outDir "sns_titles.txt"
    $rawJson = Join-Path $outDir "snes_titles_raw.json"
    
    $urls = @(
        "https://github.com/niemasd/GameDB-SNES/releases/latest/download/SNES.titles.json",
        "https://raw.githubusercontent.com/niemasd/GameDB-SNES/main/SNES.titles.json",
        "https://cdn.jsdelivr.net/gh/niemasd/GameDB-SNES@main/SNES.titles.json"
    )
    
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "MetadataRepairTool/$($script:version)")
        $jsonText = $null
        $usedUrl = $null
        foreach ($url in $urls) {
            try {
                Log-Message "Trying: $url" "White"
                $jsonText = $wc.DownloadString($url)
                if ($jsonText -and $jsonText.Length -gt 100) {
                    $usedUrl = $url
                    break
                }
            } catch {
                Log-Message "  failed: $($_.Exception.Message)" "Yellow"
            }
        }
        
        if (-not $jsonText) {
            Log-Message "Could not download titles database (offline or URL changed)." "Red"
            Log-Message "You can still place sns_titles.txt manually: SNS-XXXX-USA=Game Title" "Yellow"
            return
        }
        
        [System.IO.File]::WriteAllText($rawJson, $jsonText)
        Log-Message "Downloaded raw JSON ($([Math]::Round($jsonText.Length/1KB)) KB) from $usedUrl" "Green"
        
        $map = @{}
        $rx = [regex]'"((?:SNS|SNSP|SHVC|SFC)[-_A-Z0-9]+)"\s*:\s*"([^"]+)"'
        foreach ($m in $rx.Matches($jsonText)) {
            $id = $m.Groups[1].Value.Trim().ToUpperInvariant() -replace '_', '-'
            $title = $m.Groups[2].Value.Trim()
            if ($title.Length -lt 1) { continue }
            if ($id -match '^(SNS|SNSP|SHVC)-([A-Z0-9]{2,6})-([A-Z]{2,4})$') {
                $map["$($matches[1])-$($matches[2])-$($matches[3])"] = $title
            } elseif ($id -match '^(SNS|SNSP|SHVC)-([A-Z0-9]{2,6})$') {
                $map["$($matches[1])-$($matches[2])-USA"] = $title
            } else {
                $map[$id] = $title
            }
        }
        
        if ($map.Count -eq 0) {
            try {
                $obj = $jsonText | ConvertFrom-Json
                foreach ($prop in $obj.PSObject.Properties) {
                    $id = [string]$prop.Name
                    $title = [string]$prop.Value
                    if ($id -match 'SNS|SHVC|SNSP' -and $title) {
                        $map[$id.ToUpperInvariant()] = $title.Trim()
                    }
                }
            } catch {}
        }
        
        if ($map.Count -eq 0) {
            Log-Message "0 SNS-code entries found in this database - that's expected." "Yellow"
            Log-Message "GameDB-SNES keys its data by ROM checksum, not by SNS-XXXX-USA" "Yellow"
            Log-Message "product code (SNES carts never had unique serial numbers)." "Yellow"
            Log-Message "Raw checksum database saved: $rawJson" "Cyan"
            Log-Message "Next: SNS Code Tools -> Match ROMs by Checksum (uses this file directly)" "Green"
            return
        }
        
        $lines = @($map.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" })
        $lines | Out-File -FilePath $outFile -Encoding UTF8
        
        Log-Message "Wrote $($lines.Count) entries to: $outFile" "Green"
        Log-Message "Next: SNS Code Tools -> Map by Titles File (or Create SNS Mapping)" "Yellow"
        Log-Message "Then: Add Box Art (Mapping) or DL Covers from Mapping" "Yellow"
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

function Match-RomsByChecksum {
    # GameDB-SNES (the source behind "DL SNS Titles DB") does NOT key its
    # data by SNS-XXXX-USA product codes - SNES carts never had unique
    # serial numbers, so the project identifies games by CRC32 of the ROM
    # data instead (see snes_titles_raw.json: keys are 8-char hex CRC32s).
    #
    # This tool computes the real CRC32 of each ROM in a folder (stripping
    # the optional 512-byte copier header first, same as GameDB/GameID do)
    # and looks it up against that same database, then writes the result
    # as "<rom-filename-without-extension>=Title" - the exact KEY=Title
    # shape Rename-ImagesFromSnsCodes already reads from sns_titles.txt.
    # If your box art images share a base filename with their ROM (e.g.
    # both are "SNS-AMSE-USA"), the existing renamer will pick this up
    # with no other changes needed.
    $c = Get-Col
    $bp = $null
    if ($c -and $c.mediaPath) { $bp = $c.mediaPath }

    $fd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fd.Description = "Select folder with SNES ROMs (.sfc/.smc/.swc/.fig) to checksum-match"
    $fd.ShowNewFolderButton = $false
    if ($bp -and (Test-Path $bp)) { $fd.SelectedPath = $bp }
    if ($fd.ShowDialog() -ne "OK") { return }
    $romFolder = $fd.SelectedPath

    Log-Message "========================================" "Cyan"
    Log-Message "MATCH ROMS BY CHECKSUM (GameDB-SNES)" "Cyan"
    Log-Message "========================================" "Cyan"
    Log-Message "ROM folder: $romFolder" "White"

    try {
        # Locate (or download) the raw GameDB-SNES titles JSON, which is
        # keyed by CRC32 hex, e.g. "002c3021": "Akumajou Dracula ..."
        $outDir = $romFolder
        if ($c -and $c.mediaPath) { $outDir = Get-ToolsFolder $c.mediaPath }
        $rawJson = Join-Path $outDir "snes_titles_raw.json"
        $metaDir = $null
        if ($c -and $c.metadataPath) { $metaDir = Split-Path $c.metadataPath -Parent }
        if (-not (Test-Path $rawJson) -and $bp) {
            $found = Resolve-ToolsFile $bp "snes_titles_raw.json" $metaDir
            if ($found) { $rawJson = $found }
        }
        if (-not (Test-Path $rawJson)) {
            Log-Message "snes_titles_raw.json not found - downloading it now..." "Yellow"
            Download-SnsTitlesDatabase
            if ($bp) {
                $found = Resolve-ToolsFile $bp "snes_titles_raw.json" $metaDir
                if ($found) { $rawJson = $found }
            }
            if (-not (Test-Path $rawJson)) {
                $tryOut = Join-Path $outDir "snes_titles_raw.json"
                if (Test-Path $tryOut) { $rawJson = $tryOut }
            }
        }
        if (-not (Test-Path $rawJson)) {
            Log-Message "ERROR: Could not find or download snes_titles_raw.json." "Red"
            return
        }

        Log-Message "Loading checksum database: $rawJson" "White"
        $jsonText = Get-Content -LiteralPath $rawJson -Raw
        $crcMap = @{}
        try {
            $obj = $jsonText | ConvertFrom-Json
            foreach ($prop in $obj.PSObject.Properties) {
                $crcMap[$prop.Name.ToLowerInvariant()] = [string]$prop.Value
            }
        } catch {
            Log-Message "ERROR: Could not parse snes_titles_raw.json - $_" "Red"
            return
        }
        Log-Message "Loaded $($crcMap.Count) checksum -> title entries" "Cyan"
        if ($crcMap.Count -eq 0) { return }

        $romExt = @('.sfc', '.smc', '.fig', '.swc')
        $files = @(Get-ChildItem $romFolder -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
            $romExt -contains $_.Extension.ToLowerInvariant()
        })
        if ($files.Count -eq 0) {
            Log-Message "No SNES ROM files found in that folder." "Yellow"
            return
        }
        Log-Message "ROMs found: $($files.Count)" "Cyan"

        $matched = 0
        $unmatched = 0
        $reportLines = @("# rom_filename|crc32|title (or NOMATCH)")
        $titleMapLines = @()
        $usedNames = @{}

        foreach ($f in $files) {
            try {
                $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
                $offset = 0
                # Optional copier header: adds exactly 512 bytes, detectable
                # because it throws the size off a clean 1KB boundary.
                if (($bytes.Length % 1024) -eq 512) { $offset = 512 }
                $len = $bytes.Length - $offset
                if ($len -le 0) {
                    Log-Message "  Skipped (empty/too small): $($f.Name)" "Yellow"
                    $unmatched++
                    continue
                }
                $hex = [MrtCrc32]::ComputeHex($bytes, $offset, $len)
            } catch {
                Log-Message "  Failed to read: $($f.Name) - $_" "Yellow"
                $unmatched++
                continue
            }

            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            if ($crcMap.ContainsKey($hex)) {
                $title = $crcMap[$hex]
                $matched++
                Log-Message "  $baseName  [crc32=$hex]  =>  $title" "Green"
                $reportLines += "$($f.Name)|$hex|$title"
                if (-not $usedNames.ContainsKey($baseName)) {
                    $usedNames[$baseName] = $true
                    $titleMapLines += "$baseName=$title"
                }
            } else {
                $unmatched++
                Log-Message "  $baseName  [crc32=$hex]  (no match)" "Yellow"
                $reportLines += "$($f.Name)|$hex|NOMATCH"
            }
        }

        $reportFile = Join-Path $outDir "rom_checksum_report.txt"
        $reportLines | Out-File -FilePath $reportFile -Encoding UTF8

        $mapFile = Join-Path $outDir "sns_checksum_titles.txt"
        if ($titleMapLines.Count -gt 0) {
            $titleMapLines | Sort-Object | Out-File -FilePath $mapFile -Encoding UTF8
        }

        Log-Message "----------------------------------------" "Cyan"
        Log-Message "Matched: $matched | No match: $unmatched | Total: $($files.Count)" "Green"
        Log-Message "Report saved: $reportFile" "Cyan"
        if ($titleMapLines.Count -gt 0) {
            Log-Message "Title map saved: $mapFile" "Cyan"
            Log-Message "This uses KEY=Title format, keyed by ROM filename (no extension)." "White"
            Log-Message "If your images share the same base filename as the matching ROM," "Yellow"
            Log-Message "run Image Tools -> Rename SNS-Coded Images to Titles now - it already" "Yellow"
            Log-Message "reads sns_checksum_titles.txt as one of its title-lookup files." "Yellow"
        } else {
            Log-Message "No checksum matches - these ROM dumps may differ (bad dump, trimmed," "Yellow"
            Log-Message "or re-headered) from the copies GameDB-SNES fingerprinted." "Yellow"
        }
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

# ============================================================================
# PORT FROM PEGASUS-TOOL + ES XML
# ============================================================================

function Hide-MultiDiscAndBuildM3U {
    $c = Get-Col
    if (-not $c) { return }
    $r = [System.Windows.Forms.MessageBox]::Show(
        "Scan for multi-disc files (e.g. Game (disc 1).chd), create missing .m3u playlists,`n" +
        "and add disc files to ignore-files: so they are not listed as separate games?`n`nA metadata backup will be created first.",
        "Hide Multi-Disc + Build M3U", "YesNo", "Question")
    if ($r -ne "Yes") { return }
    Log-Message "========================================" "Cyan"
    Log-Message "HIDE MULTI-DISC + BUILD M3U - $($c.name)" "Cyan"
    Log-Message "========================================" "Cyan"
    try {
        $p = $c.metadataPath
        $romDir = Split-Path $p -Parent
        if (-not (Test-Path $romDir)) { Log-Message "ERROR: Collection folder not found: $romDir" "Red"; return }
        $discPattern = '(?i).*\(\s*dis[ck]\s*[0-9]+\s*\)$'
        $romExts = Get-RomExtensions
        $files = @(Get-ChildItem -LiteralPath $romDir -File -ErrorAction SilentlyContinue)
        $discFiles = @(); $baseToDiscs = @{}
        foreach ($f in $files) {
            if ($romExts -notcontains $f.Extension.ToLowerInvariant()) { continue }
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            if ($baseName -notmatch $discPattern) { continue }
            $discFiles += $f.Name
            $stem = ($baseName -replace '(?i)\s*\(\s*dis[ck]\s*[0-9]+\s*\)$', '').Trim()
            if (-not $baseToDiscs.ContainsKey($stem)) { $baseToDiscs[$stem] = New-Object System.Collections.ArrayList }
            [void]$baseToDiscs[$stem].Add($f.Name)
        }
        if ($discFiles.Count -eq 0) { Log-Message "No multi-disc filenames found." "Yellow"; return }
        Log-Message "Found $($discFiles.Count) disc file(s) across $($baseToDiscs.Count) title(s)" "Cyan"
        $m3uCreated = 0
        foreach ($stem in @($baseToDiscs.Keys)) {
            $m3uPath = Join-Path $romDir "$stem.m3u"
            if (-not (Test-Path -LiteralPath $m3uPath)) {
                @($baseToDiscs[$stem] | Sort-Object) | Out-File -FilePath $m3uPath -Encoding UTF8
                $m3uCreated++; Log-Message "  Created M3U: $stem.m3u" "Green"
            } else { Log-Message "  M3U exists: $stem.m3u" "White" }
        }
        CreateBackup
        $content = Get-Content $p -Raw -ErrorAction Stop
        if ($null -eq $content) { $content = "" }
        $existingIgnore = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
        if ($content -match '(?ms)^ignore-files:\s*\r?\n((?:\s+.+\r?\n)*)') {
            foreach ($line in ($matches[1] -split "`r?`n")) { $t = $line.Trim(); if ($t) { [void]$existingIgnore.Add($t) } }
        }
        foreach ($df in $discFiles) { [void]$existingIgnore.Add($df) }
        $updated = $content -replace '(?ms)^ignore-files:\s*\r?\n(?:\s+.+\r?\n)*', ''
        $ignoreBlock = "ignore-files:`r`n"
        foreach ($i in ($existingIgnore | Sort-Object)) { $ignoreBlock += "  $i`r`n" }
        $ignoreBlock += "`r`n"
        if ($updated -match '(?m)^game:\s*') {
            $updated = [regex]::Replace($updated, '(?m)^game:\s*', ($ignoreBlock + 'game: '), 1)
        } else { $updated = $updated.TrimEnd() + "`r`n`r`n" + $ignoreBlock }
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($p, $updated, $utf8)
        Log-Message "Added $($discFiles.Count) disc file(s) to ignore-files: | M3U created: $m3uCreated" "Green"
        UpdateEditor; UpdateStats
    } catch { Log-Message "ERROR: $_" "Red" }
}

function Strip-AllAssetPaths {
    $c = Get-Col; if (-not $c) { return }
    $r = [System.Windows.Forms.MessageBox]::Show(
        "Remove ALL assets.* lines from metadata?`nA backup will be created first.",
        "Strip All Assets", "YesNo", "Warning")
    if ($r -ne "Yes") { return }
    try {
        CreateBackup
        $content = Get-Content $c.metadataPath -Raw
        $updated = $content -replace '(?m)^assets\.[^:]+:.*\r?\n', ''
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($c.metadataPath, $updated, $utf8)
        Log-Message "Stripped all assets.* paths from metadata" "Green"
        UpdateEditor; UpdateStats
    } catch { Log-Message "ERROR: $_" "Red" }
}

function Backup-AllMetadataZip {
    $start = $null; $c = Get-Col
    if ($c -and $c.metadataPath) {
        $start = Split-Path $c.metadataPath -Parent
        $parent = Split-Path $start -Parent
        if ($parent -and (Test-Path $parent)) { $start = $parent }
    }
    $fd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fd.Description = "Select root folder to search for metadata files (recursive)"
    $fd.ShowNewFolderButton = $false
    if ($start -and (Test-Path $start)) { $fd.SelectedPath = $start }
    if ($fd.ShowDialog() -ne "OK") { return }
    $root = $fd.SelectedPath
    Log-Message "========================================" "Cyan"
    Log-Message "BACKUP ALL METADATA (ZIP)" "Cyan"
    Log-Message "Root: $root" "White"
    try {
        $found = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
        Ensure-CollectionsHashtable
        foreach ($key in @($script:collections.Keys)) {
            $mp = $script:collections[$key].metadataPath
            if ($mp -and (Test-Path $mp)) { [void]$found.Add((Resolve-Path $mp).Path) }
        }
        Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            $n = $_.Name
            if ($n -eq 'metadata.pegasus.txt' -or $n -match '\.metadata\.pegasus\.txt$' -or
                $n -match '\.metadata\.txt$' -or $n -eq 'metadata.txt' -or
                ($n -match '\.txt$' -and (Get-Content $_.FullName -TotalCount 8 -ErrorAction SilentlyContinue | Where-Object { $_ -match '^(collection|game):' }))) {
                [void]$found.Add($_.FullName)
            }
        }
        $list = @($found)
        if ($list.Count -eq 0) { Log-Message "No metadata files found under: $root" "Yellow"; return }
        $zipPath = Join-Path $root ("meta.backup." + (Get-Date -Format "yy-MM-dd@HH-mm") + ".zip")
        if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($f in $list) {
                $entryName = if ($f.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
                    $f.Substring($root.Length).TrimStart('\', '/')
                } else { [System.IO.Path]::GetFileName($f) }
                [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f, $entryName.Replace('\', '/'))
                Log-Message "  + $entryName" "White"
            }
        } finally { $zip.Dispose() }
        Log-Message "Zipped $($list.Count) file(s) -> $zipPath" "Green"
    } catch { Log-Message "ERROR: $_" "Red" }
}


function Edit-Genres {
    $c = Get-Col; if (-not $c) { return }
    Log-Message "========================================" "Cyan"
    Log-Message "EDIT GENRES - $($c.name)" "Cyan"
    try {
        $p = $c.metadataPath
        $content = Get-Content $p -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($content)) { Log-Message "Metadata is empty." "Yellow"; return }
        $genreMap = @{}
        $games = $content -split '(?=game: )' | Where-Object { $_ -match '^game: ' }
        foreach ($g in $games) {
            if ($g -match 'game: (.+?)(?:\r?\n|$)') { $title = $matches[1].Trim() } else { continue }
            if ($g -notmatch '(?m)^genre:\s*(.+)$') { continue }
            $genreLine = $matches[1].Trim() -replace '\s*/\s*', ', '
            foreach ($part in ($genreLine -split ',')) {
                $gn = $part.Trim(); if (-not $gn) { continue }
                if (-not $genreMap.ContainsKey($gn)) { $genreMap[$gn] = New-Object System.Collections.ArrayList }
                [void]$genreMap[$gn].Add($title)
            }
        }
        if ($genreMap.Count -eq 0) { Log-Message "No genre: fields found." "Yellow"; return }

        $dlg = New-Object System.Windows.Forms.Form
        $dlg.Text = "Edit Genres - $($c.name)"; $dlg.Size = New-Object System.Drawing.Size(520, 480)
        $dlg.StartPosition = "CenterParent"; $dlg.FormBorderStyle = "FixedDialog"; $dlg.MaximizeBox = $false
        $dlg.BackColor = $script:theme.background; $dlg.ForeColor = $script:theme.text
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = "Select one or more genres, then enter the new name (comma-separated OK):"
        $lbl.Location = New-Object System.Drawing.Point(12, 12); $lbl.Size = New-Object System.Drawing.Size(480, 24)
        $lbl.ForeColor = $script:theme.text; $dlg.Controls.Add($lbl)
        $lb = New-Object System.Windows.Forms.ListBox
        $lb.Location = New-Object System.Drawing.Point(12, 40); $lb.Size = New-Object System.Drawing.Size(480, 280)
        $lb.SelectionMode = "MultiExtended"; $lb.BackColor = $script:theme.editor; $lb.ForeColor = $script:theme.text
        foreach ($g in ($genreMap.Keys | Sort-Object)) { [void]$lb.Items.Add(("{0}  ({1})" -f $g, $genreMap[$g].Count)) }
        $dlg.Controls.Add($lb)
        $lblNew = New-Object System.Windows.Forms.Label
        $lblNew.Text = "Rename selected to:"; $lblNew.Location = New-Object System.Drawing.Point(12, 330)
        $lblNew.Size = New-Object System.Drawing.Size(140, 22); $lblNew.ForeColor = $script:theme.text; $dlg.Controls.Add($lblNew)
        $tbNew = New-Object System.Windows.Forms.TextBox
        $tbNew.Location = New-Object System.Drawing.Point(155, 328); $tbNew.Size = New-Object System.Drawing.Size(337, 24)
        $tbNew.BackColor = $script:theme.editor; $tbNew.ForeColor = $script:theme.text; $tbNew.BorderStyle = "FixedSingle"
        $dlg.Controls.Add($tbNew)
        $lb.Add_SelectedIndexChanged({
            if ($lb.SelectedItems.Count -eq 1) {
                $sel = $lb.SelectedItem.ToString()
                if ($sel -match '^(.+?)\s+\(\d+\)$') { $tbNew.Text = $matches[1].Trim() }
            }
        })
        $info = New-Object System.Windows.Forms.Label
        $info.Text = "$($genreMap.Count) unique genres  |  Ctrl+click for multi-select"
        $info.Location = New-Object System.Drawing.Point(12, 360); $info.Size = New-Object System.Drawing.Size(480, 20)
        $info.ForeColor = $script:theme.textDim; $dlg.Controls.Add($info)
        $btnApply = Create-Button "Apply Rename" 120 400 140 32
        $btnApply.BackColor = $script:theme.success; $btnApply.ForeColor = [System.Drawing.Color]::White
        $btnCancel = Create-Button "Cancel" 280 400 100 32
        $script:__genreApply = $false
        $btnApply.Add_Click({
            if ($lb.SelectedItems.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show("Select at least one genre.", "Edit Genres", "OK", "Warning"); return }
            if ([string]::IsNullOrWhiteSpace($tbNew.Text)) { [System.Windows.Forms.MessageBox]::Show("Enter a new genre name.", "Edit Genres", "OK", "Warning"); return }
            $script:__genreApply = $true; $dlg.Close()
        })
        $btnCancel.Add_Click({ $script:__genreApply = $false; $dlg.Close() })
        $dlg.Controls.Add($btnApply); $dlg.Controls.Add($btnCancel)
        $dlg.ShowDialog() | Out-Null
        if (-not $script:__genreApply) { Log-Message "Genre edit cancelled." "Yellow"; return }
        $oldGenres = @()
        foreach ($item in $lb.SelectedItems) {
            $s = $item.ToString()
            if ($s -match '^(.+?)\s+\(\d+\)$') { $oldGenres += $matches[1].Trim() }
        }
        $newGenre = $tbNew.Text.Trim()
        if ($oldGenres.Count -eq 0) { return }
        $msg = "Replace genre(s):`n  " + ($oldGenres -join ', ') + "`nwith:`n  $newGenre`n`nA backup will be created."
        if ([System.Windows.Forms.MessageBox]::Show($msg, "Confirm Genre Rename", "YesNo", "Question") -ne "Yes") {
            Log-Message "Genre edit cancelled." "Yellow"; return
        }
        CreateBackup
        $norm = $content -replace "`r`n", "`n" -replace "`r", "`n"
        $parts = [regex]::Split($norm, '(?m)(?=^game:\s*)')
        $sb = New-Object System.Text.StringBuilder; $count = 0
        $oldSet = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::Ordinal)
        foreach ($og in $oldGenres) { [void]$oldSet.Add($og) }
        foreach ($part in $parts) {
            if ([string]::IsNullOrWhiteSpace($part)) { continue }
            if ($part -match '(?m)^genre:\s*(.+)$') {
                $gl = $matches[1].Trim() -replace '\s*/\s*', ', '
                $tokens = @($gl -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                $changed = $false; $newTokens = New-Object System.Collections.ArrayList
                foreach ($t in $tokens) {
                    if ($oldSet.Contains($t)) {
                        foreach ($n in ($newGenre -split ',')) {
                            $nn = $n.Trim()
                            if ($nn -and ($newTokens -notcontains $nn)) { [void]$newTokens.Add($nn) }
                        }
                        $changed = $true
                    } elseif ($newTokens -notcontains $t) { [void]$newTokens.Add($t) }
                }
                if ($changed) {
                    $count++
                    $part = [regex]::Replace($part, '(?m)^genre:\s*.+$', ("genre: " + ($newTokens -join ', ')), 1)
                }
            }
            [void]$sb.Append($part.TrimEnd()); [void]$sb.Append("`n")
        }
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($p, ($sb.ToString().TrimEnd() + "`n"), $utf8)
        Log-Message "Updated genre on $count game(s): [$($oldGenres -join ', ')] -> [$newGenre]" "Green"
        UpdateEditor
    } catch { Log-Message "ERROR: $_" "Red" }
}

function Check-AllFilesReport {
    $c = Get-Col
    if (-not $c) { return }

    Log-Message "========================================" "Cyan"
    Log-Message "FULL FILE CHECK REPORT - $($c.name)" "Cyan"
    Log-Message "========================================" "Cyan"

    $prevCursor = [System.Windows.Forms.Cursor]::Current
    try {
        [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::WaitCursor
        if ($script:mainForm) { $script:mainForm.Enabled = $false }

        $p = $c.metadataPath
        $bp = $c.mediaPath
        $romDir = Split-Path $p -Parent
        $romExts = Get-RomExtensions
        $imgExts = @('.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp')
        $vidExts = @('.mp4', '.webm', '.avi', '.mkv')

        # --- ROMs (exact basename set + match-key set) ---
        $romBases = @{}          # basename -> $true
        $romKeySet = @{}         # Get-MatchTitleKey(basename) -> $true
        if (Test-Path $romDir) {
            Get-ChildItem -LiteralPath $romDir -File -ErrorAction SilentlyContinue | ForEach-Object {
                if ($romExts -contains $_.Extension.ToLowerInvariant()) {
                    $b = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
                    $romBases[$b] = $true
                    $k = Get-MatchTitleKey $b
                    if ($k) { $romKeySet[$k] = $true }
                }
            }
        }
        Log-Message "ROM files: $($romBases.Count)" "White"
        [System.Windows.Forms.Application]::DoEvents()

        # --- Metadata titles / file: basenames ---
        $content = Get-Content $p -Raw -ErrorAction Stop
        $metaGames = @{}   # title -> $true
        $metaFiles = @{}   # file basename -> title
        $metaKeySet = @{}  # match keys of titles
        foreach ($g in ($content -split '(?=game: )' | Where-Object { $_ -match '^game: ' })) {
            if ($g -match 'game: (.+?)(?:\r?\n|$)') { $title = $matches[1].Trim() } else { continue }
            $metaGames[$title] = $true
            $tk = Get-MatchTitleKey $title
            if ($tk) { $metaKeySet[$tk] = $true }
            if ($g -match '(?m)^file:\s*(.+)$') {
                try {
                    $fb = [System.IO.Path]::GetFileNameWithoutExtension($matches[1].Trim().Trim('"'))
                    $metaFiles[$fb] = $title
                    $fk = Get-MatchTitleKey $fb
                    if ($fk) { $metaKeySet[$fk] = $true }
                } catch {}
            }
        }
        Log-Message "Games in metadata: $($metaGames.Count)" "White"
        [System.Windows.Forms.Application]::DoEvents()

        # ROM with no metadata: not exact title, not exact file base, not fuzzy key match
        $missingMeta = New-Object System.Collections.ArrayList
        foreach ($rb in $romBases.Keys) {
            if ($metaFiles.ContainsKey($rb)) { continue }
            if ($metaGames.ContainsKey($rb)) { continue }
            $rk = Get-MatchTitleKey $rb
            if ($rk -and $metaKeySet.ContainsKey($rk)) { continue }
            [void]$missingMeta.Add($rb)
        }
        $missingMeta = @($missingMeta | Sort-Object)

        # Metadata with no ROM: not exact rom base, not fuzzy key
        $extraMeta = New-Object System.Collections.ArrayList
        foreach ($t in $metaGames.Keys) {
            if ($romBases.ContainsKey($t)) { continue }
            $tk = Get-MatchTitleKey $t
            if ($tk -and $romKeySet.ContainsKey($tk)) { continue }
            [void]$extraMeta.Add($t)
        }
        $extraMeta = @($extraMeta | Sort-Object)

        $report = New-Object System.Collections.ArrayList
        [void]$report.Add("FULL FILE CHECK - $($c.name)")
        [void]$report.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
        [void]$report.Add("ROMs: $($romBases.Count) | Metadata: $($metaGames.Count) | Missing meta: $($missingMeta.Count) | Extra meta: $($extraMeta.Count)")
        [void]$report.Add("")
        if ($missingMeta.Count -gt 0) {
            [void]$report.Add("--- ROMs missing from metadata ---")
            foreach ($m in $missingMeta) { [void]$report.Add("  $m") }
            [void]$report.Add("")
            Log-Message "ROMs missing metadata: $($missingMeta.Count)" "Yellow"
        }
        if ($extraMeta.Count -gt 0) {
            [void]$report.Add("--- Metadata without matching ROM ---")
            foreach ($m in $extraMeta) { [void]$report.Add("  $m") }
            [void]$report.Add("")
            Log-Message "Metadata without ROM: $($extraMeta.Count)" "Yellow"
        }
        [System.Windows.Forms.Application]::DoEvents()

        # --- Media folders: prebuild key maps, O(n+m) per folder ---
        $mediaRoot = $bp
        if ([string]::IsNullOrWhiteSpace($mediaRoot) -or -not (Test-Path $mediaRoot)) {
            $tryMedia = Join-Path $romDir "media"
            if (Test-Path $tryMedia) { $mediaRoot = $tryMedia }
        }
        if ($mediaRoot -and (Test-Path $mediaRoot)) {
            $subdirs = @(Get-ChildItem -LiteralPath $mediaRoot -Directory -ErrorAction SilentlyContinue)
            foreach ($sd in $subdirs) {
                $mediaFiles = @{}   # base -> filename
                $mediaKeyToName = @{}  # match key -> filename (first)
                Get-ChildItem -LiteralPath $sd.FullName -File -ErrorAction SilentlyContinue | ForEach-Object {
                    $e = $_.Extension.ToLowerInvariant()
                    if ($imgExts -contains $e -or $vidExts -contains $e) {
                        $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
                        $mediaFiles[$base] = $_.Name
                        $mk = Get-MatchTitleKey $base
                        if ($mk -and -not $mediaKeyToName.ContainsKey($mk)) {
                            $mediaKeyToName[$mk] = $_.Name
                        }
                    }
                }

                $missingImg = New-Object System.Collections.ArrayList
                foreach ($rb in $romBases.Keys) {
                    if ($mediaFiles.ContainsKey($rb)) { continue }
                    $rk = Get-MatchTitleKey $rb
                    if ($rk -and $mediaKeyToName.ContainsKey($rk)) { continue }
                    [void]$missingImg.Add($rb)
                }

                $extraImg = New-Object System.Collections.ArrayList
                foreach ($mk in $mediaFiles.Keys) {
                    if ($romBases.ContainsKey($mk)) { continue }
                    $ikk = Get-MatchTitleKey $mk
                    if ($ikk -and $romKeySet.ContainsKey($ikk)) { continue }
                    [void]$extraImg.Add($mediaFiles[$mk])
                }

                $missN = $missingImg.Count
                $orphN = $extraImg.Count
                [void]$report.Add("--- media/$($sd.Name) --- files=$($mediaFiles.Count) missing=$missN orphan=$orphN")
                if ($missN -gt 0 -and $missN -le 40) {
                    foreach ($m in ($missingImg | Sort-Object)) { [void]$report.Add("  missing: $m") }
                } elseif ($missN -gt 40) {
                    foreach ($m in ($missingImg | Sort-Object | Select-Object -First 20)) { [void]$report.Add("  missing: $m") }
                    [void]$report.Add("  ... and $($missN - 20) more missing")
                }
                if ($orphN -gt 0 -and $orphN -le 40) {
                    foreach ($m in ($extraImg | Sort-Object)) { [void]$report.Add("  orphan: $m") }
                } elseif ($orphN -gt 40) {
                    foreach ($m in ($extraImg | Sort-Object | Select-Object -First 20)) { [void]$report.Add("  orphan: $m") }
                    [void]$report.Add("  ... and $($orphN - 20) more orphans")
                }
                [void]$report.Add("")
                Log-Message ("{0}: {1} files, {2} missing, {3} orphan" -f $sd.Name, $mediaFiles.Count, $missN, $orphN) "Cyan"
                [System.Windows.Forms.Application]::DoEvents()
            }
        } else {
            Log-Message "No media folder found to scan." "Yellow"
            [void]$report.Add("(No media folder scanned)")
        }

        $outDir = if ($bp) { Get-ToolsFolder $bp } else { $romDir }
        $outFile = Join-Path $outDir "full_file_check_report.txt"
        $report | Out-File -FilePath $outFile -Encoding UTF8
        Log-Message "Report saved: $outFile" "Green"
        Log-Message "Done!" "Green"
    } catch {
        Log-Message "ERROR: $_" "Red"
    } finally {
        if ($script:mainForm) { $script:mainForm.Enabled = $true }
        [System.Windows.Forms.Cursor]::Current = $prevCursor
    }
}

function Export-EmulationStationXml {
    $c = Get-Col; if (-not $c) { return }
    Log-Message "========================================" "Cyan"
    Log-Message "EXPORT EMULATIONSTATION XML - $($c.name)" "Cyan"
    try {
        $p = $c.metadataPath; $romDir = Split-Path $p -Parent
        $outPath = Join-Path $romDir "gamelist.xml"
        if (Test-Path $outPath) { Copy-Item $outPath ($outPath + ".b") -Force; Log-Message "Backed up existing gamelist.xml -> .b" "Yellow" }
        $content = Get-Content $p -Raw -ErrorAction Stop
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('<?xml version="1.0"?>'); [void]$sb.AppendLine('<gameList>')
        $count = 0
        foreach ($g in ($content -split '(?=game: )' | Where-Object { $_ -match '^game: ' })) {
            $fields = @{}; $curKey = $null; $curVals = @()
            foreach ($line in ($g -split "`r?`n")) {
                if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
                if ($line -match '^([^\s][^:]*):\s*(.*)$') {
                    if ($null -ne $curKey) { $fields[$curKey] = ($curVals -join "`n").Trim() }
                    $curKey = $matches[1].Trim(); $curVals = @()
                    if (-not [string]::IsNullOrWhiteSpace($matches[2])) { $curVals += $matches[2].Trim() }
                } elseif ($null -ne $curKey -and $line -match '^\s+(.+)$') { $curVals += $matches[1].Trim() }
            }
            if ($null -ne $curKey) { $fields[$curKey] = ($curVals -join "`n").Trim() }
            if (-not $fields.ContainsKey("game")) { continue }
            [void]$sb.AppendLine('  <game>')
            [void]$sb.AppendLine("    <name>$([System.Security.SecurityElement]::Escape($fields['game']))</name>")
            if ($fields.ContainsKey("file") -and $fields["file"]) {
                $fp = $fields["file"].Trim()
                if (-not $fp.StartsWith("./") -and -not [System.IO.Path]::IsPathRooted($fp)) { $fp = "./$fp" }
                [void]$sb.AppendLine("    <path>$([System.Security.SecurityElement]::Escape($fp))</path>")
            }
            if ($fields.ContainsKey("description")) { [void]$sb.AppendLine("    <desc>$([System.Security.SecurityElement]::Escape($fields['description']))</desc>") }
            if ($fields.ContainsKey("release") -and $fields["release"]) {
                $rel = $fields["release"].Trim()
                if ($rel -match '^(\d{4})-(\d{2})-(\d{2})') { $rel = "$($matches[1])$($matches[2])$($matches[3])T000000" }
                [void]$sb.AppendLine("    <releasedate>$([System.Security.SecurityElement]::Escape($rel))</releasedate>")
            }
            foreach ($pair in @(@('developer','developer'),@('publisher','publisher'),@('genre','genre'),@('players','players'),@('rating','rating'))) {
                if ($fields.ContainsKey($pair[0]) -and $fields[$pair[0]]) {
                    [void]$sb.AppendLine("    <$($pair[1])>$([System.Security.SecurityElement]::Escape($fields[$pair[0]]))</$($pair[1])>")
                }
            }
            $img = $null
            foreach ($k in @('assets.screenshot','assets.box_front','assets.boxFull','assets.box_full','assets.logo')) {
                if ($fields.ContainsKey($k) -and $fields[$k]) { $img = $fields[$k]; break }
            }
            if ($img) {
                if (-not $img.StartsWith("./") -and -not [System.IO.Path]::IsPathRooted($img)) { $img = "./$img" }
                [void]$sb.AppendLine("    <image>$([System.Security.SecurityElement]::Escape($img))</image>")
            }
            $thumb = $null
            foreach ($k in @('assets.box_front_thumb','assets.logo','assets.box_front')) {
                if ($fields.ContainsKey($k) -and $fields[$k]) { $thumb = $fields[$k]; break }
            }
            if ($thumb) {
                if (-not $thumb.StartsWith("./") -and -not [System.IO.Path]::IsPathRooted($thumb)) { $thumb = "./$thumb" }
                [void]$sb.AppendLine("    <thumbnail>$([System.Security.SecurityElement]::Escape($thumb))</thumbnail>")
            }
            if ($fields.ContainsKey("assets.video") -and $fields["assets.video"]) {
                $v = $fields["assets.video"]
                if (-not $v.StartsWith("./") -and -not [System.IO.Path]::IsPathRooted($v)) { $v = "./$v" }
                [void]$sb.AppendLine("    <video>$([System.Security.SecurityElement]::Escape($v))</video>")
            }
            [void]$sb.AppendLine('  </game>'); $count++
        }
        [void]$sb.AppendLine('</gameList>')
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($outPath, $sb.ToString(), $utf8)
        Log-Message "Exported $count games -> $outPath" "Green"
    } catch { Log-Message "ERROR: $_" "Red" }
}

function Import-EmulationStationXml {
    $c = Get-Col; if (-not $c) { return }
    $start = Split-Path $c.metadataPath -Parent
    $of = New-Object System.Windows.Forms.OpenFileDialog
    $of.Title = "Select EmulationStation gamelist.xml"
    $of.Filter = "XML Files (*.xml)|*.xml|All Files (*.*)|*.*"
    if ($start -and (Test-Path $start)) { $of.InitialDirectory = $start }
    if (Test-Path (Join-Path $start "gamelist.xml")) { $of.FileName = (Join-Path $start "gamelist.xml") }
    if ($of.ShowDialog() -ne "OK") { return }

    $onlyExisting = $false
    $r = [System.Windows.Forms.MessageBox]::Show(
        "Only import games whose ROM file exists in the collection folder?`n`n" +
        "Yes = skip XML entries with missing files (recommended, like Bellerophon)`n" +
        "No  = import every game from the XML",
        "Import EmulationStation XML", "YesNoCancel", "Question")
    if ($r -eq "Cancel") { return }
    if ($r -eq "Yes") { $onlyExisting = $true }

    Log-Message "========================================" "Cyan"
    Log-Message "IMPORT EMULATIONSTATION XML - $($c.name)" "Cyan"
    Log-Message "Source: $($of.FileName)" "White"
    if ($onlyExisting) { Log-Message "Filter: only games with ROM on disk" "Cyan" }

    try {
        [xml]$doc = Get-Content $of.FileName -Raw -ErrorAction Stop
        $nodes = @($doc.SelectNodes('//game'))
        if ($nodes.Count -eq 0) { Log-Message "No <game> entries found." "Yellow"; return }

        $romDir = Split-Path $c.metadataPath -Parent
        $romExts = Get-RomExtensions
        $romBases = @{}
        if ($onlyExisting -and (Test-Path $romDir)) {
            Get-ChildItem -LiteralPath $romDir -File -ErrorAction SilentlyContinue | ForEach-Object {
                if ($romExts -contains $_.Extension.ToLowerInvariant()) {
                    $romBases[$_.Name.ToLowerInvariant()] = $true
                    $romBases[[System.IO.Path]::GetFileNameWithoutExtension($_.Name).ToLowerInvariant()] = $true
                }
            }
            Log-Message "ROM files on disk: $($romBases.Count / 2)" "White"
        }

        $p = $c.metadataPath; $existing = @{}
        if (Test-Path $p) {
            $cur = Get-Content $p -Raw -ErrorAction SilentlyContinue
            if ($cur) {
                foreach ($m in [regex]::Matches($cur, '(?m)^game: (.+)$')) {
                    $existing[$m.Groups[1].Value.Trim().ToLowerInvariant()] = $true
                }
            }
        }
        $mapEs = @{ path='file'; desc='description'; releasedate='release'; developer='developer'; publisher='publisher'; genre='genre'; players='players'; rating='rating' }
        $blocks = New-Object System.Collections.ArrayList
        $added = 0; $skipped = 0; $missingRom = 0
        foreach ($node in $nodes) {
            $name = $node.SelectSingleNode('name')
            if (-not $name -or [string]::IsNullOrWhiteSpace($name.InnerText)) { continue }
            $title = $name.InnerText.Trim(); $key = $title.ToLowerInvariant()
            if ($existing.ContainsKey($key)) { $skipped++; continue }

            $pathEl = $node.SelectSingleNode('path')
            $fileVal = if ($pathEl -and $pathEl.InnerText) { $pathEl.InnerText.Trim() } else { "" }
            if ($fileVal.StartsWith('./')) { $fileVal = $fileVal.Substring(2) }

            if ($onlyExisting) {
                $ok = $false
                if ($fileVal) {
                    $fn = [System.IO.Path]::GetFileName($fileVal)
                    $fb = [System.IO.Path]::GetFileNameWithoutExtension($fileVal)
                    if ($romBases.ContainsKey($fn.ToLowerInvariant()) -or $romBases.ContainsKey($fb.ToLowerInvariant())) { $ok = $true }
                    elseif (Test-Path -LiteralPath (Join-Path $romDir $fileVal)) { $ok = $true }
                    elseif (Test-Path -LiteralPath (Join-Path $romDir $fn)) { $ok = $true }
                }
                if (-not $ok) { $missingRom++; continue }
            }

            $existing[$key] = $true
            $sb = New-Object System.Text.StringBuilder
            [void]$sb.AppendLine("game: $title")
            foreach ($tag in $mapEs.Keys) {
                $el = $node.SelectSingleNode($tag)
                if (-not $el -or [string]::IsNullOrWhiteSpace($el.InnerText)) { continue }
                $val = $el.InnerText.Trim(); $pegKey = $mapEs[$tag]
                if ($tag -eq 'releasedate' -and $val -match '^(\d{4})(\d{2})(\d{2})') { $val = "$($matches[1])-$($matches[2])-$($matches[3])" }
                if ($tag -eq 'path' -and $val.StartsWith('./')) { $val = $val.Substring(2) }
                if ($tag -eq 'rating') {
                    # ES stores 0-1 float; Pegasus often uses percent or same float - keep percent if < 1.5
                    $d = 0.0
                    if ([double]::TryParse($val, [ref]$d) -and $d -le 1.0) { $val = [string]([int][Math]::Round($d * 100)) + '%' }
                }
                if ($pegKey -eq 'description' -and $val -match "`n") {
                    [void]$sb.AppendLine("description:")
                    foreach ($line in ($val -split "`r?`n")) { [void]$sb.AppendLine("  $line") }
                } else { [void]$sb.AppendLine("${pegKey}: $val") }
            }
            $img = $node.SelectSingleNode('image')
            if ($img -and $img.InnerText) { [void]$sb.AppendLine("assets.screenshot: $($img.InnerText.Trim())") }
            $thumb = $node.SelectSingleNode('thumbnail'); if (-not $thumb) { $thumb = $node.SelectSingleNode('thumb') }
            if ($thumb -and $thumb.InnerText) { [void]$sb.AppendLine("assets.box_front: $($thumb.InnerText.Trim())") }
            $vid = $node.SelectSingleNode('video')
            if ($vid -and $vid.InnerText) { [void]$sb.AppendLine("assets.video: $($vid.InnerText.Trim())") }
            if ($node.GetAttribute('id')) { [void]$sb.AppendLine("x-id: $($node.GetAttribute('id'))") }
            if ($node.GetAttribute('source')) { [void]$sb.AppendLine("x-source: $($node.GetAttribute('source'))") }
            [void]$sb.AppendLine(""); [void]$blocks.Add($sb.ToString()); $added++
        }
        if ($added -eq 0) {
            Log-Message "No new games (already present: $skipped | missing ROM: $missingRom)" "Yellow"
            return
        }
        CreateBackup
        $header = if (Test-Path $p) { Get-Content $p -Raw } else { "" }
        if ($null -eq $header) { $header = "" }
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($p, ($header.TrimEnd() + "`r`n`r`n" + ($blocks -join "")), $utf8)
        Log-Message "Imported $added game(s) | skipped existing: $skipped | missing ROM: $missingRom" "Green"
        UpdateEditor; UpdateStats
    } catch { Log-Message "ERROR: $_" "Red" }
}

function Backup-OrphanMedia {
    # Move media files that do not match any ROM / metadata title into media.backup\<type>\
    $c = Get-Col; if (-not $c) { return }
    $r = [System.Windows.Forms.MessageBox]::Show(
        "Move orphan media files (no matching ROM or game title) into media.backup?`n`n" +
        "Files are moved, not deleted. You can restore them manually from media.backup.",
        "Backup Orphan Media", "YesNo", "Question")
    if ($r -ne "Yes") { return }

    Log-Message "========================================" "Cyan"
    Log-Message "BACKUP ORPHAN MEDIA - $($c.name)" "Cyan"
    Log-Message "========================================" "Cyan"

    try {
        $p = $c.metadataPath
        $bp = $c.mediaPath
        $romDir = Split-Path $p -Parent
        $romExts = Get-RomExtensions
        $mediaExts = @('.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp', '.mp4', '.webm', '.avi', '.mkv')

        $keepBases = @{}
        $keepKeys = @{}
        if (Test-Path $romDir) {
            foreach ($f in @(Get-ChildItem -LiteralPath $romDir -File -ErrorAction SilentlyContinue)) {
                if ($romExts -contains $f.Extension.ToLowerInvariant()) {
                    $b = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
                    $keepBases[$b] = $true
                    $k = Get-MatchTitleKey $b
                    if ($k) { $keepKeys[$k] = $true }
                }
            }
        }
        if (Test-Path $p) {
            $content = Get-Content $p -Raw -ErrorAction SilentlyContinue
            if ($content) {
                foreach ($g in ($content -split '(?=game: )' | Where-Object { $_ -match '^game: ' })) {
                    if ($g -match 'game: (.+?)(?:\r?\n|$)') {
                        $title = $matches[1].Trim()
                        $keepBases[$title] = $true
                        $tk = Get-MatchTitleKey $title
                        if ($tk) { $keepKeys[$tk] = $true }
                    }
                    if ($g -match '(?m)^file:\s*(.+)$') {
                        try {
                            $fb = [System.IO.Path]::GetFileNameWithoutExtension($matches[1].Trim().Trim('"'))
                            $keepBases[$fb] = $true
                            $fk = Get-MatchTitleKey $fb
                            if ($fk) { $keepKeys[$fk] = $true }
                        } catch {}
                    }
                }
            }
        }
        Log-Message "Keep keys from ROMs/metadata: $($keepBases.Count)" "White"

        if ([string]::IsNullOrWhiteSpace($bp) -or -not (Test-Path $bp)) {
            $tryMedia = Join-Path $romDir "media"
            if (Test-Path $tryMedia) { $bp = $tryMedia }
        }
        if (-not $bp -or -not (Test-Path $bp)) {
            Log-Message "No media folder found." "Yellow"
            return
        }

        # Sibling of media folder: <collection>\media.backup\<type>\
        $backupRoot = Join-Path (Split-Path $bp -Parent) "media.backup"
        $moved = 0
        $subdirs = @(Get-ChildItem -LiteralPath $bp -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notin @('Tools', 'media.backup') })
        foreach ($sd in $subdirs) {
            foreach ($file in @(Get-ChildItem -LiteralPath $sd.FullName -File -ErrorAction SilentlyContinue)) {
                $e = $file.Extension.ToLowerInvariant()
                if ($mediaExts -notcontains $e) { continue }
                $base = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                if ($keepBases.ContainsKey($base)) { continue }
                $mk = Get-MatchTitleKey $base
                if ($mk -and $keepKeys.ContainsKey($mk)) { continue }

                $destDir = Join-Path $backupRoot $sd.Name
                if (-not (Test-Path $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                $dest = Join-Path $destDir $file.Name
                if (Test-Path -LiteralPath $dest) {
                    $dest = Join-Path $destDir ("{0}_{1}{2}" -f $base, (Get-Date -Format "HHmmss"), $file.Extension)
                }
                try {
                    Move-Item -LiteralPath $file.FullName -Destination $dest -Force
                    $moved++
                    Log-Message "  Moved: $($sd.Name)/$($file.Name)" "Yellow"
                } catch {
                    Log-Message "  Failed: $($file.Name) - $($_.Exception.Message)" "Red"
                }
            }
        }
        if ($moved -eq 0) {
            Log-Message "No orphan media found." "Green"
        } else {
            Log-Message "Moved $moved orphan file(s) -> $backupRoot" "Green"
        }
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}


function Batch-ImportFromLibraryRoot {
    # Scan a library root for system folders that contain gamelist.xml; import each into matching collection or create one.
    $fd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fd.Description = "Select library root (contains system folders with gamelist.xml)"
    $fd.ShowNewFolderButton = $false
    $c = Get-Col
    if ($c -and $c.metadataPath) {
        $parent = Split-Path (Split-Path $c.metadataPath -Parent) -Parent
        if ($parent -and (Test-Path $parent)) { $fd.SelectedPath = $parent }
    }
    if ($fd.ShowDialog() -ne "OK") { return }
    $root = $fd.SelectedPath

    $onlyExisting = $true
    $r = [System.Windows.Forms.MessageBox]::Show(
        "Only import games whose ROM files exist on disk?`n(Recommended)",
        "Batch Import from Library", "YesNoCancel", "Question")
    if ($r -eq "Cancel") { return }
    if ($r -eq "No") { $onlyExisting = $false }

    Log-Message "========================================" "Cyan"
    Log-Message "BATCH IMPORT FROM LIBRARY ROOT" "Cyan"
    Log-Message "Root: $root" "White"
    Log-Message "========================================" "Cyan"

    try {
        $lists = @(Get-ChildItem -LiteralPath $root -Recurse -Filter "gamelist.xml" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.DirectoryName -ne $root })
        if ($lists.Count -eq 0) {
            # also check one level deep only for speed message
            Log-Message "No gamelist.xml found under: $root" "Yellow"
            return
        }
        Log-Message "Found $($lists.Count) gamelist.xml file(s)" "Cyan"

        Ensure-CollectionsHashtable
        $romExts = Get-RomExtensions
        $totalAdded = 0
        $systemsDone = 0

        foreach ($gl in $lists) {
            $sysDir = $gl.Directory.FullName
            $sysName = $gl.Directory.Name
            Log-Message "---- $sysName ----" "Cyan"
            Log-Message "  $($gl.FullName)" "White"

            # Resolve or create collection
            $metaPath = $null
            $mediaPath = Join-Path $sysDir "media"
            if (-not (Test-Path $mediaPath)) {
                try { New-Item -ItemType Directory -Path $mediaPath -Force | Out-Null } catch {}
            }

            # Prefer existing collection whose metadata lives in this folder
            foreach ($key in @($script:collections.Keys)) {
                $mp = $script:collections[$key].metadataPath
                if ($mp -and (Test-Path $mp)) {
                    $mdir = Split-Path $mp -Parent
                    if ($mdir -and ($mdir.TrimEnd('\','/') -ieq $sysDir.TrimEnd('\','/'))) {
                        $metaPath = $mp
                        $sysName = $key
                        break
                    }
                }
            }
            if (-not $metaPath) {
                # Common names
                foreach ($cand in @("$sysName.txt", "metadata.txt", "metadata.pegasus.txt")) {
                    $try = Join-Path $sysDir $cand
                    if (Test-Path $try) { $metaPath = $try; break }
                }
            }
            if (-not $metaPath) {
                $metaPath = Join-Path $sysDir "$sysName.txt"
                $header = @"
collection: $sysName
shortname: $(($sysName -replace '[^A-Za-z0-9]','').ToLower())
launch: 

"@
                $utf8nb = New-Object System.Text.UTF8Encoding $false
                [System.IO.File]::WriteAllText($metaPath, $header, $utf8nb)
                Log-Message "  Created metadata: $metaPath" "Green"
            }
            if (-not $script:collections.ContainsKey($sysName)) {
                [void](Add-Collection $sysName $metaPath $mediaPath)
                Log-Message "  Added collection: $sysName" "Green"
            }

            # Import XML into this metadata
            try {
                [xml]$doc = Get-Content $gl.FullName -Raw -ErrorAction Stop
                $nodes = @($doc.SelectNodes('//game'))
                if ($nodes.Count -eq 0) { Log-Message "  No games in XML" "Yellow"; continue }

                $romBases = @{}
                Get-ChildItem -LiteralPath $sysDir -File -ErrorAction SilentlyContinue | ForEach-Object {
                    if ($romExts -contains $_.Extension.ToLowerInvariant()) {
                        $romBases[$_.Name.ToLowerInvariant()] = $true
                        $romBases[[System.IO.Path]::GetFileNameWithoutExtension($_.Name).ToLowerInvariant()] = $true
                    }
                }

                $existing = @{}
                $cur = Get-Content $metaPath -Raw -ErrorAction SilentlyContinue
                if ($cur) {
                    foreach ($m in [regex]::Matches($cur, '(?m)^game: (.+)$')) {
                        $existing[$m.Groups[1].Value.Trim().ToLowerInvariant()] = $true
                    }
                }
                $mapEs = @{ path='file'; desc='description'; releasedate='release'; developer='developer'; publisher='publisher'; genre='genre'; players='players'; rating='rating' }
                $blocks = New-Object System.Collections.ArrayList
                $added = 0; $skipped = 0; $missingRom = 0
                foreach ($node in $nodes) {
                    $name = $node.SelectSingleNode('name')
                    if (-not $name -or [string]::IsNullOrWhiteSpace($name.InnerText)) { continue }
                    $title = $name.InnerText.Trim(); $key = $title.ToLowerInvariant()
                    if ($existing.ContainsKey($key)) { $skipped++; continue }
                    $pathEl = $node.SelectSingleNode('path')
                    $fileVal = if ($pathEl -and $pathEl.InnerText) { $pathEl.InnerText.Trim() } else { "" }
                    if ($fileVal.StartsWith('./')) { $fileVal = $fileVal.Substring(2) }
                    if ($onlyExisting) {
                        $ok = $false
                        if ($fileVal) {
                            $fn = [System.IO.Path]::GetFileName($fileVal)
                            $fb = [System.IO.Path]::GetFileNameWithoutExtension($fileVal)
                            if ($romBases.ContainsKey($fn.ToLowerInvariant()) -or $romBases.ContainsKey($fb.ToLowerInvariant())) { $ok = $true }
                            elseif (Test-Path -LiteralPath (Join-Path $sysDir $fileVal)) { $ok = $true }
                        }
                        if (-not $ok) { $missingRom++; continue }
                    }
                    $existing[$key] = $true
                    $sb = New-Object System.Text.StringBuilder
                    [void]$sb.AppendLine("game: $title")
                    foreach ($tag in $mapEs.Keys) {
                        $el = $node.SelectSingleNode($tag)
                        if (-not $el -or [string]::IsNullOrWhiteSpace($el.InnerText)) { continue }
                        $val = $el.InnerText.Trim(); $pegKey = $mapEs[$tag]
                        if ($tag -eq 'releasedate' -and $val -match '^(\d{4})(\d{2})(\d{2})') { $val = "$($matches[1])-$($matches[2])-$($matches[3])" }
                        if ($tag -eq 'path' -and $val.StartsWith('./')) { $val = $val.Substring(2) }
                        if ($tag -eq 'rating') {
                            $d = 0.0
                            if ([double]::TryParse($val, [ref]$d) -and $d -le 1.0) { $val = [string]([int][Math]::Round($d * 100)) + '%' }
                        }
                        if ($pegKey -eq 'description' -and $val -match "`n") {
                            [void]$sb.AppendLine("description:")
                            foreach ($line in ($val -split "`r?`n")) { [void]$sb.AppendLine("  $line") }
                        } else { [void]$sb.AppendLine("${pegKey}: $val") }
                    }
                    $img = $node.SelectSingleNode('image')
                    if ($img -and $img.InnerText) { [void]$sb.AppendLine("assets.screenshot: $($img.InnerText.Trim())") }
                    $thumb = $node.SelectSingleNode('thumbnail'); if (-not $thumb) { $thumb = $node.SelectSingleNode('thumb') }
                    if ($thumb -and $thumb.InnerText) { [void]$sb.AppendLine("assets.box_front: $($thumb.InnerText.Trim())") }
                    $vid = $node.SelectSingleNode('video')
                    if ($vid -and $vid.InnerText) { [void]$sb.AppendLine("assets.video: $($vid.InnerText.Trim())") }
                    [void]$sb.AppendLine(""); [void]$blocks.Add($sb.ToString()); $added++
                }
                if ($added -gt 0) {
                    $header = if (Test-Path $metaPath) { Get-Content $metaPath -Raw } else { "" }
                    if ($null -eq $header) { $header = "" }
                    $utf8 = New-Object System.Text.UTF8Encoding $false
                    [System.IO.File]::WriteAllText($metaPath, ($header.TrimEnd() + "`r`n`r`n" + ($blocks -join "")), $utf8)
                }
                Log-Message "  +$added imported | skip $skipped | missing ROM $missingRom" "Green"
                $totalAdded += $added
                $systemsDone++
            } catch {
                Log-Message "  ERROR: $_" "Red"
            }
        }
        RefreshCollectionList
        Log-Message "========================================" "Cyan"
        Log-Message "Batch done: $systemsDone system(s), $totalAdded game(s) added" "Green"
        Log-Message "Tip: open a collection and run Image Tools -> Add All Media Types" "Yellow"
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}


function Sort-GamesAlphabetically {
    # Reorder game blocks in the collection metadata by title (A-Z).
    # Uses sort_title / sort-title when present, otherwise the game: title.
    $c = Get-Col
    if (-not $c) { return }

    Log-Message "========================================" "Cyan"
    Log-Message "SORT GAMES A-Z - $($c.name)" "Cyan"
    Log-Message "========================================" "Cyan"

    try {
        $p = $c.metadataPath
        if (-not (Test-Path $p)) {
            Log-Message "ERROR: Metadata file not found" "Red"
            return
        }

        # Prefer in-memory games when form view is active; otherwise re-parse file
        if (-not $script:rawMode) {
            try {
                Apply-HeaderFieldsFromUI
                if ($script:gameListBox -and $script:gameListBox.SelectedIndex -ge 0) {
                    ApplyGameFields
                }
            } catch {}
        }

        if ($null -eq $script:parsedGames -or @($script:parsedGames).Count -eq 0) {
            $content = Get-Content $p -Raw -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace($content)) {
                Log-Message "Metadata file is empty." "Yellow"
                return
            }
            Parse-PegasusMetadata $content
        }

        $count = @($script:parsedGames).Count
        if ($count -lt 2) {
            Log-Message "Need at least 2 games to sort (found $count)." "Yellow"
            return
        }

        $msg = "Sort all $count games in this collection alphabetically by title?`n`n" +
               "Order key: sort_title (or sort-title) if set, otherwise the game title.`n" +
               "Comparison is case-insensitive.`n`n" +
               "A backup of the metadata file will be created first."
        $result = [System.Windows.Forms.MessageBox]::Show($msg, "Sort Games A-Z", "YesNo", "Question")
        if ($result -ne "Yes") {
            Log-Message "Cancelled - no changes made." "Yellow"
            return
        }

        CreateBackup

        $sorted = @($script:parsedGames | Sort-Object -Property {
            $f = $_.Fields
            $key = $null
            if ($f -and $f.ContainsKey("sort_title") -and -not [string]::IsNullOrWhiteSpace([string]$f["sort_title"])) {
                $key = [string]$f["sort_title"]
            } elseif ($f -and $f.ContainsKey("sort-title") -and -not [string]::IsNullOrWhiteSpace([string]$f["sort-title"])) {
                $key = [string]$f["sort-title"]
            } elseif ($f -and $f.ContainsKey("game") -and -not [string]::IsNullOrWhiteSpace([string]$f["game"])) {
                $key = [string]$f["game"]
            } else {
                $key = [string]$_.Title
            }
            $key.Trim().ToLowerInvariant()
        })

        $script:parsedGames = $sorted

        $text = Build-PegasusMetadata
        $text = $text -replace "`r`n", "`n" -replace "`r", "`n"
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($p, $text, $utf8NoBom)

        Log-Message "Sorted $count games A-Z." "Green"
        Log-Message "Done!" "Green"

        UpdateEditor
        UpdateStats
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

function Remove-GamesWithoutFile {
    # Remove game: blocks that have no file: path (or an empty one).
    # Typical cause: importing SNES internal ROM header titles as games
    # (ALL CAPS names with no ROM path). Clean Bogus Games does not catch these.
    $c = Get-Col
    if (-not $c) { return }

    Log-Message "========================================" "Cyan"
    Log-Message "REMOVE GAMES WITH NO FILE - $($c.name)" "Cyan"
    Log-Message "========================================" "Cyan"

    try {
        $p = $c.metadataPath
        if (-not (Test-Path $p)) {
            Log-Message "ERROR: Metadata file not found" "Red"
            return
        }

        $content = Get-Content $p -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($content)) {
            Log-Message "Metadata file is empty." "Yellow"
            return
        }

        $norm = $content -replace "`r`n", "`n" -replace "`r", "`n"
        $parts = [regex]::Split($norm, '(?m)(?=^game:\s*)')

        $keepParts = New-Object System.Collections.ArrayList
        $removedTitles = New-Object System.Collections.ArrayList

        foreach ($part in $parts) {
            if ([string]::IsNullOrWhiteSpace($part)) { continue }
            if ($part -match '(?m)^game:\s*') {
                $title = ""
                if ($part -match '(?m)^game:\s*(.*)$') { $title = $matches[1].Trim() }
                $hasFile = $false
                if ($part -match '(?m)^file:\s*(.+)$') {
                    $fv = $matches[1].Trim().Trim('"')
                    if (-not [string]::IsNullOrWhiteSpace($fv)) { $hasFile = $true }
                }
                if (-not $hasFile) {
                    [void]$removedTitles.Add($(if ($title) { $title } else { "(untitled)" }))
                    continue
                }
            }
            [void]$keepParts.Add($part.TrimEnd())
        }

        if ($removedTitles.Count -eq 0) {
            Log-Message "No games without a file: path found." "Green"
            return
        }

        Log-Message "Found $($removedTitles.Count) game(s) with no file path:" "Yellow"
        $removedTitles | Select-Object -First 25 | ForEach-Object { Log-Message "  [$_]" "Yellow" }
        if ($removedTitles.Count -gt 25) {
            Log-Message "  ... and $($removedTitles.Count - 25) more" "Yellow"
        }

        $msg = "Found $($removedTitles.Count) game entries with no file: path.`n`n" +
               "These are often SNES internal ROM header titles (ALL CAPS) that were " +
               "imported as games by mistake, or other orphan metadata blocks.`n`n" +
               "A backup will be created first.`n`n" +
               "Remove these $($removedTitles.Count) entries now?"
        $result = [System.Windows.Forms.MessageBox]::Show($msg, "Remove Games with No File", "YesNo", "Question")
        if ($result -ne "Yes") {
            Log-Message "Cancelled - no changes made." "Yellow"
            return
        }

        CreateBackup

        $newContent = ($keepParts -join "`n").Trim() + "`n"
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($p, $newContent, $utf8NoBom)

        Log-Message "Removed $($removedTitles.Count) game(s) with no file path." "Green"
        Log-Message "Done!" "Green"

        UpdateEditor
        UpdateStats
    } catch {
        Log-Message "ERROR: $_" "Red"
    }
}

function Show-BuilderHelp {
    [System.Windows.Forms.MessageBox]::Show(
        "BUILDER / REPAIR TOOLS`n`n" +
        "Scan / Build / Import / Sync / Export lists / DL covers / SNES headers`n`n" +
        "Strip All Box Art Paths - box art only`n" +
        "Strip All Assets - every assets.* line`n" +
        "Hide Multi-Disc + M3U - (disc N) -> m3u + ignore-files`n" +
        "Backup All Meta (Zip) - recursive zip`n" +
        "Edit Genres - multi-select rename/merge`n" +
        "Full File Check Report - missing ROMs, orphans, media gaps`n" +
        "Backup Orphan Media - move unmatched media to media.backup`n" +
        "Batch Import Library - import all gamelist.xml under a root folder`n" +
        "Export / Import EmulationStation XML - gamelist.xml`n" +
        "  (Import can skip games whose ROM is missing on disk)`n" +
        "Clean Bogus Games - remove garbled titles`n" +
        "Sort Games A-Z - reorder game blocks alphabetically by title`n" +
        "Remove Games w/ No File - delete game blocks that have no file: path`n" +
        "  (common after importing SNES header title lists by mistake)`n`n" +
        "Open Workflow Guide for step-by-step help on each tool.",
        "Builder Help", "OK", "Information")
}

# ============================================================================
# START
# ============================================================================
try {
    Show-MainWindow
} catch {
    $errMsg = "Startup error:`n`n$($_.Exception.Message)`n`n$($_.ScriptStackTrace)"
    try {
        $logPath = Join-Path $env:TEMP "MetadataRepairTool_startup_error.txt"
        $errMsg | Out-File -FilePath $logPath -Encoding UTF8
        $errMsg = $errMsg + "`n`nDetails also saved to:`n$logPath"
    } catch {}
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [System.Windows.Forms.MessageBox]::Show($errMsg, "Metadata Repair Tool - Error", "OK", "Error") | Out-Null
    } catch {
        Write-Host $errMsg
    }
}