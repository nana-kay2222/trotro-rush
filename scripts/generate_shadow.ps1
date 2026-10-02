Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap 256, 256
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::Transparent)

for ($i = 0; $i -lt 40; $i++) {
    $alpha = [int](160 * (1.0 - ($i / 40.0)))
    $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($alpha, 10, 10, 15))
    $w = 230 - ($i * 4)
    $h = 160 - ($i * 3)
    $x = [int]((256 - $w) / 2)
    $y = [int]((256 - $h) / 2)
    $g.FillEllipse($brush, $x, $y, $w, $h)
    $brush.Dispose()
}
$g.Dispose()
$bmp.Save("assets/vehicles/player_trotro/shadow_blob.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host "Created vehicle contact shadow"
