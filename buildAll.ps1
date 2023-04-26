$dirs = Get-ChildItem . -Directory
$list = New-Object System.Collections.ArrayList

Clear-Host
$dirs | ForEach-Object {
    $location = $_
    Write-Host "------ $($location) ------"
    Set-Location $location
    git pull
    if (Test-Path *.sln) {
        dotnet build        
    }
    Set-Location ..
    Write-Host ""
    Write-Host ""
}

