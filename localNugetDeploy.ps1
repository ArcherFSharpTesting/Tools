# Build and Package All Projects - Create NuGet packages for all qualifying projects
$localNugetPath = "D:\Development\nuget"
$createdPackages = @()

Clear-Host

function Test-HasSolutionFile {
    param(
        [string]$directoryPath
    )
    
    $solutionFiles = Get-ChildItem $directoryPath -Filter "*.sln" -ErrorAction SilentlyContinue
    return $solutionFiles.Count -gt 0
}

function Test-HasLibWithBuildProps {
    param(
        [string]$directoryPath
    )
    
    $libPath = Join-Path $directoryPath "Lib"
    if (-not (Test-Path $libPath)) {
        return $false
    }
    
    $buildPropsPath = Join-Path $libPath "Directory.Build.props"
    return Test-Path $buildPropsPath
}

function Get-ProjectInfo {
    param(
        [string]$projectPath
    )
    
    $libPath = Join-Path $projectPath "Lib"
    $libProjectFiles = Get-ChildItem $libPath -Filter "*.fsproj" -ErrorAction SilentlyContinue
    
    if ($libProjectFiles.Count -eq 0) {
        return $null
    }
    
    $projectFile = $libProjectFiles[0].FullName
    $buildPropsPath = Join-Path $libPath "Directory.Build.props"
    
    # Get version from Directory.Build.props
    $version = "0.0.0.0"
    if (Test-Path $buildPropsPath) {
        try {
            $versionNode = (Select-Xml $buildPropsPath -XPath "/Project/PropertyGroup/VersionPrefix").Node
            if ($versionNode) {
                $version = $versionNode.InnerText
            }
        }
        catch {
            Write-Warning "Could not read version from $buildPropsPath"
        }
    }
    
    # Get assembly name
    $assemblyName = $null
    try {
        $assemblyNameNode = (Select-Xml $projectFile -XPath "/Project/PropertyGroup/AssemblyName").Node
        if ($assemblyNameNode) {
            $assemblyName = $assemblyNameNode.InnerText
        }
    }
    catch {
        # Use project file name as fallback
        $assemblyName = [System.IO.Path]::GetFileNameWithoutExtension($libProjectFiles[0].Name)
    }
    
    if (-not $assemblyName) {
        $assemblyName = [System.IO.Path]::GetFileNameWithoutExtension($libProjectFiles[0].Name)
    }
    
    return @{
        ProjectFile = $projectFile
        AssemblyName = $assemblyName
        Version = $version
        ProjectName = (Split-Path $projectPath -Leaf)
    }
}

function Build-NuGetPackage {
    param(
        [hashtable]$projectInfo,
        [string]$outputPath
    )
    
    $projectFile = $projectInfo.ProjectFile
    
    Write-Host "Building package for $($projectInfo.ProjectName)..." -ForegroundColor Yellow
    
    # Ensure output directory exists
    if (-not (Test-Path $outputPath)) {
        New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
    }
    
    # Get list of existing packages before building
    $existingPackages = @()
    if (Test-Path $outputPath) {
        $existingPackages = Get-ChildItem $outputPath -Filter "$($projectInfo.AssemblyName).*.nupkg" | ForEach-Object { $_.Name }
    }
    
    # Build and pack the project
    try {
        # First, clean and build the project
        $buildResult = & dotnet build $projectFile --configuration Release --verbosity quiet 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  Build failed for $($projectInfo.ProjectName)" -ForegroundColor Red
            Write-Host "  Error: $buildResult" -ForegroundColor Red
            return @{ Success = $false; PackageFile = $null }
        }
        
        # Create NuGet package
        $packResult = & dotnet pack $projectFile --configuration Release --output $outputPath --verbosity quiet --force 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  Pack failed for $($projectInfo.ProjectName)" -ForegroundColor Red
            Write-Host "  Error: $packResult" -ForegroundColor Red
            return @{ Success = $false; PackageFile = $null }
        }
        
        # Find the newly created package file
        $newPackages = Get-ChildItem $outputPath -Filter "$($projectInfo.AssemblyName).*.nupkg" | Where-Object { $_.Name -notin $existingPackages }
        
        if ($newPackages.Count -gt 0) {
            $createdPackage = $newPackages[0].Name
            Write-Host "  Successfully created package: $createdPackage" -ForegroundColor Green
            return @{ Success = $true; PackageFile = $createdPackage }
        } else {
            # Fallback - get the most recent package for this assembly
            $allPackages = Get-ChildItem $outputPath -Filter "$($projectInfo.AssemblyName).*.nupkg" | Sort-Object LastWriteTime -Descending
            if ($allPackages.Count -gt 0) {
                $createdPackage = $allPackages[0].Name
                Write-Host "  Package created: $createdPackage" -ForegroundColor Green
                return @{ Success = $true; PackageFile = $createdPackage }
            } else {
                Write-Host "  Package creation succeeded but file not found" -ForegroundColor Yellow
                return @{ Success = $true; PackageFile = $null }
            }
        }
    }
    catch {
        Write-Host "  Exception occurred while building $($projectInfo.ProjectName): $($_.Exception.Message)" -ForegroundColor Red
        return @{ Success = $false; PackageFile = $null }
    }
}

