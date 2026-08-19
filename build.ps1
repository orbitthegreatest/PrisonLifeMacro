# Builds PrisonLifeMacro and copies the .exe to the local OUTPUTS folder.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$out = Join-Path (Split-Path -Parent $root) "OUTPUTS\PLM output"

dotnet publish (Join-Path $root "PrisonLifeMacro.csproj") -c Release -o $out --nologo
if ($LASTEXITCODE -ne 0) { throw "Publish failed" }
Write-Host ""
Write-Host "Built: $out\PrisonLifeMacro.exe" -ForegroundColor Green