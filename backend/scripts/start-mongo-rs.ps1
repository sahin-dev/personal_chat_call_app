$ErrorActionPreference = "Stop"

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$dataDir = Join-Path $projectRoot ".mongo-rs-data"
$logDir = Join-Path $projectRoot ".mongo-rs-log"
$logFile = Join-Path $logDir "mongod.log"
$mongod = "C:\Program Files\MongoDB\Server\8.0\bin\mongod.exe"

New-Item -ItemType Directory -Force -Path $dataDir, $logDir | Out-Null

$isOpen = Test-NetConnection -ComputerName 127.0.0.1 -Port 27019 -InformationLevel Quiet
if (-not $isOpen) {
  Start-Process `
    -FilePath $mongod `
    -ArgumentList @(
      "--dbpath", $dataDir,
      "--logpath", $logFile,
      "--port", "27019",
      "--bind_ip", "127.0.0.1",
      "--replSet", "rs0"
    ) `
    -WindowStyle Hidden | Out-Null
}

$ready = $false
for ($i = 0; $i -lt 30; $i++) {
  Start-Sleep -Milliseconds 500
  if (Test-NetConnection -ComputerName 127.0.0.1 -Port 27019 -InformationLevel Quiet) {
    $ready = $true
    break
  }
}

if (-not $ready) {
  throw "MongoDB replica-set process did not open port 27019. Check $logFile"
}

pnpm exec node scripts/init-mongo-rs.js
