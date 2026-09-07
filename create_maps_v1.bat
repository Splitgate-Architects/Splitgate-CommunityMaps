<# :
@echo off
title Map Packager Automation
setlocal
chcp 65001 >nul

set "BASEDIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Get-Content '%~f0' -Raw)"
pause
exit /b %errorlevel%
#>

# ============================================================
# POWERSHELL LOGIC STARTS HERE
# ============================================================
$ErrorActionPreference = "Stop"
$baseDir = $env:BASEDIR
$targetDir = Join-Path $baseDir "ConvertMaps"
$outputDir = Join-Path $baseDir "ConvertOutput"
$comment = "Packed by CreativeCore1047"

Write-Host "Starting strict map processing..." -ForegroundColor Cyan
Write-Host "Target Directory: $targetDir" -ForegroundColor Cyan
Write-Host "Output Directory: $outputDir" -ForegroundColor Cyan
Write-Host "================================================="

if (-not (Test-Path $targetDir)) {
    Write-Host "[ERROR] The folder 'ConvertMaps' does not exist in the script's directory." -ForegroundColor Red
    Write-Host "Please make sure the script is placed in the correct main folder." -ForegroundColor Yellow
    exit
}

# Create output folder if it doesn't exist yet
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

# --- Slug helpers -------------------------------------------------------
# "+" and "&" are meaningful (e.g. "Classic" vs "Classic+" ARE different
# maps) so they're spelled out instead of being silently dropped, which
# used to make two different maps collide onto the same output filename.
#
# Non-ASCII scripts (Japanese, Cyrillic, etc.) are KEPT in the filename as-
# is rather than stripped - Windows filesystems handle Unicode names fine,
# and there's no meaningful way to "romanize" 新しいプロジェクト without a
# real translation service anyway. Decorative Unicode "lookalikes" some
# Steam/Epic names use (ᵘʳᶜʰᵒᵖᵖᵉᵈ, Ⓐⓑ①, ...) ARE smoothed down to plain
# letters though - but only for the specific Unicode ranges that actually
# contain that kind of stylized Latin text. A blanket decompose-everything
# approach was tried first and rejected: it also decomposes things like
# Japanese katakana-with-dakuten (e.g. プ "pu") into a base character plus
# a combining mark, and stripping that combining mark then silently turns
# it into a DIFFERENT character (フ "fu") - corrupting the name rather
# than prettifying it. So: only touch the known lookalike ranges, keep
# every other letter/digit in any script as-is, and handle a couple of
# specific known-safe substitutions (+, &, Quake color codes). If a
# segment still ends up completely empty after all that (blank names,
# pure emoji, etc.), it falls back to something guaranteed non-empty and
# unique instead of silently producing "_.bin" that overwrites whatever
# used that name before.
function Get-FallbackHash {
    # Deterministic short hash - same input always gives the same output,
    # so re-running the script doesn't rename things that already worked.
    param([string]$Text)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))
    return ([BitConverter]::ToString($bytes) -replace '-', '').Substring(0, 8).ToLower()
}
# Unicode ranges that specifically contain "stylized Latin lookalikes"
# (superscript letters, math-alphanumeric symbols, circled letters, etc.)
# - characters in these ranges are safe to decompose down to their plain
# letter, unlike e.g. Japanese diacritic marks, which live in completely
# different ranges and must never go through this.
$script:StylizedRanges = @(
    @(0x02B0, 0x02FF),   # Spacing Modifier Letters
    @(0x1D00, 0x1D7F),   # Phonetic Extensions
    @(0x1D80, 0x1DBF),   # Phonetic Extensions Supplement
    @(0x2070, 0x209F),   # Superscripts and Subscripts
    @(0x2100, 0x214F),   # Letterlike Symbols
    @(0x2150, 0x218F),   # Number Forms
    @(0x2460, 0x24FF),   # Enclosed Alphanumerics (circled letters)
    @(0xFF00, 0xFFEF),   # Halfwidth/Fullwidth Forms
    @(0x1D400, 0x1D7FF)  # Mathematical Alphanumeric Symbols
)
function Test-IsStylizedLookalike {
    param([int]$CodePoint)
    foreach ($range in $script:StylizedRanges) {
        if ($CodePoint -ge $range[0] -and $CodePoint -le $range[1]) { return $true }
    }
    return $false
}
# Smooths stylized Latin lookalikes (ᵘʳᶜʰᵒᵖᵖᵉᵈ -> urchopped, Ⓐⓑ① -> Ab1) to
# plain letters, WITHOUT touching anything outside those specific ranges -
# Japanese/Cyrillic/etc. text is passed through completely untouched.
function ConvertTo-SmoothedText {
    param([string]$Text)
    $sb = New-Object System.Text.StringBuilder
    $i = 0
    while ($i -lt $Text.Length) {
        if ([Char]::IsSurrogatePair($Text, $i)) {
            $cp = [Char]::ConvertToUtf32($Text, $i)
            $chunk = $Text.Substring($i, 2)
            $i += 2
        } else {
            $cp = [int]$Text[$i]
            $chunk = $Text.Substring($i, 1)
            $i += 1
        }
        if (Test-IsStylizedLookalike $cp) {
            $normalized = $chunk.Normalize([Text.NormalizationForm]::FormKD)
            foreach ($ch in $normalized.ToCharArray()) {
                $cat = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
                if ($cat -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
            }
        } else {
            [void]$sb.Append($chunk)
        }
    }
    return $sb.ToString()
}
function Get-PreCleanedText {
    param([string]$Text)
    $t = $Text -replace '\^[0-9]', ''   # Quake-style color codes: ^1, ^7, ...
    $t = $t -replace '\+', 'plus' -replace '&', 'and'
    return ConvertTo-SmoothedText $t
}
# True for any Unicode letter (in ANY script - Latin, Kanji, Hiragana,
# Katakana, Cyrillic, ...) or digit. This is what decides "keep this
# character in the filename" vs "treat it as a separator/drop it".
function Test-IsLetterOrDigit {
    param([char]$Ch)
    $cat = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($Ch)
    return $cat -in @(
        [Globalization.UnicodeCategory]::UppercaseLetter,
        [Globalization.UnicodeCategory]::LowercaseLetter,
        [Globalization.UnicodeCategory]::TitlecaseLetter,
        [Globalization.UnicodeCategory]::ModifierLetter,
        [Globalization.UnicodeCategory]::OtherLetter,
        [Globalization.UnicodeCategory]::DecimalDigitNumber,
        [Globalization.UnicodeCategory]::LetterNumber,
        [Globalization.UnicodeCategory]::OtherNumber
    )
}
function ConvertTo-DashedSlug {
    # base-name style: "Protocol Echo" -> "protocol-echo", "新しい プロジェクト" -> "新しい-プロジェクト"
    param([string]$Text)
    $t = (Get-PreCleanedText $Text).Trim()
    $sb = New-Object System.Text.StringBuilder
    $lastWasDash = $false
    foreach ($ch in $t.ToCharArray()) {
        if (Test-IsLetterOrDigit $ch) {
            [void]$sb.Append([Char]::ToLowerInvariant($ch))
            $lastWasDash = $false
        } elseif (-not $lastWasDash) {
            [void]$sb.Append('-')
            $lastWasDash = $true
        }
    }
    return $sb.ToString().Trim('-')
}
function ConvertTo-ConcatSlug {
    # gamemode/author style: "Survival Brawl" -> "survivalbrawl" (no separators at all)
    param([string]$Text)
    $t = (Get-PreCleanedText $Text).Trim()
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $t.ToCharArray()) {
        if (Test-IsLetterOrDigit $ch) { [void]$sb.Append([Char]::ToLowerInvariant($ch)) }
    }
    return $sb.ToString()
}
function ConvertTo-SafeAuthorSlug {
    param([string]$Author)
    $s = ConvertTo-ConcatSlug $Author
    if ([string]::IsNullOrEmpty($s)) { return "unknown" }
    return $s
}
function ConvertTo-SafeMapSlug {
    # Tries the map name first, then the (guaranteed-unique-on-disk) source
    # folder name, then finally a short deterministic hash of the folder
    # name - each step only used if the previous one came up empty.
    param([string]$MapName, [string]$FolderName)
    $s = ConvertTo-MapSlug $MapName
    if (-not [string]::IsNullOrEmpty($s)) { return $s }
    $s = ConvertTo-DashedSlug $FolderName
    if (-not [string]::IsNullOrEmpty($s)) { return $s }
    return "map-$(Get-FallbackHash $FolderName)"
}
function ConvertTo-MapSlug {
    # Splits off an optional "(Gamemode)" OR "[Gamemode]" suffix - both
    # bracket styles show up in the wild and mean the same thing.
    param([string]$MapName)
    if ($MapName -match '^(.*?)\s*[\(\[](.*?)[\)\]]\s*$') {
        $base = ConvertTo-DashedSlug $matches[1]
        $mode = ConvertTo-ConcatSlug $matches[2]
        if ([string]::IsNullOrEmpty($base)) { return $mode }
        if ([string]::IsNullOrEmpty($mode)) { return $base }
        return "$base-$mode"
    }
    return ConvertTo-DashedSlug $MapName
}

