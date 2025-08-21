Clear-Host
${lib_names} = @('Archer.CoreTypes', 'Archer.Logger', 'Archer.Arrow', 'Archer.Bow', 'Archer.Fletching', 'MicroLang')
#${lib_names} = @('Archer.CoreTypes')

foreach ($name in $lib_names) {
    $path = ".\$name\Lib"
    Push-Location $path
    
    Write-Host "------ $($path) ------"
    dotnet pack ./$name.Lib.fsproj --configuration Release
    
    $nupkgPath = Get-ChildItem -Path ".\bin\Release" -Filter "*.nupkg" -Recurse | Select-Object -First 1
    Copy-Item -Path $nupkgPath -Destination "D:\Development\nuget"
    
    Pop-Location
}