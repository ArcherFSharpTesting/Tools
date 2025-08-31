# Clean NuGet Local Repository - Remove all but latest versions
$localNugetPath = "D:\Development\nuget"

Clear-Host

function ConvertTo-Version {
    param(
        [string]$versionString
    )
    
    # Remove any pre-release suffixes and normalize to 4-part version
    $cleanVersion = $versionString -replace '-.*$', ''
    $parts = $cleanVersion.Split('.')
    
    # Pad to 4 parts with zeros
    $normalizedParts = @()
    for ($i = 0; $i -lt 4; $i++) {
        if ($i -lt $parts.Length -and $parts[$i] -match '^\d+$') {
            $normalizedParts += [int]$parts[$i]
        } else {
            $normalizedParts += 0
        }
    }
    
    return $normalizedParts
}

function Compare-PackageVersions {
    param(
        [array]$version1,
        [array]$version2
    )
    
    for ($i = 0; $i -lt 4; $i++) {
        if ($version1[$i] -gt $version2[$i]) {
            return 1
        } elseif ($version1[$i] -lt $version2[$i]) {
            return -1
        }
    }
    
    return 0
}

function Get-AllNuGetPackages {
    param(
        [string]$nugetPath
    )
    
    $packages = @{}
    
    if (-not (Test-Path $nugetPath)) {
        Write-Host "NuGet directory not found: $nugetPath" -ForegroundColor Red
        return $packages
    }
    
    $nupkgFiles = Get-ChildItem $nugetPath -Filter "*.nupkg" -Recurse
    
    foreach ($file in $nupkgFiles) {
        # Parse package name and version from filename
        # Expected format: PackageName.Version.nupkg
        if ($file.Name -match '^(.+?)\.(\d+(?:\.\d+){0,3}(?:-.*?)?)\.nupkg$') {
            $packageName = $Matches[1]
            $packageVersion = $Matches[2]
            $parsedVersion = ConvertTo-Version $packageVersion
            
            if (-not $packages.ContainsKey($packageName)) {
                $packages[$packageName] = @()
            }
            
            $packages[$packageName] += @{
                FileName = $file.Name
                FilePath = $file.FullName
                VersionString = $packageVersion
                ParsedVersion = $parsedVersion
                LastWriteTime = $file.LastWriteTime
            }
        }
    }
    
    return $packages
}

# Main execution
Write-Host "Scanning NuGet repository: $localNugetPath" -ForegroundColor Yellow
Write-Host ""

$allPackages = Get-AllNuGetPackages -nugetPath $localNugetPath

if ($allPackages.Count -eq 0) {
    Write-Host "No packages found in the NuGet directory." -ForegroundColor Yellow
    exit
}

$totalFilesToDelete = 0
$packagesToClean = @()

# Analyze each package group
foreach ($packageName in $allPackages.Keys) {
    $versions = $allPackages[$packageName]
    
    if ($versions.Count -gt 1) {
        # Sort versions to find the latest
        $sortedVersions = $versions | Sort-Object -Property {
            $v = $_.ParsedVersion
            "$($v[0].ToString('D10')).$($v[1].ToString('D10')).$($v[2].ToString('D10')).$($v[3].ToString('D10'))"
        } -Descending
        
        $latestVersion = $sortedVersions[0]
        $oldVersions = $sortedVersions[1..($sortedVersions.Count - 1)]
        
        $packagesToClean += [PSCustomObject]@{
            PackageName = $packageName
            LatestVersion = $latestVersion.VersionString
            LatestFile = $latestVersion.FileName
            OldVersions = $oldVersions
            FilesToDelete = $oldVersions.Count
        }
        
        $totalFilesToDelete += $oldVersions.Count
    }
}

# Display analysis results
Write-Host "Package Analysis Results" -ForegroundColor Green
Write-Host "========================" -ForegroundColor Green
Write-Host ""

if ($packagesToClean.Count -eq 0) {
    Write-Host "All packages are already at their latest versions only." -ForegroundColor Green
    exit
}

foreach ($package in $packagesToClean) {
    Write-Host "$($package.PackageName):" -ForegroundColor Cyan
    Write-Host "  Latest:  $($package.LatestVersion) (keeping: $($package.LatestFile))"
    Write-Host "  Old versions to delete:" -ForegroundColor Yellow
    
    foreach ($oldVersion in $package.OldVersions) {
        Write-Host "    - $($oldVersion.VersionString) ($($oldVersion.FileName))" -ForegroundColor Red
    }
    Write-Host ""
}

Write-Host "Summary:" -ForegroundColor Green
Write-Host "  Packages with multiple versions: $($packagesToClean.Count)"
Write-Host "  Total files to delete: $totalFilesToDelete"
Write-Host ""

# Confirm deletion
$confirmation = Read-Host "Do you want to delete the old package versions? (y/N)"

if ($confirmation -eq 'y' -or $confirmation -eq 'Y') {
    Write-Host ""
    Write-Host "Deleting old package versions..." -ForegroundColor Yellow
    
    $deletedCount = 0
    $errorCount = 0
    
    foreach ($package in $packagesToClean) {
        foreach ($oldVersion in $package.OldVersions) {
            try {
                Remove-Item $oldVersion.FilePath -Force
                Write-Host "  Deleted: $($oldVersion.FileName)" -ForegroundColor Green
                $deletedCount++
            }
            catch {
                Write-Host "  Error deleting $($oldVersion.FileName): $($_.Exception.Message)" -ForegroundColor Red
                $errorCount++
            }
        }
    }
    
    Write-Host ""
    Write-Host "Cleanup completed!" -ForegroundColor Green
    Write-Host "  Files deleted: $deletedCount"
    if ($errorCount -gt 0) {
        Write-Host "  Errors: $errorCount" -ForegroundColor Red
    }
} else {
    Write-Host "Operation cancelled." -ForegroundColor Yellow
}
