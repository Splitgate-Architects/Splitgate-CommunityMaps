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

Write-Host "Starting strict map processing (Latin-only)..." -ForegroundColor Cyan
Write-Host "Target Directory: $targetDir" -ForegroundColor Cyan
Write-Host "Output Directory: $outputDir" -ForegroundColor Cyan
Write-Host "================================================="

if (-not (Test-Path $targetDir)) {
    Write-Host "[ERROR] The folder 'ConvertMaps' does not exist in the script's directory." -ForegroundColor Red
    Write-Host "Please make sure the script is placed in the correct main folder." -ForegroundColor Yellow
    exit
}

if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

# --- Strict Latin Slug Helper ---
function ConvertTo-StrictLatin {
    param([string]$Text, [switch]$AllowDashes)
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    
    # 1. Bekannte Symbole ausschreiben und Quake-Color-Codes entfernen
    $t = $Text -replace '\^[0-9]', '' -replace '\+', 'plus' -replace '&', 'and'
    
    # 2. Akzente glätten (z.B. é -> e, ä -> a)
    $t = $t.Normalize([Text.NormalizationForm]::FormKD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $t.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }
    
    # 3. Alles in Kleinschreibung umwandeln
    $t = $sb.ToString().ToLowerInvariant()
    
    # 4. Strikt alles filtern, was nicht a-z oder 0-9 ist
    if ($AllowDashes) {
        # Für Map-Namen: Leerzeichen zu Bindestrich, dann alles außer a-z, 0-9 und - löschen
        $t = $t -replace '\s+', '-'
        $t = $t -replace '[^a-z0-9-]', ''
        # Mehrfache Bindestriche reduzieren und an Rändern abschneiden
        $t = $t -replace '-+', '-'
        return $t.Trim('-')
    } else {
        # Für Autorennamen: Einfach alles zusammenziehen
        return ($t -replace '[^a-z0-9]', '')
    }
}

$folders = Get-ChildItem -Path $targetDir -Directory
$processedCount = 0
$skippedFolders = @()      
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

    # Lese README aus
    $lines = @(Get-Content $readme -Encoding UTF8 | Where-Object { $_.Trim() -ne "" })
    $mapName = ""
    $author = ""

    if ($lines.Count -ge 2) {
        if ($lines[0] -match "^#+\s*(.*)") { $mapName = $matches[1].Trim() }
        if ($lines[1] -match "(?i)^#+\s*Author:\s*(.*)") { $author = $matches[1].Trim() }
    }

    # Info.json mit den Originalnamen schreiben
    $jsonObj = [ordered]@{
        name = if ([string]::IsNullOrWhiteSpace($mapName)) { $folder.Name } else { $mapName }
        author = if ([string]::IsNullOrWhiteSpace($author)) { "Unknown" } else { $author }
    }
    $jsonPath = Join-Path $subFolder "info.json"
    $jsonObj | ConvertTo-Json -Depth 2 | Set-Content $jsonPath -Encoding UTF8

    # --- Dateinamen generieren (Code_Author_Mapname) ---
    $cleanOrigin = $folder.Name.ToLower() -replace '[^a-z0-9-]', ''
    $cleanAuthor = ConvertTo-StrictLatin $author
    $cleanMap = ConvertTo-StrictLatin $mapName -AllowDashes

    # Total-Fallback, falls Autor UND Mapname aus nicht-lateinischen Zeichen bestanden (z.B. nur Japanisch)
    if ([string]::IsNullOrEmpty($cleanAuthor) -and [string]::IsNullOrEmpty($cleanMap)) {
        $baseFileName = $cleanOrigin
        Write-Host "  -> [STRICT FALLBACK] No valid latin characters found. Using code only: $baseFileName" -ForegroundColor DarkYellow
    } else {
        if ([string]::IsNullOrEmpty($cleanAuthor)) { $cleanAuthor = "unknown" }
        if ([string]::IsNullOrEmpty($cleanMap)) { $cleanMap = "unknown" }
        $baseFileName = "${cleanOrigin}_${cleanAuthor}_${cleanMap}"
    }

    $binFileName = "${baseFileName}.bin"
    $imgFileName = "${baseFileName}.jpg"

    # Kollisions-Schutz
    if ($usedFileNames.ContainsKey($binFileName)) {
        $originalBinFileName = $binFileName
        $suffix = 2
        while ($usedFileNames.ContainsKey($binFileName)) {
            $binFileName = "${baseFileName}-$suffix.bin"
            $imgFileName = "${baseFileName}-$suffix.jpg"
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

    # ZIP erstellen
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

        Move-Item -Path $zipPath -Destination $binPath -Force
        Copy-Item -Path $imgFile -Destination $targetImgPath -Force

        Write-Host "  -> Successfully packed: $binFileName" -ForegroundColor Green
        $processedCount++
    } else {
        Write-Host "  -> [ERROR] ZIP archive could not be created." -ForegroundColor Red
        $skippedFolders += "$($folder.Name)  (ZIP creation failed)"
    }

    if (Test-Path $jsonPath) { Remove-Item $jsonPath -Force }
}

Write-Host "`n================================================="
Write-Host "Process completed! $processedCount map(s) successfully packed." -ForegroundColor Cyan

if ($skippedFolders.Count -gt 0) {
    Write-Host "`n[NOTICE] The following $($skippedFolders.Count) folder(s) were skipped entirely:" -ForegroundColor DarkGray
    foreach ($skip in $skippedFolders) {
        Write-Host " - $skip" -ForegroundColor DarkGray
    }
}