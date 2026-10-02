Add-Type -AssemblyName System.Drawing

function Crop-Image {
    param (
        [string]$sourcePath,
        [string]$destPath,
        [int]$x,
        [int]$y,
        [int]$w,
        [int]$h
    )
    $fullSrc = [System.IO.Path]::GetFullPath($sourcePath)
    $fullDest = [System.IO.Path]::GetFullPath($destPath)
    
    $src = [System.Drawing.Bitmap]::FromFile($fullSrc)
    $rect = New-Object System.Drawing.Rectangle($x, $y, $w, $h)
    $dest = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($dest)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($src, (New-Object System.Drawing.Rectangle(0, 0, $w, $h)), $rect, [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    $dest.Save($fullDest, [System.Drawing.Imaging.ImageFormat]::Png)
    $dest.Dispose()
    $src.Dispose()
    Write-Host "Extracted $destPath ($w x $h)"
}

Crop-Image -sourcePath "assets/buildings/mosque/mosque_original.png" -destPath "assets/buildings/mosque/mosque_wall_bay.png" -x 550 -y 360 -w 420 -h 335
Crop-Image -sourcePath "assets/buildings/mosque/mosque_original.png" -destPath "assets/buildings/mosque/mosque_roof.png" -x 600 -y 180 -w 600 -h 170
Crop-Image -sourcePath "assets/buildings/mosque/mosque_original.png" -destPath "assets/buildings/mosque/mosque_minaret.png" -x 1980 -y 15 -w 170 -h 380
Crop-Image -sourcePath "assets/buildings/mosque/mosque_original.png" -destPath "assets/buildings/mosque/mosque_dome.png" -x 1750 -y 120 -w 220 -h 210
Crop-Image -sourcePath "assets/buildings/mosque/mosque_original.png" -destPath "assets/buildings/mosque/mosque_porch.png" -x 1680 -y 320 -w 450 -h 375

Crop-Image -sourcePath "assets/buildings/compound_house/compound_house_small_original.png" -destPath "assets/buildings/compound_house/house_wall_bay.png" -x 300 -y 360 -w 460 -h 250
Crop-Image -sourcePath "assets/buildings/compound_house/compound_house_small_original.png" -destPath "assets/buildings/compound_house/house_roof.png" -x 300 -y 240 -w 600 -h 120
Crop-Image -sourcePath "assets/buildings/compound_house/compound_house_small_original.png" -destPath "assets/buildings/compound_house/house_veranda.png" -x 1360 -y 360 -w 380 -h 255
Crop-Image -sourcePath "assets/buildings/compound_house/compound_house_large_original.png" -destPath "assets/buildings/compound_house/compound_perimeter_wall.png" -x 150 -y 400 -w 900 -h 230
