# Archer First-Time Setup Script
# This script builds, packs, and tests Archer projects in order.

Clear-Host

$localNugetRepo = "D:\Development\nuget"
$projectOrder = @(
    "Types",
    "Reporting",
    "Validations",
    "Runner",
    "Core" #,
    #"VSAdapter"
)

$buildFailures = @()
$testFailures = @()

# Ensure local NuGet repo is registered
$nugetSources = dotnet nuget list source | Out-String
if ($nugetSources -notmatch [regex]::Escape($localNugetRepo)) {
    Write-Host "Registering local NuGet repo: $localNugetRepo"
    dotnet nuget add source $localNugetRepo -n LocalArcher -p 1
} else {
    Write-Host "Local NuGet repo already registered."
}

# Build and pack each project
foreach ($proj in $projectOrder) {
    $libPath = Join-Path $proj "Lib"
    $projFiles = Get-ChildItem -Path $libPath -Filter *.fsproj
    if ($projFiles.Count -eq 0) {
        Write-Host "No .fsproj found in $libPath. Skipping."
        $buildFailures += $proj
        continue
    }
    $fsproj = $projFiles[0].FullName
    Write-Host "Building $fsproj..."
    $buildResult = dotnet build $fsproj
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Build failed for $proj." -ForegroundColor Red
        $buildFailures += $proj
        Write-Host "\n==== SUMMARY ===="
        Write-Host "Build/pack failed for: $($buildFailures -join ", ")" -ForegroundColor Red
        exit 1
    }
    Write-Host "Packing $fsproj..."
    $packResult = dotnet pack $fsproj -o $localNugetRepo
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Pack failed for $proj." -ForegroundColor Red
        $buildFailures += $proj
        Write-Host "\n==== SUMMARY ===="
        Write-Host "Build/pack failed for: $($buildFailures -join ", ")" -ForegroundColor Red
        exit 1
    }
    Write-Host "Build and pack succeeded for $proj."
}

# Test each project
foreach ($proj in $projectOrder) {
    $testPath = Join-Path $proj "Tests"
    if (-not (Test-Path $testPath)) {
        $testPath = Join-Path $proj "Tests.Scripts"
    }if (-not (Test-Path $testPath)) {
        $testPath = Join-Path $proj "Test.Scripts"
    }
    if (-not (Test-Path $testPath)) {
        Write-Host "No test directory found for $proj. Skipping tests."
        $testFailures += $proj
        continue
    }
    $testProjFiles = Get-ChildItem -Path $testPath -Filter *.fsproj
    if ($testProjFiles.Count -eq 0) {
        Write-Host "No test .fsproj found in $testPath. Skipping."
        $testFailures += $proj
        continue
    }
    foreach ($testProj in $testProjFiles) {
        # Get all target frameworks from the project file
        $frameworks = Select-String -Path $testProj.FullName -Pattern '<TargetFrameworks?>(.+?)<\/TargetFrameworks?>' | ForEach-Object {
            if ($_.Matches[0].Groups[1].Value -match ';') {
                $_.Matches[0].Groups[1].Value -split ';'
            } else {
                $_.Matches[0].Groups[1].Value
            }
        }
        if (-not $frameworks) {
            Write-Host "No target frameworks found in $($testProj.FullName), running default."
            $frameworks = @('')
        }
        foreach ($fw in $frameworks) {
            if ($fw -ne '') {
                Write-Host "Running tests for $($testProj.FullName) on framework $fw..."
                dotnet test $testProj.FullName -f $fw
            } else {
                Write-Host "Running tests for $($testProj.FullName) on default framework..."
                dotnet test $testProj.FullName
            }
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Test run failed for $proj on framework $fw."
                $testFailures += "$proj ($fw)"
                break
            }
        }
    }
}

# Report summary
Write-Host "\n==== SUMMARY ===="
if ($buildFailures.Count -eq 0) {
    Write-Host "All projects built and packed successfully."
} else {
    Write-Host "Build/pack failed for: $($buildFailures -join ", ")"
}
if ($testFailures.Count -eq 0) {
    Write-Host "All tests ran successfully."
} else {
    Write-Host "Test run failed for: $($testFailures -join ", ")"
}
