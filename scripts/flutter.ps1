. "$PSScriptRoot/toolchain.ps1"
$flutterCommand = Join-Path $flutterBin 'flutter.bat'
if (-not (Test-Path -LiteralPath $flutterCommand)) { throw 'Project Flutter SDK missing. See docs/development-environment.md.' }
& $flutterCommand @args
exit $LASTEXITCODE
