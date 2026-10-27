# Bascule le bridge entre le backend LOCAL et le backend DISTANT (WireGuard).
#   .\switch.ps1 local     -> bridge sur la stack Stoat de ce PC
#   .\switch.ps1 remote    -> bridge sur le backend de l'autre PC (.env.remote)
# Les deux modes partagent le même token Discord : un seul bridge doit tourner
# à la fois, sinon chaque message serait relayé deux fois. Le script arrête
# donc toujours l'autre mode avant de démarrer celui demandé.
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("local", "remote")]
    [string]$Mode
)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$local  = @("compose")
$remote = @("compose", "-f", "docker-compose.yaml", "-f", "docker-compose.remote.yaml",
            "--env-file", ".env", "--env-file", ".env.remote")

if ($Mode -eq "local") {
    Write-Host "==> Arrêt du bridge distant"
    & docker @remote stop stoatcord-bot
    Write-Host "==> Démarrage de la stack locale"
    & docker @local up -d
    $url = "http://stoat.localhost"
} else {
    if (-not (Test-Path .env.remote)) { throw ".env.remote manquant : copier .env.remote.example" }
    Write-Host "==> Arrêt du bridge local"
    & docker @local stop stoatcord-bot
    Write-Host "==> Démarrage du mode distant"
    & docker @remote up -d
    $url = "http://localhost:8080"
}

Write-Host "`n==> Bridges en cours d'exécution :"
docker ps --filter "name=stoatcord-bot" --format "  {{.Names}}  ({{.Status}})"
Write-Host "`nClient web : $url"
