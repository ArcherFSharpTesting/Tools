$dirs = Get-ChildItem . -Directory
$list = New-Object System.Collections.ArrayList

Clear-Host
$dirs | ForEach-Object {
    $location = $_
    Write-Host "------ $($location) ------"
    Push-Location $location
    git pull
    if (Test-Path *.sln) {
        dotnet build .\Lib
    }
    Pop-Location
    Write-Host ""
    Write-Host ""
}

