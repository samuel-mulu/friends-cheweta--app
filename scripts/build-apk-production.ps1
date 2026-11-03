# Build release APK against the Render production backend.
$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))

$apiBaseUrl = "https://friends-cheweta-backend.onrender.com/api"
$socketBaseUrl = "https://friends-cheweta-backend.onrender.com"

flutter clean
flutter pub get
flutter build apk --release `
  --dart-define=API_BASE_URL=$apiBaseUrl `
  --dart-define=SOCKET_BASE_URL=$socketBaseUrl

Write-Host ""
Write-Host "APK output: build\app\outputs\flutter-apk\app-release.apk"
