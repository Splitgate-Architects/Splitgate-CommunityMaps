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
function Get-FallbackHash {
    param([string]$Text)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))
    return ([BitConverter]::ToString($bytes) -replace '-', '').Substring(0, 8).ToLower()
}

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
    param([string]$MapName, [string]$FolderName)
    $s = ConvertTo-MapSlug $MapName
    if (-not [string]::IsNullOrEmpty($s)) { return $s }
    $s = ConvertTo-DashedSlug $FolderName
    if (-not [string]::IsNullOrEmpty($s)) { return $s }
    return "map-$(Get-FallbackHash $FolderName)"
}

function ConvertTo-MapSlug {
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
$skippedFolders = @()      
$fallbackFolders = @()     
$usedFileNames = @{}       

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

    $lines = @(Get-Content $readme -Encoding UTF8 | Where-Object { $_.Trim() -ne "" })

    $mapName = ""
    $author = ""
    $usedFallback = $false

    if ($lines.Count -ge 2) {
        if ($lines[0] -match "^#+\s*(.*)") { $mapName = $matches[1].Trim() }
        if ($lines[1] -match "(?i)^#+\s*Author:\s*(.*)") { $author = $matches[1].Trim() }
    }

    if ([string]::IsNullOrWhiteSpace($mapName) -or [string]::IsNullOrWhiteSpace($author)) {
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

    # Generate filename base inklusive Ursprungs-Ordnername zur Eindeutigkeit
    $cleanAuthor = ConvertTo-SafeAuthorSlug $author
    $cleanMap = ConvertTo-SafeMapSlug $mapName $folder.Name
    $cleanOrigin = ConvertTo-DashedSlug $folder.Name

    $binFileName = "${cleanAuthor}_${cleanMap}_${cleanOrigin}.bin"
    $imgFileName = "${cleanAuthor}_${cleanMap}_${cleanOrigin}.jpg"

    if ($usedFileNames.ContainsKey($binFileName)) {
        $originalBinFileName = $binFileName
        $suffix = 2
        while ($usedFileNames.ContainsKey($binFileName)) {
            $binFileName = "${cleanAuthor}_${cleanMap}_${cleanOrigin}-$suffix.bin"
            $imgFileName = "${cleanAuthor}_${cleanMap}_${cleanOrigin}-$suffix.jpg"
            $suffix++
        }
        Write-Host "  -> [COLLISION] '$originalBinFileName' is already used." -ForegroundColor Magenta
        Write-Host "     Renamed this one to '$binFileName' instead." -ForegroundColor Magenta
    }
    $usedFileNames[$binFileName] = $folder.Name

    $zipPath = Join-Path $baseDir "temp_$($folder.Name).zip"
    $binPath = Join-Path $outputDir $binFileName
    $targetImgPath = Join-Path $outputDir $imgFileName

    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    if (Test-Path $binPath) { Remove-Item $binPath -Force }

    Push-Location $subFolder
    Compress-Archive -Path "info.json", "Screenshot.jpg", "World.cf1047" -DestinationPath $zipPath -Force
    Pop-Location

    if (Test-Path $zipPath) {
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

        Move-Item -Path $zipPath -Destination $binPath -Force
        Copy-Item -Path $imgFile -Destination $targetImgPath -Force

        $tag = if ($usedFallback) { " [FALLBACK NAME]" } else { "" }
        Write-Host "  -> Successfully packed: $binFileName (+ extracted JPG)$tag" -ForegroundColor Green
        $processedCount++
    } else {
        Write-Host "  -> [ERROR] ZIP archive could not be created." -ForegroundColor Red
        $skippedFolders += "$($folder.Name)  (ZIP creation failed)"
    }

    if (Test-Path $jsonPath) { Remove-Item $jsonPath -Force }
}

Write-Host "`n================================================="
Write-Host "Process completed! $processedCount map(s) successfully packed." -ForegroundColor Cyan

if ($fallbackFolders.Count -gt 0) {
    Write-Host "`n[NOTICE] The following $($fallbackFolders.Count) folder(s) were packed using a FALLBACK name" -ForegroundColor DarkYellow
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