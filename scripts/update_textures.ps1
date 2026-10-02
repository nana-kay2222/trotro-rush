Add-Type -AssemblyName System.Drawing

# 1. High-fidelity 3-lane road texture (512x1024)
$road = New-Object System.Drawing.Bitmap 512, 1024
$rg = [System.Drawing.Graphics]::FromImage($road)
# Dark warm asphalt (RGB 42, 44, 46)
$asphaltBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 42, 44, 46))
$rg.FillRectangle($asphaltBrush, 0, 0, 512, 1024)

# Fine asphalt aggregate grain
$rand = New-Object System.Random(77)
for ($i = 0; $i -lt 15000; $i++) {
    $nx = $rand.Next(0, 512)
    $ny = $rand.Next(0, 1024)
    $shade = $rand.Next(-12, 12)
    $c = [Math]::Max(0, [Math]::Min(255, 44 + $shade))
    $road.SetPixel($nx, $ny, [System.Drawing.Color]::FromArgb(255, $c, $c, [Math]::Max(0, $c - 3)))
}

# Road shoulder solid lines (width 8px)
$yellowBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 235, 180, 35))
$whiteBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 240, 240, 238))

# Left shoulder solid line: x = 16 to 24
$rg.FillRectangle($yellowBrush, 16, 0, 8, 1024)
# Right shoulder solid line: x = 488 to 496
$rg.FillRectangle($whiteBrush, 488, 0, 8, 1024)

# Center dashed lines separating the 3 lanes:
# Lane 1/2 divider at x = 173 to 179 (width 6px)
# Lane 2/3 divider at x = 333 to 339 (width 6px)
$dashLength = 80
$gapLength = 48
$step = $dashLength + $gapLength
for ($y = 0; $y -lt 1024; $y += $step) {
    $h = [Math]::Min($dashLength, 1024 - $y)
    $rg.FillRectangle($whiteBrush, 173, $y, 6, $h)
    $rg.FillRectangle($whiteBrush, 333, $y, 6, $h)
}
$rg.Dispose()
$road.Save("assets/environment/road_3lane.png", [System.Drawing.Imaging.ImageFormat]::Png)
$road.Dispose()
Write-Host "Updated road_3lane.png"

# 2. Rich Ghanaian Laterite Red Soil (512x512)
$soil = New-Object System.Drawing.Bitmap 512, 512
$sg = [System.Drawing.Graphics]::FromImage($soil)
# Base red laterite: deep rich African red-brown (RGB: 142, 60, 34)
$baseBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 142, 60, 34))
$sg.FillRectangle($baseBrush, 0, 0, 512, 512)

# Soil variation, small stones, dried patches
for ($i = 0; $i -lt 25000; $i++) {
    $nx = $rand.Next(0, 512)
    $ny = $rand.Next(0, 512)
    $v = $rand.Next(-28, 28)
    $r = [Math]::Max(0, [Math]::Min(255, 142 + $v))
    $g = [Math]::Max(0, [Math]::Min(255, 60 + [int]($v * 0.55)))
    $b = [Math]::Max(0, [Math]::Min(255, 34 + [int]($v * 0.35)))
    $soil.SetPixel($nx, $ny, [System.Drawing.Color]::FromArgb(255, $r, $g, $b))
}

# Add subtle dirt pebbles / gravel clumps
for ($i = 0; $i -lt 80; $i++) {
    $cx = $rand.Next(10, 500)
    $cy = $rand.Next(10, 500)
    $rad = $rand.Next(2, 6)
    $pebCol = [System.Drawing.Color]::FromArgb(255, 115 + $rand.Next(-15,15), 52 + $rand.Next(-10,10), 28 + $rand.Next(-8,8))
    $pebBrush = New-Object System.Drawing.SolidBrush ($pebCol)
    $sg.FillEllipse($pebBrush, $cx, $cy, $rad, $rad)
    $pebBrush.Dispose()
}
$sg.Dispose()
$soil.Save("assets/environment/laterite_earth.png", [System.Drawing.Imaging.ImageFormat]::Png)
$soil.Dispose()
Write-Host "Updated laterite_earth.png"
