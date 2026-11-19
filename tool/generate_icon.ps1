Add-Type -AssemblyName System.Drawing

function New-IconPngBytes([int]$sz) {
    $bmp = New-Object System.Drawing.Bitmap($sz, $sz, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)

    $s = [float]$sz
    $r = $s * 0.25
    $d = $r * 2.0

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $d, $d, 180, 90)
    $path.AddArc($s - $d, 0, $d, $d, 270, 90)
    $path.AddArc($s - $d, $s - $d, $d, $d, 0, 90)
    $path.AddArc(0, $s - $d, $d, $d, 90, 90)
    $path.CloseFigure()

    $tileBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 24, 24, 27))
    $g.FillPath($tileBrush, $path)

    $white = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
    $fgBrush = New-Object System.Drawing.SolidBrush($white)
    $strokeW = [Math]::Max(1.4, $s * 0.072)
    $pen = New-Object System.Drawing.Pen($white, [float]$strokeW)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round

    $cx = $s * 0.5
    $cy = $s * 0.5
    $ringR = $s * 0.285
    $g.DrawEllipse($pen, [float]($cx - $ringR), [float]($cy - $ringR), [float]($ringR * 2.0), [float]($ringR * 2.0))

    $diag = $ringR * 0.70710678
    $tlx = [float]($cx - $diag)
    $tly = [float]($cy - $diag)
    $trx = [float]($cx + $diag)
    $topRightY = [float]($cy - $diag)
    $blx = [float]($cx - $diag)
    $bly = [float]($cy + $diag * 0.82)
    $brx = [float]($cx + $diag)
    $bry = [float]($cy + $diag * 0.82)
    $midx = [float]$cx
    $midy = [float]($cy + $ringR * 0.08)

    $mPath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $pts = [System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF($blx, $bly)),
        (New-Object System.Drawing.PointF($tlx, $tly)),
        (New-Object System.Drawing.PointF($midx, $midy)),
        (New-Object System.Drawing.PointF($trx, $topRightY)),
        (New-Object System.Drawing.PointF($brx, $bry))
    )
    $mPath.AddLines($pts)
    $g.DrawPath($pen, $mPath)

    $nodeR = [Math]::Max(1.2, $s * 0.062)
    $g.FillEllipse($fgBrush, [float]($tlx - $nodeR), [float]($tly - $nodeR), [float]($nodeR * 2.0), [float]($nodeR * 2.0))
    $g.FillEllipse($fgBrush, [float]($trx - $nodeR), [float]($topRightY - $nodeR), [float]($nodeR * 2.0), [float]($nodeR * 2.0))
    $cNodeR = $nodeR * 1.08
    $g.FillEllipse($fgBrush, [float]($midx - $cNodeR), [float]($midy - $cNodeR), [float]($cNodeR * 2.0), [float]($cNodeR * 2.0))

    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
    return ,$ms.ToArray()
}

$sizes = @(16, 24, 32, 48, 64, 128, 256)
$pngs = @()
foreach ($sz in $sizes) {
    $pngs += ,(New-IconPngBytes $sz)
}

$icoPath = "C:\projects\Klaro\windows\runner\resources\app_icon.ico"
$fs = [System.IO.File]::Open($icoPath, [System.IO.FileMode]::Create)
$bw = New-Object System.IO.BinaryWriter($fs)

$bw.Write([uint16]0)
$bw.Write([uint16]1)
$bw.Write([uint16]$sizes.Count)

$offset = 6 + (16 * $sizes.Count)
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $sz = $sizes[$i]
    $bytes = $pngs[$i]
    $wByte = if ($sz -ge 256) { [byte]0 } else { [byte]$sz }
    $bw.Write($wByte)
    $bw.Write($wByte)
    $bw.Write([byte]0)
    $bw.Write([byte]0)
    $bw.Write([uint16]1)
    $bw.Write([uint16]32)
    $bw.Write([uint32]$bytes.Length)
    $bw.Write([uint32]$offset)
    $offset += $bytes.Length
}

for ($i = 0; $i -lt $sizes.Count; $i++) {
    $bw.Write($pngs[$i])
}

$bw.Flush()
$bw.Close()
$fs.Close()
Get-Item $icoPath | Select-Object FullName, Length, LastWriteTime
