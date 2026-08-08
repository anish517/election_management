# start_all.ps1
# One-click startup script for the EMS Election Management System
# Starts: Django Server + Celery Worker + Celery Beat (Redis must be installed)
#
# Usage: Right-click this file -> "Run with PowerShell"
#        OR in terminal: powershell -ExecutionPolicy Bypass -File start_all.ps1

$backendPath = "f:\election_management\backend"
$venvPython  = "f:\election_management\venv\Scripts\activate"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   EMS Election Management System" -ForegroundColor Cyan  
Write-Host "   Starting all background services..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------
# 1. Start Redis (if not already running)
# ---------------------------------------------------
$redisRunning = & "C:\Program Files\Redis\redis-cli.exe" ping 2>$null
if ($redisRunning -eq "PONG") {
    Write-Host "[1/3] Redis       : Already running ✅" -ForegroundColor Green
} else {
    Write-Host "[1/3] Redis       : Starting..." -ForegroundColor Yellow
    Start-Process -NoNewWindow "C:\Program Files\Redis\redis-server.exe" -ArgumentList "--port 6379 --daemonize no"
    Start-Sleep -Seconds 2
    Write-Host "                  Started ✅" -ForegroundColor Green
}

# ---------------------------------------------------
# 2. Start Celery Worker in a new terminal window
# ---------------------------------------------------
Write-Host "[2/3] Celery Worker: Starting in new window..." -ForegroundColor Yellow
Start-Process powershell -ArgumentList `
    "-NoExit", `
    "-Command", `
    "Write-Host 'CELERY WORKER' -ForegroundColor Cyan; cd '$backendPath'; ..\venv\Scripts\activate; celery -A ems_backend worker --pool=solo -l info"

Start-Sleep -Seconds 2
Write-Host "                   Started ✅" -ForegroundColor Green

# ---------------------------------------------------
# 3. Start Celery Beat in a new terminal window
# ---------------------------------------------------
Write-Host "[3/3] Celery Beat  : Starting in new window..." -ForegroundColor Yellow
Start-Process powershell -ArgumentList `
    "-NoExit", `
    "-Command", `
    "Write-Host 'CELERY BEAT (Scheduler)' -ForegroundColor Magenta; cd '$backendPath'; ..\venv\Scripts\activate; celery -A ems_backend beat -l info --scheduler django_celery_beat.schedulers:DatabaseScheduler"

Start-Sleep -Seconds 2
Write-Host "                   Started ✅" -ForegroundColor Green

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  All services are now running!" -ForegroundColor Green
Write-Host ""
Write-Host "  Next: Start Django manually in your" -ForegroundColor White
Write-Host "  backend terminal:" -ForegroundColor White
Write-Host "    python manage.py runserver" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Elections will now auto-advance" -ForegroundColor White
Write-Host "  states every 60 seconds. 🎉" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

Read-Host "Press Enter to close this window"
