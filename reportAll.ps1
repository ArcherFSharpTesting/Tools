# Get all subdirectories
$dirs = Get-ChildItem . -Directory
$projectList = New-Object System.Collections.ArrayList
$localNugetPath = "D:\Development\nuget"

Clear-Host

function NormalizeVersion {
    param(
        [string]$version
    )
    
    if ([string]::IsNullOrWhiteSpace($version) -or $version -eq "None") {
        return "0.0.0.0"
    }
    
    # Remove any pre-release suffixes (e.g., "1.2.3-alpha" becomes "1.2.3")
    $cleanVersion = $version -replace '-.*$', ''
    
    # Split into parts and ensure we have exactly 4 parts
    $parts = $cleanVersion.Split('.')
    $normalizedParts = @()
    
    for ($i = 0; $i -lt 4; $i++) {
        if ($i -lt $parts.Length -and $parts[$i] -match '^\d+$') {
            $normalizedParts += $parts[$i]
        } else {
            $normalizedParts += "0"
        }
    }
    
    return $normalizedParts -join '.'
}

function Compare-Versions {
    param(
        [string]$version1,
        [string]$version2
    )
    
    $norm1 = NormalizeVersion $version1
    $norm2 = NormalizeVersion $version2
    
    return $norm1 -eq $norm2
}

function Get-ProjectVersion {
    param(
        [string]$projectPath
    )
    
    $buildPropsPath = Join-Path $projectPath "Lib\Directory.Build.props"
    $libProjectFiles = Get-ChildItem (Join-Path $projectPath "Lib") -Filter "*.fsproj" -ErrorAction SilentlyContinue
    
    # Check for Directory.Build.props first
    if (Test-Path $buildPropsPath) {
        try {
            $versionNode = (Select-Xml $buildPropsPath -XPath "/Project/PropertyGroup/VersionPrefix").Node
            if ($versionNode) {
                return $versionNode.InnerText
            }
        }
        catch {
            # Continue to next option if XML parsing fails
        }
    }
    
    # Check for Version in F# project file
    if ($libProjectFiles.Count -gt 0) {
        $projectFile = $libProjectFiles[0].FullName
        try {
            $versionNode = (Select-Xml $projectFile -XPath "/Project/PropertyGroup/Version").Node
            if ($versionNode) {
                return $versionNode.InnerText
            }
        }
        catch {
            # Continue to fallback
        }
    }
    
    # Default version
    return "0.0.0.0"
}

function Get-AssemblyName {
    param(
        [string]$projectPath
    )
    
    $libProjectFiles = Get-ChildItem (Join-Path $projectPath "Lib") -Filter "*.fsproj" -ErrorAction SilentlyContinue
    
    if ($libProjectFiles.Count -gt 0) {
        $projectFile = $libProjectFiles[0].FullName
        
        # Check for AssemblyName in project file
        try {
            $assemblyNameNode = (Select-Xml $projectFile -XPath "/Project/PropertyGroup/AssemblyName").Node
            if ($assemblyNameNode) {
                return $assemblyNameNode.InnerText
            }
        }
        catch {
            # Continue to fallback
        }
        
        # Use project file name without extension as fallback
        return [System.IO.Path]::GetFileNameWithoutExtension($libProjectFiles[0].Name)
    }
    
    # Final fallback - use directory name
    return (Split-Path $projectPath -Leaf)
}

function Get-NuGetPackages {
    param(
        [string]$nugetPath
    )
    
    $packages = @{}
    
    if (Test-Path $nugetPath) {
        $nupkgFiles = Get-ChildItem $nugetPath -Filter "*.nupkg" -Recurse
        
        foreach ($file in $nupkgFiles) {
            # Parse package name and version from filename
            # Expected format: PackageName.Version.nupkg
            if ($file.Name -match '^(.+?)\.(\d+(?:\.\d+){0,3}(?:-.*?)?)\.nupkg$') {
                $packageName = $Matches[1]
                $packageVersion = $Matches[2]
                
                if (-not $packages.ContainsKey($packageName) -or 
                    $file.LastWriteTime -gt $packages[$packageName].LastWriteTime) {
                    $packages[$packageName] = @{
                        Version = $packageVersion
                        LastWriteTime = $file.LastWriteTime
                        FileName = $file.Name
                    }
                }
            }
        }
    }
    
    return $packages
}

# Get all NuGet packages from local repository
Write-Host "Scanning local NuGet repository: $localNugetPath" -ForegroundColor Yellow
$nugetPackages = Get-NuGetPackages -nugetPath $localNugetPath

# Process each directory
$dirs | ForEach-Object {
    $location = $_
    $solutionFiles = Get-ChildItem $location.FullName -Filter "*.sln" -ErrorAction SilentlyContinue
    
    # Only process directories that contain a .NET solution file
    if ($solutionFiles.Count -gt 0) {
        $libPath = Join-Path $location.FullName "Lib"
        
        # Check if Lib directory exists
        if (Test-Path $libPath) {
            $currentVersion = Get-ProjectVersion -projectPath $location.FullName
            $assemblyName = Get-AssemblyName -projectPath $location.FullName
            $projectName = Split-Path $location.FullName -Leaf
            
            # Look for deployed package
            $deployedVersion = "None"
            $deployedDate = $null
            
            if ($nugetPackages.ContainsKey($assemblyName)) {
                $deployedVersion = $nugetPackages[$assemblyName].Version
                $deployedDate = $nugetPackages[$assemblyName].LastWriteTime
            }
            
            [void]$projectList.Add([PSCustomObject]@{
                ProjectName = $projectName
                AssemblyName = $assemblyName
                CurrentVersion = $currentVersion
                DeployedVersion = $deployedVersion
                DeployedDate = $deployedDate
            })
        }
    }
}

# Display results
Write-Host ""
Write-Host "Project Analysis Report" -ForegroundColor Green
Write-Host "======================" -ForegroundColor Green
Write-Host ""

# Calculate the maximum project name length for alignment
$maxProjectNameLength = ($projectList | ForEach-Object { $_.ProjectName.Length } | Measure-Object -Maximum).Maximum

$projectList | ForEach-Object {
    $paddedProjectName = $_.ProjectName.PadRight($maxProjectNameLength)
    
    if ($_.DeployedDate) {
        $paddedDate = $_.DeployedDate.ToString('yyyy-MM-dd HH:mm:ss').PadRight($maxProjectNameLength)
        Write-Host "$($_.ProjectName):    $($paddedDate)" -ForegroundColor Cyan
    } else {
        $paddedDate = "Not deployed".PadRight($maxProjectNameLength)
        Write-Host "$($_.ProjectName)    $($paddedDate)" -ForegroundColor Cyan
    }
    
    # Status comparison using normalized version comparison
    if ($_.DeployedVersion -eq "None") {
        Write-Host "  Status:           Not deployed" -ForegroundColor Yellow
    } elseif (Compare-Versions $_.CurrentVersion $_.DeployedVersion) {
        Write-Host "  Status:           Up to date" -ForegroundColor Green
    } else {
        Write-Host "  Status:           Version mismatch" -ForegroundColor Red
        Write-Host "  Normalized Current:  $(NormalizeVersion $_.CurrentVersion)" -ForegroundColor Gray
        Write-Host "  Normalized Deployed: $(NormalizeVersion $_.DeployedVersion)" -ForegroundColor Gray
    }
    
    Write-Host ""
}