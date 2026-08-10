# 生成 Cardory Windows App 图标（多尺寸标准 ICO）
# 源图：assets/branding/app_icon_source.png (1024x1024)
# 输出：windows/runner/resources/app_icon.ico
# 逻辑：裁掉源图四周 14% 留白，再缩放到 16/24/32/48/64/128/256 写入 ICO。

Add-Type -AssemblyName System.Drawing

$src = 'assets/branding/app_icon_source.png'
$out = 'windows/runner/resources/app_icon.ico'

# 1) 载入源图
$srcImg = [System.Drawing.Image]::FromFile((Resolve-Path $src))

# 2) 裁切中心区域（去掉 14% 四周留白，保留 logo 内容）
$cropRatio = 0.72
$crop = [int]($srcImg.Width * $cropRatio)
$cropX = [int](($srcImg.Width - $crop) / 2)
$cropY = [int](($srcImg.Height - $crop) / 2)

$cropRect = New-Object System.Drawing.Rectangle($cropX, $cropY, $crop, $crop)
$cropped = New-Object System.Drawing.Bitmap($crop, $crop)
$g = [System.Drawing.Graphics]::FromImage($cropped)
$g.DrawImage($srcImg, (New-Object System.Drawing.Rectangle(0,0,$crop,$crop)), $cropRect, [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()

# 3) 缩放各尺寸的 PNG
$sizes = 16,24,32,48,64,128,256
$pngStreams = @()
foreach ($s in $sizes) {
  $bmp = New-Object System.Drawing.Bitmap($cropped, $s, $s)
  $ms = New-Object System.IO.MemoryStream
  $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
  $pngStreams += ,$ms
  $bmp.Dispose()
}

# 4) 组装 ICO
$outDir = Resolve-Path (Split-Path $out -Parent)
$outPath = Join-Path $outDir 'app_icon.ico'
$fs = [System.IO.File]::Create($outPath)
$bw = New-Object System.IO.BinaryWriter($fs)

# ICONDIR
$bw.Write([uint16]0)      # reserved
$bw.Write([uint16]1)      # type=1 ICO
$bw.Write([uint16]$sizes.Count)

# ICONDIRENTRY
$offset = 6 + $sizes.Count * 16
for ($i = 0; $i -lt $sizes.Count; $i++) {
  $s = $sizes[$i]
  if ($s -ge 256) { $bw.Write([byte]0) } else { $bw.Write([byte]$s) }  # width
  if ($s -ge 256) { $bw.Write([byte]0) } else { $bw.Write([byte]$s) }  # height
  $bw.Write([byte]0)   # colors
  $bw.Write([byte]0)   # reserved
  $bw.Write([uint16]1) # planes
  $bw.Write([uint16]32)# bpp
  $bw.Write([uint32]$pngStreams[$i].Length)
  $bw.Write([uint32]$offset)
  $offset += $pngStreams[$i].Length
}

# 图像数据
for ($i = 0; $i -lt $pngStreams.Count; $i++) {
  $bw.Write($pngStreams[$i].ToArray())
}

$bw.Flush()
$fs.Close()

Write-Output "Generated $outPath with sizes: $($sizes -join ', ')"

# 清理
foreach ($ms in $pngStreams) { $ms.Dispose() }
$cropped.Dispose()
$srcImg.Dispose()
