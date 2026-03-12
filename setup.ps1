$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$envFile = Join-Path $root ".env"

if (-not (Test-Path $envFile)) {
    Copy-Item (Join-Path $root ".env.example") $envFile
    Write-Host ".env aangemaakt vanuit .env.example"
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker ontbreekt op de host."
}

$composeCmd = $null
try {
    docker compose version | Out-Null
    $composeCmd = "docker compose"
} catch {
    if (Get-Command docker-compose -ErrorAction SilentlyContinue) {
        $composeCmd = "docker-compose"
    } else {
        throw "Geen docker compose client gevonden."
    }
}

try {
    $maxMapCount = (sysctl -n vm.max_map_count) 2>$null
    if ($maxMapCount -ne "262144") {
        Write-Warning "vm.max_map_count is $maxMapCount. Voor OpenSearch is 262144 aanbevolen."
    }
} catch {
    Write-Warning "Kon vm.max_map_count niet uitlezen op deze host."
}

Write-Host "Compose config valideren"
Invoke-Expression "$composeCmd config" | Out-Null

Write-Host "Stack builden en starten"
Invoke-Expression "$composeCmd up -d --build"

Write-Host "Gebruik '$composeCmd logs -f php' om de eerste Magento bootstrap te volgen."
