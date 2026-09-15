param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$mobileRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$webRoot = (Resolve-Path -LiteralPath (Join-Path $mobileRoot '../../web/rentflow-web')).Path
$sourcePath = Join-Path $mobileRoot 'assets/brand/mark-source.png'
$masterPath = Join-Path $mobileRoot 'assets/brand/mark-master-1024.png'

function New-SizedBitmap([System.Drawing.Image] $source, [int] $size) {
  $bitmap = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.Clear([System.Drawing.Color]::FromArgb(48, 60, 31))
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.DrawImage($source, [System.Drawing.Rectangle]::new(0, 0, $size, $size))
  } finally {
    $graphics.Dispose()
  }
  return $bitmap
}

function Save-Icon([System.Drawing.Image] $source, [int] $size, [string] $destination) {
  $directory = Split-Path -Parent $destination
  if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
  $bitmap = New-SizedBitmap $source $size
  try { $bitmap.Save($destination, [System.Drawing.Imaging.ImageFormat]::Png) }
  finally { $bitmap.Dispose() }
}

$screenshot = [System.Drawing.Bitmap]::new($sourcePath)
$artwork = [System.Drawing.Bitmap]::new(168, 168, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$cropGraphics = [System.Drawing.Graphics]::FromImage($artwork)
try {
  $cropGraphics.DrawImage($screenshot, [System.Drawing.Rectangle]::new(0, 0, 168, 168), [System.Drawing.Rectangle]::new(11, 8, 168, 168), [System.Drawing.GraphicsUnit]::Pixel)
} finally { $cropGraphics.Dispose() }
# The source is a screenshot of a rounded tile on white. Launcher artwork needs
# opaque, full-bleed corners; replace only the screenshot's exterior pixels.
for ($x = 0; $x -lt 168; $x++) {
  for ($y = 0; $y -lt 168; $y++) {
    $cornerX = if ($x -lt 40) { 40 } elseif ($x -gt 127) { 127 } else { $x }
    $cornerY = if ($y -lt 40) { 40 } elseif ($y -gt 127) { 127 } else { $y }
    $outside = (($x - $cornerX) * ($x - $cornerX) + ($y - $cornerY) * ($y - $cornerY)) -gt (40 * 40)
    $pixel = $artwork.GetPixel($x, $y)
    $cornerDistance = ($x - $cornerX) * ($x - $cornerX) + ($y - $cornerY) * ($y - $cornerY)
    $brightExterior = $cornerDistance -gt (30 * 30) -and $pixel.R -gt 100 -and $pixel.G -gt 100 -and $pixel.B -gt 100
    $borderLeak = ($x -lt 12 -or $x -gt 155 -or $y -lt 10 -or $y -gt 151) -and $pixel.R -gt 80 -and $pixel.G -gt 80 -and $pixel.B -gt 80
    if ($outside -or $brightExterior -or $borderLeak) { $artwork.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(48, 60, 31)) }
  }
}
$master = [System.Drawing.Bitmap]::new(1024, 1024, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$graphics = [System.Drawing.Graphics]::FromImage($master)
$clip = [System.Drawing.Drawing2D.GraphicsPath]::new()
try {
  # Crop only the supplied square artwork, then extend its dark olive corners
  # to a full-bleed launcher tile (iOS and Android apply their own masks).
  $diameter = 248
  $end = 1023
  $clip.AddArc(0, 0, $diameter, $diameter, 180, 90)
  $clip.AddArc($end - $diameter, 0, $diameter, $diameter, 270, 90)
  $clip.AddArc($end - $diameter, $end - $diameter, $diameter, $diameter, 0, 90)
  $clip.AddArc(0, $end - $diameter, $diameter, $diameter, 90, 90)
  $clip.CloseFigure()
  $graphics.Clear([System.Drawing.Color]::FromArgb(48, 60, 31))
  $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $graphics.SetClip($clip)
  $graphics.DrawImage($artwork, [System.Drawing.Rectangle]::new(0, 0, 1024, 1024))
  $graphics.ResetClip()
  $master.Save($masterPath, [System.Drawing.Imaging.ImageFormat]::Png)
  $master.Save((Join-Path $webRoot 'src/assets/rentflow-mark.png'), [System.Drawing.Imaging.ImageFormat]::Png)

  $androidSizes = @{ mdpi = 48; hdpi = 72; xhdpi = 96; xxhdpi = 144; xxxhdpi = 192 }
  foreach ($density in $androidSizes.Keys) {
    Save-Icon $master $androidSizes[$density] (Join-Path $mobileRoot "android/app/src/main/res/mipmap-$density/ic_launcher.png")
  }

  $iosFolder = Join-Path $mobileRoot 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
  $iosContents = Get-Content -LiteralPath (Join-Path $iosFolder 'Contents.json') -Raw | ConvertFrom-Json
  foreach ($image in $iosContents.images) {
    $points = [double]::Parse($image.size.Split('x')[0], [System.Globalization.CultureInfo]::InvariantCulture)
    $scale = [int]$image.scale.TrimEnd('x')
    Save-Icon $master ([int]($points * $scale)) (Join-Path $iosFolder $image.filename)
  }

  $macFolder = Join-Path $mobileRoot 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
  foreach ($size in @(16, 32, 64, 128, 256, 512, 1024)) {
    Save-Icon $master $size (Join-Path $macFolder "app_icon_$size.png")
  }

  $flutterWeb = Join-Path $mobileRoot 'web'
  Save-Icon $master 32 (Join-Path $flutterWeb 'favicon.png')
  foreach ($size in @(192, 512)) {
    Save-Icon $master $size (Join-Path $flutterWeb "icons/Icon-$size.png")
    Save-Icon $master $size (Join-Path $flutterWeb "icons/Icon-maskable-$size.png")
  }

  $reactPublic = Join-Path $webRoot 'public'
  Save-Icon $master 64 (Join-Path $reactPublic 'favicon.png')
  Save-Icon $master 180 (Join-Path $reactPublic 'apple-touch-icon.png')
  Save-Icon $master 192 (Join-Path $reactPublic 'icon-192.png')
  Save-Icon $master 512 (Join-Path $reactPublic 'icon-512.png')

  # Windows .ico contains several PNG resolutions and uses the same artwork.
  $windowsIcon = Join-Path $mobileRoot 'windows/runner/resources/app_icon.ico'
  $sizes = @(16, 32, 48, 64, 128, 256)
  $streams = @()
  foreach ($size in $sizes) {
    $bitmap = New-SizedBitmap $master $size
    $stream = [System.IO.MemoryStream]::new()
    $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    $streams += $stream
  }
  $file = [System.IO.File]::Create($windowsIcon)
  $writer = [System.IO.BinaryWriter]::new($file)
  try {
    $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$sizes.Count)
    $offset = 6 + 16 * $sizes.Count
    for ($index = 0; $index -lt $sizes.Count; $index++) {
      $size = $sizes[$index]
      $writer.Write([byte]($size % 256)); $writer.Write([byte]($size % 256))
      $writer.Write([byte]0); $writer.Write([byte]0)
      $writer.Write([uint16]1); $writer.Write([uint16]32)
      $writer.Write([uint32]$streams[$index].Length)
      $writer.Write([uint32]$offset)
      $offset += $streams[$index].Length
    }
    foreach ($stream in $streams) { $writer.Write($stream.ToArray()); $stream.Dispose() }
  } finally { $writer.Dispose(); $file.Dispose() }
} finally {
  $clip.Dispose()
  $graphics.Dispose()
  $master.Dispose()
  $artwork.Dispose()
  $screenshot.Dispose()
}

Write-Output 'RentFlow AI launcher, browser, and desktop icons generated from the supplied artwork.'
