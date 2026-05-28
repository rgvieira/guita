# Script de Deploy para o dispositivo 2109119DG (b6fd1f9e)
$ErrorActionPreference = "Stop"

Write-Host "--- Iniciando Build para Android (arm64) ---" -ForegroundColor Cyan

# 1. Limpeza e Dependências
Write-Host "[1/3] Limpando e obtendo dependências..." -ForegroundColor Yellow
flutter clean
flutter pub get

# 2. Compilação focada na arquitetura do dispositivo
Write-Host "[2/3] Compilando APK Debug (android-arm64)..." -ForegroundColor Yellow
flutter build apk --debug --target-platform android-arm64

# 3. Transferência via ADB
$DeviceID = "b6fd1f9e"
$LocalPath = "build\app\outputs\flutter-apk\app-debug.apk"
$RemoteDir = "/sdcard/Download/apk"
$RemoteFileName = "guitarra_debug.apk"

Write-Host "[3/3] Enviando para o dispositivo $DeviceID..." -ForegroundColor Yellow

# Garante que a pasta existe no celular
adb -s $DeviceID shell mkdir -p $RemoteDir
# Copia o arquivo
adb -s $DeviceID push $LocalPath "$RemoteDir/$RemoteFileName"

Write-Host "`nSucesso! O arquivo está em: Download/apk/$RemoteFileName" -ForegroundColor Green
