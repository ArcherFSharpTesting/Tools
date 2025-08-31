$dirs = Get-ChildItem . -Directory

Clear-Host
$dirs | ForEach-Object {
    $location = $_
    Write-Host ""
    Write-Host "------ $($location) ------"
    Push-Location $location

    # Check if this directory is a git repository
    if (Test-Path .git) {
        git pull
    } else {
        Write-Host "Not a git repository, skipping git pull" -ForegroundColor Yellow
    }

    Pop-Location
}