# Windows 작업 스케줄러용: Supabase 동기화 (odds + predictions)
# .env 를 프로젝트 루트 또는 backend에 두고 SUPABASE_URL, SUPABASE_SERVICE_KEY, KRA_SERVICE_KEY 설정
# 예: $env:SINCE = "20260101"
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root
$envFiles = @(
    (Join-Path $Root ".env"),
    (Join-Path $Root "backend\.env")
)
foreach ($f in $envFiles) {
    if (Test-Path $f) {
        Get-Content $f | ForEach-Object {
            if ($_ -match '^\s*#' -or $_ -notmatch '=') { return }
            $pair = $_.Split('=', 2)
            if ($pair.Length -eq 2) { Set-Item -Path "Env:$($pair[0].Trim())" -Value $pair[1].Trim() }
        }
    }
}
if (-not $env:SINCE) {
    $env:SINCE = (Get-Date).AddDays(-14).ToString("yyyyMMdd")
}
$env:PYTHONPATH = (Join-Path $Root "backend") + ";" + $env:PYTHONPATH
Write-Host "scheduled_ops SINCE=$($env:SINCE)"
python (Join-Path $Root "backend\ops_sync.py") odds --since $env:SINCE --max-races 400 --sleep 0.35
python (Join-Path $Root "backend\ops_sync.py") predictions --since $env:SINCE --max-races 800 --model-version heuristic-place-1.1
Write-Host "scheduled_ops done"
