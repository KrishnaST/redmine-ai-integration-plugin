[CmdletBinding()]
param([switch]$InstallJavascriptTooling)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
Push-Location $projectDirectory
try {
    $rubyHome = Join-Path $PSScriptRoot 'runtime\rubyinstaller-4.0.9-1-x64'
    $rubyExecutable = Join-Path $rubyHome 'bin\ruby.exe'
    if (-not (Test-Path -LiteralPath $rubyExecutable)) { $rubyExecutable = (Get-Command ruby -ErrorAction Stop).Source }
    if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'runtime\gems')) {
        $env:GEM_HOME = Join-Path $PSScriptRoot 'runtime\gems'
        $env:GEM_PATH = $env:GEM_HOME + ';' + (Join-Path $rubyHome 'lib\ruby\gems\4.0.0')
    }
    New-Item -ItemType Directory -Force -Path (Join-Path $projectDirectory 'tmp') | Out-Null
    $env:TMP = Join-Path $projectDirectory 'tmp'
    $env:TEMP = $env:TMP
    $env:PYTHONDONTWRITEBYTECODE = '1'
    & $rubyExecutable test\test_controllers.rb
    if ($LASTEXITCODE -ne 0) { throw 'Ruby tests failed.' }
    $rubySources = @(Get-ChildItem -Path app,lib,config,db -Filter '*.rb' -Recurse) + @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'deployment') -Filter '*.rb') + @(Get-Item tools\package.rb)
    foreach ($source in $rubySources) {
        & $rubyExecutable -c $source.FullName | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Ruby syntax failed: $($source.Name)" }
    }
    if ($InstallJavascriptTooling) {
        npm.cmd install --prefix tools\runtime\javascript --cache tools\runtime\npm-cache --no-audit --no-fund --package-lock=false jsdom@31.0.1
        if ($LASTEXITCODE -ne 0) { throw 'JavaScript test tooling installation failed.' }
    }
    node --check assets\javascripts\settings.js
    if ($LASTEXITCODE -ne 0) { throw 'JavaScript syntax failed.' }
    node test\test_settings_js.cjs
    if ($LASTEXITCODE -ne 0) { throw 'Dynamic form tests failed.' }
    python -m unittest discover -s test -p test_deployment_environment.py
    if ($LASTEXITCODE -ne 0) { throw 'Deployment helper tests failed.' }
    & $rubyExecutable tools\package.rb
    if ($LASTEXITCODE -ne 0) { throw 'Packaging failed.' }
    & $rubyExecutable -r rubygems/package -r zlib -e 'Zlib::GzipReader.open(ARGV[0]) { |gzip| Gem::Package::TarReader.new(gzip) { |tar| names = tar.map(&:full_name); abort "Unsafe archive entry" unless names.all? { |name| name.start_with?("redmine_ai_integration/") && !name.include?("..") }; abort "Missing JavaScript asset" unless names.include?("redmine_ai_integration/assets/javascripts/settings.js"); puts "Verified #{names.size} production archive entries" } }' dist\redmine_ai_integration-1.1.0.tar.gz
    if ($LASTEXITCODE -ne 0) { throw 'Archive verification failed.' }
    git diff --check
    if ($LASTEXITCODE -ne 0) { throw 'Whitespace verification failed.' }
} finally {
    Pop-Location
}