# Main execution
Write-Host "Scanning for projects to package..." -ForegroundColor Yellow
Write-Host "Output directory: $localNugetPath" -ForegroundColor Yellow
Write-Host ""

# Get all subdirectories
$directories = Get-ChildItem . -Directory

$qualifyingProjects = @()

# Analyze each directory
foreach ($dir in $directories) {
    Write-Host "Checking $($dir.Name)..." -ForegroundColor Cyan
    
    # Check if directory has a .NET solution file
    if (-not (Test-HasSolutionFile $dir.FullName)) {
        Write-Host "  No solution file found, skipping" -ForegroundColor Gray
        continue
    }
    
    # Check if directory has Lib with Directory.Build.props
    if (-not (Test-HasLibWithBuildProps $dir.FullName)) {
        Write-Host "  No Lib directory with Directory.Build.props found, skipping" -ForegroundColor Gray
        continue
    }
    
    # Get project information
    $projectInfo = Get-ProjectInfo $dir.FullName
    if ($projectInfo) {
        Write-Host "  Qualified: $($projectInfo.AssemblyName) v$($projectInfo.Version)" -ForegroundColor Green
        $qualifyingProjects += $projectInfo
    } else {
        Write-Host "  Could not determine project information, skipping" -ForegroundColor Yellow
    }
}

if ($qualifyingProjects.Count -eq 0) {
    Write-Host ""
    Write-Host "No qualifying projects found." -ForegroundColor Yellow
    exit
}

Write-Host ""
Write-Host "Found $($qualifyingProjects.Count) qualifying project(s)" -ForegroundColor Green
Write-Host ""

# Build packages
$successfulBuilds = @()
$failedBuilds = @()

foreach ($project in $qualifyingProjects) {
    $result = Build-NuGetPackage $project $localNugetPath
    if ($result.Success) {
        $successfulBuilds += @{
            Project = $project
            PackageFile = $result.PackageFile
        }
        if ($result.PackageFile) {
            $createdPackages += $result.PackageFile
        }
    } else {
        $failedBuilds += $project
    }
}

# Report results
Write-Host ""
Write-Host "Package Creation Report" -ForegroundColor Green
Write-Host "======================" -ForegroundColor Green
Write-Host ""

if ($successfulBuilds.Count -gt 0) {
    Write-Host "Successfully created packages:" -ForegroundColor Green
    foreach ($build in $successfulBuilds) {
        $project = $build.Project
        $packageFile = $build.PackageFile
        if ($packageFile) {
            Write-Host "  ✓ $packageFile" -ForegroundColor Green
        } else {
            Write-Host "  ✓ $($project.ProjectName) (package file not tracked)" -ForegroundColor Green
        }
    }
    Write-Host ""
}

if ($failedBuilds.Count -gt 0) {
    Write-Host "Failed to create packages:" -ForegroundColor Red
    foreach ($project in $failedBuilds) {
        Write-Host "  ✗ $($project.ProjectName) ($($project.AssemblyName))" -ForegroundColor Red
    }
    Write-Host ""
}

Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Total projects processed: $($qualifyingProjects.Count)"
Write-Host "  Successful builds: $($successfulBuilds.Count)"
Write-Host "  Failed builds: $($failedBuilds.Count)"
Write-Host "  Output directory: $localNugetPath"

if ($createdPackages.Count -gt 0) {
    Write-Host ""
    Write-Host "Created package files:" -ForegroundColor Yellow
    foreach ($package in $createdPackages) {
        $packagePath = Join-Path $localNugetPath $package
        if (Test-Path $packagePath) {
            $fileInfo = Get-Item $packagePath
            Write-Host "  $package ($($fileInfo.Length) bytes, $($fileInfo.LastWriteTime))" -ForegroundColor White
        } else {
            Write-Host "  $package (file not found)" -ForegroundColor Red
        }
    }
}
