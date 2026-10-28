. "$PSScriptRoot/toolchain.ps1"
$dartCommand = Join-Path $flutterBin 'dart.bat'
if (-not (Test-Path -LiteralPath $dartCommand)) { throw 'Project Dart SDK missing. See docs/development-environment.md.' }
& $dartCommand @args
exit $LASTEXITCODE
