$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$toolingRoot = Join-Path $projectRoot '.tooling'
$env:PUB_CACHE = Join-Path $projectRoot '.local/pub-cache'
$env:GRADLE_USER_HOME = Join-Path $projectRoot '.local/gradle'
$env:ANDROID_USER_HOME = Join-Path $projectRoot '.local/android-user'
$env:ANDROID_HOME = Join-Path $toolingRoot 'android-sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:DART_SUPPRESS_ANALYTICS = 'true'
$jdkRoot = Join-Path $toolingRoot 'java'
if (Test-Path -LiteralPath $jdkRoot) {
    $jdkDirectory = Get-ChildItem -LiteralPath $jdkRoot -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'bin/java.exe') } | Select-Object -First 1
    if ($jdkDirectory) {
        $env:JAVA_HOME = $jdkDirectory.FullName
        $env:PATH = "$env:JAVA_HOME/bin;$env:PATH"
    }
}
$flutterBin = Join-Path $toolingRoot 'flutter/bin'
$env:PATH = "$flutterBin;$env:ANDROID_HOME/platform-tools;$env:PATH"