$folders = Get-ChildItem -Path $targetDir -Directory
$processedCount = 0
$skippedFolders = @()      # missing required files - can't be fixed automatically
$fallbackFolders = @()     # README unparseable - packed anyway using the folder name
$usedFileNames = @{}       # binFileName -> source folder that claimed it first (collision guard)

foreach ($folder in $folders) {
    $subFolder = $folder.FullName
    $readme = Join-Path $subFolder "README.md"
    $mapFile = Join-Path $subFolder "World.cf1047"
    $imgFile = Join-Path $subFolder "Screenshot.jpg"

    $missing = @()
    if (-not (Test-Path $readme))  { $missing += "README.md" }
    if (-not (Test-Path $mapFile)) { $missing += "World.cf1047" }
    if (-not (Test-Path $imgFile)) { $missing += "Screenshot.jpg" }

    if ($missing.Count -gt 0) {
        Write-Host "`nAnalyzing folder: $($folder.Name)" -ForegroundColor Yellow
        Write-Host "  -> [SKIPPED] Missing: $($missing -join ', ')" -ForegroundColor Red
        $skippedFolders += "$($folder.Name)  (missing: $($missing -join ', '))"
        continue
    }

    Write-Host "`nAnalyzing folder: $($folder.Name)" -ForegroundColor Yellow

    # Read README.md and filter out empty lines to ensure we get the real first two lines
    $lines = @(Get-Content $readme -Encoding UTF8 | Where-Object { $_.Trim() -ne "" })

    $mapName = ""
    $author = ""
    $usedFallback = $false

    if ($lines.Count -ge 2) {
        if ($lines[0] -match "^#+\s*(.*)") { $mapName = $matches[1].Trim() }
        if ($lines[1] -match "(?i)^#+\s*Author:\s*(.*)") { $author = $matches[1].Trim() }
    }

    if ([string]::IsNullOrWhiteSpace($mapName) -or [string]::IsNullOrWhiteSpace($author)) {
        # Don't skip - fall back to the source folder name, which is
        # guaranteed unique on disk, so it can never collide with anything.
        # This still gets packed (with a screenshot etc.), just flagged so
        # you know to go fix that README later.
        $mapName = $folder.Name
        $author = "Unknown"
        $usedFallback = $true
        Write-Host "  -> [FALLBACK] Could not parse name/author from README.md - using folder name '$mapName'" -ForegroundColor DarkYellow
        $fallbackFolders += $folder.Name
    } else {
        Write-Host "  -> Found: '$mapName' by '$author'"
    }

    # Create info.json
    $jsonObj = [ordered]@{
        name = $mapName
        author = $author
    }
    $jsonPath = Join-Path $subFolder "info.json"
    $jsonObj | ConvertTo-Json -Depth 2 | Set-Content $jsonPath -Encoding UTF8

    # Generate filename base
    $cleanAuthor = ConvertTo-SafeAuthorSlug $author
    $cleanMap = ConvertTo-SafeMapSlug $mapName $folder.Name

    $binFileName = "${cleanAuthor}_${cleanMap}.bin"
    $imgFileName = "${cleanAuthor}_${cleanMap}.jpg"

    # --- Collision guard: never silently overwrite another map's output ---
    if ($usedFileNames.ContainsKey($binFileName)) {
        $originalBinFileName = $binFileName
        $suffix = 2
        while ($usedFileNames.ContainsKey($binFileName)) {
            $binFileName = "${cleanAuthor}_${cleanMap}-$suffix.bin"
            $imgFileName = "${cleanAuthor}_${cleanMap}-$suffix.jpg"
            $suffix++
        }
        Write-Host "  -> [COLLISION] '$originalBinFileName' is already used by '$($usedFileNames[$originalBinFileName])'." -ForegroundColor Magenta
        Write-Host "     Renamed this one to '$binFileName' instead - check if these are actually duplicates." -ForegroundColor Magenta
    }
    $usedFileNames[$binFileName] = $folder.Name

    $zipPath = Join-Path $baseDir "temp_$($folder.Name).zip"
    $binPath = Join-Path $outputDir $binFileName
    $targetImgPath = Join-Path $outputDir $imgFileName

    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    if (Test-Path $binPath) { Remove-Item $binPath -Force }

    # Create ZIP using native Windows PowerShell command
    Push-Location $subFolder
    Compress-Archive -Path "info.json", "Screenshot.jpg", "World.cf1047" -DestinationPath $zipPath -Force
    Pop-Location

    if (Test-Path $zipPath) {
        # ZIP Comment Hex-Patching
        $bytes = [System.IO.File]::ReadAllBytes($zipPath)
        $commentBytes = [System.Text.Encoding]::ASCII.GetBytes($comment)
        $eocdPos = -1
        for ($i = $bytes.Length - 22; $i -ge 0; $i--) {
            if ($bytes[$i] -eq 0x50 -and $bytes[$i+1] -eq 0x4B -and $bytes[$i+2] -eq 0x05 -and $bytes[$i+3] -eq 0x06) {
                $eocdPos = $i
                break
            }
        }

        if ($eocdPos -ne -1) {
            $head = $bytes[0..($eocdPos + 19)]
            $newLen = [System.BitConverter]::GetBytes([UInt16]$commentBytes.Length)
            $result = New-Object byte[] ($head.Length + 2 + $commentBytes.Length)
            [Array]::Copy($head, 0, $result, 0, $head.Length)
            [Array]::Copy($newLen, 0, $result, $head.Length, 2)
            [Array]::Copy($commentBytes, 0, $result, $head.Length + 2, $commentBytes.Length)
            [System.IO.File]::WriteAllBytes($zipPath, $result)
        } else {
            Write-Host "  -> [WARNING] Could not find signature for ZIP comment." -ForegroundColor DarkYellow
        }

        # Move and rename finished ZIP to ConvertOutput folder as .bin
        Move-Item -Path $zipPath -Destination $binPath -Force

        # Copy screenshot to ConvertOutput directory with matching name
        Copy-Item -Path $imgFile -Destination $targetImgPath -Force

        $tag = if ($usedFallback) { " [FALLBACK NAME]" } else { "" }
        Write-Host "  -> Successfully packed: $binFileName (+ extracted JPG)$tag" -ForegroundColor Green
        $processedCount++
    } else {
        Write-Host "  -> [ERROR] ZIP archive could not be created." -ForegroundColor Red
        $skippedFolders += "$($folder.Name)  (ZIP creation failed)"
    }

    # Cleanup info.json from the subfolder
    if (Test-Path $jsonPath) { Remove-Item $jsonPath -Force }
}

Write-Host "`n================================================="
Write-Host "Process completed! $processedCount map(s) successfully packed." -ForegroundColor Cyan

if ($fallbackFolders.Count -gt 0) {
    Write-Host "`n[NOTICE] The following $($fallbackFolders.Count) folder(s) were packed using a FALLBACK name" -ForegroundColor DarkYellow
    Write-Host "(README.md didn't match the expected format) - fix their README.md and re-run to get proper names:" -ForegroundColor DarkYellow
    foreach ($fb in $fallbackFolders) {
        Write-Host " - $fb" -ForegroundColor DarkYellow
    }
}

if ($skippedFolders.Count -gt 0) {
    Write-Host "`n[NOTICE] The following $($skippedFolders.Count) folder(s) were skipped entirely:" -ForegroundColor DarkGray
    foreach ($skip in $skippedFolders) {
        Write-Host " - $skip" -ForegroundColor DarkGray
    }
}