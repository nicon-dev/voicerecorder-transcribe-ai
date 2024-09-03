# Konfiguration
$usbName = "RECORDER"
$recordFolderName = "RECORD"
$uploadUrl = "https://4fd3ba33-de74-4f51-9dba-c11eb8c45c94-00-5hmnc3mmrezo.spock.replit.dev/transcribeAudioMake"
$authUser = "admin"
$authPass = "1234ws"
$scriptPath = $PSScriptRoot # Verwendet den aktuellen Ordner des Skripts
$uploadedFilesLog = Join-Path -Path $scriptPath -ChildPath "uploaded_files.txt"
$debugLog = Join-Path -Path $scriptPath -ChildPath "debug.log"

# Funktion zum Schreiben von Debug-Informationen
function Write-DebugLog {
    param([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $message"
    $logMessage | Out-File -Append -FilePath $debugLog
    Write-Host $logMessage
}

# Erstelle debug.log, falls nicht vorhanden
if (-not (Test-Path $debugLog)) {
    New-Item -Path $debugLog -ItemType File | Out-Null
    Write-DebugLog "Debug-Log-Datei erstellt: $debugLog"
}

# Erstelle uploaded_files.txt, falls nicht vorhanden
if (-not (Test-Path $uploadedFilesLog)) {
    New-Item -Path $uploadedFilesLog -ItemType File | Out-Null
    Write-DebugLog "Uploaded-Files-Log-Datei erstellt: $uploadedFilesLog"
}

Write-DebugLog "Skript gestartet"

# Funktion zum Bestimmen des MIME-Typs basierend auf der Dateiendung
function Get-MimeType {
    param ([string]$fileName)
    $extension = [System.IO.Path]::GetExtension($fileName).ToLower()
    switch ($extension) {
        ".mp3" { return "audio/mpeg" }
        ".wav" { return "audio/wav" }
        ".ogg" { return "audio/ogg" }
        ".flac" { return "audio/flac" }
        ".m4a" { return "audio/mp4" }
        default { return "application/octet-stream" }
    }
}

# Funktion zum Hochladen einer Datei
function Upload-File {
    param (
        [string]$filePath
    )

    $url = $uploadUrl
    $auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${authUser}:${authPass}"))
    $fileName = [System.IO.Path]::GetFileName($filePath)
    $mimeType = Get-MimeType -fileName $fileName

    $headers = @{
        "Authorization" = "Basic $auth"
    }

    Write-DebugLog "Upload-Headers: $($headers | ConvertTo-Json -Compress)"

    $boundary = [System.Guid]::NewGuid().ToString()
    $LF = "`r`n"
    $fileContent = [System.IO.File]::ReadAllBytes($filePath)
    $fileContentEncoded = [System.Text.Encoding]::GetEncoding('ISO-8859-1').GetString($fileContent)

    $body = @(
        "--$boundary",
        "Content-Disposition: form-data; name=`"audio`"; filename=`"$fileName`"",
        "Content-Type: $mimeType$LF",
        $fileContentEncoded,
        "--$boundary--$LF"
    ) -join $LF

    try {
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body -ContentType "multipart/form-data; boundary=`"$boundary`""
        Write-DebugLog "Datei erfolgreich hochgeladen: $fileName"
        return $true
    }
    catch {
        Write-DebugLog ("Fehler beim Hochladen der Datei {0}: {1}" -f $fileName, $_.Exception.Message)
        return $false
    }
}

# Funktion zum Überprüfen und Hochladen von Dateien
function Check-AndUploadFiles {
    Write-DebugLog "Suche USB-Gerät: $usbName"
    $allDrives = Get-WmiObject Win32_LogicalDisk
    Write-DebugLog "Alle gefundenen Laufwerke: $($allDrives | Format-Table VolumeName, DeviceID | Out-String)"
    
    $usbDrive = $allDrives | Where-Object { $_.VolumeName -eq $usbName }
    Write-DebugLog "Gefundenes USB-Laufwerk: $($usbDrive | Format-List | Out-String)"

    if ($usbDrive) {
        Write-DebugLog "USB-Gerät '$usbName' gefunden. Pfad: $($usbDrive.DeviceID)"
        
        $recordFolder = Join-Path -Path $usbDrive.DeviceID -ChildPath $recordFolderName
        Write-DebugLog "Suche RECORD-Ordner: $recordFolder"
        
        if (Test-Path $recordFolder) {
            Write-DebugLog "RECORD Ordner gefunden: $recordFolder"
            
            # Liste der bereits hochgeladenen Dateien laden
            $uploadedFiles = @()
            if ((Test-Path $uploadedFilesLog) -and (Get-Item $uploadedFilesLog).Length -gt 0) {
                $uploadedFiles = Get-Content $uploadedFilesLog
                Write-DebugLog "Bereits hochgeladene Dateien: $($uploadedFiles -join ', ')"
            } else {
                Write-DebugLog "uploaded_files.txt ist leer oder nicht vorhanden. Alle Dateien werden hochgeladen."
            }

            # Alle Dateien im RECORD Ordner durchlaufen
            $allFiles = Get-ChildItem -Path $recordFolder -File
            Write-DebugLog "Gefundene Dateien:"
            $allFiles | ForEach-Object { Write-DebugLog "- $($_.FullName)" }

            if ($allFiles.Count -eq 0) {
                Write-DebugLog "Keine Dateien im RECORD-Ordner gefunden."
            }

            foreach ($file in $allFiles) {
                if ($uploadedFiles -notcontains $file.Name) {
                    Write-DebugLog "Versuche Datei hochzuladen: $($file.FullName)"
                    
                    $uploadSuccess = Upload-File -filePath $file.FullName
                    
                    if ($uploadSuccess) {
                        $file.Name | Out-File -Append -FilePath $uploadedFilesLog
                    }
                }
                else {
                    Write-DebugLog "Datei wurde bereits hochgeladen, überspringe: $($file.Name)"
                }
            }
        }
        else {
            Write-DebugLog "RECORD Ordner nicht gefunden auf dem USB-Gerät. Pfad: $recordFolder"
        }
    }
    else {
        Write-DebugLog "USB-Gerät '$usbName' nicht gefunden"
    }
}

# Endlosschleife zum kontinuierlichen Überprüfen
while ($true) {
    Check-AndUploadFiles
    Write-DebugLog "Warte 60 Sekunden vor der nächsten Überprüfung..."
    Start-Sleep -Seconds 60
}
