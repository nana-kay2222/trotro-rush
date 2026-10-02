Add-Type -AssemblyName System.Drawing

$srcPath = (Resolve-Path "assets/buildings/mosque/mosque_original.png").Path
$img = [System.Drawing.Bitmap]::FromFile($srcPath)
Write-Host "Mosque image dimensions: $($img.Width) x $($img.Height)"

# Crop porch without any sky background:
# Porch archway and doors: x = 1680 to 2150, y = 370 to 700
$w = 460
$h = 330
$x = 1690
$y = 370

$dest = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($dest)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
# Fill with warm cream stucco first so any transparent area becomes matching stucco
$creamBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 243, 232, 196))
$g.FillRectangle($creamBrush, 0, 0, $w, $h)

$rect = New-Object System.Drawing.Rectangle($x, $y, $w, $h)
$g.DrawImage($img, (New-Object System.Drawing.Rectangle(0, 0, $w, $h)), $rect, [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()
$dest.Save((Resolve-Path "assets/buildings/mosque").Path + "\mosque_porch.png", [System.Drawing.Imaging.ImageFormat]::Png)
$dest.Dispose()
$img.Dispose()
Write-Host "Updated mosque_porch.png cleanly without white sky"

# 2. Update laterite earth with rich African red laterite tone
$lateritePath = (Resolve-Path "assets/environment").Path + "\laterite_earth.png"
$laterite = New-Object System.Drawing.Bitmap 512, 512
$lg = [System.Drawing.Graphics]::FromImage($laterite)
# Rich deep laterite red-brown (RGB: 130, 48, 25)
$baseBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 130, 48, 25))
$lg.FillRectangle($baseBrush, 0, 0, 512, 512)

$rand = New-Object System.Random(88)
for ($i = 0; $i -lt 30000; $i++) {
    $nx = $rand.Next(0, 512)
    $ny = $rand.Next(0, 512)
    $v = $rand.Next(-22, 22)
    $r = [Math]::Max(0, [Math]::Min(255, 130 + $v))
    $g = [Math]::Max(0, [Math]::Min(255, 48 + [int]($v * 0.5)))
    $b = [Math]::Max(0, [Math]::Min(255, 25 + [int]($v * 0.3)))
    $laterite.SetPixel($nx, $ny, [System.Drawing.Color]::FromArgb(255, $r, $g, $b))
}
# Small laterite stones & pebble clusters
for ($i = 0; $i -lt 120; $i++) {
    $cx = $rand.Next(10, 500)
    $cy = $rand.Next(10, 500)
    $rad = $rand.Next(2, 6)
    $pebCol = [System.Drawing.Color]::FromArgb(255, 105 + $rand.Next(-15,15), 40 + $rand.Next(-10,10), 20 + $rand.Next(-8,8))
    $pebBrush = New-Object System.Drawing.SolidBrush ($pebCol)
    $lg.FillEllipse($pebBrush, $cx, $cy, $rad, $rad)
    $pebBrush.Dispose()
}
$lg.Dispose()
$laterite.Save($lateritePath, [System.Drawing.Imaging.ImageFormat]::Png)
$laterite.Dispose()
Write-Host "Updated laterite_earth.png with rich red African soil"
