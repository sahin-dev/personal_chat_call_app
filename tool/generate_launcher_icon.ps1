Add-Type -AssemblyName System.Drawing

$projectRoot = Split-Path -Parent $PSScriptRoot
$fontPath = 'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf'
$fontCollection = New-Object System.Drawing.Text.PrivateFontCollection
$fontCollection.AddFontFile($fontPath)
$fontFamily = $fontCollection.Families[0]

function New-LauncherBitmap([int] $size) {
    $bitmap = New-Object System.Drawing.Bitmap($size, $size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $graphics.Clear([System.Drawing.ColorTranslator]::FromHtml('#F7F9F9'))

    $font = New-Object System.Drawing.Font(
        $fontFamily,
        ($size * 0.59),
        [System.Drawing.FontStyle]::Regular,
        [System.Drawing.GraphicsUnit]::Pixel
    )
    $brush = New-Object System.Drawing.SolidBrush(
        [System.Drawing.ColorTranslator]::FromHtml('#087F73')
    )
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center
    $glyph = [char]::ConvertFromUtf32(0xF79D)
    $bounds = New-Object System.Drawing.RectangleF(0, 0, $size, $size)
    $graphics.DrawString($glyph, $font, $brush, $bounds, $format)

    $format.Dispose()
    $brush.Dispose()
    $font.Dispose()
    $graphics.Dispose()
    return $bitmap
}

$assetsDirectory = Join-Path $projectRoot 'assets'
New-Item -ItemType Directory -Force -Path $assetsDirectory | Out-Null
$source = New-LauncherBitmap 1024
$source.Save(
    (Join-Path $assetsDirectory 'app_icon.png'),
    [System.Drawing.Imaging.ImageFormat]::Png
)
$source.Dispose()

$sizes = @{
    'mdpi' = 48
    'hdpi' = 72
    'xhdpi' = 96
    'xxhdpi' = 144
    'xxxhdpi' = 192
}
foreach ($density in $sizes.Keys) {
    $bitmap = New-LauncherBitmap $sizes[$density]
    $path = Join-Path $projectRoot "android\app\src\main\res\mipmap-$density\ic_launcher.png"
    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
}

$fontCollection.Dispose()
