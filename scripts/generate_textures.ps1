Add-Type -AssemblyName System.Drawing

function Crop-Image {
    param ([string]$srcPath, [string]$destPath, [int]$x, [int]$y, [int]$w, [int]$h)
    $src = [System.Drawing.Bitmap]::FromFile((Resolve-Path $srcPath))
    $rect = New-Object System.Drawing.Rectangle($x, $y, $w, $h)
    $dest = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($dest)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($src, (New-Object System.Drawing.Rectangle(0, 0, $w, $h)), $rect, [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    $dest.Save((Resolve-Path (Split-Path $destPath -Parent)).Path + "\" + (Split-Path $destPath -Leaf), [System.Drawing.Imaging.ImageFormat]::Png)
    $dest.Dispose()
    $src.Dispose()
    Write-Host "Saved $destPath ($w x $h)"
}

# Mosque clean wall bay (crop below eaves): y=380, h=315
Crop-Image "assets/buildings/mosque/mosque_original.png" "assets/buildings/mosque/mosque_wall_bay.png" 550 380 420 315

# Compound house clean wall bay: y=380, h=230
Crop-Image "assets/buildings/compound_house/compound_house_small_original.png" "assets/buildings/compound_house/house_wall_bay.png" 300 380 460 230

# Compound house clean perimeter wall: y=450, h=180
Crop-Image "assets/buildings/compound_house/compound_house_large_original.png" "assets/buildings/compound_house/compound_perimeter_wall.png" 150 450 900 180

# Compound house front veranda clean:
Crop-Image "assets/buildings/compound_house/compound_house_small_original.png" "assets/buildings/compound_house/house_veranda.png" 1360 380 380 235

# Generate seamless 3-lane road texture (512x1024)
$road = New-Object System.Drawing.Bitmap 512, 1024
$rg = [System.Drawing.Graphics]::FromImage($road)
# Dark asphalt base
$asphaltBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 48, 50, 52))
$rg.FillRectangle($asphaltBrush, 0, 0, 512, 1024)

# Subtle asphalt grain/noise
$rand = New-Object System.Random(42)
for ($i = 0; $i -lt 8000; $i++) {
    $nx = $rand.Next(0, 512)
    $ny = $rand.Next(0, 1024)
    $shade = $rand.Next(-10, 10)
    $c = [Math]::Max(0, [Math]::Min(255, 50 + $shade))
    $road.SetPixel($nx, $ny, [System.Drawing.Color]::FromArgb(255, $c, $c, [Math]::Max(0, $c - 2)))
}

# 3 Lanes = 2 internal dashed white lines, 2 outer solid lines
# Road edges: x = 16 and x = 496 (solid lines)
$whitePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(240, 240, 235), 6)
$yellowPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(245, 185, 30), 6)
# Left and right shoulder lines
$rg.DrawLine($yellowPen, 20, 0, 20, 1024)
$rg.DrawLine($whitePen, 492, 0, 492, 1024)

# Lane dividers: lane 1/3 at x = 177, lane 2/3 at x = 335
# Dashed pattern: 60px dash, 40px gap
$dashLen = 70
$gapLen = 58
$y = 0
while ($y -lt 1024) {
    $rg.DrawLine($whitePen, 177, $y, 177, [Math]::Min(1024, $y + $dashLen))
    $rg.DrawLine($whitePen, 335, $y, 335, [Math]::Min(1024, $y + $dashLen))
    $y += $dashLen + $gapLen
}
$rg.Dispose()
$road.Save("assets/environment/road_3lane.png", [System.Drawing.Imaging.ImageFormat]::Png)
$road.Dispose()
Write-Host "Created assets/environment/road_3lane.png"

