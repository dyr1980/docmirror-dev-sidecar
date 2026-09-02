#Requires -Version 5.1
<#
  dev-sidecar 开发环境统一启动/检查脚本

  用法（在仓库根目录或任意目录执行）:
    pwsh -File _script\dev.ps1 -Action start      # 启动开发环境并等待端口就绪
    pwsh -File _script\dev.ps1 -Action check      # 检查端口监听状态
    pwsh -File _script\dev.ps1 -Action stop       # 停止开发环境（按端口结束进程）
    pwsh -File _script\dev.ps1 -Action restart    # 停止后重新启动

  可选参数:
    -Port 8081          # 前端 dev server 端口，默认 8081
    -Foreground         # start 时在前台运行，日志直接输出到当前终端（Ctrl+C 停止）
    -SkipKill           # start/restart 时不先结束已占用端口的进程
#>
param(
  [ValidateSet('start', 'check', 'stop', 'restart')]
  [string]$Action = 'start',

  [int]$Port = 8081,

  [switch]$Foreground,

  [switch]$SkipKill
)

$ErrorActionPreference = 'SilentlyContinue'

$repoRoot = Split-Path -Parent $PSScriptRoot
$guiDir = Join-Path $repoRoot 'packages\gui'
$electronDev = Join-Path $PSScriptRoot 'electron-dev.mjs'
$proxyHttpPort = 31180
$proxyHttpsPort = 31181
$ports = @($Port, $proxyHttpPort, $proxyHttpsPort)

function Get-Listeners([int[]]$TargetPorts) {
  Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $TargetPorts -contains $_.LocalPort }
}

function Show-Status([string]$Title) {
  Write-Host "== $Title =="
  $listeners = @(Get-Listeners $ports)
  if ($listeners.Count -gt 0) {
    $listeners | Sort-Object LocalPort | ForEach-Object {
      $procName = (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName
      Write-Host ("  {0}:{1,-6} PID {2,-7} {3}" -f $_.LocalAddress, $_.LocalPort, $_.OwningProcess, $procName)
    }
  } else {
    Write-Host '  no listeners'
  }
  Write-Host ''
}

function Stop-DevSidecar([int[]]$TargetPorts) {
  Write-Host '== stopping dev-sidecar =='
  $listeners = @(Get-Listeners $TargetPorts)
  $procIds = @($listeners | Select-Object -ExpandProperty OwningProcess -Unique)
  if ($procIds.Count -eq 0) {
    Write-Host '  no listeners'
  } else {
    foreach ($procId in $procIds) {
      Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
      Write-Host "  killed PID $procId"
    }
  }
  Start-Sleep -Milliseconds 600
  Write-Host ''
}

function Wait-Ports([int[]]$TargetPorts, [int]$TimeoutSec = 120) {
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  $ready = @{}

  while ((Get-Date) -lt $deadline) {
    $listeners = @(Get-Listeners $TargetPorts)
    foreach ($p in $TargetPorts) {
      if ($listeners.LocalPort -contains $p) {
        $ready[$p] = $true
      }
    }

    if ($ready.Count -ge $TargetPorts.Count) {
      break
    }

    Start-Sleep -Seconds 1
  }

  if ($ready.Count -lt $TargetPorts.Count) {
    $missing = @($TargetPorts | Where-Object { -not $ready.ContainsKey($_) })
    Write-Host "等待端口超时，未就绪端口: $($missing -join ', ')"
  } else {
    Write-Host "端口已全部就绪: $($TargetPorts -join ', ')"
  }
}

function Start-DevSidecar([int]$DevPort) {
  $node = (Get-Command node -ErrorAction Stop).Source

  if ($Foreground) {
    Write-Host "== starting dev-sidecar in foreground (Ctrl+C to stop) =="
    Push-Location $guiDir
    try {
      & $node $electronDev '--port' "$DevPort"
    } finally {
      Pop-Location
    }
    return
  }

  Write-Host "== starting dev-sidecar =="
  $proc = Start-Process -FilePath $node -ArgumentList @($electronDev, '--port', "$DevPort") -WorkingDirectory $guiDir -WindowStyle Hidden -PassThru
  Write-Host "  launcher PID: $($proc.Id)"
  Wait-Ports $ports
  Show-Status 'port status after start'
}

switch ($Action) {
  'check' {
    Show-Status "port status (dev: $Port, http proxy: $proxyHttpPort, https proxy: $proxyHttpsPort)"
    break
  }

  'stop' {
    Stop-DevSidecar $ports
    Show-Status 'port status after stop'
    break
  }

  'start' {
    if (-not $SkipKill) {
      Stop-DevSidecar $ports
    }
    Start-DevSidecar $Port
    break
  }

  'restart' {
    Stop-DevSidecar $ports
    Start-DevSidecar $Port
    break
  }
}
