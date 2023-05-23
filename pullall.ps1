$dirs = Get-ChildItem . -Directory
$list = New-Object System.Collections.ArrayList

Clear-Host
$dirs | ForEach-Object {
    $location = $_
    Write-Host ""
    Write-Host "------ $($location) ------"
    Set-Location $location
    git pull
    if (Test-Path .\Lib\Directory.Build.props) {
        $value = (Select-Xml .\Lib\Directory.Build.props -XPath "/Project/PropertyGroup/VersionPrefix").Node.InnerText
    } else {
        $value = "None"
    }
    $files = @()
    $file = $null
    $files = Get-ChildItem C:\Nuget.Local "$($location.Name)*.nupkg"
    $file = ($files | Sort-Object -Property {$_.LastWriteTime} -Descending | Select-Object -First 1).Name ?? "None"
    [void]$list.Add([Tuple]::Create($value, $file, $location))
    Set-Location ..
}

.\reportAll.ps1