# Generate Ghanaian Laterite Earth texture (512x512) - warm red African soil
$laterite = New-Object System.Drawing.Bitmap 512, 512
$lg = [System.Drawing.Graphics]::FromImage($laterite)
# Base red soil: rich red-brown (RGB: 168, 78, 48)
$earthBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 162, 75, 46))
$lg.FillRectangle($earthBrush, 0, 0, 512, 512)
for ($i = 0; $i -lt 12000; $i++) {
    $nx = $rand.Next(0, 512)
    $ny = $rand.Next(0, 512)
    $rvar = $rand.Next(-25, 25)
    $r = [Math]::Max(0, [Math]::Min(255, 162 + $rvar))
    $g = [Math]::Max(0, [Math]::Min(255, 75 + [int]($rvar * 0.6)))
    $b = [Math]::Max(0, [Math]::Min(255, 46 + [int]($rvar * 0.4)))
    $laterite.SetPixel($nx, $ny, [System.Drawing.Color]::FromArgb(255, $r, $g, $b))
}
$lg.Dispose()
$laterite.Save("assets/environment/laterite_earth.png", [System.Drawing.Imaging.ImageFormat]::Png)
$laterite.Dispose()
Write-Host "Created assets/environment/laterite_earth.png"

# Generate concrete curb / gutter texture (256x256)
$curb = New-Object System.Drawing.Bitmap 256, 256
$cg = [System.Drawing.Graphics]::FromImage($curb)
$curbBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 145, 140, 135))
$cg.FillRectangle($curbBrush, 0, 0, 256, 256)
for ($i = 0; $i -lt 3000; $i++) {
    $nx = $rand.Next(0, 256)
    $ny = $rand.Next(0, 256)
    $cvar = $rand.Next(-18, 18)
    $c = [Math]::Max(0, [Math]::Min(255, 145 + $cvar))
    $curb.SetPixel($nx, $ny, [System.Drawing.Color]::FromArgb(255, $c, [Math]::Max(0, $c - 3), [Math]::Max(0, $c - 8)))
}
$cg.Dispose()
$curb.Save("assets/environment/curb_concrete.png", [System.Drawing.Imaging.ImageFormat]::Png)
$curb.Dispose()
Write-Host "Created assets/environment/curb_concrete.png"

# Generate tileable corrugated metal roof textures
# 1) Green corrugated roof (Mosque): deep green with highlights and shadows along ridges
$greenRoof = New-Object System.Drawing.Bitmap 256, 256
for ($x = 0; $x -lt 256; $x++) {
    $wave = [Math]::Sin($x * [Math]::PI * 2 / 16.0) # 16px wave period
    $r = [int](25 + 15 * $wave)
    $g = [int](105 + 35 * $wave)
    $b = [int](85 + 25 * $wave)
    for ($y = 0; $y -lt 256; $y++) {
        $n = $rand.Next(-4, 4)
        $greenRoof.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, [Math]::Max(0, [Math]::Min(255, $r + $n)), [Math]::Max(0, [Math]::Min(255, $g + $n)), [Math]::Max(0, [Math]::Min(255, $b + $n))))
    }
}
$greenRoof.Save("assets/buildings/mosque/roof_green_corrugated.png", [System.Drawing.Imaging.ImageFormat]::Png)
$greenRoof.Dispose()
Write-Host "Created assets/buildings/mosque/roof_green_corrugated.png"

# 2) Red/terracotta corrugated roof (Compound house): oxide red with highlights
$redRoof = New-Object System.Drawing.Bitmap 256, 256
for ($x = 0; $x -lt 256; $x++) {
    $wave = [Math]::Sin($x * [Math]::PI * 2 / 16.0) # 16px wave period
    $r = [int](155 + 35 * $wave)
    $g = [int](55 + 18 * $wave)
    $b = [int](50 + 15 * $wave)
    for ($y = 0; $y -lt 256; $y++) {
        $n = $rand.Next(-4, 4)
        $redRoof.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, [Math]::Max(0, [Math]::Min(255, $r + $n)), [Math]::Max(0, [Math]::Min(255, $g + $n)), [Math]::Max(0, [Math]::Min(255, $b + $n))))
    }
}
$redRoof.Save("assets/buildings/compound_house/roof_red_corrugated.png", [System.Drawing.Imaging.ImageFormat]::Png)
$redRoof.Dispose()
Write-Host "Created assets/buildings/compound_house/roof_red_corrugated.png"
